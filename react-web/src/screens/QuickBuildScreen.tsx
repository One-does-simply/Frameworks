import { useState, useEffect, useRef, useCallback } from 'react'
import { useNavigate } from 'react-router'
import { render } from '@/engine/template-engine.ts'
import {
  fetchTemplateCatalog,
  fetchTemplate,
  type TemplateCatalogEntry,
} from '@/engine/template-catalog.ts'
import { AppRegistry } from '@/engine/app-registry.ts'
import { parseSpec, isOk } from '@/parser/spec-parser.ts'
import pb from '@/lib/pocketbase.ts'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog'
import { toast } from 'sonner'
import {
  ArrowLeft,
  Loader2,
  Rocket,
  ChevronRight,
  ChevronDown,
  Plus,
  X,
  GripVertical,
  Pencil,
  Check,
  Palette,
} from 'lucide-react'
import { loadThemeCatalog } from '@/engine/branding-service.ts'
import { ColorRow } from '@/components/ColorCustomizer.tsx'

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface TemplateQuestion {
  id: string
  label: string
  type: 'text' | 'select' | 'checkbox' | 'field-list' | 'field-ref'
  required?: boolean
  placeholder?: string
  options?: string[]
  default?: unknown
  ref?: string // for field-ref: references a field-list question
  presets?: FieldPreset[]
}

interface FieldPreset {
  label: string
  name: string
  type: string
  options?: string[]
}

interface FieldEntry {
  name: string
  label: string
  type: string
  options?: string[]
}

interface ReviewableText {
  path: string[]
  label: string
  category: string
  value: string
  isMultiline?: boolean
}

// ---------------------------------------------------------------------------
// QuickBuildScreen — template picker + question wizard + text review
// ---------------------------------------------------------------------------

export function QuickBuildScreen() {
  const navigate = useNavigate()
  const registry = useRef(new AppRegistry(pb)).current

  // Phase 1: Catalog
  const [catalog, setCatalog] = useState<TemplateCatalogEntry[] | null>(null)
  const [loadingCatalog, setLoadingCatalog] = useState(true)
  const [catalogError, setCatalogError] = useState<string | null>(null)

  // Phase 2: Questions
  const [templateJson, setTemplateJson] = useState<Record<string, unknown> | null>(null)
  const [templateName, setTemplateName] = useState<string | null>(null)
  const [questions, setQuestions] = useState<TemplateQuestion[] | null>(null)
  const [answers, setAnswers] = useState<Record<string, unknown>>({})
  const [fieldLists, setFieldLists] = useState<Record<string, FieldEntry[]>>({})
  const [rendering, setRendering] = useState(false)
  const [renderError, setRenderError] = useState<string | null>(null)

  // Phase 3: Text review
  const [renderedSpec, setRenderedSpec] = useState<Record<string, unknown> | null>(null)
  const [reviewTexts, setReviewTexts] = useState<ReviewableText[] | null>(null)
  const [reviewValues, setReviewValues] = useState<Record<string, string>>({})

  // Phase 2.5: Theme selection
  const [inThemePhase, setInThemePhase] = useState(false)
  const [selectedTheme, setSelectedTheme] = useState('indigo')
  const [colorOverrides, setColorOverrides] = useState<Record<string, string>>({})
  const [themeCatalog, setThemeCatalog] = useState<Array<{ name: string; displayName: string; tags?: { style?: string; palette?: string } | string[] }> | null>(null)

  // Branding fields (theme phase)
  const [brandingLogo, setBrandingLogo] = useState('')
  const [brandingFavicon, setBrandingFavicon] = useState('')
  const [brandingHeaderStyle, setBrandingHeaderStyle] = useState<'light' | 'solid' | 'transparent'>('light')
  const [brandingFontFamily, setBrandingFontFamily] = useState('')

  // Saving
  const [saving, setSaving] = useState(false)

  // Add field dialog
  const [addFieldFor, setAddFieldFor] = useState<string | null>(null)
  const [editFieldFor, setEditFieldFor] = useState<{ questionId: string; index: number } | null>(null)

  // -------------------------------------------------------------------------
  // Phase 1: Load catalog
  // -------------------------------------------------------------------------

  const loadCatalog = useCallback(async () => {
    setLoadingCatalog(true)
    setCatalogError(null)
    const entries = await fetchTemplateCatalog()
    if (entries) {
      setCatalog(entries)
    } else {
      setCatalogError('Could not load template catalog. Check your internet connection.')
    }
    setLoadingCatalog(false)
  }, [])

  useEffect(() => {
    loadCatalog()
  }, [loadCatalog])

  async function selectTemplate(entry: TemplateCatalogEntry) {
    setLoadingCatalog(true)
    setCatalogError(null)

    const tmpl = await fetchTemplate(entry.file)
    if (!tmpl) {
      setCatalogError(`Could not load template "${entry.name}"`)
      setLoadingCatalog(false)
      return
    }

    const qs = (tmpl['questions'] as TemplateQuestion[]) ?? []
    const initialAnswers: Record<string, unknown> = {}
    const initialFieldLists: Record<string, FieldEntry[]> = {}

    for (const q of qs) {
      if (q.type === 'checkbox') {
        initialAnswers[q.id] = q.default === true
      } else if (q.type === 'field-list') {
        initialFieldLists[q.id] = []
      } else if (q.id === 'theme') {
        // Use framework default theme, falling back to template default
        initialAnswers[q.id] = localStorage.getItem('ods_default_theme') ?? q.default ?? 'indigo'
      } else if (q.default != null) {
        initialAnswers[q.id] = q.default
      }
    }

    setTemplateJson(tmpl)
    setTemplateName((tmpl['templateName'] as string) ?? entry.name)
    setQuestions(qs)
    setAnswers(initialAnswers)
    setFieldLists(initialFieldLists)
    setLoadingCatalog(false)
  }

  // -------------------------------------------------------------------------
  // Phase 2: Build
  // -------------------------------------------------------------------------

  function validateRequired(): boolean {
    if (!questions) return false
    for (const q of questions) {
      if (!q.required) continue
      if (q.type === 'field-list') {
        if (!fieldLists[q.id] || fieldLists[q.id].length === 0) return false
      } else {
        const answer = answers[q.id]
        if (answer == null || (typeof answer === 'string' && answer.trim() === '')) return false
      }
    }
    return true
  }

  // -------------------------------------------------------------------------
  // Phase 3: Finish
  // -------------------------------------------------------------------------

  async function finishWithSpec() {
    if (!renderedSpec || !reviewTexts) return

    // Apply text edits back into the rendered spec.
    for (let i = 0; i < reviewTexts.length; i++) {
      const rt = reviewTexts[i]
      const editedValue = reviewValues[String(i)] ?? rt.value
      setNestedValue(renderedSpec, rt.path, editedValue)
    }

    const specJson = JSON.stringify(renderedSpec, null, 2)

    // Validate before saving
    const result = parseSpec(specJson)
    if (result.parseError || !isOk(result)) {
      toast.error('Generated spec has validation errors. Please try a different template.')
      return
    }

    const appName = result.app!.appName
    const description = result.app!.help?.overview ?? ''

    setSaving(true)
    try {
      const saved = await registry.saveApp(appName, specJson, description)
      setSaving(false)
      if (saved) {
        toast.success(`"${appName}" created!`)
        navigate(`/${saved.slug}`)
      } else {
        toast.error('Failed to save app')
      }
    } catch (e) {
      setSaving(false)
      toast.error(`Save failed: ${e instanceof Error ? e.message : String(e)}`)
    }
  }

  // -------------------------------------------------------------------------
  // Answer updaters
  // -------------------------------------------------------------------------

  function setAnswer(id: string, value: unknown) {
    setAnswers((prev) => ({ ...prev, [id]: value }))
  }

  function updateFieldList(questionId: string, updater: (prev: FieldEntry[]) => FieldEntry[]) {
    setFieldLists((prev) => ({
      ...prev,
      [questionId]: updater(prev[questionId] ?? []),
    }))
  }

  // -------------------------------------------------------------------------
  // Phase 2.5: Theme selection
  // -------------------------------------------------------------------------

  async function goToThemePhase() {
    const catalog = await loadThemeCatalog()
    let themeFromAnswers = (answers['theme'] as string) ?? localStorage.getItem('ods_default_theme') ?? 'indigo'
    // Handle legacy 'light'/'dark' theme names from old templates
    if (themeFromAnswers === 'light') themeFromAnswers = 'indigo'
    if (themeFromAnswers === 'dark') themeFromAnswers = 'slate'
    setThemeCatalog(catalog)
    setSelectedTheme(themeFromAnswers)
    setColorOverrides({})
    setBrandingLogo('')
    setBrandingFavicon('')
    setBrandingHeaderStyle('light')
    setBrandingFontFamily('')
    setInThemePhase(true)
  }

  function backToWizardFromTheme() {
    setInThemePhase(false)
    setThemeCatalog(null)
    setColorOverrides({})
    setBrandingLogo('')
    setBrandingFavicon('')
    setBrandingHeaderStyle('light')
    setBrandingFontFamily('')
  }

  function backToTheme() {
    setRenderedSpec(null)
    setReviewTexts(null)
    setInThemePhase(true)
  }

  function continueFromTheme() {
    // Inject theme into answers
    setAnswers((prev) => ({ ...prev, theme: selectedTheme }))

    // Render the template then inject branding
    setRendering(true)
    setRenderError(null)
    try {
      const context: Record<string, unknown> = { ...answers, theme: selectedTheme }
      for (const [key, value] of Object.entries(fieldLists)) {
        context[key] = value
      }
      const templateBody = templateJson!['template']
      const rendered = render(templateBody, context) as Record<string, unknown>

      // Inject branding
      const branding = (rendered['branding'] as Record<string, unknown>) ?? {}
      branding['theme'] = selectedTheme
      branding['mode'] = 'system'
      if (Object.keys(colorOverrides).length > 0) {
        branding['overrides'] = { ...colorOverrides }
      }
      if (brandingLogo.trim()) branding['logo'] = brandingLogo.trim()
      if (brandingFavicon.trim()) branding['favicon'] = brandingFavicon.trim()
      branding['headerStyle'] = brandingHeaderStyle
      if (brandingFontFamily.trim()) branding['fontFamily'] = brandingFontFamily.trim()
      rendered['branding'] = branding

      const texts = extractReviewableTexts(rendered)
      const initialValues: Record<string, string> = {}
      texts.forEach((t, i) => { initialValues[String(i)] = t.value })

      setRenderedSpec(rendered)
      setReviewTexts(texts)
      setReviewValues(initialValues)
      setInThemePhase(false)
      setRendering(false)
    } catch (e) {
      setRendering(false)
      setRenderError(`Failed to build app: ${e instanceof Error ? e.message : String(e)}`)
    }
  }

  // -------------------------------------------------------------------------
  // Determine phase
  // -------------------------------------------------------------------------

  const inTextReview = reviewTexts != null
  const inTheme = inThemePhase && !inTextReview
  const inWizard = questions != null && !inTextReview && !inTheme
  const inCatalog = !inWizard && !inTheme && !inTextReview

  // Breadcrumb step: 0=catalog (no breadcrumb), 1=details, 2=theme, 3=text review
  const breadcrumbStep = inTextReview ? 3 : inTheme ? 2 : inWizard ? 1 : 0

  // -------------------------------------------------------------------------
  // Render
  // -------------------------------------------------------------------------

  const breadcrumbLabels = ['Enter App Details', 'Choose Theme', 'Customize App Text']

  return (
    <div className="flex min-h-screen flex-col bg-background">
      {/* Top bar */}
      <header className="sticky top-0 z-40 flex flex-col border-b bg-background/95 supports-backdrop-filter:backdrop-blur-sm">
        <div className="flex h-14 items-center gap-3 px-4">
          <Button
            variant="ghost"
            size="icon-sm"
            onClick={() => {
              if (inTextReview) backToTheme()
              else if (inTheme) backToWizardFromTheme()
              else if (inWizard) { setQuestions(null); setTemplateJson(null) }
              else navigate('/admin')
            }}
          >
            <ArrowLeft className="size-5" />
          </Button>
          <h1 className="flex-1 truncate text-base font-semibold">{templateName ?? 'Quick Build'}</h1>
        </div>

        {/* Breadcrumb — visible once a template is selected */}
        {!inCatalog && (
          <nav className="flex items-center gap-1.5 px-4 pb-2.5 text-xs">
            {breadcrumbLabels.map((label, i) => {
              const step = i + 1
              const isCurrent = step === breadcrumbStep
              const isPast = step < breadcrumbStep
              return (
                <span key={label} className="flex items-center gap-1.5">
                  {i > 0 && <ChevronRight className="size-3 text-muted-foreground/50" />}
                  {isPast ? (
                    <button
                      type="button"
                      className="text-muted-foreground hover:text-foreground"
                      onClick={() => {
                        if (step === 1 && breadcrumbStep >= 2) {
                          if (inTextReview) { backToTheme(); setTimeout(backToWizardFromTheme, 0) }
                          else backToWizardFromTheme()
                        }
                        if (step === 2 && inTextReview) backToTheme()
                      }}
                    >
                      {label}
                    </button>
                  ) : (
                    <span className={isCurrent ? 'font-semibold text-primary' : 'text-muted-foreground/50'}>
                      {label}
                    </span>
                  )}
                </span>
              )
            })}
          </nav>
        )}
      </header>

      {/* Content */}
      <div className="flex-1 overflow-y-auto">
        {inTextReview
          ? <TextReviewPhase
              texts={reviewTexts}
              values={reviewValues}
              onValueChange={(i, v) => setReviewValues((prev) => ({ ...prev, [String(i)]: v }))}
              onFinish={finishWithSpec}
              saving={saving}
            />
          : inTheme
            ? <ThemePhase
                catalog={themeCatalog}
                selectedTheme={selectedTheme}
                colorOverrides={colorOverrides}
                onSelectTheme={setSelectedTheme}
                onOverrideChange={(token: string, value: string) => setColorOverrides(prev => ({ ...prev, [token]: value }))}
                onResetOverride={(token: string) => setColorOverrides(prev => { const next = { ...prev }; delete next[token]; return next })}
                onContinue={continueFromTheme}
                rendering={rendering}
                renderError={renderError}
                brandingLogo={brandingLogo}
                onBrandingLogoChange={setBrandingLogo}
                brandingFavicon={brandingFavicon}
                onBrandingFaviconChange={setBrandingFavicon}
                brandingHeaderStyle={brandingHeaderStyle}
                onBrandingHeaderStyleChange={setBrandingHeaderStyle}
                brandingFontFamily={brandingFontFamily}
                onBrandingFontFamilyChange={setBrandingFontFamily}
              />
            : inWizard
              ? <WizardPhase
                  questions={questions}
                  answers={answers}
                  fieldLists={fieldLists}
                  onSetAnswer={setAnswer}
                  onUpdateFieldList={updateFieldList}
                  onBuild={goToThemePhase}
                  canBuild={validateRequired()}
                  rendering={rendering}
                  renderError={renderError}
                  onAddField={setAddFieldFor}
                  onEditField={setEditFieldFor}
                />
              : <CatalogPhase
                  catalog={catalog}
                  loading={loadingCatalog}
                  error={catalogError}
                  onSelect={selectTemplate}
                  onRetry={loadCatalog}
                />
        }
      </div>

      {/* Add Field Dialog */}
      <AddFieldDialog
        open={addFieldFor != null}
        onOpenChange={(open) => !open && setAddFieldFor(null)}
        onAdd={(field) => {
          if (addFieldFor) {
            updateFieldList(addFieldFor, (prev) => [...prev, field])
            setAddFieldFor(null)
          }
        }}
      />

      {/* Edit Field Dialog */}
      {editFieldFor && (
        <EditFieldDialog
          open
          onOpenChange={(open) => !open && setEditFieldFor(null)}
          field={fieldLists[editFieldFor.questionId]?.[editFieldFor.index]}
          onSave={(updated) => {
            if (editFieldFor) {
              updateFieldList(editFieldFor.questionId, (prev) => {
                const next = [...prev]
                next[editFieldFor.index] = updated
                return next
              })
              setEditFieldFor(null)
            }
          }}
        />
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Phase 1: Catalog Picker
// ---------------------------------------------------------------------------

function CatalogPhase({
  catalog,
  loading,
  error,
  onSelect,
  onRetry,
}: {
  catalog: TemplateCatalogEntry[] | null
  loading: boolean
  error: string | null
  onSelect: (entry: TemplateCatalogEntry) => void
  onRetry: () => void
}) {
  if (loading) {
    return (
      <div className="flex items-center justify-center py-16">
        <Loader2 className="size-5 animate-spin text-muted-foreground" />
        <span className="ml-2 text-sm text-muted-foreground">Loading templates...</span>
      </div>
    )
  }

  if (error) {
    return (
      <div className="mx-auto max-w-md space-y-4 py-16 text-center">
        <p className="text-muted-foreground">{error}</p>
        <Button onClick={onRetry}>Retry</Button>
      </div>
    )
  }

  if (!catalog || catalog.length === 0) {
    return (
      <p className="py-16 text-center text-muted-foreground">
        No templates available yet.
      </p>
    )
  }

  return (
    <div className="mx-auto max-w-2xl space-y-4 p-6">
      <div>
        <h2 className="text-lg font-semibold">Pick a template to get started</h2>
        <p className="text-sm text-muted-foreground">
          Answer a few questions and your app will be ready to go.
        </p>
      </div>

      <div className="space-y-2">
        {catalog.map((entry) => (
          <Card
            key={entry.id}
            className="cursor-pointer transition-colors hover:bg-muted/50"
            onClick={() => onSelect(entry)}
          >
            <CardContent className="flex items-center gap-4 py-4">
              <Rocket className="size-6 shrink-0 text-primary" />
              <div className="min-w-0 flex-1">
                <div className="font-medium">{entry.name}</div>
                <div className="text-sm text-muted-foreground line-clamp-2">
                  {entry.description}
                </div>
              </div>
              <ChevronRight className="size-5 shrink-0 text-muted-foreground" />
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Phase 2: Question Wizard
// ---------------------------------------------------------------------------

function WizardPhase({
  questions,
  answers,
  fieldLists,
  onSetAnswer,
  onUpdateFieldList,
  onBuild,
  canBuild,
  rendering,
  renderError,
  onAddField,
  onEditField,
}: {
  questions: TemplateQuestion[]
  answers: Record<string, unknown>
  fieldLists: Record<string, FieldEntry[]>
  onSetAnswer: (id: string, value: unknown) => void
  onUpdateFieldList: (id: string, updater: (prev: FieldEntry[]) => FieldEntry[]) => void
  onBuild: () => void
  canBuild: boolean
  rendering: boolean
  renderError: string | null
  onAddField: (questionId: string) => void
  onEditField: (params: { questionId: string; index: number }) => void
}) {
  return (
    <div className="mx-auto flex max-w-2xl flex-col p-6">
      <div className="flex-1 space-y-6">
        {questions.filter((q) => q.id !== 'theme').map((q) => (
          <QuestionField
            key={q.id}
            question={q}
            value={answers[q.id]}
            fields={fieldLists[q.id]}
            allFieldLists={fieldLists}
            onValueChange={(v) => onSetAnswer(q.id, v)}
            onFieldsChange={(updater) => onUpdateFieldList(q.id, updater)}
            onAddField={() => onAddField(q.id)}
            onEditField={(index) => onEditField({ questionId: q.id, index })}
          />
        ))}

        {renderError && (
          <div className="rounded-lg border border-destructive/50 bg-destructive/10 px-4 py-3 text-sm text-destructive">
            {renderError}
          </div>
        )}
      </div>

      <div className="sticky bottom-0 border-t bg-background py-4">
        <Button
          className="w-full"
          onClick={onBuild}
          disabled={rendering || !canBuild}
        >
          {rendering ? (
            <Loader2 className="mr-2 size-4 animate-spin" />
          ) : (
            <Palette className="mr-2 size-4" />
          )}
          {rendering ? 'Loading...' : 'Choose Theme'}
        </Button>
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Individual question renderers
// ---------------------------------------------------------------------------

function QuestionField({
  question,
  value,
  fields,
  allFieldLists,
  onValueChange,
  onFieldsChange,
  onAddField,
  onEditField,
}: {
  question: TemplateQuestion
  value: unknown
  fields?: FieldEntry[]
  allFieldLists: Record<string, FieldEntry[]>
  onValueChange: (v: unknown) => void
  onFieldsChange: (updater: (prev: FieldEntry[]) => FieldEntry[]) => void
  onAddField: () => void
  onEditField: (index: number) => void
}) {
  return (
    <div className="space-y-2">
      <Label className="text-sm font-medium">
        {question.label}
        {question.required && <span className="ml-1 text-destructive">*</span>}
      </Label>

      {question.type === 'text' && (
        <Input
          placeholder={question.placeholder}
          value={(value as string) ?? ''}
          onChange={(e) => onValueChange(e.target.value)}
        />
      )}

      {question.type === 'select' && question.options && (
        <>
          <Select
            value={(value as string) ?? ''}
            onValueChange={(v) => onValueChange(v)}
          >
            <SelectTrigger>
              <SelectValue placeholder={question.placeholder ?? 'Select...'} />
            </SelectTrigger>
            <SelectContent className="max-h-60">
              {question.options.map((opt) => (
                <SelectItem key={opt} value={opt}>
                  {opt.charAt(0).toUpperCase() + opt.slice(1)}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>

          {/* Live theme preview for the theme question */}
          {question.id === 'theme' && value && (
            <ThemePreview themeName={value as string} />
          )}
        </>
      )}

      {question.type === 'checkbox' && (
        <div className="flex items-center gap-2">
          <input
            type="checkbox"
            checked={value === true}
            onChange={(e) => onValueChange(e.target.checked)}
            className="h-4 w-4 rounded border-input accent-primary"
          />
          <span className="text-sm text-muted-foreground">{question.label}</span>
        </div>
      )}

      {question.type === 'field-list' && (
        <FieldListBuilder
          fields={fields ?? []}
          presets={question.presets}
          onChange={onFieldsChange}
          onAddCustom={onAddField}
          onEdit={onEditField}
        />
      )}

      {question.type === 'field-ref' && (
        <FieldRefSelector
          value={value as string | undefined}
          refId={question.ref}
          allFieldLists={allFieldLists}
          placeholder={question.placeholder}
          onChange={(v) => onValueChange(v)}
        />
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Field-list builder
// ---------------------------------------------------------------------------

function FieldListBuilder({
  fields,
  presets,
  onChange,
  onAddCustom,
  onEdit,
}: {
  fields: FieldEntry[]
  presets?: FieldPreset[]
  onChange: (updater: (prev: FieldEntry[]) => FieldEntry[]) => void
  onAddCustom: () => void
  onEdit: (index: number) => void
}) {
  const addedNames = new Set(fields.map((f) => f.name))

  function moveField(from: number, to: number) {
    onChange((prev) => {
      const next = [...prev]
      const [item] = next.splice(from, 1)
      next.splice(to, 0, item)
      return next
    })
  }

  return (
    <div className="space-y-3">
      {/* Preset chips */}
      {presets && presets.length > 0 && (
        <div className="flex flex-wrap gap-2">
          {presets.map((preset) => {
            const isAdded = addedNames.has(preset.name)
            return (
              <button
                key={preset.name}
                onClick={() => {
                  if (isAdded) {
                    onChange((prev) => prev.filter((f) => f.name !== preset.name))
                  } else {
                    onChange((prev) => [...prev, { ...preset }])
                  }
                }}
                className={`inline-flex items-center rounded-full border px-3 py-1 text-xs font-medium transition-colors ${
                  isAdded
                    ? 'border-primary bg-primary/10 text-primary'
                    : 'border-border text-muted-foreground hover:border-primary hover:text-foreground'
                }`}
              >
                {isAdded && <Check className="mr-1 size-3" />}
                {preset.label}
              </button>
            )
          })}
        </div>
      )}

      {/* Field list */}
      {fields.length > 0 && (
        <div className="space-y-1">
          {fields.map((field, idx) => (
            <div
              key={`${field.name}-${idx}`}
              className="flex items-center gap-2 rounded-lg border px-3 py-2"
            >
              {fields.length > 1 && (
                <div className="flex flex-col">
                  <button
                    onClick={() => idx > 0 && moveField(idx, idx - 1)}
                    disabled={idx === 0}
                    className="text-muted-foreground hover:text-foreground disabled:opacity-30"
                  >
                    <GripVertical className="size-4" />
                  </button>
                </div>
              )}
              <div className="min-w-0 flex-1">
                <div className="text-sm font-medium">{field.label}</div>
                <div className="text-xs text-muted-foreground">{field.type}</div>
              </div>
              <button
                onClick={() => onEdit(idx)}
                className="text-muted-foreground hover:text-foreground"
              >
                <Pencil className="size-3.5" />
              </button>
              <button
                onClick={() => onChange((prev) => prev.filter((_, i) => i !== idx))}
                className="text-muted-foreground hover:text-destructive"
              >
                <X className="size-4" />
              </button>
            </div>
          ))}
        </div>
      )}

      <Button variant="outline" size="sm" onClick={onAddCustom}>
        <Plus className="mr-1 size-3.5" />
        Add Custom Field
      </Button>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Field-ref selector
// ---------------------------------------------------------------------------

function FieldRefSelector({
  value,
  refId,
  allFieldLists,
  placeholder,
  onChange,
}: {
  value?: string
  refId?: string
  allFieldLists: Record<string, FieldEntry[]>
  placeholder?: string
  onChange: (v: string) => void
}) {
  const refFields = refId ? allFieldLists[refId] ?? [] : []

  if (refFields.length === 0) {
    return <p className="text-sm text-muted-foreground">Add fields above first</p>
  }

  return (
    <Select value={value ?? ''} onValueChange={(v) => { if (v !== null) onChange(v) }}>
      <SelectTrigger>
        <SelectValue placeholder={placeholder ?? 'Select a field...'} />
      </SelectTrigger>
      <SelectContent>
        {refFields.map((f) => (
          <SelectItem key={f.name} value={f.name}>
            {f.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  )
}

// ---------------------------------------------------------------------------
// Phase 3: Text Review
// ---------------------------------------------------------------------------

function TextReviewPhase({
  texts,
  values,
  onValueChange,
  onFinish,
  saving,
}: {
  texts: ReviewableText[]
  values: Record<string, string>
  onValueChange: (index: number, value: string) => void
  onFinish: () => void
  saving: boolean
}) {
  // Group by category
  const grouped = new Map<string, { text: ReviewableText; index: number }[]>()
  texts.forEach((text, index) => {
    const list = grouped.get(text.category) ?? []
    list.push({ text, index })
    grouped.set(text.category, list)
  })

  return (
    <div className="mx-auto flex max-w-2xl flex-col p-6">
      <div className="flex-1 space-y-6">
        <div>
          <h2 className="text-lg font-semibold">Review the text in your app</h2>
          <p className="text-sm text-muted-foreground">
            These are the labels, titles, and messages your users will see.
            Edit any you'd like to customize.
          </p>
        </div>

        {Array.from(grouped.entries()).map(([category, items]) => (
          <div key={category} className="space-y-3">
            <h3 className="text-sm font-semibold text-primary">{category}</h3>
            {items.map(({ text, index }) => (
              <div key={index} className="space-y-1">
                <Label className="text-xs text-muted-foreground">{text.label}</Label>
                {text.isMultiline ? (
                  <Textarea
                    value={values[String(index)] ?? text.value}
                    onChange={(e) => onValueChange(index, e.target.value)}
                    rows={3}
                    className="text-sm"
                  />
                ) : (
                  <Input
                    value={values[String(index)] ?? text.value}
                    onChange={(e) => onValueChange(index, e.target.value)}
                    className="text-sm"
                  />
                )}
              </div>
            ))}
          </div>
        ))}
      </div>

      <div className="sticky bottom-0 border-t bg-background py-4">
        <Button className="w-full" onClick={onFinish} disabled={saving}>
          {saving ? (
            <Loader2 className="mr-2 size-4 animate-spin" />
          ) : (
            <Check className="mr-2 size-4" />
          )}
          Looks Good — Launch App
        </Button>
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Phase 2.5: Theme Selection
// ---------------------------------------------------------------------------

function ThemePhase({
  catalog,
  selectedTheme,
  colorOverrides,
  onSelectTheme,
  onOverrideChange,
  onResetOverride,
  onContinue,
  rendering,
  renderError,
  brandingLogo,
  onBrandingLogoChange,
  brandingFavicon,
  onBrandingFaviconChange,
  brandingHeaderStyle,
  onBrandingHeaderStyleChange,
  brandingFontFamily,
  onBrandingFontFamilyChange,
}: {
  catalog: Array<{ name: string; displayName: string; tags?: { style?: string; palette?: string } | string[] }> | null
  selectedTheme: string
  colorOverrides: Record<string, string>
  onSelectTheme: (theme: string) => void
  onOverrideChange: (token: string, value: string) => void
  onResetOverride: (token: string) => void
  onContinue: () => void
  rendering: boolean
  renderError: string | null
  brandingLogo: string
  onBrandingLogoChange: (v: string) => void
  brandingFavicon: string
  onBrandingFaviconChange: (v: string) => void
  brandingHeaderStyle: 'light' | 'solid' | 'transparent'
  onBrandingHeaderStyleChange: (v: 'light' | 'solid' | 'transparent') => void
  brandingFontFamily: string
  onBrandingFontFamilyChange: (v: string) => void
}) {
  const [activeStyle, setActiveStyle] = useState<string | null>(null)
  const [activePalette, setActivePalette] = useState<string | null>(null)
  const [brandingOpen, setBrandingOpen] = useState(false)

  // Helper to extract style/palette from tags (supports both old array and new object format)
  const getStyle = (tags?: { style?: string; palette?: string } | string[]): string | undefined =>
    tags && !Array.isArray(tags) ? tags.style : undefined
  const getPalette = (tags?: { style?: string; palette?: string } | string[]): string | undefined =>
    tags && !Array.isArray(tags) ? tags.palette : undefined

  // Collect all unique styles and palettes
  const allStyles = [...new Set((catalog ?? []).map((e) => getStyle(e.tags)).filter(Boolean) as string[])].sort()
  const allPalettes = [...new Set((catalog ?? []).map((e) => getPalette(e.tags)).filter(Boolean) as string[])].sort()

  // Filter and sort themes
  const filteredCatalog = (catalog ?? [])
    .filter((e) => {
      if (activeStyle && getStyle(e.tags) !== activeStyle) return false
      if (activePalette && getPalette(e.tags) !== activePalette) return false
      return true
    })
    .sort((a, b) => a.displayName.localeCompare(b.displayName))

  return (
    <div className="flex h-full flex-col">
      <div className="flex min-h-0 flex-1">
        {/* Left pane — scrollable theme list */}
        <div className="flex w-56 shrink-0 flex-col border-r">
          <div className="px-3 pt-3 pb-1 text-sm font-semibold">Themes</div>

          {/* Two-dimension tag filters */}
          <div className="space-y-1.5 px-3 pb-2">
            {allStyles.length > 0 && (
              <div>
                <div className="mb-0.5 text-[9px] font-semibold uppercase tracking-wider text-muted-foreground">Style</div>
                <div className="flex flex-wrap gap-1">
                  {allStyles.map((tag) => (
                    <button
                      key={tag}
                      type="button"
                      className={`rounded-full px-2 py-0.5 text-[10px] transition-colors ${
                        activeStyle === tag
                          ? 'bg-primary text-primary-foreground'
                          : 'bg-muted text-muted-foreground hover:bg-muted/80'
                      }`}
                      onClick={() => setActiveStyle(activeStyle === tag ? null : tag)}
                    >
                      {tag}
                    </button>
                  ))}
                </div>
              </div>
            )}
            {allPalettes.length > 0 && (
              <div>
                <div className="mb-0.5 text-[9px] font-semibold uppercase tracking-wider text-muted-foreground">Palette</div>
                <div className="flex flex-wrap gap-1">
                  {allPalettes.map((tag) => (
                    <button
                      key={tag}
                      type="button"
                      className={`rounded-full px-2 py-0.5 text-[10px] transition-colors ${
                        activePalette === tag
                          ? 'bg-primary text-primary-foreground'
                          : 'bg-muted text-muted-foreground hover:bg-muted/80'
                      }`}
                      onClick={() => setActivePalette(activePalette === tag ? null : tag)}
                    >
                      {tag}
                    </button>
                  ))}
                </div>
              </div>
            )}
          </div>

          <div className="flex-1 space-y-1 overflow-y-auto px-2 pb-2">
            {filteredCatalog.map((entry) => (
              <ThemeCard
                key={entry.name}
                themeName={entry.name}
                displayName={entry.displayName}
                tags={entry.tags}
                isSelected={entry.name === selectedTheme}
                onSelect={() => onSelectTheme(entry.name)}
              />
            ))}
          </div>
        </div>

        {/* Right pane — preview + color customization */}
        <div className="flex-1 overflow-y-auto p-4">
          <ThemePreviewDual themeName={selectedTheme} overrides={colorOverrides} />

          <h3 className="mt-4 mb-2 text-sm font-semibold">Customize Colors</h3>
          <div className="space-y-1.5">
            <ColorRow label="Primary" token="primary" themeName={selectedTheme} override={colorOverrides['primary']} onChange={(v) => onOverrideChange('primary', v)} onReset={() => onResetOverride('primary')} />
            <ColorRow label="Secondary" token="secondary" themeName={selectedTheme} override={colorOverrides['secondary']} onChange={(v) => onOverrideChange('secondary', v)} onReset={() => onResetOverride('secondary')} />
            <ColorRow label="Accent" token="accent" themeName={selectedTheme} override={colorOverrides['accent']} onChange={(v) => onOverrideChange('accent', v)} onReset={() => onResetOverride('accent')} />
            <ColorRow label="Background" token="base100" themeName={selectedTheme} override={colorOverrides['base100']} onChange={(v) => onOverrideChange('base100', v)} onReset={() => onResetOverride('base100')} />
            <ColorRow label="Text" token="baseContent" themeName={selectedTheme} override={colorOverrides['baseContent']} onChange={(v) => onOverrideChange('baseContent', v)} onReset={() => onResetOverride('baseContent')} />
            <ColorRow label="Error" token="error" themeName={selectedTheme} override={colorOverrides['error']} onChange={(v) => onOverrideChange('error', v)} onReset={() => onResetOverride('error')} />
          </div>

          {/* Collapsible App Branding section */}
          <button
            type="button"
            onClick={() => setBrandingOpen(!brandingOpen)}
            className="mt-4 flex items-center gap-1 text-sm font-semibold hover:text-primary transition-colors"
          >
            {brandingOpen ? <ChevronDown className="size-4" /> : <ChevronRight className="size-4" />}
            App Branding
          </button>

          {brandingOpen && (
            <div className="mt-2 space-y-3 rounded-lg border bg-muted/30 p-3">
              <p className="text-[11px] text-muted-foreground">
                Optional branding options. Leave blank to use defaults.
              </p>

              <div className="space-y-1">
                <Label className="text-xs">Logo URL</Label>
                <Input
                  value={brandingLogo}
                  onChange={(e) => onBrandingLogoChange(e.target.value)}
                  placeholder="https://example.com/logo.png"
                  className="h-8 text-xs"
                />
              </div>

              <div className="space-y-1">
                <Label className="text-xs">Favicon URL</Label>
                <Input
                  value={brandingFavicon}
                  onChange={(e) => onBrandingFaviconChange(e.target.value)}
                  placeholder="https://example.com/favicon.ico"
                  className="h-8 text-xs"
                />
              </div>

              <div className="space-y-1">
                <Label className="text-xs">Header Style</Label>
                <div className="flex gap-1 rounded-lg border p-0.5 w-fit">
                  {(['light', 'solid', 'transparent'] as const).map((style) => (
                    <button
                      key={style}
                      type="button"
                      onClick={() => onBrandingHeaderStyleChange(style)}
                      className={`rounded-md px-3 py-1 text-xs font-medium transition-colors ${
                        brandingHeaderStyle === style
                          ? 'bg-primary text-primary-foreground'
                          : 'text-muted-foreground hover:text-foreground'
                      }`}
                    >
                      {style.charAt(0).toUpperCase() + style.slice(1)}
                    </button>
                  ))}
                </div>
              </div>

              <div className="space-y-1">
                <Label className="text-xs">Font Family</Label>
                <Input
                  value={brandingFontFamily}
                  onChange={(e) => onBrandingFontFamilyChange(e.target.value)}
                  placeholder="e.g., Inter, Georgia"
                  className="h-8 text-xs"
                />
              </div>
            </div>
          )}

          {renderError && (
            <div className="mt-3 rounded-lg border border-destructive/50 bg-destructive/10 px-4 py-3 text-sm text-destructive">
              {renderError}
            </div>
          )}
        </div>
      </div>

      <div className="border-t px-4 py-3">
        <Button className="w-full" onClick={onContinue} disabled={rendering}>
          {rendering ? (
            <Loader2 className="mr-2 size-4 animate-spin" />
          ) : (
            <ChevronRight className="mr-2 size-4" />
          )}
          {rendering ? 'Building...' : 'Continue'}
        </Button>
      </div>
    </div>
  )
}

function ThemeCard({
  themeName,
  displayName,
  tags,
  isSelected,
  onSelect,
}: {
  themeName: string
  displayName: string
  tags?: { style?: string; palette?: string } | string[]
  isSelected: boolean
  onSelect: () => void
}) {
  const [colors, setColors] = useState<Record<string, string> | null>(null)

  useEffect(() => {
    let cancelled = false
    fetch(`${THEMES_BASE}/${themeName}.json`)
      .then((r) => r.json())
      .then((data) => {
        if (cancelled) return
        const variant = data.light ?? data.dark
        setColors(variant?.colors ?? null)
      })
      .catch(() => {})
    return () => { cancelled = true }
  }, [themeName])

  return (
    <button
      type="button"
      onClick={onSelect}
      className={`flex flex-col gap-1 rounded-lg border px-3 py-2 text-left text-sm transition-colors ${
        isSelected
          ? 'border-primary bg-primary/5 font-semibold ring-1 ring-primary'
          : 'border-border hover:border-primary/50 hover:bg-muted/50'
      }`}
    >
      <div className="flex w-full items-center gap-2">
        {colors && (
          <div className="flex gap-0.5">
            <span className="size-3 rounded-full border border-black/10" style={{ background: colors.primary }} />
            <span className="size-3 rounded-full border border-black/10" style={{ background: colors.secondary }} />
            <span className="size-3 rounded-full border border-black/10" style={{ background: colors.accent }} />
          </div>
        )}
        <span className="flex-1 truncate">{displayName}</span>
        {isSelected && <Check className="size-3.5 shrink-0 text-primary" />}
      </div>
      {tags && !Array.isArray(tags) && (tags.style || tags.palette) && (
        <div className="flex flex-wrap gap-1">
          {tags.style && <span className="rounded-full bg-muted px-1.5 py-px text-[9px] text-muted-foreground">{tags.style}</span>}
          {tags.palette && <span className="rounded-full bg-muted px-1.5 py-px text-[9px] text-muted-foreground">{tags.palette}</span>}
        </div>
      )}
    </button>
  )
}

function ThemePreviewDual({ themeName, overrides }: { themeName: string; overrides: Record<string, string> }) {
  return (
    <div className="grid grid-cols-2 gap-3">
      <div>
        <div className="mb-1 text-xs font-medium text-muted-foreground">Light</div>
        <ThemePreviewFull themeName={themeName} overrides={overrides} mode="light" />
      </div>
      <div>
        <div className="mb-1 text-xs font-medium text-muted-foreground">Dark</div>
        <ThemePreviewFull themeName={themeName} overrides={overrides} mode="dark" />
      </div>
    </div>
  )
}

function ThemePreviewFull({ themeName, overrides, mode }: { themeName: string; overrides: Record<string, string>; mode: 'light' | 'dark' }) {
  const [themeData, setThemeData] = useState<Record<string, unknown> | null>(null)

  useEffect(() => {
    let cancelled = false
    fetch(`${THEMES_BASE}/${themeName}.json`)
      .then((r) => r.json())
      .then((data) => {
        if (!cancelled) setThemeData(data)
      })
      .catch(() => { if (!cancelled) setThemeData(null) })
    return () => { cancelled = true }
  }, [themeName])

  if (!themeData) return null

  const variant = (themeData[mode] ?? themeData.light ?? themeData.dark) as Record<string, unknown> | undefined
  const colors = (variant?.['colors'] as Record<string, string>) ?? null
  const design = (variant?.['design'] ?? (themeData['design'] as Record<string, string>)) as Record<string, string> | null

  if (!colors) return null

  // Merge overrides
  const c = { ...colors, ...overrides }

  const radius = design?.radiusBox ?? '.5rem'
  const primary = c.primary ?? 'oklch(45% .24 277)'
  const primaryContent = c.primaryContent ?? 'oklch(93% .034 273)'
  const secondary = c.secondary ?? 'oklch(65% .241 354)'
  const secondaryContent = c.secondaryContent ?? 'oklch(94% .028 342)'
  const accent = c.accent ?? 'oklch(77% .152 182)'
  const base100 = c.base100 ?? 'oklch(100% 0 0)'
  const base200 = c.base200 ?? 'oklch(98% 0 0)'
  const base300 = c.base300 ?? 'oklch(95% 0 0)'
  const baseContent = c.baseContent ?? 'oklch(21% .006 286)'
  const success = c.success ?? 'oklch(76% .177 163)'
  const error = c.error ?? 'oklch(71% .194 13)'

  return (
    <div className="overflow-hidden border" style={{ background: base100, color: baseContent, borderRadius: radius, borderColor: base300 }}>
      {/* Mini app bar */}
      <div className="flex items-center gap-2 px-4 py-2" style={{ background: base200, borderBottom: `1px solid ${base300}` }}>
        <div className="h-2 w-2 rounded-full" style={{ background: primary }} />
        <span className="text-xs font-semibold" style={{ color: baseContent }}>Preview</span>
        <span className="flex-1" />
        <span className="text-[10px]" style={{ color: accent }}>
          {themeName.charAt(0).toUpperCase() + themeName.slice(1)}
        </span>
      </div>

      {/* Content */}
      <div className="space-y-3 p-4">
        <div>
          <div className="text-sm font-semibold" style={{ color: baseContent }}>Sample Heading</div>
          <div className="text-xs" style={{ color: baseContent, opacity: 0.7 }}>This is how body text will look.</div>
        </div>
        <div className="px-3 py-1.5 text-xs" style={{ background: base200, border: `1px solid ${base300}`, borderRadius: radius, color: baseContent, opacity: 0.6 }}>
          Input field...
        </div>
        <div className="flex gap-2">
          <div className="px-3 py-1 text-xs font-medium" style={{ background: primary, color: primaryContent, borderRadius: radius }}>Primary</div>
          <div className="px-3 py-1 text-xs font-medium" style={{ background: secondary, color: secondaryContent, borderRadius: radius }}>Secondary</div>
          <div className="px-3 py-1 text-xs font-medium" style={{ background: accent, color: c.accentContent, borderRadius: radius }}>Accent</div>
        </div>
        <div className="flex gap-2">
          <span className="rounded-full px-2 py-0.5 text-[10px] font-medium" style={{ background: success, color: c.successContent }}>Success</span>
          <span className="rounded-full px-2 py-0.5 text-[10px] font-medium" style={{ background: error, color: c.errorContent }}>Error</span>
          <span className="rounded-full px-2 py-0.5 text-[10px] font-medium" style={{ background: c.warning, color: c.warningContent }}>Warning</span>
        </div>
      </div>
    </div>
  )
}

// ColorRow, GridColorPicker, WhyAccessiblePopover, COLOR_GRID, TOKEN_HINTS, TOKEN_PAIRS
// are now imported from @/components/ColorCustomizer.tsx

// ---------------------------------------------------------------------------
// Add Field Dialog
// ---------------------------------------------------------------------------

const FIELD_TYPES = [
  { value: 'text', label: 'Text' },
  { value: 'number', label: 'Number' },
  { value: 'date', label: 'Date' },
  { value: 'datetime', label: 'Date & Time' },
  { value: 'select', label: 'Dropdown' },
  { value: 'multiline', label: 'Long Text' },
  { value: 'email', label: 'Email' },
  { value: 'checkbox', label: 'Checkbox' },
]

function AddFieldDialog({
  open,
  onOpenChange,
  onAdd,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  onAdd: (field: FieldEntry) => void
}) {
  const [name, setName] = useState('')
  const [type, setType] = useState('text')
  const [options, setOptions] = useState('')

  function handleAdd() {
    if (!name.trim()) return
    const field: FieldEntry = {
      name: toCamelCase(name.trim()),
      label: name.trim(),
      type,
    }
    if (type === 'select' && options.trim()) {
      field.options = options.split(',').map((s) => s.trim()).filter(Boolean)
    }
    onAdd(field)
    setName('')
    setType('text')
    setOptions('')
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-sm">
        <DialogHeader>
          <DialogTitle>Add Field</DialogTitle>
          <DialogDescription>Define a custom field for your app.</DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-2">
            <Label>Field Name</Label>
            <Input
              placeholder="e.g., Due Date, Priority"
              value={name}
              onChange={(e) => setName(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleAdd()}
              autoFocus
            />
          </div>
          <div className="space-y-2">
            <Label>Type</Label>
            <Select value={type} onValueChange={(v) => { if (v !== null) setType(v) }}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {FIELD_TYPES.map((ft) => (
                  <SelectItem key={ft.value} value={ft.value}>
                    {ft.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          {type === 'select' && (
            <div className="space-y-2">
              <Label>Options (comma-separated)</Label>
              <Input
                placeholder="e.g., Low, Medium, High"
                value={options}
                onChange={(e) => setOptions(e.target.value)}
              />
            </div>
          )}
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
            <Button onClick={handleAdd} disabled={!name.trim()}>Add</Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}

// ---------------------------------------------------------------------------
// Edit Field Dialog
// ---------------------------------------------------------------------------

function EditFieldDialog({
  open,
  onOpenChange,
  field,
  onSave,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  field?: FieldEntry
  onSave: (updated: FieldEntry) => void
}) {
  const [label, setLabel] = useState(field?.label ?? '')
  const [options, setOptions] = useState(field?.options?.join(', ') ?? '')

  useEffect(() => {
    if (field) {
      setLabel(field.label)
      setOptions(field.options?.join(', ') ?? '')
    }
  }, [field])

  if (!field) return null

  function handleSave() {
    if (!label.trim() || !field) return
    const updated: FieldEntry = {
      ...field,
      label: label.trim(),
      name: toCamelCase(label.trim()),
    }
    if (field.type === 'select') {
      updated.options = options.split(',').map((s) => s.trim()).filter(Boolean)
    }
    onSave(updated)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-sm">
        <DialogHeader>
          <DialogTitle>Edit Field</DialogTitle>
          <DialogDescription>Update the field name or options.</DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-2">
            <Label>Display Name</Label>
            <Input
              value={label}
              onChange={(e) => setLabel(e.target.value)}
              autoFocus
            />
          </div>
          {field.type === 'select' && (
            <div className="space-y-2">
              <Label>Options (comma-separated)</Label>
              <Input
                value={options}
                onChange={(e) => setOptions(e.target.value)}
              />
            </div>
          )}
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
            <Button onClick={handleSave} disabled={!label.trim()}>Save</Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}

// ---------------------------------------------------------------------------
// Text extraction (mirrors Flutter's _extractReviewableTexts)
// ---------------------------------------------------------------------------

function extractReviewableTexts(spec: Record<string, unknown>): ReviewableText[] {
  const results: ReviewableText[] = []

  // App name
  if (typeof spec['appName'] === 'string') {
    results.push({ path: ['appName'], label: 'App Name', category: 'App', value: spec['appName'] })
  }

  // Help overview
  const help = spec['help'] as Record<string, unknown> | undefined
  if (help && typeof help['overview'] === 'string') {
    results.push({
      path: ['help', 'overview'],
      label: 'Help Overview',
      category: 'Help & Guidance',
      value: help['overview'] as string,
      isMultiline: true,
    })
    const pageHelp = help['pages'] as Record<string, unknown> | undefined
    if (pageHelp) {
      for (const [key, val] of Object.entries(pageHelp)) {
        if (typeof val === 'string') {
          results.push({
            path: ['help', 'pages', key],
            label: `Help: ${key}`,
            category: 'Help & Guidance',
            value: val,
            isMultiline: true,
          })
        }
      }
    }
  }

  // Tour steps
  const tour = spec['tour'] as unknown[]
  if (Array.isArray(tour)) {
    tour.forEach((step, i) => {
      const s = step as Record<string, unknown>
      if (typeof s['title'] === 'string') {
        results.push({ path: ['tour', String(i), 'title'], label: `Tour Step ${i + 1} Title`, category: 'Help & Guidance', value: s['title'] as string })
      }
      if (typeof s['content'] === 'string') {
        results.push({ path: ['tour', String(i), 'content'], label: `Tour Step ${i + 1} Text`, category: 'Help & Guidance', value: s['content'] as string, isMultiline: true })
      }
    })
  }

  // Pages
  const pages = spec['pages'] as Record<string, unknown> | undefined
  if (pages) {
    for (const [pageId, pageVal] of Object.entries(pages)) {
      const page = pageVal as Record<string, unknown>
      const pageTitle = (page['title'] as string) ?? pageId

      if (typeof page['title'] === 'string') {
        results.push({ path: ['pages', pageId, 'title'], label: 'Page Title', category: `Page: ${pageTitle}`, value: page['title'] as string })
      }

      const content = page['content'] as unknown[]
      if (Array.isArray(content)) {
        extractFromComponents(content, ['pages', pageId, 'content'], pageTitle, results)
      }
    }
  }

  // Menu labels
  const menu = spec['menu'] as unknown[]
  if (Array.isArray(menu)) {
    menu.forEach((item, i) => {
      const m = item as Record<string, unknown>
      if (typeof m['label'] === 'string') {
        results.push({ path: ['menu', String(i), 'label'], label: `Menu Item ${i + 1}`, category: 'Navigation', value: m['label'] as string })
      }
    })
  }

  return results
}

function extractFromComponents(
  components: unknown[],
  basePath: string[],
  pageTitle: string,
  results: ReviewableText[],
) {
  components.forEach((comp, i) => {
    const c = comp as Record<string, unknown>
    const type = c['component'] as string | undefined
    const path = [...basePath, String(i)]

    switch (type) {
      case 'text': {
        const content = c['content'] as string | undefined
        if (content && !isAggregateOnly(content)) {
          results.push({ path: [...path, 'content'], label: 'Text', category: `Page: ${pageTitle}`, value: content, isMultiline: content.length > 60 })
        }
        break
      }
      case 'button': {
        if (typeof c['label'] === 'string') {
          results.push({ path: [...path, 'label'], label: 'Button Label', category: `Page: ${pageTitle}`, value: c['label'] as string })
        }
        const onClick = c['onClick'] as unknown[]
        if (Array.isArray(onClick)) {
          onClick.forEach((action, j) => {
            const a = action as Record<string, unknown>
            if (a['action'] === 'showMessage' && typeof a['message'] === 'string') {
              results.push({ path: [...path, 'onClick', String(j), 'message'], label: 'Success Message', category: `Page: ${pageTitle}`, value: a['message'] as string })
            }
          })
        }
        break
      }
      case 'summary':
        if (typeof c['label'] === 'string') {
          results.push({ path: [...path, 'label'], label: 'Summary Card Label', category: `Page: ${pageTitle}`, value: c['label'] as string })
        }
        break
      case 'chart':
        if (typeof c['title'] === 'string') {
          results.push({ path: [...path, 'title'], label: 'Chart Title', category: `Page: ${pageTitle}`, value: c['title'] as string })
        }
        break
      case 'list': {
        const rowActions = c['rowActions'] as unknown[]
        if (Array.isArray(rowActions)) {
          rowActions.forEach((ra, j) => {
            const a = ra as Record<string, unknown>
            if (typeof a['label'] === 'string') {
              results.push({ path: [...path, 'rowActions', String(j), 'label'], label: 'Row Action', category: `Page: ${pageTitle}`, value: a['label'] as string })
            }
            if (typeof a['confirm'] === 'string') {
              results.push({ path: [...path, 'rowActions', String(j), 'confirm'], label: 'Confirmation Text', category: `Page: ${pageTitle}`, value: a['confirm'] as string })
            }
          })
        }
        break
      }
      case 'tabs': {
        const tabs = c['tabs'] as unknown[]
        if (Array.isArray(tabs)) {
          tabs.forEach((tab, t) => {
            const tb = tab as Record<string, unknown>
            if (typeof tb['label'] === 'string') {
              results.push({ path: [...path, 'tabs', String(t), 'label'], label: 'Tab Label', category: `Page: ${pageTitle}`, value: tb['label'] as string })
            }
            const tabContent = tb['content'] as unknown[]
            if (Array.isArray(tabContent)) {
              extractFromComponents(tabContent, [...path, 'tabs', String(t), 'content'], pageTitle, results)
            }
          })
        }
        break
      }
    }
  })
}

function isAggregateOnly(text: string): boolean {
  const stripped = text.replace(/\{[A-Z]+\([^}]*\)\}/g, '').trim()
  return stripped === '' || /^[%,\s]*$/.test(stripped)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function setNestedValue(root: unknown, path: string[], value: string): void {
  let current: unknown = root
  for (let i = 0; i < path.length - 1; i++) {
    const key = path[i]
    if (current && typeof current === 'object' && !Array.isArray(current)) {
      current = (current as Record<string, unknown>)[key]
    } else if (Array.isArray(current)) {
      const idx = parseInt(key, 10)
      if (!isNaN(idx) && idx < current.length) {
        current = current[idx]
      } else {
        return
      }
    } else {
      return
    }
  }
  const lastKey = path[path.length - 1]
  if (current && typeof current === 'object' && !Array.isArray(current)) {
    (current as Record<string, unknown>)[lastKey] = value
  } else if (Array.isArray(current)) {
    const idx = parseInt(lastKey, 10)
    if (!isNaN(idx) && idx < current.length) {
      current[idx] = value
    }
  }
}

function toCamelCase(input: string): string {
  const words = input.split(/[\s_-]+/)
  if (words.length === 0) return input.toLowerCase()
  const first = words[0].toLowerCase()
  const rest = words.slice(1).map((w) => {
    if (!w) return ''
    return w[0].toUpperCase() + w.substring(1).toLowerCase()
  })
  return first + rest.join('')
}

// ---------------------------------------------------------------------------
// ThemePreview — shows sample UI elements styled with the selected theme
// ---------------------------------------------------------------------------

const THEMES_BASE = 'https://one-does-simply.github.io/Specification/Themes'

function ThemePreview({ themeName }: { themeName: string }) {
  const [colors, setColors] = useState<Record<string, string> | null>(null)
  const [design, setDesign] = useState<Record<string, string> | null>(null)

  useEffect(() => {
    let cancelled = false
    fetch(`${THEMES_BASE}/${themeName}.json`)
      .then((r) => r.json())
      .then((data) => {
        if (cancelled) return
        // Use light variant for the preview
        const variant = data.light ?? data.dark
        setColors(variant?.colors ?? null)
        setDesign(variant?.design ?? null)
      })
      .catch(() => {
        if (!cancelled) { setColors(null); setDesign(null) }
      })
    return () => { cancelled = true }
  }, [themeName])

  if (!colors) return null

  const radius = design?.radiusBox ?? '.5rem'
  const primary = colors.primary ?? 'oklch(45% .24 277)'
  const primaryContent = colors.primaryContent ?? 'oklch(93% .034 273)'
  const secondary = colors.secondary ?? 'oklch(65% .241 354)'
  const secondaryContent = colors.secondaryContent ?? 'oklch(94% .028 342)'
  const accent = colors.accent ?? 'oklch(77% .152 182)'
  const base100 = colors.base100 ?? 'oklch(100% 0 0)'
  const base200 = colors.base200 ?? 'oklch(98% 0 0)'
  const base300 = colors.base300 ?? 'oklch(95% 0 0)'
  const baseContent = colors.baseContent ?? 'oklch(21% .006 286)'
  const success = colors.success ?? 'oklch(76% .177 163)'
  const error = colors.error ?? 'oklch(71% .194 13)'

  return (
    <div
      className="mt-3 overflow-hidden border"
      style={{ background: base100, color: baseContent, borderRadius: radius, borderColor: base300 }}
    >
      {/* Mini app bar */}
      <div className="flex items-center gap-2 px-4 py-2" style={{ background: base200, borderBottom: `1px solid ${base300}` }}>
        <div className="h-2 w-2 rounded-full" style={{ background: primary }} />
        <span className="text-xs font-semibold" style={{ color: baseContent }}>Preview</span>
        <span className="flex-1" />
        <span className="text-[10px]" style={{ color: accent }}>
          {themeName.charAt(0).toUpperCase() + themeName.slice(1)}
        </span>
      </div>

      {/* Content */}
      <div className="space-y-3 p-4">
        {/* Sample text */}
        <div>
          <div className="text-sm font-semibold" style={{ color: baseContent }}>Sample Heading</div>
          <div className="text-xs" style={{ color: baseContent, opacity: 0.7 }}>This is how body text will look.</div>
        </div>

        {/* Sample input */}
        <div
          className="px-3 py-1.5 text-xs"
          style={{ background: base200, border: `1px solid ${base300}`, borderRadius: radius, color: baseContent, opacity: 0.6 }}
        >
          Input field...
        </div>

        {/* Buttons */}
        <div className="flex gap-2">
          <div
            className="px-3 py-1 text-xs font-medium"
            style={{ background: primary, color: primaryContent, borderRadius: radius }}
          >
            Primary
          </div>
          <div
            className="px-3 py-1 text-xs font-medium"
            style={{ background: secondary, color: secondaryContent, borderRadius: radius }}
          >
            Secondary
          </div>
          <div
            className="px-3 py-1 text-xs font-medium"
            style={{ background: accent, color: colors.accentContent, borderRadius: radius }}
          >
            Accent
          </div>
        </div>

        {/* Status badges */}
        <div className="flex gap-2">
          <span className="rounded-full px-2 py-0.5 text-[10px] font-medium" style={{ background: success, color: colors.successContent }}>Success</span>
          <span className="rounded-full px-2 py-0.5 text-[10px] font-medium" style={{ background: error, color: colors.errorContent }}>Error</span>
          <span className="rounded-full px-2 py-0.5 text-[10px] font-medium" style={{ background: colors.warning, color: colors.warningContent }}>Warning</span>
        </div>
      </div>
    </div>
  )
}

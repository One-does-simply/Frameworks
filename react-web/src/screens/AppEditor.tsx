import { useState, useEffect, useRef } from 'react'
import { useParams, useNavigate, Link } from 'react-router'
import { AppRegistry, type AppRecord } from '@/engine/app-registry.ts'
import { parseSpec, isOk } from '@/parser/spec-parser.ts'
import type { ValidationMessage } from '@/parser/spec-validator.ts'
import pb from '@/lib/pocketbase.ts'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'
import { Badge } from '@/components/ui/badge'
import { toast } from 'sonner'
import { ArrowLeft, ExternalLink, Check, AlertTriangle, Loader2 } from 'lucide-react'

// ---------------------------------------------------------------------------
// AppEditor — JSON spec editor for a single app
// ---------------------------------------------------------------------------

export function AppEditor() {
  const { appId } = useParams<{ appId: string }>()
  const navigate = useNavigate()
  const registry = useRef(new AppRegistry(pb)).current

  const [app, setApp] = useState<AppRecord | null>(null)
  const [loading, setLoading] = useState(true)
  const [specText, setSpecText] = useState('')
  const [saving, setSaving] = useState(false)
  const [dirty, setDirty] = useState(false)
  const [messages, setMessages] = useState<ValidationMessage[]>([])

  // Load app record
  useEffect(() => {
    async function load() {
      if (!appId) return
      setLoading(true)
      try {
        const record = await pb.collection('_ods_apps').getOne(appId, { requestKey: null })
        const appRecord: AppRecord = {
          id: record.id,
          name: record['name'] as string,
          slug: record['slug'] as string,
          specJson: typeof record['specJson'] === 'string' ? record['specJson'] : JSON.stringify(record['specJson']),
          status: (record['status'] as string) === 'archived' ? 'archived' : 'active',
          description: (record['description'] as string) ?? '',
          created: record.created,
          updated: record.updated,
        }
        setApp(appRecord)

        // Pretty-print the JSON for editing
        try {
          const parsed = JSON.parse(appRecord.specJson)
          setSpecText(JSON.stringify(parsed, null, 2))
        } catch {
          setSpecText(appRecord.specJson)
        }
      } catch {
        toast.error('App not found')
        navigate('/admin')
      }
      setLoading(false)
    }
    load()
  }, [appId, navigate])

  // -------------------------------------------------------------------------
  // Validate
  // -------------------------------------------------------------------------

  function handleValidate() {
    setMessages([])
    const result = parseSpec(specText)

    if (result.parseError) {
      setMessages([{ level: 'error', message: result.parseError }])
      return
    }

    setMessages(result.validation.messages)

    if (isOk(result)) {
      toast.success('Spec is valid')
    } else {
      toast.warning('Validation found issues')
    }
  }

  // -------------------------------------------------------------------------
  // Save
  // -------------------------------------------------------------------------

  async function handleSave() {
    if (!app) return

    // Validate first
    const result = parseSpec(specText)
    if (result.parseError) {
      setMessages([{ level: 'error', message: result.parseError }])
      toast.error('Fix JSON errors before saving')
      return
    }
    if (!isOk(result)) {
      const errors = result.validation.messages.filter((m) => m.level === 'error')
      if (errors.length > 0) {
        setMessages(result.validation.messages)
        toast.error('Fix validation errors before saving')
        return
      }
    }

    setSaving(true)
    const success = await registry.updateApp(app.id, specText)
    setSaving(false)

    if (success) {
      setDirty(false)
      toast.success('App spec saved')
    } else {
      toast.error('Failed to save')
    }
  }

  // -------------------------------------------------------------------------
  // Render
  // -------------------------------------------------------------------------

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background">
        <Loader2 className="size-5 animate-spin text-muted-foreground" />
      </div>
    )
  }

  if (!app) return null

  const errorCount = messages.filter((m) => m.level === 'error').length
  const warningCount = messages.filter((m) => m.level === 'warning').length

  return (
    <div className="flex min-h-screen flex-col bg-background">
      {/* Top bar */}
      <header className="sticky top-0 z-40 flex h-14 items-center gap-3 border-b bg-background/95 px-4 supports-backdrop-filter:backdrop-blur-sm">
        <Button variant="ghost" size="icon-sm" onClick={() => navigate('/admin')}>
          <ArrowLeft className="size-5" />
        </Button>
        <div className="min-w-0 flex-1">
          <h1 className="truncate text-base font-semibold">Edit: {app.name}</h1>
          <p className="truncate text-xs text-muted-foreground">/{app.slug}</p>
        </div>
        <Button variant="outline" size="sm">
          <Link to={`/${app.slug}`}>
            <ExternalLink className="mr-1 size-3.5" />
            Open App
          </Link>
        </Button>
        <Button variant="outline" size="sm" onClick={handleValidate}>
          <Check className="mr-1 size-3.5" />
          Validate
        </Button>
        <Button size="sm" onClick={handleSave} disabled={saving || !dirty}>
          {saving && <Loader2 className="mr-1 size-3.5 animate-spin" />}
          Save
        </Button>
      </header>

      {/* Validation messages */}
      {messages.length > 0 && (
        <div className="border-b bg-muted/30 px-4 py-3">
          <div className="mb-2 flex gap-3 text-sm">
            {errorCount > 0 && (
              <Badge variant="destructive">
                {errorCount} error{errorCount !== 1 ? 's' : ''}
              </Badge>
            )}
            {warningCount > 0 && (
              <Badge variant="secondary">
                {warningCount} warning{warningCount !== 1 ? 's' : ''}
              </Badge>
            )}
          </div>
          <ul className="max-h-40 space-y-1 overflow-y-auto text-sm">
            {messages.map((m, i) => (
              <li key={i} className="flex items-start gap-2">
                {m.level === 'error' ? (
                  <AlertTriangle className="mt-0.5 size-3.5 shrink-0 text-destructive" />
                ) : (
                  <AlertTriangle className="mt-0.5 size-3.5 shrink-0 text-amber-500" />
                )}
                <span className={m.level === 'error' ? 'text-destructive' : 'text-amber-700 dark:text-amber-400'}>
                  {m.context && <code className="mr-1 rounded bg-muted px-1 text-xs">{m.context}</code>}
                  {m.message}
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Editor */}
      <div className="flex-1 p-4">
        <Textarea
          value={specText}
          onChange={(e) => {
            setSpecText(e.target.value)
            setDirty(true)
          }}
          className="h-full min-h-[calc(100vh-12rem)] resize-none font-mono text-xs leading-relaxed"
          spellCheck={false}
        />
      </div>
    </div>
  )
}

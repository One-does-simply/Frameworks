import { useState, useEffect, useRef, useCallback } from 'react'
import { useNavigate, Link } from 'react-router'
import { AppRegistry, type AppRecord } from '@/engine/app-registry.ts'
import { logError } from '@/engine/log-service.ts'
import { parseSpec, isOk } from '@/parser/spec-parser.ts'
import { loadFromFile, loadFromUrl, loadFromText } from '@/engine/spec-loader.ts'
import pb from '@/lib/pocketbase.ts'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import { Badge } from '@/components/ui/badge'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog'
import {
  AlertDialog,
  AlertDialogContent,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogAction,
  AlertDialogCancel,
} from '@/components/ui/alert-dialog'
import { toast } from 'sonner'
import {
  FileUp,
  Loader2,
  Pencil,
  Sparkles,
  Archive,
  ArchiveRestore,
  Trash2,
  ChevronDown,
  ChevronRight,
  Plus,
  BookOpen,
  Sun,
  Moon,
  Monitor,
  Zap,
  LayoutGrid,
  MoreVertical,
  Play,
  Link2,
  Download,
  Code,
  Star,
  Info,
  Settings as SettingsIcon,
  LogOut,
  Link as LinkIcon,
} from 'lucide-react'
import { ExampleCatalogDialog } from './ExampleCatalogDialog.tsx'
import { DataExportDialog } from './DataExportDialog.tsx'
import { GenerateCodeDialog } from './GenerateCodeDialog.tsx'
import { DataService } from '@/engine/data-service.ts'
import type { OdsApp } from '@/models/ods-app.ts'
import {
  OnboardingScreen,
  isOnboardingComplete,
} from './OnboardingScreen.tsx'
import {
  getThemeMode,
  setThemeMode,
  type ThemeMode,
} from '@/engine/theme-store.ts'
import {
  getDefaultAppSlug,
  setDefaultAppSlug,
  ensureDefaultApp,
} from '@/engine/default-app-store.ts'

// ---------------------------------------------------------------------------
// AdminDashboard — manage all ODS apps
// ---------------------------------------------------------------------------

type LoadMode = 'file' | 'url' | 'paste' | null

export function AdminDashboard() {
  const navigate = useNavigate()
  const registry = useRef(new AppRegistry(pb)).current

  const [apps, setApps] = useState<AppRecord[]>([])
  const [loading, setLoading] = useState(true)
  const [archivedOpen, setArchivedOpen] = useState(false)
  const [catalogOpen, setCatalogOpen] = useState(false)
  const [showOnboarding, setShowOnboarding] = useState(false)
  const [theme, setTheme] = useState<ThemeMode>(getThemeMode)
  const [defaultSlug, setDefaultSlug] = useState<string | null>(getDefaultAppSlug)

  // Add app state
  const [mode, setMode] = useState<LoadMode>(null)
  const [urlInput, setUrlInput] = useState('')
  const [pasteInput, setPasteInput] = useState('')
  const [localError, setLocalError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const fileInputRef = useRef<HTMLInputElement>(null)

  // Delete confirmation
  const [deleteTarget, setDeleteTarget] = useState<AppRecord | null>(null)

  // Off-ramp dialogs
  const [exportTarget, setExportTarget] = useState<{ app: OdsApp; dataService: DataService } | null>(null)
  const [generateTarget, setGenerateTarget] = useState<OdsApp | null>(null)

  const activeApps = apps.filter((a) => a.status === 'active')
  const archivedApps = apps.filter((a) => a.status === 'archived')

  // -------------------------------------------------------------------------
  // Load app list
  // -------------------------------------------------------------------------

  const loadApps = useCallback(async () => {
    setLoading(true)
    const list = await registry.listApps()
    setApps(list)
    setLoading(false)

    // Ensure first active app becomes default if none set
    const active = list.filter((a) => a.status === 'active')
    if (active.length > 0) {
      ensureDefaultApp(active[0].slug)
      setDefaultSlug(getDefaultAppSlug())
    }

    // Show onboarding if this is first visit and no apps exist
    if (list.length === 0 && !isOnboardingComplete()) {
      setShowOnboarding(true)
    }
  }, [registry])

  useEffect(() => {
    loadApps()
  }, [loadApps])

  // Shared install handler for onboarding + catalog dialog
  async function installExample(name: string, specJson: string, description: string) {
    await registry.saveApp(name, specJson, description)
  }

  // -------------------------------------------------------------------------
  // Save new app from spec JSON
  // -------------------------------------------------------------------------

  async function saveSpec(jsonString: string) {
    setLocalError(null)
    setSaving(true)

    // Validate the spec first
    const result = parseSpec(jsonString)
    if (result.parseError) {
      setLocalError(result.parseError)
      setSaving(false)
      return
    }
    if (!isOk(result)) {
      const errorMsg = result.validation.messages
        .filter((m) => m.level === 'error')
        .map((m) => m.message)
        .join('\n')
      setLocalError(errorMsg)
      setSaving(false)
      return
    }

    const appName = result.app!.appName
    const description = result.app!.help?.overview ?? ''

    try {
      const saved = await registry.saveApp(appName, jsonString, description)
      setSaving(false)

      if (saved) {
        toast.success(`App "${appName}" saved`)
        setMode(null)
        setUrlInput('')
        setPasteInput('')
        await loadApps()
        navigate(`/${saved.slug}`)
      } else {
        setLocalError('Failed to save app to PocketBase')
      }
    } catch (e) {
      setSaving(false)
      const msg = e instanceof Error ? e.message : String(e)
      logError('AdminDashboard', 'Save app error', e)
      setLocalError(`Failed to save app: ${msg}`)
    }
  }

  // -------------------------------------------------------------------------
  // File loading
  // -------------------------------------------------------------------------

  async function handleFileSelect(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    try {
      const text = await loadFromFile(file)
      await saveSpec(text)
    } catch (err) {
      setLocalError(err instanceof Error ? err.message : 'Failed to read file')
    }
    if (fileInputRef.current) fileInputRef.current.value = ''
  }

  async function handleUrlLoad() {
    if (!urlInput.trim()) {
      setLocalError('Please enter a URL')
      return
    }
    try {
      const text = await loadFromUrl(urlInput.trim())
      await saveSpec(text)
    } catch (err) {
      setLocalError(err instanceof Error ? err.message : 'Failed to fetch from URL')
    }
  }

  async function handlePasteLoad() {
    try {
      const text = loadFromText(pasteInput)
      await saveSpec(text)
    } catch (err) {
      setLocalError(err instanceof Error ? err.message : 'Invalid JSON')
    }
  }

  // -------------------------------------------------------------------------
  // App actions
  // -------------------------------------------------------------------------

  async function handleArchive(app: AppRecord) {
    const success = await registry.archiveApp(app.id)
    if (success) {
      toast.success(`"${app.name}" archived`)
      await loadApps()
    } else {
      toast.error('Failed to archive app')
    }
  }

  async function handleRestore(app: AppRecord) {
    const success = await registry.restoreApp(app.id)
    if (success) {
      toast.success(`"${app.name}" restored`)
      await loadApps()
    } else {
      toast.error('Failed to restore app')
    }
  }

  async function handleDelete() {
    if (!deleteTarget) return
    const success = await registry.deleteApp(deleteTarget.id)
    if (success) {
      toast.success(`"${deleteTarget.name}" deleted`)
      setDeleteTarget(null)
      await loadApps()
    } else {
      toast.error('Failed to delete app')
      setDeleteTarget(null)
    }
  }

  // -------------------------------------------------------------------------
  // Off-ramp: parse spec -> open dialog
  // -------------------------------------------------------------------------

  function handleExportData(appRecord: AppRecord) {
    const result = parseSpec(appRecord.specJson)
    if (!result.app) {
      toast.error('Could not parse app spec')
      return
    }
    const ds = new DataService(pb)
    ds.initialize(result.app.appName)
    setExportTarget({ app: result.app, dataService: ds })
  }

  function handleSetDefault(app: AppRecord) {
    setDefaultAppSlug(app.slug)
    setDefaultSlug(app.slug)
    toast.success(`"${app.name}" set as default app`)
  }

  function handleLogout() {
    pb.authStore.clear()
    navigate('/')
    window.location.reload()
  }

  function handleCopyUrl(app: AppRecord) {
    const url = `${window.location.origin}/${app.slug}`
    navigator.clipboard.writeText(url)
    toast.success(`URL copied: ${url}`)
  }

  function handleGenerateCode(appRecord: AppRecord) {
    const result = parseSpec(appRecord.specJson)
    if (!result.app) {
      toast.error('Could not parse app spec')
      return
    }
    setGenerateTarget(result.app)
  }

  // -------------------------------------------------------------------------
  // Render
  // -------------------------------------------------------------------------

  // Show onboarding if first run
  if (showOnboarding) {
    return (
      <OnboardingScreen
        onComplete={() => {
          setShowOnboarding(false)
          loadApps()
        }}
        onInstall={installExample}
      />
    )
  }

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="border-b bg-gradient-to-r from-indigo-600 to-violet-600 px-6 py-5 text-white">
        <div className="mx-auto flex max-w-5xl items-center gap-4">
          <div className="flex-1 min-w-0">
            <h1 className="text-xl font-extrabold tracking-tight">One Does Simply</h1>
            <p className="text-sm text-white/75">Vibe Coding with Guardrails</p>
          </div>

          {/* Learn More */}
          <a
            href="https://one-does-simply.github.io/Specification/"
            target="_blank"
            rel="noopener noreferrer"
            className="rounded-md p-1.5 text-white/70 hover:text-white hover:bg-white/10 transition-colors"
            title="Learn More"
          >
            <Info className="size-4" />
          </a>

          {/* Theme toggle */}
          <div className="flex gap-0.5 rounded-lg border border-white/20 bg-white/10 p-0.5">
            {([
              { mode: 'light' as ThemeMode, icon: Sun },
              { mode: 'system' as ThemeMode, icon: Monitor },
              { mode: 'dark' as ThemeMode, icon: Moon },
            ]).map(({ mode, icon: Icon }) => (
              <button
                key={mode}
                onClick={() => { setTheme(mode); setThemeMode(mode) }}
                className={`rounded-md p-1.5 transition-colors ${
                  theme === mode
                    ? 'bg-white text-indigo-700'
                    : 'text-white/70 hover:text-white'
                }`}
                aria-label={`${mode} theme`}
              >
                <Icon className="size-4" />
              </button>
            ))}
          </div>

          {/* Icon buttons */}
          <Link to="/admin/settings" className="rounded-md p-1.5 text-white/70 hover:text-white hover:bg-white/10 transition-colors" title="Settings">
            <SettingsIcon className="size-4" />
          </Link>
          <button onClick={handleLogout} className="rounded-md p-1.5 text-white/70 hover:text-white hover:bg-white/10 transition-colors" title="Logout">
            <LogOut className="size-4" />
          </button>
        </div>
      </header>

      <div className="mx-auto max-w-5xl space-y-6 p-6">
        {/* Error display */}
        {localError && (
          <div className="rounded-lg border border-destructive/50 bg-destructive/10 px-4 py-3 text-sm text-destructive whitespace-pre-wrap">
            {localError}
          </div>
        )}

        {saving && (
          <div className="flex items-center gap-2 text-muted-foreground">
            <Loader2 className="size-4 animate-spin" />
            <span>Saving app...</span>
          </div>
        )}

        {/* Hidden file input */}
        <input
          ref={fileInputRef}
          type="file"
          accept=".json,application/json"
          className="hidden"
          onChange={handleFileSelect}
        />

        {/* My Apps header with Add App dropdown */}
        <section>
          <div className="mb-4 flex items-center">
            <h2 className="text-lg font-bold">
              My Apps {!loading && activeApps.length > 0 && <span className="text-muted-foreground font-normal">({activeApps.length})</span>}
            </h2>
            <div className="flex-1" />
            <AddAppButton
              onPickFile={() => fileInputRef.current?.click()}
              onLoadUrl={() => { setLocalError(null); setMode('url') }}
              onPasteJson={() => { setLocalError(null); setMode('paste') }}
              onBrowseExamples={() => setCatalogOpen(true)}
              onQuickBuild={() => navigate('/admin/quick-build')}
            />
          </div>

          {loading ? (
            <div className="flex items-center gap-2 py-8 text-muted-foreground">
              <Loader2 className="size-4 animate-spin" />
              Loading apps...
            </div>
          ) : activeApps.length === 0 ? (
            <div className="flex flex-col items-center gap-3 rounded-xl border border-dashed py-16 text-center">
              <LayoutGrid className="size-10 text-muted-foreground/40" />
              <div>
                <p className="font-medium text-muted-foreground">No apps yet</p>
                <p className="text-sm text-muted-foreground/70">Add an app above or browse examples to get started.</p>
              </div>
            </div>
          ) : (
            <div className="space-y-2">
              {activeApps.map((app) => (
                <AppCard
                  key={app.id}
                  app={app}
                  isDefault={app.slug === defaultSlug}
                  onOpen={() => navigate(`/${app.slug}`)}
                  onEdit={() => navigate(`/admin/apps/${app.id}/edit`)}
                  onEditWithAi={() => navigate(`/admin/apps/${app.id}/edit-ai`)}
                  onExportData={() => handleExportData(app)}
                  onGenerateCode={() => handleGenerateCode(app)}
                  onArchive={() => handleArchive(app)}
                  onDelete={() => setDeleteTarget(app)}
                  onSetDefault={() => handleSetDefault(app)}
                  onCopyUrl={() => handleCopyUrl(app)}
                />
              ))}
            </div>
          )}
        </section>

        {/* Archived Apps */}
        {archivedApps.length > 0 && (
          <section>
            <button
              onClick={() => setArchivedOpen(!archivedOpen)}
              className="mb-4 flex items-center gap-2 text-lg font-semibold text-muted-foreground hover:text-foreground"
            >
              {archivedOpen ? (
                <ChevronDown className="size-5" />
              ) : (
                <ChevronRight className="size-5" />
              )}
              Archived ({archivedApps.length})
            </button>

            {archivedOpen && (
              <div className="space-y-2">
                {archivedApps.map((app) => (
                  <AppCard
                    key={app.id}
                    app={app}
                    archived
                    onOpen={() => navigate(`/${app.slug}`)}
                    onEdit={() => navigate(`/admin/apps/${app.id}/edit`)}
                    onEditWithAi={() => navigate(`/admin/apps/${app.id}/edit-ai`)}
                    onExportData={() => handleExportData(app)}
                    onGenerateCode={() => handleGenerateCode(app)}
                    onRestore={() => handleRestore(app)}
                    onDelete={() => setDeleteTarget(app)}
                  />
                ))}
              </div>
            )}
          </section>
        )}

        {/* Footer */}
        <p className="pb-4 text-center text-xs text-muted-foreground/50">
          ODS React Web Framework
        </p>
      </div>

      {/* URL Dialog */}
      <Dialog open={mode === 'url'} onOpenChange={(open) => !open && setMode(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Load from URL</DialogTitle>
            <DialogDescription>
              Enter the URL of an ODS app spec JSON file.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <Input
              placeholder="https://example.com/app-spec.json"
              value={urlInput}
              onChange={(e) => setUrlInput(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleUrlLoad()}
            />
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setMode(null)}>
                Cancel
              </Button>
              <Button onClick={handleUrlLoad} disabled={saving}>
                {saving ? <Loader2 className="mr-2 size-4 animate-spin" /> : null}
                Load
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Paste Dialog */}
      <Dialog open={mode === 'paste'} onOpenChange={(open) => !open && setMode(null)}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Paste JSON Spec</DialogTitle>
            <DialogDescription>
              Paste your ODS app specification JSON below.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <Textarea
              placeholder='{"appName": "My App", ...}'
              value={pasteInput}
              onChange={(e) => setPasteInput(e.target.value)}
              rows={12}
              className="font-mono text-xs"
            />
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={() => setMode(null)}>
                Cancel
              </Button>
              <Button onClick={handlePasteLoad} disabled={saving}>
                {saving ? <Loader2 className="mr-2 size-4 animate-spin" /> : null}
                Save App
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Delete Confirmation */}
      <AlertDialog open={!!deleteTarget} onOpenChange={(v) => !v && setDeleteTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete App</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to permanently delete &quot;{deleteTarget?.name}&quot;?
              This removes the app record but does not delete its data collections.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleDelete}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Example Catalog Dialog */}
      <ExampleCatalogDialog
        open={catalogOpen}
        onOpenChange={setCatalogOpen}
        existingSlugs={apps.map((a) => a.slug)}
        onInstall={async (name, specJson, description) => {
          await installExample(name, specJson, description)
          await loadApps()
        }}
      />

      {/* Off-ramp: Export Data */}
      {exportTarget && (
        <DataExportDialog
          open={!!exportTarget}
          onOpenChange={(v) => { if (!v) setExportTarget(null) }}
          app={exportTarget.app}
          dataService={exportTarget.dataService}
        />
      )}

      {/* Off-ramp: Generate Code */}
      {generateTarget && (
        <GenerateCodeDialog
          open={!!generateTarget}
          onOpenChange={(v) => { if (!v) setGenerateTarget(null) }}
          app={generateTarget}
        />
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// AppCard — single app tile
// ---------------------------------------------------------------------------

interface AppCardProps {
  app: AppRecord
  archived?: boolean
  isDefault?: boolean
  onOpen: () => void
  onEdit: () => void
  onEditWithAi?: () => void
  onExportData?: () => void
  onGenerateCode?: () => void
  onArchive?: () => void
  onRestore?: () => void
  onDelete: () => void
  onSetDefault?: () => void
  onCopyUrl?: () => void
}

function AppCard({ app, archived, isDefault, onOpen, onEdit, onEditWithAi, onExportData, onGenerateCode, onArchive, onRestore, onDelete, onSetDefault, onCopyUrl }: AppCardProps) {
  const [menuOpen, setMenuOpen] = useState(false)
  const menuBtnRef = useRef<HTMLButtonElement>(null)
  const [menuPos, setMenuPos] = useState<{ top: number; left: number } | null>(null)

  function openMenu() {
    if (menuBtnRef.current) {
      const rect = menuBtnRef.current.getBoundingClientRect()
      setMenuPos({ top: rect.bottom + 4, left: rect.right })
    }
    setMenuOpen(true)
  }

  function closeMenu() {
    setMenuOpen(false)
    setMenuPos(null)
  }

  return (
    <Card
      className="group cursor-pointer transition-all hover:shadow-md hover:border-primary/20"
      onClick={onOpen}
    >
      <CardContent className="flex items-center gap-4 p-4">
        {/* App icon */}
        <div className="flex size-11 shrink-0 items-center justify-center rounded-xl bg-primary/10">
          <LayoutGrid className="size-5 text-primary" />
        </div>

        {/* App info */}
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <h3 className="truncate text-sm font-semibold">{app.name}</h3>
            {isDefault && <Badge variant="default" className="text-[10px] px-1.5 py-0 bg-amber-500 hover:bg-amber-500">Default</Badge>}
            {archived && <Badge variant="secondary" className="text-[10px] px-1.5 py-0">Archived</Badge>}
          </div>
          {app.description ? (
            <p className="truncate text-xs text-muted-foreground">{app.description}</p>
          ) : (
            <p className="text-xs text-muted-foreground">/{app.slug}</p>
          )}
        </div>

        {/* Context menu trigger */}
        <div onClick={(e) => e.stopPropagation()}>
          <button
            ref={menuBtnRef}
            onClick={() => menuOpen ? closeMenu() : openMenu()}
            className="rounded-lg p-1.5 text-muted-foreground hover:bg-muted hover:text-foreground"
          >
            <MoreVertical className="size-4" />
          </button>
        </div>

        {/* Play button */}
        <Play className="size-6 shrink-0 text-primary" />
      </CardContent>

      {/* Context menu — rendered as fixed portal to escape overflow clipping */}
      {menuOpen && menuPos && (
        <>
          <div className="fixed inset-0 z-40" onClick={closeMenu} />
          <div
            className="fixed z-50 w-48 rounded-lg border bg-popover p-1 shadow-lg"
            style={{ top: menuPos.top, left: menuPos.left - 192 }}
            onClick={(e) => e.stopPropagation()}
          >
            {onEditWithAi && <ContextMenuItem icon={Sparkles} label="Edit with AI" onClick={() => { closeMenu(); onEditWithAi() }} />}
            <ContextMenuItem icon={Pencil} label="Edit JSON Spec" onClick={() => { closeMenu(); onEdit() }} />
            {onCopyUrl && <ContextMenuItem icon={LinkIcon} label="Copy Client URL" onClick={() => { closeMenu(); onCopyUrl() }} />}
            {onSetDefault && !isDefault && (
              <ContextMenuItem icon={Star} label="Set as Default" onClick={() => { closeMenu(); onSetDefault() }} />
            )}
            <div className="my-1 h-px bg-border" />
            {onExportData && <ContextMenuItem icon={Download} label="Export Data" onClick={() => { closeMenu(); onExportData() }} />}
            {onGenerateCode && <ContextMenuItem icon={Code} label="Generate Code" onClick={() => { closeMenu(); onGenerateCode() }} />}
            <div className="my-1 h-px bg-border" />
            {archived ? (
              onRestore && <ContextMenuItem icon={ArchiveRestore} label="Restore" onClick={() => { closeMenu(); onRestore() }} />
            ) : (
              onArchive && <ContextMenuItem icon={Archive} label="Archive" onClick={() => { closeMenu(); onArchive() }} />
            )}
            <ContextMenuItem icon={Trash2} label="Delete" onClick={() => { closeMenu(); onDelete() }} destructive />
          </div>
        </>
      )}
    </Card>
  )
}

function ContextMenuItem({ icon: Icon, label, onClick, destructive }: {
  icon: React.ComponentType<{ className?: string }>
  label: string
  onClick: () => void
  destructive?: boolean
}) {
  return (
    <button
      onClick={onClick}
      className={`flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-sm transition-colors ${
        destructive
          ? 'text-destructive hover:bg-destructive/10'
          : 'text-popover-foreground hover:bg-muted'
      }`}
    >
      <Icon className="size-3.5" />
      {label}
    </button>
  )
}

// ---------------------------------------------------------------------------
// AddAppButton — popup menu matching Flutter's _AddAppButton
// ---------------------------------------------------------------------------

function AddAppButton({
  onPickFile,
  onLoadUrl,
  onPasteJson,
  onBrowseExamples,
  onQuickBuild,
}: {
  onPickFile: () => void
  onLoadUrl: () => void
  onPasteJson: () => void
  onBrowseExamples: () => void
  onQuickBuild: () => void
}) {
  const [open, setOpen] = useState(false)

  function item(action: () => void) {
    return () => { setOpen(false); action() }
  }

  return (
    <div className="relative">
      <button
        onClick={() => setOpen(!open)}
        className="inline-flex items-center gap-1.5 rounded-lg bg-primary px-3.5 py-2 text-[13px] font-semibold text-primary-foreground transition-colors hover:bg-primary/90"
      >
        <Plus className="size-4" />
        Add App
      </button>

      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div className="absolute right-0 top-full z-50 mt-2 w-72 rounded-xl border bg-popover p-1.5 shadow-xl">
            <AddAppMenuItem
              icon={Zap}
              title="Quick Build"
              subtitle="Build an app in seconds from a template"
              onClick={item(onQuickBuild)}
            />
            <AddAppMenuItem
              icon={BookOpen}
              title="Browse Examples"
              subtitle="Pick from the example catalog"
              onClick={item(onBrowseExamples)}
            />
            <div className="my-1.5 h-px bg-border" />
            <AddAppMenuItem
              icon={FileUp}
              title="Open Spec File"
              subtitle="Load a .json file from your device"
              onClick={item(onPickFile)}
            />
            <AddAppMenuItem
              icon={Link2}
              title="Load from URL"
              subtitle="Fetch a spec from the web"
              onClick={item(onLoadUrl)}
            />
            <div className="my-1.5 h-px bg-border" />
            <AddAppMenuItem
              icon={Sparkles}
              title="Create New"
              subtitle="Build an app with AI assistance"
              onClick={item(onPasteJson)}
            />
          </div>
        </>
      )}
    </div>
  )
}

function AddAppMenuItem({
  icon: Icon,
  title,
  subtitle,
  onClick,
}: {
  icon: React.ComponentType<{ className?: string }>
  title: string
  subtitle: string
  onClick: () => void
}) {
  return (
    <button
      onClick={onClick}
      className="flex w-full items-start gap-3 rounded-lg px-3 py-2.5 text-left transition-colors hover:bg-muted"
    >
      <Icon className="mt-0.5 size-5 shrink-0 text-muted-foreground" />
      <div className="min-w-0">
        <div className="text-sm font-medium">{title}</div>
        <div className="text-xs text-muted-foreground">{subtitle}</div>
      </div>
    </button>
  )
}

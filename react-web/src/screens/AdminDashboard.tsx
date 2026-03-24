import { useState, useEffect, useRef, useCallback } from 'react'
import { useNavigate, Link } from 'react-router'
import { AppRegistry, type AppRecord } from '@/engine/app-registry.ts'
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
  Globe,
  ClipboardPaste,
  Loader2,
  ExternalLink,
  Pencil,
  Archive,
  ArchiveRestore,
  Trash2,
  Users,
  ChevronDown,
  ChevronRight,
  Plus,
} from 'lucide-react'

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

  // Add app state
  const [mode, setMode] = useState<LoadMode>(null)
  const [urlInput, setUrlInput] = useState('')
  const [pasteInput, setPasteInput] = useState('')
  const [localError, setLocalError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const fileInputRef = useRef<HTMLInputElement>(null)

  // Delete confirmation
  const [deleteTarget, setDeleteTarget] = useState<AppRecord | null>(null)

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
  }, [registry])

  useEffect(() => {
    loadApps()
  }, [loadApps])

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
      console.error('Save app error:', e)
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
  // Render
  // -------------------------------------------------------------------------

  return (
    <div className="min-h-screen bg-background">
      {/* Top bar */}
      <header className="sticky top-0 z-40 flex h-14 items-center gap-4 border-b bg-background/95 px-6 supports-backdrop-filter:backdrop-blur-sm">
        <h1 className="text-lg font-semibold">ODS Admin</h1>
        <div className="flex-1" />
        <Button variant="ghost" size="sm">
          <Link to="/admin/users">
            <Users className="mr-2 size-4" />
            Users
          </Link>
        </Button>
      </header>

      <div className="mx-auto max-w-5xl space-y-8 p-6">
        {/* Add App section */}
        <section>
          <h2 className="mb-4 flex items-center gap-2 text-lg font-semibold">
            <Plus className="size-5" />
            Add App
          </h2>

          {/* Error display */}
          {localError && (
            <div className="mb-4 rounded-lg border border-destructive/50 bg-destructive/10 px-4 py-3 text-sm text-destructive whitespace-pre-wrap">
              {localError}
            </div>
          )}

          {saving && (
            <div className="mb-4 flex items-center gap-2 text-muted-foreground">
              <Loader2 className="size-4 animate-spin" />
              <span>Saving app...</span>
            </div>
          )}

          <div className="grid gap-3 sm:grid-cols-3">
            <Card
              className="cursor-pointer transition-colors hover:bg-muted/50"
              onClick={() => fileInputRef.current?.click()}
            >
              <CardContent className="flex flex-col items-center gap-2 py-6 text-center">
                <FileUp className="size-8 text-primary" />
                <span className="text-sm font-medium">Load from File</span>
              </CardContent>
            </Card>

            <Card
              className="cursor-pointer transition-colors hover:bg-muted/50"
              onClick={() => {
                setLocalError(null)
                setMode('url')
              }}
            >
              <CardContent className="flex flex-col items-center gap-2 py-6 text-center">
                <Globe className="size-8 text-primary" />
                <span className="text-sm font-medium">Load from URL</span>
              </CardContent>
            </Card>

            <Card
              className="cursor-pointer transition-colors hover:bg-muted/50"
              onClick={() => {
                setLocalError(null)
                setMode('paste')
              }}
            >
              <CardContent className="flex flex-col items-center gap-2 py-6 text-center">
                <ClipboardPaste className="size-8 text-primary" />
                <span className="text-sm font-medium">Paste JSON</span>
              </CardContent>
            </Card>
          </div>

          {/* Hidden file input */}
          <input
            ref={fileInputRef}
            type="file"
            accept=".json,application/json"
            className="hidden"
            onChange={handleFileSelect}
          />
        </section>

        {/* Active Apps */}
        <section>
          <h2 className="mb-4 text-lg font-semibold">
            Apps {!loading && `(${activeApps.length})`}
          </h2>

          {loading ? (
            <div className="flex items-center gap-2 py-8 text-muted-foreground">
              <Loader2 className="size-4 animate-spin" />
              Loading apps...
            </div>
          ) : activeApps.length === 0 ? (
            <div className="rounded-lg border border-dashed py-12 text-center text-muted-foreground">
              No apps loaded yet. Add one above to get started.
            </div>
          ) : (
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {activeApps.map((app) => (
                <AppCard
                  key={app.id}
                  app={app}
                  onOpen={() => navigate(`/${app.slug}`)}
                  onEdit={() => navigate(`/admin/apps/${app.id}/edit`)}
                  onArchive={() => handleArchive(app)}
                  onDelete={() => setDeleteTarget(app)}
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
              <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                {archivedApps.map((app) => (
                  <AppCard
                    key={app.id}
                    app={app}
                    archived
                    onOpen={() => navigate(`/${app.slug}`)}
                    onEdit={() => navigate(`/admin/apps/${app.id}/edit`)}
                    onRestore={() => handleRestore(app)}
                    onDelete={() => setDeleteTarget(app)}
                  />
                ))}
              </div>
            )}
          </section>
        )}

        {/* Footer */}
        <p className="pb-4 text-center text-xs text-muted-foreground">
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
    </div>
  )
}

// ---------------------------------------------------------------------------
// AppCard — single app tile
// ---------------------------------------------------------------------------

interface AppCardProps {
  app: AppRecord
  archived?: boolean
  onOpen: () => void
  onEdit: () => void
  onArchive?: () => void
  onRestore?: () => void
  onDelete: () => void
}

function AppCard({ app, archived, onOpen, onEdit, onArchive, onRestore, onDelete }: AppCardProps) {
  const created = new Date(app.created).toLocaleDateString()

  return (
    <Card className="flex flex-col">
      <CardContent className="flex flex-1 flex-col gap-3 p-4">
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0">
            <h3 className="truncate font-semibold">{app.name}</h3>
            <p className="text-xs text-muted-foreground">/{app.slug}</p>
          </div>
          <Badge variant={archived ? 'secondary' : 'default'}>
            {archived ? 'Archived' : 'Active'}
          </Badge>
        </div>

        {app.description && (
          <p className="line-clamp-2 text-sm text-muted-foreground">{app.description}</p>
        )}

        <p className="text-xs text-muted-foreground">Created {created}</p>

        <div className="mt-auto flex flex-wrap gap-2 pt-2">
          <Button variant="default" size="sm" onClick={onOpen}>
            <ExternalLink className="mr-1 size-3.5" />
            Open
          </Button>
          <Button variant="outline" size="sm" onClick={onEdit}>
            <Pencil className="mr-1 size-3.5" />
            Edit
          </Button>
          {archived ? (
            onRestore && (
              <Button variant="outline" size="sm" onClick={onRestore}>
                <ArchiveRestore className="mr-1 size-3.5" />
                Restore
              </Button>
            )
          ) : (
            onArchive && (
              <Button variant="outline" size="sm" onClick={onArchive}>
                <Archive className="mr-1 size-3.5" />
                Archive
              </Button>
            )
          )}
          <Button
            variant="ghost"
            size="sm"
            onClick={onDelete}
            className="text-destructive hover:text-destructive"
          >
            <Trash2 className="mr-1 size-3.5" />
            Delete
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}

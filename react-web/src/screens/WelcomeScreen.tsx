import { useState, useRef } from 'react'
import { useAppStore } from '@/engine/app-store.ts'
import { DataService } from '@/engine/data-service.ts'
import { AuthService } from '@/engine/auth-service.ts'
import { loadFromFile, loadFromUrl, loadFromText } from '@/engine/spec-loader.ts'
import pb from '@/lib/pocketbase.ts'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog'
import { FileUp, Globe, ClipboardPaste, Loader2 } from 'lucide-react'

// ---------------------------------------------------------------------------
// WelcomeScreen — the "My Apps" landing page
// ---------------------------------------------------------------------------

type LoadMode = 'file' | 'url' | 'paste' | null

export function WelcomeScreen() {
  const loadSpec = useAppStore((s) => s.loadSpec)
  const loadError = useAppStore((s) => s.loadError)
  const isLoading = useAppStore((s) => s.isLoading)

  const [mode, setMode] = useState<LoadMode>(null)
  const [urlInput, setUrlInput] = useState('')
  const [pasteInput, setPasteInput] = useState('')
  const [localError, setLocalError] = useState<string | null>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)

  // PocketBase admin auth state
  const [showPbSetup, setShowPbSetup] = useState(false)
  const [pbEmail, setPbEmail] = useState('')
  const [pbPassword, setPbPassword] = useState('')
  const [pbAuthError, setPbAuthError] = useState<string | null>(null)
  const [pendingJson, setPendingJson] = useState<string | null>(null)

  const error = localError ?? loadError

  // -------------------------------------------------------------------------
  // Load handler — authenticates with PocketBase if needed, then loads spec
  // -------------------------------------------------------------------------

  async function handleLoad(jsonString: string) {
    setLocalError(null)
    const dataService = new DataService(pb)

    // Check if we have admin auth from the current session
    if (!dataService.isAdminAuthenticated && !pb.authStore.isValid) {
      // Need admin credentials — show the setup dialog
      setPendingJson(jsonString)
      setShowPbSetup(true)
      return
    }

    await doLoadSpec(jsonString, dataService)
  }

  async function handlePbAuth() {
    setPbAuthError(null)
    const dataService = new DataService(pb)
    const success = await dataService.authenticateAdmin(pbEmail, pbPassword)
    if (!success) {
      setPbAuthError('Invalid PocketBase admin credentials. Check the email and password you used when setting up PocketBase.')
      return
    }
    setShowPbSetup(false)
    if (pendingJson) {
      await doLoadSpec(pendingJson, dataService)
      setPendingJson(null)
    }
  }

  async function doLoadSpec(jsonString: string, dataService: DataService) {
    const authService = new AuthService(pb)
    const success = await loadSpec(jsonString, dataService, authService)
    if (!success) {
      // loadError is set by the store
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
      await handleLoad(text)
    } catch (err) {
      setLocalError(err instanceof Error ? err.message : 'Failed to read file')
    }
    // Reset the input so the same file can be re-selected
    if (fileInputRef.current) fileInputRef.current.value = ''
  }

  // -------------------------------------------------------------------------
  // URL loading
  // -------------------------------------------------------------------------

  async function handleUrlLoad() {
    if (!urlInput.trim()) {
      setLocalError('Please enter a URL')
      return
    }
    try {
      const text = await loadFromUrl(urlInput.trim())
      await handleLoad(text)
    } catch (err) {
      setLocalError(err instanceof Error ? err.message : 'Failed to fetch from URL')
    }
  }

  // -------------------------------------------------------------------------
  // Paste loading
  // -------------------------------------------------------------------------

  async function handlePasteLoad() {
    try {
      const text = loadFromText(pasteInput)
      await handleLoad(text)
    } catch (err) {
      setLocalError(err instanceof Error ? err.message : 'Invalid JSON')
    }
  }

  // -------------------------------------------------------------------------
  // Render
  // -------------------------------------------------------------------------

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-background p-4">
      <div className="w-full max-w-lg space-y-6">
        {/* Header */}
        <div className="text-center">
          <h1 className="text-3xl font-bold tracking-tight text-foreground">
            One Does Simply
          </h1>
          <p className="mt-2 text-muted-foreground">
            Load an ODS app spec to get started
          </p>
        </div>

        {/* Error display */}
        {error && (
          <div className="rounded-lg border border-destructive/50 bg-destructive/10 px-4 py-3 text-sm text-destructive">
            {error}
          </div>
        )}

        {/* Loading spinner */}
        {isLoading && (
          <div className="flex items-center justify-center gap-2 text-muted-foreground">
            <Loader2 className="size-4 animate-spin" />
            <span>Loading app...</span>
          </div>
        )}

        {/* Load options */}
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
            onClick={() => { setLocalError(null); setMode('url') }}
          >
            <CardContent className="flex flex-col items-center gap-2 py-6 text-center">
              <Globe className="size-8 text-primary" />
              <span className="text-sm font-medium">Load from URL</span>
            </CardContent>
          </Card>

          <Card
            className="cursor-pointer transition-colors hover:bg-muted/50"
            onClick={() => { setLocalError(null); setMode('paste') }}
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
                <Button onClick={handleUrlLoad} disabled={isLoading}>
                  {isLoading ? <Loader2 className="mr-2 size-4 animate-spin" /> : null}
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
                <Button onClick={handlePasteLoad} disabled={isLoading}>
                  {isLoading ? <Loader2 className="mr-2 size-4 animate-spin" /> : null}
                  Load App
                </Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>

        {/* Footer */}
        <p className="text-center text-xs text-muted-foreground">
          ODS React Web Framework
        </p>
      </div>

      {/* PocketBase Admin Setup Dialog */}
      <Dialog open={showPbSetup} onOpenChange={setShowPbSetup}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>PocketBase Setup</DialogTitle>
            <DialogDescription>
              Enter the admin credentials you created when setting up PocketBase.
              These are saved locally so you only need to enter them once.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 pt-2">
            <div className="space-y-1">
              <label className="text-sm font-medium">Admin Email</label>
              <Input
                type="email"
                value={pbEmail}
                onChange={(e) => setPbEmail(e.target.value)}
                placeholder="admin@example.com"
                autoFocus
              />
            </div>
            <div className="space-y-1">
              <label className="text-sm font-medium">Admin Password</label>
              <Input
                type="password"
                value={pbPassword}
                onChange={(e) => setPbPassword(e.target.value)}
                placeholder="Password"
                onKeyDown={(e) => { if (e.key === 'Enter') handlePbAuth() }}
              />
            </div>
            {pbAuthError && (
              <p className="text-sm text-destructive">{pbAuthError}</p>
            )}
            <Button onClick={handlePbAuth} className="w-full">
              Connect to PocketBase
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

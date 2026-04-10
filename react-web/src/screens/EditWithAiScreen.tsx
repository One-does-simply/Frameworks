import { useState, useEffect, useRef } from 'react'
import { useParams, useNavigate } from 'react-router'
import { AppRegistry, type AppRecord } from '@/engine/app-registry.ts'
import { parseSpec, isOk } from '@/parser/spec-parser.ts'
import pb from '@/lib/pocketbase.ts'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'
import { toast } from 'sonner'
import {
  ArrowLeft,
  ClipboardCheck,
  Check,
  Loader2,
  MessageSquare,
  FileJson,
} from 'lucide-react'

// ---------------------------------------------------------------------------
// Build Helper prompt — bundled as a static string.
// In production you'd fetch this from an asset; here we inline the essentials.
// ---------------------------------------------------------------------------

const BUILD_HELPER_URL =
  'https://one-does-simply.github.io/Specification/build-helper-prompt.txt'

// ---------------------------------------------------------------------------
// EditWithAiScreen — 3-step guided flow: copy prompt, copy spec, paste back
// ---------------------------------------------------------------------------

export function EditWithAiScreen() {
  const { appId } = useParams<{ appId: string }>()
  const navigate = useNavigate()
  const registry = useRef(new AppRegistry(pb)).current

  const [app, setApp] = useState<AppRecord | null>(null)
  const [loading, setLoading] = useState(true)
  const [promptCopied, setPromptCopied] = useState(false)
  const [specCopied, setSpecCopied] = useState(false)
  const [pasteText, setPasteText] = useState('')
  const [importError, setImportError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [buildHelperPrompt, setBuildHelperPrompt] = useState<string | null>(null)

  // Load app record
  useEffect(() => {
    async function load() {
      if (!appId) return
      setLoading(true)
      try {
        const record = await pb.collection('_ods_apps').getOne(appId, { requestKey: null })
        setApp({
          id: record.id,
          name: record['name'] as string,
          slug: record['slug'] as string,
          specJson:
            typeof record['specJson'] === 'string'
              ? record['specJson']
              : JSON.stringify(record['specJson']),
          status: (record['status'] as string) === 'archived' ? 'archived' : 'active',
          description: (record['description'] as string) ?? '',
          created: record.created,
          updated: record.updated,
        })
      } catch {
        toast.error('App not found')
        navigate('/admin')
      }
      setLoading(false)
    }
    load()
  }, [appId, navigate])

  // Fetch build helper prompt
  useEffect(() => {
    async function fetchPrompt() {
      try {
        const resp = await fetch(BUILD_HELPER_URL)
        if (resp.ok) {
          setBuildHelperPrompt(await resp.text())
        }
      } catch {
        // Fallback — user can still copy spec and work with AI without the prompt
      }
    }
    fetchPrompt()
  }, [])

  // -------------------------------------------------------------------------
  // Step 1: Copy build helper prompt
  // -------------------------------------------------------------------------

  async function handleCopyPrompt() {
    const text = buildHelperPrompt ?? 'You are the ODS Build Helper. Help me edit an ODS app specification JSON.'
    try {
      await navigator.clipboard.writeText(text)
      setPromptCopied(true)
      toast.success('Build Helper prompt copied to clipboard')
    } catch {
      toast.error('Failed to copy — try manually selecting the text')
    }
  }

  // -------------------------------------------------------------------------
  // Step 2: Copy current spec
  // -------------------------------------------------------------------------

  async function handleCopySpec() {
    if (!app) return
    try {
      // Pretty-print for readability
      let pretty: string
      try {
        pretty = JSON.stringify(JSON.parse(app.specJson), null, 2)
      } catch {
        pretty = app.specJson
      }
      await navigator.clipboard.writeText(pretty)
      setSpecCopied(true)
      toast.success('App spec copied to clipboard')
    } catch {
      toast.error('Failed to copy — try manually selecting the text')
    }
  }

  // -------------------------------------------------------------------------
  // Step 3: Paste updated spec
  // -------------------------------------------------------------------------

  async function handleImport() {
    if (!app || !pasteText.trim()) return

    setImportError(null)
    setSaving(true)

    // Validate JSON
    const result = parseSpec(pasteText)
    if (result.parseError) {
      setImportError(result.parseError)
      setSaving(false)
      return
    }
    if (!isOk(result)) {
      const errors = result.validation.messages
        .filter((m) => m.level === 'error')
        .map((m) => m.message)
        .join('\n')
      setImportError(errors)
      setSaving(false)
      return
    }

    // Save updated spec
    const success = await registry.updateApp(app.id, pasteText)
    setSaving(false)

    if (success) {
      toast.success('App updated successfully!')
      navigate('/admin')
    } else {
      setImportError('Failed to save the updated spec')
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

  return (
    <div className="flex min-h-screen flex-col bg-background">
      {/* Top bar */}
      <header className="sticky top-0 z-40 flex h-14 items-center gap-3 border-b bg-background/95 px-4 supports-backdrop-filter:backdrop-blur-sm">
        <Button variant="ghost" size="icon-sm" onClick={() => navigate('/admin')}>
          <ArrowLeft className="size-5" />
        </Button>
        <h1 className="flex-1 truncate text-base font-semibold">
          Edit with AI: {app.name}
        </h1>
      </header>

      <div className="mx-auto max-w-2xl space-y-6 p-6">
        <p className="text-sm text-muted-foreground">
          Use an AI chatbot (ChatGPT, Claude, etc.) to modify your app. Follow the three steps below.
        </p>

        {/* Step 1 */}
        <div className="rounded-lg border p-4">
          <div className="mb-2 flex items-center gap-2">
            <span className="flex size-6 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-foreground">
              1
            </span>
            <h2 className="font-semibold">Copy the Build Helper Prompt</h2>
          </div>
          <p className="mb-3 text-sm text-muted-foreground">
            This tells the AI how ODS specs work. Paste it as your first message in a new chat.
          </p>
          <Button onClick={handleCopyPrompt} variant={promptCopied ? 'secondary' : 'default'}>
            {promptCopied ? (
              <>
                <ClipboardCheck className="mr-2 size-4" />
                Copied!
              </>
            ) : (
              <>
                <MessageSquare className="mr-2 size-4" />
                Copy Build Helper Prompt
              </>
            )}
          </Button>
        </div>

        {/* Step 2 */}
        <div className="rounded-lg border p-4">
          <div className="mb-2 flex items-center gap-2">
            <span className="flex size-6 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-foreground">
              2
            </span>
            <h2 className="font-semibold">Copy Your Current App Spec</h2>
          </div>
          <p className="mb-3 text-sm text-muted-foreground">
            Paste this into the AI chat as your second message. Tell the AI what changes you want.
          </p>
          <Button onClick={handleCopySpec} variant={specCopied ? 'secondary' : 'default'}>
            {specCopied ? (
              <>
                <ClipboardCheck className="mr-2 size-4" />
                Copied!
              </>
            ) : (
              <>
                <FileJson className="mr-2 size-4" />
                Copy App Spec
              </>
            )}
          </Button>
        </div>

        {/* Step 3 */}
        <div className="rounded-lg border p-4">
          <div className="mb-2 flex items-center gap-2">
            <span className="flex size-6 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-foreground">
              3
            </span>
            <h2 className="font-semibold">Paste the Updated Spec</h2>
          </div>
          <p className="mb-3 text-sm text-muted-foreground">
            Copy the AI's updated JSON and paste it below. We'll validate and save it.
          </p>

          {importError && (
            <div className="mb-3 rounded-lg border border-destructive/50 bg-destructive/10 px-4 py-3 text-sm text-destructive whitespace-pre-wrap">
              {importError}
            </div>
          )}

          <Textarea
            placeholder='Paste updated JSON here...'
            value={pasteText}
            onChange={(e) => setPasteText(e.target.value)}
            rows={10}
            className="mb-3 font-mono text-xs"
          />

          <Button onClick={handleImport} disabled={saving || !pasteText.trim()}>
            {saving ? (
              <Loader2 className="mr-2 size-4 animate-spin" />
            ) : (
              <Check className="mr-2 size-4" />
            )}
            Validate & Save
          </Button>
        </div>
      </div>
    </div>
  )
}

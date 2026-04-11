import { useState } from 'react'
import { useAppStore } from '@/engine/app-store.ts'
import type { OdsApp } from '@/models/ods-app.ts'
import { generateProject, packAsZip } from '@/engine/code-generator.ts'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog'
import { Separator } from '@/components/ui/separator'
import { toast } from 'sonner'
import { logError } from '@/engine/log-service.ts'
import { Code, FolderArchive } from 'lucide-react'

// ---------------------------------------------------------------------------
// GenerateCodeDialog — generate a standalone React project from the ODS spec
//
// Can be used from either:
//   1. Inside an app (reads from store)  — pass no extra props
//   2. Admin dashboard (pass app prop)
// ---------------------------------------------------------------------------

interface GenerateCodeDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  /** When provided, use this app instead of reading from store. */
  app?: OdsApp
}

export function GenerateCodeDialog({ open, onOpenChange, app: appProp }: GenerateCodeDialogProps) {
  const storeApp = useAppStore((s) => s.app)
  const app = appProp ?? storeApp!
  const [isGenerating, setIsGenerating] = useState(false)

  async function handleGenerate() {
    setIsGenerating(true)
    try {
      const files = generateProject(app)
      const fileCount = Object.keys(files).length
      const safeName = app.appName.replace(/[^a-zA-Z0-9]+/g, '-').replace(/^-|-$/g, '').toLowerCase()

      const blob = await packAsZip(files, safeName)

      // Trigger download
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `${safeName}.zip`
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      URL.revokeObjectURL(url)

      toast.success(`Generated ${fileCount} files — download started.`)
      onOpenChange(false)
    } catch (err) {
      logError('CodeGen', 'Code generation failed', err)
      toast.error('Code generation failed. Check the console for details.')
    } finally {
      setIsGenerating(false)
    }
  }

  // Count what the generated project would include
  const pageCount = Object.keys(app.pages).length
  const dsCount = Object.values(app.dataSources).filter((ds) => ds.url.startsWith('local://')).length
  const hasCharts = Object.values(app.pages).some((p) =>
    p.content.some((c) => c.component === 'chart'),
  )

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Code className="size-5 text-primary" />
            Generate Code
          </DialogTitle>
          <DialogDescription>
            Generate a standalone React project from your ODS app — complete
            source code that you fully own and can customize without limits.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          {/* What's included */}
          <div className="rounded-lg bg-muted/50 p-4">
            <p className="mb-2 text-sm font-medium">Includes:</p>
            <ul className="space-y-1.5 text-sm text-muted-foreground">
              <li className="flex items-start gap-2">
                <span className="mt-0.5 text-primary">•</span>
                React + TypeScript + Vite + Tailwind CSS
              </li>
              <li className="flex items-start gap-2">
                <span className="mt-0.5 text-primary">•</span>
                {pageCount} page{pageCount === 1 ? '' : 's'} with forms, lists, and buttons
              </li>
              <li className="flex items-start gap-2">
                <span className="mt-0.5 text-primary">•</span>
                localStorage database with {dsCount} table{dsCount === 1 ? '' : 's'}
                {app.dataSources && Object.values(app.dataSources).some((ds) => ds.seedData?.length)
                  ? ' + seed data'
                  : ''}
              </li>
              {hasCharts && (
                <li className="flex items-start gap-2">
                  <span className="mt-0.5 text-primary">•</span>
                  Charts powered by Recharts
                </li>
              )}
              <li className="flex items-start gap-2">
                <span className="mt-0.5 text-primary">•</span>
                Sidebar navigation and responsive layout
              </li>
              <li className="flex items-start gap-2">
                <span className="mt-0.5 text-primary">•</span>
                README with setup instructions
              </li>
            </ul>
          </div>

          <Separator />

          <div className="rounded-lg border p-4">
            <p className="mb-1 text-sm font-medium">How it works:</p>
            <ol className="list-inside list-decimal space-y-1 text-sm text-muted-foreground">
              <li>Download the ZIP file</li>
              <li>Extract to a folder</li>
              <li>
                Run <code className="rounded bg-muted px-1 py-0.5 text-xs">npm install</code> then{' '}
                <code className="rounded bg-muted px-1 py-0.5 text-xs">npm run dev</code>
              </li>
              <li>Edit anything — it's your code now!</li>
            </ol>
          </div>

          {/* Generate button */}
          <button
            onClick={handleGenerate}
            disabled={isGenerating}
            className="flex w-full items-center justify-center gap-2 rounded-lg bg-primary px-4 py-3 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90 disabled:opacity-50"
          >
            <FolderArchive className="size-4" />
            {isGenerating ? 'Generating...' : 'Download React Project (.zip)'}
          </button>
        </div>

        <DialogFooter showCloseButton />
      </DialogContent>
    </Dialog>
  )
}

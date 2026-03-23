import { useAppStore } from '@/engine/app-store.ts'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
import { Card } from '@/components/ui/card'
import { Separator } from '@/components/ui/separator'

// ---------------------------------------------------------------------------
// HelpScreen — app overview + per-page help from the spec's `help` object
// ---------------------------------------------------------------------------

interface HelpScreenProps {
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function HelpScreen({ open, onOpenChange }: HelpScreenProps) {
  const app = useAppStore((s) => s.app)!
  const help = app.help

  if (!help) return null

  // Build a map of page IDs to their human-readable titles
  const pageTitles: Record<string, string> = {}
  for (const [pageId, page] of Object.entries(app.pages)) {
    pageTitles[pageId] = page.title
  }

  const pageEntries = Object.entries(help.pages)

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{app.appName} Help</DialogTitle>
        </DialogHeader>

        <div className="max-h-[70vh] space-y-6 overflow-y-auto pr-1">
          {/* Overview */}
          <div>
            <h3 className="mb-2 text-base font-bold">Overview</h3>
            <p className="text-sm leading-relaxed text-foreground">
              {help.overview}
            </p>
          </div>

          {/* Per-page help */}
          {pageEntries.length > 0 && (
            <>
              <Separator />
              <div>
                <h3 className="mb-3 text-base font-bold">Page Guide</h3>
                <div className="space-y-3">
                  {pageEntries.map(([pageId, helpText]) => {
                    const pageTitle = pageTitles[pageId] ?? pageId
                    return (
                      <Card key={pageId} className="p-4">
                        <h4 className="mb-1 text-sm font-bold">{pageTitle}</h4>
                        <p className="text-sm text-muted-foreground">
                          {helpText}
                        </p>
                      </Card>
                    )
                  })}
                </div>
              </div>
            </>
          )}
        </div>

        <DialogFooter showCloseButton />
      </DialogContent>
    </Dialog>
  )
}

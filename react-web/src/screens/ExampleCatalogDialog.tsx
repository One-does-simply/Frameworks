import { useState, useEffect } from 'react'
import {
  fetchCatalog,
  fetchExampleSpec,
  type CatalogEntry,
} from '@/engine/example-catalog.ts'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { toast } from 'sonner'
import { logWarn } from '@/engine/log-service.ts'
import { Loader2, Check, BookOpen } from 'lucide-react'

// ---------------------------------------------------------------------------
// ExampleCatalogDialog — browse and install example apps from the catalog
// ---------------------------------------------------------------------------

interface ExampleCatalogDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  existingSlugs: string[]
  onInstall: (name: string, specJson: string, description: string) => Promise<void>
}

export function ExampleCatalogDialog({
  open,
  onOpenChange,
  existingSlugs,
  onInstall,
}: ExampleCatalogDialogProps) {
  const [catalog, setCatalog] = useState<CatalogEntry[] | null>(null)
  const [loading, setLoading] = useState(false)
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [installing, setInstalling] = useState(false)

  useEffect(() => {
    if (!open) return
    setLoading(true)
    fetchCatalog().then((entries) => {
      setCatalog(entries)
      setLoading(false)
    })
  }, [open])

  // Filter out examples that are already installed (by matching slug-like IDs)
  const available = catalog?.filter(
    (e) => !existingSlugs.some((s) => s.includes(e.id.replace(/_/g, '-'))),
  )

  function toggleEntry(id: string) {
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  function selectAll() {
    if (!available) return
    setSelected(new Set(available.map((e) => e.id)))
  }

  function selectNone() {
    setSelected(new Set())
  }

  async function handleInstall() {
    if (!catalog || selected.size === 0) return
    setInstalling(true)

    const toInstall = catalog.filter((e) => selected.has(e.id))
    let installed = 0

    for (const entry of toInstall) {
      const specJson = await fetchExampleSpec(entry.file)
      if (specJson) {
        try {
          await onInstall(entry.name, specJson, entry.description)
          installed++
        } catch (err) {
          logWarn('ExampleCatalog', 'Failed to install example', err)
        }
      }
    }

    setInstalling(false)
    toast.success(`Installed ${installed} example app${installed !== 1 ? 's' : ''}`)
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <BookOpen className="size-5" />
            Example Apps
          </DialogTitle>
          <DialogDescription>
            Select example apps to install from the ODS catalog.
          </DialogDescription>
        </DialogHeader>

        {loading ? (
          <div className="flex items-center justify-center py-8">
            <Loader2 className="size-5 animate-spin text-muted-foreground" />
            <span className="ml-2 text-sm text-muted-foreground">Loading catalog...</span>
          </div>
        ) : !catalog ? (
          <p className="py-8 text-center text-sm text-muted-foreground">
            Could not load the example catalog. Check your internet connection.
          </p>
        ) : available && available.length === 0 ? (
          <p className="py-8 text-center text-sm text-muted-foreground">
            All available examples are already installed!
          </p>
        ) : (
          <>
            <div className="flex gap-2 text-xs">
              <button onClick={selectAll} className="text-primary hover:underline">
                Select all
              </button>
              <span className="text-muted-foreground">|</span>
              <button onClick={selectNone} className="text-primary hover:underline">
                Select none
              </button>
              <span className="ml-auto text-muted-foreground">
                {selected.size} selected
              </span>
            </div>

            <div className="max-h-[50vh] space-y-1 overflow-y-auto">
              {available?.map((entry) => (
                <label
                  key={entry.id}
                  className="flex cursor-pointer items-start gap-3 rounded-lg px-3 py-2 hover:bg-muted"
                >
                  <input
                    type="checkbox"
                    checked={selected.has(entry.id)}
                    onChange={() => toggleEntry(entry.id)}
                    className="mt-1 h-4 w-4 rounded border-input accent-primary"
                  />
                  <div className="min-w-0">
                    <div className="font-medium text-sm">{entry.name}</div>
                    <div className="text-xs text-muted-foreground line-clamp-2">
                      {entry.description}
                    </div>
                  </div>
                </label>
              ))}
            </div>
          </>
        )}

        <DialogFooter>
          {catalog && available && available.length > 0 && (
            <Button
              onClick={handleInstall}
              disabled={installing || selected.size === 0}
            >
              {installing ? (
                <Loader2 className="mr-2 size-4 animate-spin" />
              ) : (
                <Check className="mr-2 size-4" />
              )}
              Install Selected ({selected.size})
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

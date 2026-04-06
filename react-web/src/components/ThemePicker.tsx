import { useState, useEffect } from 'react'
import { loadThemeCatalog } from '@/engine/branding-service.ts'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Check, Palette } from 'lucide-react'

// ---------------------------------------------------------------------------
// ThemePicker — reusable theme selector with catalog, tag filters, color dots
// ---------------------------------------------------------------------------

const THEMES_BASE = 'https://one-does-simply.github.io/Specification/Themes'

interface ThemePickerProps {
  value: string
  onValueChange: (theme: string) => void
}

type CatalogEntry = {
  name: string
  displayName: string
  nativeScheme: string
  tags?: { style?: string; palette?: string } | string[]
}

export function ThemePicker({ value, onValueChange }: ThemePickerProps) {
  const [open, setOpen] = useState(false)
  const [catalog, setCatalog] = useState<CatalogEntry[] | null>(null)
  const [activeStyle, setActiveStyle] = useState<string | null>(null)
  const [activePalette, setActivePalette] = useState<string | null>(null)

  // Load catalog on first open
  useEffect(() => {
    if (!open || catalog) return
    loadThemeCatalog().then(setCatalog).catch(() => setCatalog([]))
  }, [open, catalog])

  // Tag helpers
  const getStyle = (tags?: CatalogEntry['tags']): string | undefined =>
    tags && !Array.isArray(tags) ? tags.style : undefined
  const getPalette = (tags?: CatalogEntry['tags']): string | undefined =>
    tags && !Array.isArray(tags) ? tags.palette : undefined

  // Collect unique tags
  const allStyles = [...new Set((catalog ?? []).map((e) => getStyle(e.tags)).filter(Boolean) as string[])].sort()
  const allPalettes = [...new Set((catalog ?? []).map((e) => getPalette(e.tags)).filter(Boolean) as string[])].sort()

  // Filter + sort
  const filteredCatalog = (catalog ?? [])
    .filter((e) => {
      if (activeStyle && getStyle(e.tags) !== activeStyle) return false
      if (activePalette && getPalette(e.tags) !== activePalette) return false
      return true
    })
    .sort((a, b) => a.displayName.localeCompare(b.displayName))

  // Find the display name for the current value
  const currentEntry = (catalog ?? []).find((e) => e.name === value)
  const displayLabel = currentEntry?.displayName ?? (value ? value.charAt(0).toUpperCase() + value.slice(1) : 'Select theme...')

  function handleSelect(themeName: string) {
    onValueChange(themeName)
    setOpen(false)
  }

  return (
    <>
      <Button
        variant="outline"
        className="w-40 justify-between gap-2 px-3 text-sm font-normal"
        onClick={() => setOpen(true)}
      >
        <div className="flex items-center gap-2 truncate">
          <Palette className="size-3.5 shrink-0 text-muted-foreground" />
          <span className="truncate">{displayLabel}</span>
        </div>
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-md max-h-[80vh] flex flex-col">
          <DialogHeader>
            <DialogTitle>Choose Theme</DialogTitle>
            <DialogDescription>
              Pick a theme for your app. Use the filters to narrow down by style or palette.
            </DialogDescription>
          </DialogHeader>

          {/* Tag filters */}
          <div className="space-y-1.5 px-1">
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

          {/* Theme grid */}
          <div className="flex-1 min-h-0 overflow-y-auto space-y-1 px-1 pb-1">
            {!catalog && (
              <div className="py-8 text-center text-sm text-muted-foreground">Loading themes...</div>
            )}
            {catalog && filteredCatalog.length === 0 && (
              <div className="py-8 text-center text-sm text-muted-foreground">No themes match the filters.</div>
            )}
            {filteredCatalog.map((entry) => (
              <ThemeCard
                key={entry.name}
                themeName={entry.name}
                displayName={entry.displayName}
                tags={entry.tags}
                isSelected={entry.name === value}
                onSelect={() => handleSelect(entry.name)}
              />
            ))}
          </div>
        </DialogContent>
      </Dialog>
    </>
  )
}

// ---------------------------------------------------------------------------
// ThemeCard — individual theme entry with color dots and tags
// ---------------------------------------------------------------------------

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
      className={`flex flex-col gap-1 rounded-lg border px-3 py-2 text-left text-sm transition-colors w-full ${
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

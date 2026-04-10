import { useState, useEffect } from 'react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog'
import { ChevronRight } from 'lucide-react'
import { hexToRgb, rgbToHex, contrastRatio, fixContrast } from '@/engine/color-helpers.ts'

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const THEMES_BASE = 'https://one-does-simply.github.io/Specification/Themes'

/** 6x8 curated color grid: 6 hue rows (reds, oranges, greens, teals, blues, purples) x 8 shades + 1 grayscale row */
export const COLOR_GRID: string[][] = [
  // Reds
  ['#FFCDD2','#EF9A9A','#E57373','#EF5350','#F44336','#E53935','#C62828','#B71C1C'],
  // Oranges / Yellows
  ['#FFE0B2','#FFCC80','#FFB74D','#FFA726','#FF9800','#FB8C00','#EF6C00','#E65100'],
  // Greens
  ['#C8E6C9','#A5D6A7','#81C784','#66BB6A','#4CAF50','#43A047','#2E7D32','#1B5E20'],
  // Teals / Cyans
  ['#B2EBF2','#80DEEA','#4DD0E1','#26C6DA','#00BCD4','#00ACC1','#00838F','#006064'],
  // Blues / Indigos
  ['#BBDEFB','#90CAF9','#64B5F6','#42A5F5','#2196F3','#1E88E5','#1565C0','#0D47A1'],
  // Purples / Pinks
  ['#E1BEE7','#CE93D8','#BA68C8','#AB47BC','#9C27B0','#8E24AA','#6A1B9A','#4A148C'],
  // Grays (black to white)
  ['#FFFFFF','#E0E0E0','#BDBDBD','#9E9E9E','#757575','#616161','#424242','#212121'],
]

export const TOKEN_HINTS: Record<string, string> = {
  primary: 'Main action buttons and links',
  secondary: 'Supporting actions and highlights',
  accent: 'Decorative elements and badges',
  neutral: 'Muted surfaces — sidebar, disabled states',
  base100: 'Page background color',
  base200: 'Cards, popovers, elevated surfaces',
  base300: 'Borders, dividers, input outlines',
  baseContent: 'Main body text color',
  error: 'Error messages and alerts',
  success: 'Success confirmations and indicators',
  warning: 'Caution indicators and alerts',
  info: 'Informational tips and help text',
}

export const TOKEN_PAIRS: Record<string, string> = {
  primary: 'primaryContent',
  secondary: 'secondaryContent',
  accent: 'accentContent',
  neutral: 'neutralContent',
  base100: 'baseContent',
  base200: 'baseContent',
  base300: 'baseContent',
  baseContent: 'base100',
  error: 'errorContent',
  success: 'successContent',
  warning: 'warningContent',
  info: 'infoContent',
}

// ---------------------------------------------------------------------------
// oklchToHex — convert oklch CSS string to hex by rendering in the DOM
// ---------------------------------------------------------------------------

function oklchToHex(oklch: string): string {
  const el = document.createElement('div')
  el.style.color = oklch
  document.body.appendChild(el)
  const computed = getComputedStyle(el).color
  document.body.removeChild(el)
  const match = computed.match(/(\d+)/g)
  if (match && match.length >= 3) {
    return '#' + match.slice(0, 3).map((n: string) => parseInt(n).toString(16).padStart(2, '0')).join('')
  }
  return '#888888'
}

// ---------------------------------------------------------------------------
// ColorRow — a row component showing a color swatch, label, and picker dialog
// ---------------------------------------------------------------------------

export function ColorRow({
  label,
  token,
  themeName,
  override,
  onChange,
  onReset,
}: {
  label: string
  token: string
  themeName: string
  override?: string
  onChange: (hex: string) => void
  onReset: () => void
}) {
  const [baseColor, setBaseColor] = useState<string>('#888888')
  const [pairedColor, setPairedColor] = useState<string | null>(null)
  const [pickerOpen, setPickerOpen] = useState(false)

  useEffect(() => {
    let cancelled = false
    fetch(`${THEMES_BASE}/${themeName}.json`)
      .then((r) => r.json())
      .then((data) => {
        if (cancelled) return
        const variant = data.light ?? data.dark
        const colors = variant?.colors
        if (colors?.[token]) setBaseColor(oklchToHex(colors[token]))
        const pairToken = TOKEN_PAIRS[token]
        if (pairToken && colors?.[pairToken]) setPairedColor(oklchToHex(colors[pairToken]))
      })
      .catch(() => {})
    return () => { cancelled = true }
  }, [themeName, token])

  const displayColor = override ?? baseColor

  return (
    <>
      <div className="flex items-center gap-3">
        <button
          type="button"
          className="size-8 shrink-0 rounded-lg border border-border shadow-sm transition-shadow hover:shadow-md"
          style={{ background: displayColor }}
          title={`Pick ${label} color`}
          onClick={() => setPickerOpen(true)}
        />
        <div className="flex-1">
          <div className="text-sm font-medium">{label}</div>
          {override && <div className="text-xs text-primary">Custom</div>}
        </div>
        {override && (
          <button
            type="button"
            onClick={onReset}
            className="text-xs text-muted-foreground hover:text-foreground"
          >
            Reset
          </button>
        )}
      </div>

      <Dialog open={pickerOpen} onOpenChange={setPickerOpen}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Pick {label} Color</DialogTitle>
            <DialogDescription>{TOKEN_HINTS[token] ?? 'Choose a color'}</DialogDescription>
          </DialogHeader>
          <GridColorPicker
            currentColor={displayColor}
            pairedColor={pairedColor}
            token={token}
            onSelect={(hex) => { onChange(hex); setPickerOpen(false) }}
            onCancel={() => setPickerOpen(false)}
          />
        </DialogContent>
      </Dialog>
    </>
  )
}

// ---------------------------------------------------------------------------
// WhyAccessiblePopover
// ---------------------------------------------------------------------------

export function WhyAccessiblePopover() {
  const [open, setOpen] = useState(false)
  return (
    <>
      <button
        type="button"
        className="text-[10px] text-primary hover:underline"
        onClick={() => setOpen(true)}
      >
        Why?
      </button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Why Color Contrast Matters</DialogTitle>
            <DialogDescription>Making your app usable for everyone</DialogDescription>
          </DialogHeader>
          <div className="space-y-2 text-sm text-muted-foreground">
            <p>
              Color contrast is the difference in brightness between text and its background.
              When contrast is too low, text becomes hard or impossible to read — especially for people
              with low vision, color blindness, or anyone using a screen in bright sunlight.
            </p>
            <p>
              The <span className="font-medium text-foreground">WCAG AA standard</span> requires a minimum contrast ratio of
              {' '}<span className="font-medium text-foreground">4.5:1</span> for normal text. This is the internationally
              recognized benchmark for web accessibility, and ODS enforces it for all built-in themes.
            </p>
            <p>
              Colors in the <span className="font-medium text-foreground">Recommended</span> section meet this standard against
              the text that will appear on top of them. You can still pick any color, but low-contrast choices will show a warning.
            </p>
          </div>
        </DialogContent>
      </Dialog>
    </>
  )
}

// ---------------------------------------------------------------------------
// GridColorPicker — the picker dialog content with grid, contrast, hex, RGB
// ---------------------------------------------------------------------------

export function GridColorPicker({
  currentColor,
  pairedColor,
  _token,
  onSelect,
  onCancel,
}: {
  currentColor: string
  pairedColor: string | null
  token: string
  onSelect: (hex: string) => void
  onCancel: () => void
}) {
  const [selected, setSelected] = useState(currentColor)
  const [showRgb, setShowRgb] = useState(false)
  const [hexInput, setHexInput] = useState(currentColor)

  useEffect(() => { setHexInput(selected) }, [selected])

  const [r, g, b] = hexToRgb(selected)

  // Contrast against paired color
  const ratio = pairedColor ? contrastRatio(selected, pairedColor) : null
  const passesAA = ratio !== null && ratio >= 4.5

  return (
    <div className="space-y-3">
      {/* Current vs New preview */}
      <div className="flex items-center gap-3">
        <div className="flex-1 text-center">
          <div className="mb-1 text-[10px] font-medium text-muted-foreground">Current</div>
          <div className="mx-auto h-10 w-full rounded-lg border border-border" style={{ background: currentColor }} />
        </div>
        <div className="flex-1 text-center">
          <div className="mb-1 text-[10px] font-medium text-muted-foreground">New</div>
          <div className="mx-auto h-10 w-full rounded-lg border border-border" style={{ background: selected }} />
        </div>
        {ratio !== null && (
          <div className="flex-1 text-center">
            <div className="mb-1 text-[10px] font-medium text-muted-foreground">Contrast</div>
            <div className={`rounded-lg border px-2 py-2 text-xs font-semibold ${passesAA ? 'border-green-200 bg-green-50 text-green-700 dark:border-green-800 dark:bg-green-950 dark:text-green-400' : 'border-red-200 bg-red-50 text-red-700 dark:border-red-800 dark:bg-red-950 dark:text-red-400'}`}>
              {ratio.toFixed(1)}:1 {passesAA ? '\u2713' : '\u26A0'}
            </div>
          </div>
        )}
      </div>

      {/* Color grid — split into recommended (passes contrast) and other */}
      {(() => {
        const allColors = COLOR_GRID.flat()
        const gridCols = 8

        // Build recommended: original accessible colors + fixed versions of non-accessible ones
        const recommended: string[] = []
        const other: string[] = []
        const seen = new Set<string>()

        if (pairedColor) {
          for (const hex of allColors) {
            if (contrastRatio(hex, pairedColor) >= 4.5) {
              recommended.push(hex)
              seen.add(hex.toUpperCase())
            } else {
              other.push(hex)
            }
          }
          // Add fixed versions of failing colors (deduplicated)
          for (const hex of other) {
            const fixed = fixContrast(hex, pairedColor)
            if (!seen.has(fixed.toUpperCase())) {
              recommended.push(fixed)
              seen.add(fixed.toUpperCase())
            }
          }
        } else {
          recommended.push(...allColors)
        }

        const renderGrid = (colors: string[]) => {
          const rows: string[][] = []
          for (let i = 0; i < colors.length; i += gridCols) rows.push(colors.slice(i, i + gridCols))
          return rows.map((row, ri) => (
            <div key={ri} className="flex gap-0.5">
              {row.map((hex) => (
                <button
                  key={hex}
                  type="button"
                  className={`h-7 flex-1 rounded-sm border transition-transform hover:scale-110 ${selected.toUpperCase() === hex.toUpperCase() ? 'ring-2 ring-primary ring-offset-1' : 'border-transparent'}`}
                  style={{ background: hex }}
                  onClick={() => setSelected(hex)}
                  title={hex}
                />
              ))}
              {/* Pad last row */}
              {row.length < gridCols && Array.from({ length: gridCols - row.length }).map((_, i) => (
                <div key={`pad-${i}`} className="h-7 flex-1" />
              ))}
            </div>
          ))
        }

        return (
          <div className="space-y-2">
            {recommended.length > 0 && (
              <div>
                {pairedColor && (
                  <div className="mb-1 flex items-center gap-1.5 text-[10px] font-medium text-muted-foreground">
                    Recommended (accessible)
                    <WhyAccessiblePopover />
                  </div>
                )}
                <div className="space-y-0.5">{renderGrid(recommended)}</div>
              </div>
            )}
            {other.length > 0 && (
              <div>
                <div className="mb-1 text-[10px] font-medium text-muted-foreground">Other (low contrast)</div>
                <div className="space-y-0.5 opacity-50">{renderGrid(other)}</div>
              </div>
            )}
          </div>
        )
      })()}

      {/* Contrast warning banner */}
      {ratio !== null && !passesAA && pairedColor && (
        <div className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-xs text-red-700 dark:border-red-800 dark:bg-red-950 dark:text-red-400">
          This color may make text hard to read. A contrast ratio of at least 4.5:1 is needed for accessible text.{' '}
          <button
            type="button"
            className="inline font-semibold underline hover:no-underline"
            onClick={() => setSelected(fixContrast(selected, pairedColor))}
          >
            Fix for me
          </button>
        </div>
      )}

      {/* Hex input */}
      <div className="flex items-center gap-2">
        <Label className="text-xs">Hex</Label>
        <Input
          className="h-7 flex-1 font-mono text-xs"
          value={hexInput}
          onChange={(e) => {
            setHexInput(e.target.value)
            const v = e.target.value.trim()
            if (/^#[0-9a-fA-F]{6}$/.test(v)) setSelected(v)
          }}
        />
      </div>

      {/* Collapsible RGB sliders */}
      <button
        type="button"
        className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
        onClick={() => setShowRgb(!showRgb)}
      >
        <ChevronRight className={`size-3 transition-transform ${showRgb ? 'rotate-90' : ''}`} />
        Custom RGB color
      </button>

      {showRgb && (
        <div className="space-y-2 pl-1">
          {([['R', r, 0], ['G', g, 1], ['B', b, 2]] as const).map(([ch, val, idx]) => (
            <div key={ch} className="flex items-center gap-2">
              <span className="w-3 text-xs font-semibold" style={{ color: ch === 'R' ? '#e53935' : ch === 'G' ? '#43a047' : '#1e88e5' }}>{ch}</span>
              <input
                type="range"
                min={0}
                max={255}
                value={val}
                className="h-1.5 flex-1 appearance-none rounded-full"
                style={{
                  background: `linear-gradient(to right, ${rgbToHex(...([r, g, b].map((c, i) => i === idx ? 0 : c) as [number, number, number]))}, ${rgbToHex(...([r, g, b].map((c, i) => i === idx ? 255 : c) as [number, number, number]))})`,
                }}
                onChange={(e) => {
                  const rgb: [number, number, number] = [r, g, b]
                  rgb[idx] = parseInt(e.target.value)
                  setSelected(rgbToHex(...rgb))
                }}
              />
              <span className="w-7 text-right font-mono text-xs">{val}</span>
            </div>
          ))}
        </div>
      )}

      {/* Actions */}
      <div className="flex justify-end gap-2 pt-1">
        <Button variant="outline" size="sm" onClick={onCancel}>Cancel</Button>
        <Button size="sm" onClick={() => onSelect(selected)}>Select</Button>
      </div>
    </div>
  )
}

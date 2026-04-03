// ---------------------------------------------------------------------------
// Color helper utilities — WCAG contrast, hex/RGB conversion, contrast fixing
// Extracted from QuickBuildScreen for testability and reuse.
// ---------------------------------------------------------------------------

export function hexToRgb(hex: string): [number, number, number] {
  const h = hex.replace('#', '')
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)]
}

export function rgbToHex(r: number, g: number, b: number): string {
  return '#' + [r, g, b].map((c) => Math.max(0, Math.min(255, Math.round(c))).toString(16).padStart(2, '0')).join('')
}

/** WCAG relative luminance from sRGB hex */
export function relativeLuminance(hex: string): number {
  const [r, g, b] = hexToRgb(hex).map((c) => {
    const s = c / 255
    return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4
  })
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

export function contrastRatio(hex1: string, hex2: string): number {
  const l1 = relativeLuminance(hex1)
  const l2 = relativeLuminance(hex2)
  const lighter = Math.max(l1, l2)
  const darker = Math.min(l1, l2)
  return (lighter + 0.05) / (darker + 0.05)
}

/** Find the closest accessible hex color by adjusting lightness toward the paired color's opposite. */
export function fixContrast(hex: string, pairedHex: string): string {
  const [r, g, b] = hexToRgb(hex)
  const pairedLum = relativeLuminance(pairedHex)
  // Determine direction: if paired is dark, we need to go lighter, and vice versa
  const goLighter = pairedLum < 0.2

  // Binary search on a brightness multiplier
  let lo = 0, hi = 1
  let bestHex = hex
  for (let iter = 0; iter < 30; iter++) {
    const mid = (lo + hi) / 2
    // Blend toward white (goLighter) or black (!goLighter)
    const nr = goLighter ? r + (255 - r) * mid : r * (1 - mid)
    const ng = goLighter ? g + (255 - g) * mid : g * (1 - mid)
    const nb = goLighter ? b + (255 - b) * mid : b * (1 - mid)
    const candidate = rgbToHex(Math.round(nr), Math.round(ng), Math.round(nb))
    const ratio = contrastRatio(candidate, pairedHex)
    if (ratio >= 4.5) {
      bestHex = candidate
      hi = mid // Try to stay closer to the original
    } else {
      lo = mid
    }
  }
  return bestHex
}

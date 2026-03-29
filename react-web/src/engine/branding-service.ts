import type { OdsBranding } from '../models/ods-branding.ts'

/**
 * Applies ODS branding to the document by overriding CSS custom properties.
 *
 * ODS Ethos: The builder provides a single hex color and a couple of style
 * hints. This service derives a full light/dark palette, sets border-radius,
 * loads fonts, and configures the favicon — all from those simple inputs.
 */

const DEFAULT_PRIMARY = '#4F46E5'

// ---------------------------------------------------------------------------
// Hex → OKLCH conversion (simplified, suitable for CSS custom property values)
// ---------------------------------------------------------------------------

function hexToRgb(hex: string): [number, number, number] {
  const h = hex.replace('#', '')
  return [
    parseInt(h.slice(0, 2), 16) / 255,
    parseInt(h.slice(2, 4), 16) / 255,
    parseInt(h.slice(4, 6), 16) / 255,
  ]
}

/** Convert linear sRGB to OKLCH (approximate). */
function rgbToOklch(r: number, g: number, b: number): [number, number, number] {
  // sRGB → linear
  const toLinear = (c: number) => c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
  const lr = toLinear(r)
  const lg = toLinear(g)
  const lb = toLinear(b)

  // Linear sRGB → OKLab
  const l_ = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb
  const m_ = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb
  const s_ = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb
  const l = Math.cbrt(l_)
  const m = Math.cbrt(m_)
  const s = Math.cbrt(s_)
  const L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
  const a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
  const bOk = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s

  // OKLab → OKLCH
  const C = Math.sqrt(a * a + bOk * bOk)
  let H = (Math.atan2(bOk, a) * 180) / Math.PI
  if (H < 0) H += 360

  return [L, C, H]
}

function hexToOklch(hex: string): string {
  const [r, g, b] = hexToRgb(hex)
  const [L, C, H] = rgbToOklch(r, g, b)
  return `oklch(${L.toFixed(3)} ${C.toFixed(3)} ${H.toFixed(1)})`
}

/** Generate a lighter variant (for backgrounds, accents). */
function lighten(hex: string, amount: number): string {
  const [r, g, b] = hexToRgb(hex)
  const [L, C, H] = rgbToOklch(r, g, b)
  return `oklch(${Math.min(1, L + amount).toFixed(3)} ${(C * 0.3).toFixed(3)} ${H.toFixed(1)})`
}

/** Generate a darker variant. */
function darken(hex: string, amount: number): string {
  const [r, g, b] = hexToRgb(hex)
  const [L, C, H] = rgbToOklch(r, g, b)
  return `oklch(${Math.max(0, L - amount).toFixed(3)} ${(C * 0.5).toFixed(3)} ${H.toFixed(1)})`
}

// ---------------------------------------------------------------------------
// Apply / reset branding
// ---------------------------------------------------------------------------

/** Saved original CSS variable values for restoration on reset. */
let savedOriginals: Map<string, string> | null = null

/**
 * Apply branding from an ODS spec to the document. Overrides CSS custom
 * properties for colors, radius, and font. Sets favicon if provided.
 */
export function applyBranding(branding: OdsBranding): void {
  const root = document.documentElement
  const style = root.style

  // Save originals on first call so we can restore them later
  if (!savedOriginals) {
    savedOriginals = new Map()
    const computed = getComputedStyle(root)
    for (const prop of CSS_PROPS_TO_OVERRIDE) {
      savedOriginals.set(prop, computed.getPropertyValue(prop))
    }
  }

  const primary = branding.primaryColor || DEFAULT_PRIMARY
  const accent = branding.accentColor || primary

  // Primary color
  const primaryOklch = hexToOklch(primary)
  style.setProperty('--primary', primaryOklch)
  style.setProperty('--ring', primaryOklch)
  style.setProperty('--sidebar-primary', primaryOklch)
  style.setProperty('--sidebar-ring', primaryOklch)
  style.setProperty('--chart-1', primaryOklch)

  // Accent (derived from accent color or primary)
  style.setProperty('--accent', lighten(accent, 0.55))
  style.setProperty('--accent-foreground', darken(accent, 0.15))
  style.setProperty('--sidebar-accent', lighten(accent, 0.55))
  style.setProperty('--sidebar-accent-foreground', darken(accent, 0.15))

  // Corner style → radius
  const radiusMap = { sharp: '0.25rem', rounded: '0.625rem', pill: '1.5rem' }
  style.setProperty('--radius', radiusMap[branding.cornerStyle] ?? '0.625rem')

  // Font family
  if (branding.fontFamily) {
    style.setProperty('--font-sans', `'${branding.fontFamily}', sans-serif`)
    style.setProperty('--font-heading', `'${branding.fontFamily}', sans-serif`)
    root.style.fontFamily = `'${branding.fontFamily}', system-ui, sans-serif`
  }

  // Favicon
  if (branding.favicon) {
    let link = document.querySelector<HTMLLinkElement>('link[rel="icon"]')
    if (!link) {
      link = document.createElement('link')
      link.rel = 'icon'
      document.head.appendChild(link)
    }
    link.href = branding.favicon
  }

  // Header style is handled by the AppShell component reading branding.headerStyle
}

/** Reset all branding overrides back to the original CSS values. */
export function resetBranding(): void {
  if (!savedOriginals) return
  const style = document.documentElement.style
  for (const [prop, value] of savedOriginals) {
    style.setProperty(prop, value)
  }
  // Reset font
  document.documentElement.style.fontFamily = ''
  savedOriginals = null
}

const CSS_PROPS_TO_OVERRIDE = [
  '--primary', '--ring', '--sidebar-primary', '--sidebar-ring',
  '--accent', '--accent-foreground', '--sidebar-accent', '--sidebar-accent-foreground',
  '--radius', '--font-sans', '--font-heading', '--chart-1',
]

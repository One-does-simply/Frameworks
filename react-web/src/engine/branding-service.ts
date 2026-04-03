import type { OdsBranding } from '../models/ods-branding.ts'

/**
 * Applies ODS branding to the document by loading a theme from the catalog
 * and mapping its design tokens to CSS custom properties.
 *
 * ODS Ethos: The builder picks a theme name. This service does everything else.
 */

// Theme catalog URL — fetched from the ODS GitHub Pages site
const THEMES_BASE = 'https://one-does-simply.github.io/Specification/Themes'

/** Cached theme data to avoid refetching. */
const themeCache = new Map<string, Record<string, unknown>>()

/** Saved original CSS variable values for restoration on reset. */
let savedOriginals: Map<string, string> | null = null

// ---------------------------------------------------------------------------
// Token → CSS variable mapping (DaisyUI → shadcn)
// ---------------------------------------------------------------------------

const COLOR_MAP: Record<string, string[]> = {
  primary:          ['--primary', '--ring', '--sidebar-primary', '--sidebar-ring', '--chart-1'],
  primaryContent:   ['--primary-foreground', '--sidebar-primary-foreground'],
  secondary:        ['--secondary', '--chart-2'],
  secondaryContent: ['--secondary-foreground'],
  accent:           ['--accent', '--sidebar-accent', '--chart-3'],
  accentContent:    ['--accent-foreground', '--sidebar-accent-foreground'],
  neutral:          ['--muted'],
  neutralContent:   ['--muted-foreground'],
  base100:          ['--background', '--card', '--sidebar'],
  base200:          ['--popover'],
  base300:          ['--border', '--input', '--sidebar-border'],
  baseContent:      ['--foreground', '--card-foreground', '--popover-foreground', '--sidebar-foreground'],
  info:             ['--chart-4'],
  success:          ['--chart-5'],
  error:            ['--destructive'],
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/** Load a theme JSON from the catalog (cached). */
export async function loadTheme(themeName: string): Promise<Record<string, unknown> | null> {
  if (themeCache.has(themeName)) return themeCache.get(themeName)!
  try {
    const resp = await fetch(`${THEMES_BASE}/${themeName}.json`)
    if (!resp.ok) return null
    const data = await resp.json()
    themeCache.set(themeName, data)
    return data
  } catch {
    return null
  }
}

/** Resolve which mode to use (light/dark/system → light or dark). */
function resolveMode(mode: string): 'light' | 'dark' {
  if (mode === 'light' || mode === 'dark') return mode
  // system — check OS preference
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
}

/**
 * Apply branding from an ODS spec to the document.
 * Loads the theme, resolves the mode, maps tokens to CSS variables.
 */
export async function applyBranding(branding: OdsBranding): Promise<void> {
  const root = document.documentElement
  const style = root.style

  // Save originals on first call
  if (!savedOriginals) {
    savedOriginals = new Map()
    const computed = getComputedStyle(root)
    for (const props of Object.values(COLOR_MAP)) {
      for (const prop of props) {
        savedOriginals.set(prop, computed.getPropertyValue(prop))
      }
    }
    savedOriginals.set('--radius', getComputedStyle(root).getPropertyValue('--radius'))
    savedOriginals.set('--font-sans', getComputedStyle(root).getPropertyValue('--font-sans'))
  }

  // Load theme
  const themeData = await loadTheme(branding.theme || 'indigo')
  if (!themeData) return

  // Resolve mode
  const mode = resolveMode(branding.mode)
  const variant = themeData[mode] as Record<string, unknown> | undefined
  if (!variant) return

  const colors = variant['colors'] as Record<string, string> | undefined
  const design = themeData['design'] as Record<string, string> | undefined  // design is at theme level
  if (!colors) return

  // Apply token overrides from spec
  const mergedColors = { ...colors, ...(branding.overrides ?? {}) }

  // Map color tokens to CSS variables
  for (const [token, cssProps] of Object.entries(COLOR_MAP)) {
    const value = mergedColors[token]
    if (value) {
      for (const prop of cssProps) {
        style.setProperty(prop, value)
      }
    }
  }

  // Apply dark class based on mode
  if (mode === 'dark') {
    root.classList.add('dark')
  } else {
    root.classList.remove('dark')
  }

  // Design tokens
  if (design) {
    const radiusBox = branding.overrides?.radiusBox ?? design['radiusBox']
    if (radiusBox) style.setProperty('--radius', radiusBox)
  }

  // Font family
  if (branding.fontFamily) {
    style.setProperty('--font-sans', `'${branding.fontFamily}', sans-serif`)
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
}

/** Reset all branding overrides back to the original CSS values. */
export function resetBranding(): void {
  if (!savedOriginals) return
  const style = document.documentElement.style
  for (const [prop, value] of savedOriginals) {
    style.setProperty(prop, value)
  }
  document.documentElement.style.fontFamily = ''
  document.documentElement.classList.remove('dark')
  savedOriginals = null
}

/** Get the list of available themes from the catalog. */
export async function loadThemeCatalog(): Promise<Array<{ name: string; displayName: string; nativeScheme: string; tags?: { style?: string; palette?: string } | string[] }>> {
  try {
    const resp = await fetch(`${THEMES_BASE}/catalog.json`)
    if (!resp.ok) return []
    const data = await resp.json()
    return data.themes ?? []
  } catch {
    return []
  }
}

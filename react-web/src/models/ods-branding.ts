/** App-level branding and theming configuration. */
export interface OdsBranding {
  /** Named theme from the catalog (e.g., 'corporate', 'nord', 'dracula'). */
  theme: string
  /** Color mode: light, dark, or system. */
  mode: 'light' | 'dark' | 'system'
  /** Logo URL for sidebar/drawer header. */
  logo?: string
  /** Favicon URL for browser tab. */
  favicon?: string
  /** App bar style. */
  headerStyle: 'solid' | 'light' | 'transparent'
  /** Custom font family. */
  fontFamily?: string
  /** Per-token overrides on top of the theme. */
  overrides?: Record<string, string>
}

export function parseBranding(json: unknown): OdsBranding {
  if (json == null || typeof json !== 'object') {
    return { theme: 'indigo', mode: 'system', headerStyle: 'light' }
  }
  const j = json as Record<string, unknown>

  // Backward compatibility: legacy format had primaryColor/cornerStyle
  if (j['primaryColor'] && !j['theme']) {
    const overrides: Record<string, string> = {}
    if (j['primaryColor']) overrides.primary = j['primaryColor'] as string
    if (j['accentColor']) overrides.accent = j['accentColor'] as string
    return {
      theme: 'indigo',
      mode: 'system',
      logo: j['logo'] as string | undefined,
      favicon: j['favicon'] as string | undefined,
      headerStyle: (['solid', 'light', 'transparent'].includes(j['headerStyle'] as string)
        ? j['headerStyle'] as 'solid' | 'light' | 'transparent'
        : 'light'),
      fontFamily: j['fontFamily'] as string | undefined,
      overrides: Object.keys(overrides).length > 0 ? overrides : undefined,
    }
  }

  let parsedTheme = (j['theme'] as string) ?? 'indigo'
  if (parsedTheme === 'light') parsedTheme = 'indigo'
  if (parsedTheme === 'dark') parsedTheme = 'slate'

  return {
    theme: parsedTheme,
    mode: (['light', 'dark', 'system'].includes(j['mode'] as string)
      ? j['mode'] as 'light' | 'dark' | 'system'
      : 'system'),
    logo: j['logo'] as string | undefined,
    favicon: j['favicon'] as string | undefined,
    headerStyle: (['solid', 'light', 'transparent'].includes(j['headerStyle'] as string)
      ? j['headerStyle'] as 'solid' | 'light' | 'transparent'
      : 'light'),
    fontFamily: j['fontFamily'] as string | undefined,
    overrides: j['overrides'] as Record<string, string> | undefined,
  }
}

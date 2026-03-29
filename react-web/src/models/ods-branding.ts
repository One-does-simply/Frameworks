/** App-level branding and theming configuration. */
export interface OdsBranding {
  primaryColor: string
  accentColor?: string
  fontFamily?: string
  logo?: string
  favicon?: string
  headerStyle: 'solid' | 'light' | 'transparent'
  cornerStyle: 'rounded' | 'sharp' | 'pill'
}

const DEFAULT_PRIMARY = '#4F46E5'

export function parseBranding(json: unknown): OdsBranding {
  if (json == null || typeof json !== 'object') {
    return { primaryColor: DEFAULT_PRIMARY, headerStyle: 'light', cornerStyle: 'rounded' }
  }
  const j = json as Record<string, unknown>
  return {
    primaryColor: (j['primaryColor'] as string) ?? DEFAULT_PRIMARY,
    accentColor: j['accentColor'] as string | undefined,
    fontFamily: j['fontFamily'] as string | undefined,
    logo: j['logo'] as string | undefined,
    favicon: j['favicon'] as string | undefined,
    headerStyle: (['solid', 'light', 'transparent'].includes(j['headerStyle'] as string)
      ? j['headerStyle'] as 'solid' | 'light' | 'transparent'
      : 'light'),
    cornerStyle: (['rounded', 'sharp', 'pill'].includes(j['cornerStyle'] as string)
      ? j['cornerStyle'] as 'rounded' | 'sharp' | 'pill'
      : 'rounded'),
  }
}

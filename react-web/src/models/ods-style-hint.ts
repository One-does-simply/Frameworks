/** An open-ended bag of styling hints attached to any ODS component. */
export type OdsStyleHint = Record<string, unknown>

/** Type-safe accessor for a hint key. */
export function getHint<T>(hint: OdsStyleHint, key: string): T | undefined {
  const value = hint[key]
  return value as T | undefined
}

// Convenience accessors matching Flutter's OdsStyleHint getters
export const hintVariant = (h: OdsStyleHint) => getHint<string>(h, 'variant')
export const hintEmphasis = (h: OdsStyleHint) => getHint<string>(h, 'emphasis')
export const hintAlign = (h: OdsStyleHint) => getHint<string>(h, 'align')
export const hintColor = (h: OdsStyleHint) => getHint<string>(h, 'color')
export const hintIcon = (h: OdsStyleHint) => getHint<string>(h, 'icon')
export const hintSize = (h: OdsStyleHint) => getHint<string>(h, 'size')
export const hintDensity = (h: OdsStyleHint) => getHint<string>(h, 'density')
export const hintElevation = (h: OdsStyleHint): number | undefined => {
  const v = h['elevation']
  if (typeof v === 'number') return Math.floor(v)
  return undefined
}

export function parseStyleHint(json: unknown): OdsStyleHint {
  if (json != null && typeof json === 'object' && !Array.isArray(json)) {
    return json as OdsStyleHint
  }
  return {}
}

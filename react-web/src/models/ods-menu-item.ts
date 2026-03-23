/** A single entry in the application's navigation menu. */
export interface OdsMenuItem {
  label: string
  mapsTo: string
  roles?: string[]
}

export function parseMenuItem(json: unknown): OdsMenuItem {
  const j = json as Record<string, unknown>
  return {
    label: j['label'] as string,
    mapsTo: j['mapsTo'] as string,
    roles: j['roles'] as string[] | undefined,
  }
}

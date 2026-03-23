/** Row-level security configuration for a data source. */
export interface OdsOwnership {
  enabled: boolean
  ownerField: string
  adminOverride: boolean
}

export function parseOwnership(json: unknown): OdsOwnership {
  if (json == null || typeof json !== 'object') {
    return { enabled: false, ownerField: '_owner', adminOverride: true }
  }
  const j = json as Record<string, unknown>
  return {
    enabled: (j['enabled'] as boolean) ?? false,
    ownerField: (j['ownerField'] as string) ?? '_owner',
    adminOverride: (j['adminOverride'] as boolean) ?? true,
  }
}

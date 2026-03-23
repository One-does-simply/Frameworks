/** Multi-user authentication and role configuration. */
export interface OdsAuth {
  multiUser: boolean
  multiUserOnly: boolean
  customRoles: string[]
  defaultRole: string
}

/** All available roles: three built-ins plus custom. */
export function allRoles(auth: OdsAuth): string[] {
  return ['guest', 'user', 'admin', ...auth.customRoles]
}

export function parseAuth(json: unknown): OdsAuth {
  if (json == null || typeof json !== 'object') {
    return { multiUser: false, multiUserOnly: false, customRoles: [], defaultRole: 'user' }
  }
  const j = json as Record<string, unknown>
  return {
    multiUser: (j['multiUser'] as boolean) ?? false,
    multiUserOnly: (j['multiUserOnly'] as boolean) ?? false,
    customRoles: (j['roles'] as string[]) ?? [],
    defaultRole: (j['defaultRole'] as string) ?? 'user',
  }
}

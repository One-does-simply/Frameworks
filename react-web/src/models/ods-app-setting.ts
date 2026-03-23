/** A single user-configurable app setting. */
export interface OdsAppSetting {
  label: string
  type: string
  defaultValue: string
  options?: string[]
}

export function parseAppSetting(json: unknown): OdsAppSetting {
  const j = json as Record<string, unknown>
  return {
    label: (j['label'] as string) ?? '',
    type: (j['type'] as string) ?? 'text',
    defaultValue: (j['default'] as string) ?? '',
    options: j['options'] as string[] | undefined,
  }
}

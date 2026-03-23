/** Conditional visibility rule for components (field-based or data-based). */
export interface OdsComponentVisibleWhen {
  field?: string
  form?: string
  equals?: string
  notEquals?: string
  source?: string
  countEquals?: number
  countMin?: number
  countMax?: number
}

export function isFieldBased(v: OdsComponentVisibleWhen): boolean {
  return v.field != null && v.form != null
}

export function isDataBased(v: OdsComponentVisibleWhen): boolean {
  return v.source != null
}

export function parseComponentVisibleWhen(json: unknown): OdsComponentVisibleWhen | undefined {
  if (json == null || typeof json !== 'object') return undefined
  const j = json as Record<string, unknown>
  return {
    field: j['field'] as string | undefined,
    form: j['form'] as string | undefined,
    equals: j['equals'] != null ? String(j['equals']) : undefined,
    notEquals: j['notEquals'] != null ? String(j['notEquals']) : undefined,
    source: j['source'] as string | undefined,
    countEquals: j['countEquals'] as number | undefined,
    countMin: j['countMin'] as number | undefined,
    countMax: j['countMax'] as number | undefined,
  }
}

/** Field-level visibility condition (simpler than component-level). */
export interface OdsVisibleWhen {
  field: string
  equals: string
}

export function parseVisibleWhen(json: unknown): OdsVisibleWhen | undefined {
  if (json == null || typeof json !== 'object') return undefined
  const j = json as Record<string, unknown>
  return {
    field: j['field'] as string,
    equals: j['equals'] as string,
  }
}

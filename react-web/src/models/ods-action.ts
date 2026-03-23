/** A computed field value evaluated at submit time. */
export interface OdsComputedField {
  field: string
  expression: string
}

function parseComputedField(json: unknown): OdsComputedField {
  const j = json as Record<string, unknown>
  return { field: j['field'] as string, expression: j['expression'] as string }
}

/** An action triggered by user interaction (button tap, row action, etc.). */
export interface OdsAction {
  action: string
  target?: string
  dataSource?: string
  matchField?: string
  populateForm?: string
  withData?: Record<string, unknown>
  confirm?: string
  computedFields: OdsComputedField[]
  filter?: Record<string, string>
  onEnd?: OdsAction
  message?: string
  cascade?: Record<string, string>
  preserveFields: string[]
}

// Helper type guards
export const isNavigate = (a: OdsAction) => a.action === 'navigate'
export const isSubmit = (a: OdsAction) => a.action === 'submit'
export const isUpdate = (a: OdsAction) => a.action === 'update'
export const isShowMessage = (a: OdsAction) => a.action === 'showMessage'
export const isRecordAction = (a: OdsAction) =>
  a.action === 'firstRecord' || a.action === 'nextRecord' ||
  a.action === 'previousRecord' || a.action === 'lastRecord'

export function parseAction(json: unknown): OdsAction {
  const j = json as Record<string, unknown>
  const filterRaw = j['filter'] as Record<string, unknown> | undefined
  const onEndRaw = j['onEnd'] as Record<string, unknown> | undefined
  const cascadeRaw = j['cascade'] as Record<string, unknown> | undefined

  return {
    action: j['action'] as string,
    target: j['target'] as string | undefined,
    dataSource: j['dataSource'] as string | undefined,
    matchField: j['matchField'] as string | undefined,
    populateForm: j['populateForm'] as string | undefined,
    withData: j['withData'] as Record<string, unknown> | undefined,
    confirm: j['confirm'] as string | undefined,
    computedFields: Array.isArray(j['computedFields'])
      ? (j['computedFields'] as unknown[]).map(parseComputedField)
      : [],
    filter: filterRaw
      ? Object.fromEntries(Object.entries(filterRaw).map(([k, v]) => [k, String(v)]))
      : undefined,
    onEnd: onEndRaw ? parseAction(onEndRaw) : undefined,
    message: j['message'] as string | undefined,
    cascade: cascadeRaw
      ? Object.fromEntries(Object.entries(cascadeRaw).map(([k, v]) => [k, String(v)]))
      : undefined,
    preserveFields: (j['preserveFields'] as string[]) ?? [],
  }
}

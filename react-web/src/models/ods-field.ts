import { parseVisibleWhen, type OdsVisibleWhen } from './ods-visible-when.ts'

/** Filters dynamic options based on a sibling field's value. */
export interface OdsOptionsFilter {
  field: string
  fromField: string
}

/** Dynamic option source for select fields. */
export interface OdsOptionsFrom {
  dataSource: string
  valueField: string
  filter?: OdsOptionsFilter
}

/** Validation constraints beyond required. */
export interface OdsValidation {
  min?: number
  max?: number
  minLength?: number
  pattern?: string
  message?: string
}

/** Validates a value and returns an error message, or undefined if valid. */
export function validateField(
  validation: OdsValidation | undefined,
  value: string,
  fieldType: string,
): string | undefined {
  if (!validation || !value) return undefined

  if (fieldType === 'email') {
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value)) {
      return validation.message ?? 'Please enter a valid email address'
    }
  }

  if (validation.minLength != null && value.length < validation.minLength) {
    return validation.message ?? `Must be at least ${validation.minLength} characters`
  }

  if (validation.pattern != null) {
    if (!new RegExp(validation.pattern).test(value)) {
      return validation.message ?? 'Invalid format'
    }
  }

  if ((validation.min != null || validation.max != null) && fieldType === 'number') {
    const parsed = Number(value)
    if (isNaN(parsed)) return undefined
    if (validation.min != null && parsed < validation.min) {
      return validation.message ?? `Must be at least ${validation.min}`
    }
    if (validation.max != null && parsed > validation.max) {
      return validation.message ?? `Must be at most ${validation.max}`
    }
  }

  return undefined
}

/** A single field/column definition used in forms and data sources. */
export interface OdsFieldDefinition {
  name: string
  type: string
  label?: string
  required: boolean
  placeholder?: string
  defaultValue?: string
  options?: string[]
  optionsFrom?: OdsOptionsFrom
  formula?: string
  visibleWhen?: OdsVisibleWhen
  validation?: OdsValidation
  currency: boolean
  readOnly: boolean
  displayVariant?: string
  optionLabels?: string[]
  roles?: string[]
}

export const isComputed = (f: OdsFieldDefinition) => f.formula != null

export function parseFieldDefinition(json: unknown): OdsFieldDefinition {
  const j = json as Record<string, unknown>
  return {
    name: j['name'] as string,
    type: j['type'] as string,
    label: j['label'] as string | undefined,
    required: (j['required'] as boolean) ?? false,
    placeholder: j['placeholder'] as string | undefined,
    defaultValue: j['default'] as string | undefined,
    options: Array.isArray(j['options']) ? j['options'] as string[] : typeof j['options'] === 'string' ? (j['options'] as string).split(',').map(s => s.trim()).filter(Boolean) : undefined,
    optionsFrom: parseOptionsFrom(j['optionsFrom']),
    formula: j['formula'] as string | undefined,
    visibleWhen: parseVisibleWhen(j['visibleWhen']),
    validation: parseValidation(j['validation']),
    currency: (j['currency'] as boolean) ?? false,
    readOnly: (j['readOnly'] as boolean) ?? false,
    displayVariant: j['displayVariant'] as string | undefined,
    optionLabels: j['optionLabels'] as string[] | undefined,
    roles: j['roles'] as string[] | undefined,
  }
}

function parseOptionsFrom(json: unknown): OdsOptionsFrom | undefined {
  if (json == null || typeof json !== 'object') return undefined
  const j = json as Record<string, unknown>
  const filterRaw = j['filter'] as Record<string, unknown> | undefined
  return {
    dataSource: j['dataSource'] as string,
    valueField: j['valueField'] as string,
    filter: filterRaw
      ? { field: filterRaw['field'] as string, fromField: filterRaw['fromField'] as string }
      : undefined,
  }
}

function parseValidation(json: unknown): OdsValidation | undefined {
  if (json == null || typeof json !== 'object') return undefined
  const j = json as Record<string, unknown>
  return {
    min: j['min'] as number | undefined,
    max: j['max'] as number | undefined,
    minLength: j['minLength'] as number | undefined,
    pattern: j['pattern'] as string | undefined,
    message: j['message'] as string | undefined,
  }
}

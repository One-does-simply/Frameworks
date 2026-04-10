import { describe, it, expect } from 'vitest'
import {
  parseComponentVisibleWhen,
  parseVisibleWhen,
  isFieldBased,
  isDataBased,
  type OdsComponentVisibleWhen,
  type OdsVisibleWhen,
} from '../../../src/models/ods-visible-when.ts'

// ===========================================================================
// OdsComponentVisibleWhen model tests
// ===========================================================================

describe('parseComponentVisibleWhen', () => {
  // -------------------------------------------------------------------------
  // Null / undefined input
  // -------------------------------------------------------------------------

  it('returns undefined for null input', () => {
    expect(parseComponentVisibleWhen(null)).toBeUndefined()
  })

  it('returns undefined for undefined input', () => {
    expect(parseComponentVisibleWhen(undefined)).toBeUndefined()
  })

  it('returns undefined for non-object input', () => {
    expect(parseComponentVisibleWhen('string')).toBeUndefined()
  })

  it('returns undefined for number input', () => {
    expect(parseComponentVisibleWhen(42)).toBeUndefined()
  })

  // -------------------------------------------------------------------------
  // Field-based condition
  // -------------------------------------------------------------------------

  it('parses field-based condition', () => {
    const result = parseComponentVisibleWhen({
      field: 'status',
      form: 'mainForm',
      equals: 'active',
    })
    expect(result).toBeDefined()
    expect(result!.field).toBe('status')
    expect(result!.form).toBe('mainForm')
    expect(result!.equals).toBe('active')
  })

  it('parses field-based condition with notEquals', () => {
    const result = parseComponentVisibleWhen({
      field: 'role',
      form: 'userForm',
      notEquals: 'guest',
    })
    expect(result!.field).toBe('role')
    expect(result!.form).toBe('userForm')
    expect(result!.notEquals).toBe('guest')
    expect(result!.equals).toBeUndefined()
  })

  // -------------------------------------------------------------------------
  // Data-based condition
  // -------------------------------------------------------------------------

  it('parses data-based condition with source and countEquals', () => {
    const result = parseComponentVisibleWhen({
      source: 'tasks',
      countEquals: 0,
    })
    expect(result!.source).toBe('tasks')
    expect(result!.countEquals).toBe(0)
  })

  it('parses data-based condition with countMin and countMax', () => {
    const result = parseComponentVisibleWhen({
      source: 'items',
      countMin: 1,
      countMax: 10,
    })
    expect(result!.source).toBe('items')
    expect(result!.countMin).toBe(1)
    expect(result!.countMax).toBe(10)
  })

  it('parses data-based condition with only source', () => {
    const result = parseComponentVisibleWhen({ source: 'records' })
    expect(result!.source).toBe('records')
    expect(result!.countEquals).toBeUndefined()
    expect(result!.countMin).toBeUndefined()
    expect(result!.countMax).toBeUndefined()
  })

  // -------------------------------------------------------------------------
  // equals coercion via String()
  // -------------------------------------------------------------------------

  it('coerces numeric equals to string', () => {
    const result = parseComponentVisibleWhen({
      field: 'count',
      form: 'f',
      equals: 42,
    })
    expect(result!.equals).toBe('42')
  })

  it('coerces boolean equals to string', () => {
    const result = parseComponentVisibleWhen({
      field: 'active',
      form: 'f',
      equals: true,
    })
    expect(result!.equals).toBe('true')
  })

  it('coerces numeric notEquals to string', () => {
    const result = parseComponentVisibleWhen({
      field: 'count',
      form: 'f',
      notEquals: 0,
    })
    expect(result!.notEquals).toBe('0')
  })

  it('leaves equals undefined when not provided', () => {
    const result = parseComponentVisibleWhen({
      field: 'x',
      form: 'f',
    })
    expect(result!.equals).toBeUndefined()
    expect(result!.notEquals).toBeUndefined()
  })

  // -------------------------------------------------------------------------
  // Empty object
  // -------------------------------------------------------------------------

  it('parses empty object with all fields undefined', () => {
    const result = parseComponentVisibleWhen({})
    expect(result).toBeDefined()
    expect(result!.field).toBeUndefined()
    expect(result!.form).toBeUndefined()
    expect(result!.source).toBeUndefined()
  })
})

// ===========================================================================
// isFieldBased / isDataBased type guards
// ===========================================================================

describe('isFieldBased', () => {
  it('returns true when field and form are set', () => {
    const v: OdsComponentVisibleWhen = { field: 'status', form: 'mainForm', equals: 'yes' }
    expect(isFieldBased(v)).toBe(true)
  })

  it('returns false when field is missing', () => {
    const v: OdsComponentVisibleWhen = { form: 'mainForm' }
    expect(isFieldBased(v)).toBe(false)
  })

  it('returns false when form is missing', () => {
    const v: OdsComponentVisibleWhen = { field: 'status' }
    expect(isFieldBased(v)).toBe(false)
  })

  it('returns false when both field and form are missing', () => {
    const v: OdsComponentVisibleWhen = { source: 'tasks' }
    expect(isFieldBased(v)).toBe(false)
  })
})

describe('isDataBased', () => {
  it('returns true when source is set', () => {
    const v: OdsComponentVisibleWhen = { source: 'tasks', countEquals: 0 }
    expect(isDataBased(v)).toBe(true)
  })

  it('returns false when source is not set', () => {
    const v: OdsComponentVisibleWhen = { field: 'status', form: 'f' }
    expect(isDataBased(v)).toBe(false)
  })

  it('returns false for empty object', () => {
    const v: OdsComponentVisibleWhen = {}
    expect(isDataBased(v)).toBe(false)
  })
})

// ===========================================================================
// OdsVisibleWhen (field-level) model tests
// ===========================================================================

describe('parseVisibleWhen', () => {
  it('parses valid input with field and equals', () => {
    const result = parseVisibleWhen({ field: 'type', equals: 'advanced' })
    expect(result).toBeDefined()
    expect(result!.field).toBe('type')
    expect(result!.equals).toBe('advanced')
  })

  it('returns undefined for null input', () => {
    expect(parseVisibleWhen(null)).toBeUndefined()
  })

  it('returns undefined for undefined input', () => {
    expect(parseVisibleWhen(undefined)).toBeUndefined()
  })

  it('returns undefined for non-object input', () => {
    expect(parseVisibleWhen('not-object')).toBeUndefined()
  })

  it('returns undefined for number input', () => {
    expect(parseVisibleWhen(123)).toBeUndefined()
  })

  it('parses object with missing equals', () => {
    const result = parseVisibleWhen({ field: 'status' })
    expect(result).toBeDefined()
    expect(result!.field).toBe('status')
    expect(result!.equals).toBeUndefined()
  })

  it('parses object with missing field', () => {
    const result = parseVisibleWhen({ equals: 'yes' })
    expect(result).toBeDefined()
    expect(result!.field).toBeUndefined()
    expect(result!.equals).toBe('yes')
  })
})

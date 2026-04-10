import { describe, it, expect } from 'vitest'
import {
  parseAction,
  isNavigate,
  isSubmit,
  isUpdate,
  isShowMessage,
  isRecordAction,
  type OdsAction,
} from '../../../src/models/ods-action.ts'

// ===========================================================================
// OdsAction model tests
// ===========================================================================

describe('parseAction', () => {
  // -------------------------------------------------------------------------
  // Minimal input
  // -------------------------------------------------------------------------

  it('parses minimal input with just action type', () => {
    const result = parseAction({ action: 'navigate' })
    expect(result.action).toBe('navigate')
    expect(result.target).toBeUndefined()
    expect(result.dataSource).toBeUndefined()
    expect(result.matchField).toBeUndefined()
    expect(result.withData).toBeUndefined()
    expect(result.confirm).toBeUndefined()
    expect(result.message).toBeUndefined()
    expect(result.computedFields).toEqual([])
    expect(result.filter).toBeUndefined()
    expect(result.onEnd).toBeUndefined()
    expect(result.cascade).toBeUndefined()
    expect(result.preserveFields).toEqual([])
  })

  // -------------------------------------------------------------------------
  // Full fields
  // -------------------------------------------------------------------------

  it('parses full action with all optional fields', () => {
    const result = parseAction({
      action: 'submit',
      target: 'detailPage',
      dataSource: 'tasks',
      matchField: 'id',
      withData: { status: 'done' },
      confirm: 'Are you sure?',
      message: 'Saved successfully',
    })
    expect(result.action).toBe('submit')
    expect(result.target).toBe('detailPage')
    expect(result.dataSource).toBe('tasks')
    expect(result.matchField).toBe('id')
    expect(result.withData).toEqual({ status: 'done' })
    expect(result.confirm).toBe('Are you sure?')
    expect(result.message).toBe('Saved successfully')
  })

  // -------------------------------------------------------------------------
  // computedFields
  // -------------------------------------------------------------------------

  it('parses computedFields array', () => {
    const result = parseAction({
      action: 'submit',
      computedFields: [
        { field: 'total', expression: 'price * qty' },
        { field: 'tax', expression: 'total * 0.08' },
      ],
    })
    expect(result.computedFields).toHaveLength(2)
    expect(result.computedFields[0].field).toBe('total')
    expect(result.computedFields[0].expression).toBe('price * qty')
    expect(result.computedFields[1].field).toBe('tax')
  })

  it('defaults computedFields to empty array when not provided', () => {
    const result = parseAction({ action: 'navigate' })
    expect(result.computedFields).toEqual([])
  })

  // -------------------------------------------------------------------------
  // Nested onEnd action (recursive)
  // -------------------------------------------------------------------------

  it('parses nested onEnd action', () => {
    const result = parseAction({
      action: 'submit',
      dataSource: 'tasks',
      onEnd: {
        action: 'navigate',
        target: 'listPage',
      },
    })
    expect(result.onEnd).toBeDefined()
    expect(result.onEnd!.action).toBe('navigate')
    expect(result.onEnd!.target).toBe('listPage')
  })

  it('parses deeply nested onEnd actions', () => {
    const result = parseAction({
      action: 'submit',
      onEnd: {
        action: 'showMessage',
        message: 'Done!',
        onEnd: {
          action: 'navigate',
          target: 'home',
        },
      },
    })
    expect(result.onEnd!.action).toBe('showMessage')
    expect(result.onEnd!.onEnd!.action).toBe('navigate')
    expect(result.onEnd!.onEnd!.target).toBe('home')
  })

  it('sets onEnd to undefined when not provided', () => {
    const result = parseAction({ action: 'navigate' })
    expect(result.onEnd).toBeUndefined()
  })

  // -------------------------------------------------------------------------
  // Filter and cascade objects
  // -------------------------------------------------------------------------

  it('parses filter object with string values', () => {
    const result = parseAction({
      action: 'navigate',
      filter: { status: 'active', category: 'work' },
    })
    expect(result.filter).toEqual({ status: 'active', category: 'work' })
  })

  it('coerces filter values to strings', () => {
    const result = parseAction({
      action: 'navigate',
      filter: { count: 42, flag: true },
    })
    expect(result.filter).toEqual({ count: '42', flag: 'true' })
  })

  it('parses cascade object', () => {
    const result = parseAction({
      action: 'submit',
      cascade: { parentId: 'id', parentName: 'name' },
    })
    expect(result.cascade).toEqual({ parentId: 'id', parentName: 'name' })
  })

  it('coerces cascade values to strings', () => {
    const result = parseAction({
      action: 'submit',
      cascade: { num: 99 },
    })
    expect(result.cascade).toEqual({ num: '99' })
  })

  it('sets filter to undefined when not provided', () => {
    const result = parseAction({ action: 'navigate' })
    expect(result.filter).toBeUndefined()
  })

  it('sets cascade to undefined when not provided', () => {
    const result = parseAction({ action: 'navigate' })
    expect(result.cascade).toBeUndefined()
  })

  // -------------------------------------------------------------------------
  // preserveFields
  // -------------------------------------------------------------------------

  it('parses preserveFields array', () => {
    const result = parseAction({
      action: 'submit',
      preserveFields: ['name', 'email'],
    })
    expect(result.preserveFields).toEqual(['name', 'email'])
  })

  it('defaults preserveFields to empty array when not provided', () => {
    const result = parseAction({ action: 'navigate' })
    expect(result.preserveFields).toEqual([])
  })

  // -------------------------------------------------------------------------
  // populateForm
  // -------------------------------------------------------------------------

  it('parses populateForm field', () => {
    const result = parseAction({
      action: 'navigate',
      populateForm: 'editForm',
    })
    expect(result.populateForm).toBe('editForm')
  })
})

// ===========================================================================
// Type guards
// ===========================================================================

describe('isNavigate', () => {
  it('returns true for navigate action', () => {
    const action = parseAction({ action: 'navigate' })
    expect(isNavigate(action)).toBe(true)
  })

  it('returns false for non-navigate action', () => {
    const action = parseAction({ action: 'submit' })
    expect(isNavigate(action)).toBe(false)
  })
})

describe('isSubmit', () => {
  it('returns true for submit action', () => {
    const action = parseAction({ action: 'submit' })
    expect(isSubmit(action)).toBe(true)
  })

  it('returns false for non-submit action', () => {
    const action = parseAction({ action: 'navigate' })
    expect(isSubmit(action)).toBe(false)
  })
})

describe('isUpdate', () => {
  it('returns true for update action', () => {
    const action = parseAction({ action: 'update' })
    expect(isUpdate(action)).toBe(true)
  })

  it('returns false for non-update action', () => {
    const action = parseAction({ action: 'submit' })
    expect(isUpdate(action)).toBe(false)
  })
})

describe('isShowMessage', () => {
  it('returns true for showMessage action', () => {
    const action = parseAction({ action: 'showMessage' })
    expect(isShowMessage(action)).toBe(true)
  })

  it('returns false for non-showMessage action', () => {
    const action = parseAction({ action: 'navigate' })
    expect(isShowMessage(action)).toBe(false)
  })
})

describe('isRecordAction', () => {
  it('returns true for firstRecord', () => {
    const action = parseAction({ action: 'firstRecord' })
    expect(isRecordAction(action)).toBe(true)
  })

  it('returns true for nextRecord', () => {
    const action = parseAction({ action: 'nextRecord' })
    expect(isRecordAction(action)).toBe(true)
  })

  it('returns true for previousRecord', () => {
    const action = parseAction({ action: 'previousRecord' })
    expect(isRecordAction(action)).toBe(true)
  })

  it('returns true for lastRecord', () => {
    const action = parseAction({ action: 'lastRecord' })
    expect(isRecordAction(action)).toBe(true)
  })

  it('returns false for non-record action', () => {
    const action = parseAction({ action: 'navigate' })
    expect(isRecordAction(action)).toBe(false)
  })
})

import { describe, it, expect } from 'vitest'
import { parseOwnership, type OdsOwnership } from '../../../src/models/ods-ownership.ts'

// ===========================================================================
// OdsOwnership model tests
// ===========================================================================

describe('parseOwnership', () => {
  // -------------------------------------------------------------------------
  // Null / missing / invalid input
  // -------------------------------------------------------------------------

  it('returns defaults for null input', () => {
    const result = parseOwnership(null)
    expect(result.enabled).toBe(false)
    expect(result.ownerField).toBe('_owner')
    expect(result.adminOverride).toBe(true)
  })

  it('returns defaults for undefined input', () => {
    const result = parseOwnership(undefined)
    expect(result.enabled).toBe(false)
    expect(result.ownerField).toBe('_owner')
    expect(result.adminOverride).toBe(true)
  })

  it('returns defaults for non-object input (string)', () => {
    const result = parseOwnership('not-an-object')
    expect(result.enabled).toBe(false)
    expect(result.ownerField).toBe('_owner')
    expect(result.adminOverride).toBe(true)
  })

  it('returns defaults for non-object input (number)', () => {
    const result = parseOwnership(42)
    expect(result.enabled).toBe(false)
    expect(result.ownerField).toBe('_owner')
    expect(result.adminOverride).toBe(true)
  })

  // -------------------------------------------------------------------------
  // Valid ownership objects
  // -------------------------------------------------------------------------

  it('parses a full valid ownership object', () => {
    const result = parseOwnership({
      enabled: true,
      ownerField: 'createdBy',
      adminOverride: false,
    })
    expect(result.enabled).toBe(true)
    expect(result.ownerField).toBe('createdBy')
    expect(result.adminOverride).toBe(false)
  })

  it('parses partial object with defaults for missing fields', () => {
    const result = parseOwnership({})
    expect(result.enabled).toBe(false)
    expect(result.ownerField).toBe('_owner')
    expect(result.adminOverride).toBe(true)
  })

  it('parses enabled true with custom ownerField', () => {
    const result = parseOwnership({
      enabled: true,
      ownerField: 'userId',
    })
    expect(result.enabled).toBe(true)
    expect(result.ownerField).toBe('userId')
    expect(result.adminOverride).toBe(true)
  })

  it('parses adminOverride false', () => {
    const result = parseOwnership({
      adminOverride: false,
    })
    expect(result.enabled).toBe(false)
    expect(result.ownerField).toBe('_owner')
    expect(result.adminOverride).toBe(false)
  })

  it('defaults ownerField when only enabled is set', () => {
    const result = parseOwnership({ enabled: true })
    expect(result.ownerField).toBe('_owner')
  })

  it('defaults adminOverride to true when only enabled is set', () => {
    const result = parseOwnership({ enabled: true })
    expect(result.adminOverride).toBe(true)
  })
})

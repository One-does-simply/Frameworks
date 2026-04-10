import { describe, it, expect } from 'vitest'
import {
  parseStyleHint,
  getHint,
  hintVariant,
  hintEmphasis,
  hintAlign,
  hintColor,
  hintIcon,
  hintSize,
  hintDensity,
  hintElevation,
} from '../../../src/models/ods-style-hint.ts'

// ===========================================================================
// OdsStyleHint model tests
// ===========================================================================

describe('parseStyleHint', () => {
  // -------------------------------------------------------------------------
  // Null / invalid input
  // -------------------------------------------------------------------------

  it('returns empty object for null', () => {
    expect(parseStyleHint(null)).toEqual({})
  })

  it('returns empty object for undefined', () => {
    expect(parseStyleHint(undefined)).toEqual({})
  })

  it('returns empty object for array', () => {
    expect(parseStyleHint([1, 2, 3])).toEqual({})
  })

  it('returns empty object for string', () => {
    expect(parseStyleHint('not-an-object')).toEqual({})
  })

  it('returns empty object for number', () => {
    expect(parseStyleHint(42)).toEqual({})
  })

  it('returns empty object for boolean', () => {
    expect(parseStyleHint(true)).toEqual({})
  })

  // -------------------------------------------------------------------------
  // Valid object input
  // -------------------------------------------------------------------------

  it('passes through a valid object', () => {
    const hint = { variant: 'outlined', color: 'primary' }
    const result = parseStyleHint(hint)
    expect(result).toEqual({ variant: 'outlined', color: 'primary' })
  })

  it('passes through an empty object', () => {
    expect(parseStyleHint({})).toEqual({})
  })
})

// ===========================================================================
// getHint
// ===========================================================================

describe('getHint', () => {
  it('extracts a typed value', () => {
    const hint = { variant: 'filled', size: 'lg' }
    expect(getHint<string>(hint, 'variant')).toBe('filled')
  })

  it('returns undefined for missing key', () => {
    const hint = { variant: 'filled' }
    expect(getHint<string>(hint, 'color')).toBeUndefined()
  })

  it('extracts a number value', () => {
    const hint = { elevation: 3 }
    expect(getHint<number>(hint, 'elevation')).toBe(3)
  })
})

// ===========================================================================
// Convenience accessors
// ===========================================================================

describe('convenience accessors', () => {
  const hint = {
    variant: 'outlined',
    emphasis: 'high',
    align: 'center',
    color: 'primary',
    icon: 'star',
    size: 'lg',
    density: 'compact',
    elevation: 2.7,
  }

  it('hintVariant returns variant', () => {
    expect(hintVariant(hint)).toBe('outlined')
  })

  it('hintEmphasis returns emphasis', () => {
    expect(hintEmphasis(hint)).toBe('high')
  })

  it('hintAlign returns align', () => {
    expect(hintAlign(hint)).toBe('center')
  })

  it('hintColor returns color', () => {
    expect(hintColor(hint)).toBe('primary')
  })

  it('hintIcon returns icon', () => {
    expect(hintIcon(hint)).toBe('star')
  })

  it('hintSize returns size', () => {
    expect(hintSize(hint)).toBe('lg')
  })

  it('hintDensity returns density', () => {
    expect(hintDensity(hint)).toBe('compact')
  })

  // -------------------------------------------------------------------------
  // hintElevation
  // -------------------------------------------------------------------------

  it('hintElevation returns floored number', () => {
    expect(hintElevation(hint)).toBe(2)
  })

  it('hintElevation returns integer unchanged', () => {
    expect(hintElevation({ elevation: 4 })).toBe(4)
  })

  it('hintElevation returns undefined for non-number', () => {
    expect(hintElevation({ elevation: 'high' })).toBeUndefined()
  })

  it('hintElevation returns undefined when missing', () => {
    expect(hintElevation({})).toBeUndefined()
  })

  // -------------------------------------------------------------------------
  // Accessors return undefined for missing keys
  // -------------------------------------------------------------------------

  it('hintVariant returns undefined when missing', () => {
    expect(hintVariant({})).toBeUndefined()
  })

  it('hintEmphasis returns undefined when missing', () => {
    expect(hintEmphasis({})).toBeUndefined()
  })

  it('hintAlign returns undefined when missing', () => {
    expect(hintAlign({})).toBeUndefined()
  })

  it('hintColor returns undefined when missing', () => {
    expect(hintColor({})).toBeUndefined()
  })

  it('hintIcon returns undefined when missing', () => {
    expect(hintIcon({})).toBeUndefined()
  })

  it('hintSize returns undefined when missing', () => {
    expect(hintSize({})).toBeUndefined()
  })

  it('hintDensity returns undefined when missing', () => {
    expect(hintDensity({})).toBeUndefined()
  })
})

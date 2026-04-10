import { describe, it, expect } from 'vitest'
import { loadFromText } from '../../../src/engine/spec-loader.ts'

// ===========================================================================
// Spec loader tests — loadFromText (pure function, no I/O)
//
// loadFromFile and loadFromUrl require browser APIs (FileReader, fetch)
// and are better tested via E2E. loadFromText is a pure validator.
// ===========================================================================

describe('loadFromText', () => {
  // -------------------------------------------------------------------------
  // Valid input
  // -------------------------------------------------------------------------

  it('returns the text unchanged for valid JSON', () => {
    const spec = '{"appName": "Test", "startPage": "home", "pages": {}}'
    expect(loadFromText(spec)).toBe(spec)
  })

  it('returns non-JSON text unchanged (validation is caller responsibility)', () => {
    const text = 'not json at all'
    expect(loadFromText(text)).toBe(text)
  })

  it('preserves whitespace and formatting', () => {
    const text = '  { "appName": "Test" }  '
    expect(loadFromText(text)).toBe(text)
  })

  // -------------------------------------------------------------------------
  // Invalid input
  // -------------------------------------------------------------------------

  it('throws for empty string', () => {
    expect(() => loadFromText('')).toThrow('empty')
  })

  it('throws for whitespace-only string', () => {
    expect(() => loadFromText('   ')).toThrow('empty')
  })

  it('throws for non-string input', () => {
    expect(() => loadFromText(123 as any)).toThrow('Expected a string')
  })

  it('throws for null input', () => {
    expect(() => loadFromText(null as any)).toThrow('Expected a string')
  })

  it('throws for undefined input', () => {
    expect(() => loadFromText(undefined as any)).toThrow('Expected a string')
  })
})

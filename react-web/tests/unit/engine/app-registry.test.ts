import { describe, it, expect } from 'vitest'
import { slugify } from '../../../src/engine/app-registry.ts'

// ===========================================================================
// App registry tests — slugify (pure function)
//
// AppRegistry class methods require PocketBase and are better tested
// via integration/E2E tests. slugify is a pure function we can unit test.
// ===========================================================================

describe('slugify', () => {
  // -------------------------------------------------------------------------
  // Basic conversion
  // -------------------------------------------------------------------------

  it('converts simple name to lowercase slug', () => {
    expect(slugify('My App')).toBe('my-app')
  })

  it('converts to lowercase', () => {
    expect(slugify('Hello World')).toBe('hello-world')
  })

  it('replaces spaces with hyphens', () => {
    expect(slugify('customer feedback')).toBe('customer-feedback')
  })

  it('replaces underscores with hyphens', () => {
    expect(slugify('my_cool_app')).toBe('my-cool-app')
  })

  it('replaces multiple spaces with single hyphen', () => {
    expect(slugify('too   many   spaces')).toBe('too-many-spaces')
  })

  // -------------------------------------------------------------------------
  // Special characters
  // -------------------------------------------------------------------------

  it('removes special characters', () => {
    expect(slugify('App (v2.0)!')).toBe('app-v20')
  })

  it('removes emoji and unicode', () => {
    expect(slugify('My App 🚀')).toBe('my-app')
  })

  it('handles ampersands and symbols', () => {
    expect(slugify('Sales & Marketing')).toBe('sales-marketing')
  })

  it('removes leading and trailing hyphens', () => {
    expect(slugify('-trimmed-')).toBe('trimmed')
  })

  it('handles consecutive special characters', () => {
    expect(slugify('a!!!b')).toBe('ab')
  })

  // -------------------------------------------------------------------------
  // Edge cases
  // -------------------------------------------------------------------------

  it('truncates to 64 characters', () => {
    const longName = 'a'.repeat(100)
    expect(slugify(longName).length).toBeLessThanOrEqual(64)
  })

  it('handles empty string', () => {
    expect(slugify('')).toBe('')
  })

  it('handles string with only special characters', () => {
    expect(slugify('!!!')).toBe('')
  })

  it('preserves numbers', () => {
    expect(slugify('App 2024 v3')).toBe('app-2024-v3')
  })

  it('handles already-slugified input', () => {
    expect(slugify('already-a-slug')).toBe('already-a-slug')
  })
})

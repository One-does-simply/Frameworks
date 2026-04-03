import { describe, it, expect } from 'vitest'
import { parseBranding, type OdsBranding } from '../../../src/models/ods-branding.ts'

// ===========================================================================
// OdsBranding model tests
// ===========================================================================

describe('parseBranding', () => {
  // -------------------------------------------------------------------------
  // Null / missing input
  // -------------------------------------------------------------------------

  it('returns defaults for null input', () => {
    const result = parseBranding(null)
    expect(result.theme).toBe('indigo')
    expect(result.mode).toBe('system')
    expect(result.headerStyle).toBe('light')
  })

  it('returns defaults for undefined input', () => {
    const result = parseBranding(undefined)
    expect(result.theme).toBe('indigo')
    expect(result.mode).toBe('system')
    expect(result.headerStyle).toBe('light')
  })

  it('returns defaults for non-object input', () => {
    const result = parseBranding('not-an-object')
    expect(result.theme).toBe('indigo')
    expect(result.mode).toBe('system')
  })

  it('returns defaults for number input', () => {
    const result = parseBranding(42)
    expect(result.theme).toBe('indigo')
  })

  // -------------------------------------------------------------------------
  // Valid branding object
  // -------------------------------------------------------------------------

  it('parses a full valid branding object', () => {
    const result = parseBranding({
      theme: 'nord',
      mode: 'dark',
      logo: 'https://example.com/logo.png',
      favicon: 'https://example.com/favicon.ico',
      headerStyle: 'solid',
      fontFamily: 'Inter',
      overrides: { primary: 'oklch(50% 0.2 260)' },
    })
    expect(result.theme).toBe('nord')
    expect(result.mode).toBe('dark')
    expect(result.logo).toBe('https://example.com/logo.png')
    expect(result.favicon).toBe('https://example.com/favicon.ico')
    expect(result.headerStyle).toBe('solid')
    expect(result.fontFamily).toBe('Inter')
    expect(result.overrides?.primary).toBe('oklch(50% 0.2 260)')
  })

  it('parses minimal branding with only theme', () => {
    const result = parseBranding({ theme: 'corporate' })
    expect(result.theme).toBe('corporate')
    expect(result.mode).toBe('system')
    expect(result.headerStyle).toBe('light')
    expect(result.logo).toBeUndefined()
    expect(result.fontFamily).toBeUndefined()
    expect(result.overrides).toBeUndefined()
  })

  // -------------------------------------------------------------------------
  // Default values
  // -------------------------------------------------------------------------

  it('defaults theme to indigo', () => {
    const result = parseBranding({})
    expect(result.theme).toBe('indigo')
  })

  it('defaults mode to system', () => {
    const result = parseBranding({})
    expect(result.mode).toBe('system')
  })

  it('defaults headerStyle to light', () => {
    const result = parseBranding({})
    expect(result.headerStyle).toBe('light')
  })

  it('falls back to system for invalid mode', () => {
    const result = parseBranding({ mode: 'invalid-mode' })
    expect(result.mode).toBe('system')
  })

  it('falls back to light for invalid headerStyle', () => {
    const result = parseBranding({ headerStyle: 'glowing' })
    expect(result.headerStyle).toBe('light')
  })

  // -------------------------------------------------------------------------
  // Legacy format backward compatibility (primaryColor -> overrides)
  // -------------------------------------------------------------------------

  it('migrates legacy primaryColor to overrides', () => {
    const result = parseBranding({
      primaryColor: '#4F46E5',
    })
    expect(result.theme).toBe('indigo')
    expect(result.mode).toBe('system')
    expect(result.overrides?.primary).toBe('#4F46E5')
  })

  it('migrates legacy accentColor to overrides', () => {
    const result = parseBranding({
      primaryColor: '#4F46E5',
      accentColor: '#EC4899',
    })
    expect(result.overrides?.primary).toBe('#4F46E5')
    expect(result.overrides?.accent).toBe('#EC4899')
  })

  it('legacy format preserves logo and favicon', () => {
    const result = parseBranding({
      primaryColor: '#123456',
      logo: 'https://example.com/logo.png',
      favicon: 'https://example.com/fav.ico',
    })
    expect(result.logo).toBe('https://example.com/logo.png')
    expect(result.favicon).toBe('https://example.com/fav.ico')
  })

  it('legacy format preserves fontFamily', () => {
    const result = parseBranding({
      primaryColor: '#123456',
      fontFamily: 'Roboto',
    })
    expect(result.fontFamily).toBe('Roboto')
  })

  it('legacy format preserves valid headerStyle', () => {
    const result = parseBranding({
      primaryColor: '#123456',
      headerStyle: 'transparent',
    })
    expect(result.headerStyle).toBe('transparent')
  })

  it('ignores legacy format when theme is present', () => {
    const result = parseBranding({
      theme: 'dracula',
      primaryColor: '#123456',
    })
    // When theme is set, primaryColor is NOT treated as legacy
    expect(result.theme).toBe('dracula')
    expect(result.overrides).toBeUndefined()
  })

  // -------------------------------------------------------------------------
  // Legacy theme name migration
  // -------------------------------------------------------------------------

  it('migrates legacy theme name "light" to "indigo"', () => {
    const result = parseBranding({ theme: 'light' })
    expect(result.theme).toBe('indigo')
  })

  it('migrates legacy theme name "dark" to "slate"', () => {
    const result = parseBranding({ theme: 'dark' })
    expect(result.theme).toBe('slate')
  })

  it('preserves valid theme names unchanged', () => {
    const result = parseBranding({ theme: 'nord' })
    expect(result.theme).toBe('nord')
  })

  // -------------------------------------------------------------------------
  // Mode values
  // -------------------------------------------------------------------------

  it('accepts mode light', () => {
    const result = parseBranding({ mode: 'light' })
    expect(result.mode).toBe('light')
  })

  it('accepts mode dark', () => {
    const result = parseBranding({ mode: 'dark' })
    expect(result.mode).toBe('dark')
  })

  it('accepts mode system', () => {
    const result = parseBranding({ mode: 'system' })
    expect(result.mode).toBe('system')
  })
})

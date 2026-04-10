import { describe, it, expect, beforeEach, vi } from 'vitest'

// ===========================================================================
// Theme store tests — mode persistence and CSS class application
// ===========================================================================

// Mock localStorage and document for node environment
const store: Record<string, string> = {}
const mockLocalStorage = {
  getItem: (key: string) => store[key] ?? null,
  setItem: (key: string, value: string) => { store[key] = value },
  removeItem: (key: string) => { delete store[key] },
  clear: () => { for (const k of Object.keys(store)) delete store[k] },
}
vi.stubGlobal('localStorage', mockLocalStorage)

// Mock document.documentElement with classList
const classList = new Set<string>()
const mockDocEl = {
  classList: {
    add: (cls: string) => classList.add(cls),
    remove: (cls: string) => classList.delete(cls),
    contains: (cls: string) => classList.has(cls),
  },
}
vi.stubGlobal('document', { documentElement: mockDocEl })

// Mock matchMedia
vi.stubGlobal('window', {
  ...globalThis,
  localStorage: mockLocalStorage,
  matchMedia: () => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() }),
})

const { getThemeMode, setThemeMode, applyTheme } = await import('../../../src/engine/theme-store.ts')

describe('theme-store', () => {
  beforeEach(() => {
    mockLocalStorage.clear()
    classList.clear()
  })

  // -------------------------------------------------------------------------
  // getThemeMode
  // -------------------------------------------------------------------------

  describe('getThemeMode', () => {
    it('defaults to system when nothing stored', () => {
      expect(getThemeMode()).toBe('system')
    })

    it('returns light when stored', () => {
      mockLocalStorage.setItem('ods_theme_mode', 'light')
      expect(getThemeMode()).toBe('light')
    })

    it('returns dark when stored', () => {
      mockLocalStorage.setItem('ods_theme_mode', 'dark')
      expect(getThemeMode()).toBe('dark')
    })

    it('returns system when stored', () => {
      mockLocalStorage.setItem('ods_theme_mode', 'system')
      expect(getThemeMode()).toBe('system')
    })

    it('defaults to system for invalid stored value', () => {
      mockLocalStorage.setItem('ods_theme_mode', 'invalid')
      expect(getThemeMode()).toBe('system')
    })
  })

  // -------------------------------------------------------------------------
  // applyTheme
  // -------------------------------------------------------------------------

  describe('applyTheme', () => {
    it('adds dark class for dark mode', () => {
      applyTheme('dark')
      expect(classList.has('dark')).toBe(true)
    })

    it('removes dark class for light mode', () => {
      classList.add('dark')
      applyTheme('light')
      expect(classList.has('dark')).toBe(false)
    })
  })

  // -------------------------------------------------------------------------
  // setThemeMode
  // -------------------------------------------------------------------------

  describe('setThemeMode', () => {
    it('persists mode to localStorage', () => {
      setThemeMode('dark')
      expect(store['ods_theme_mode']).toBe('dark')
    })

    it('applies dark class when setting dark', () => {
      setThemeMode('dark')
      expect(classList.has('dark')).toBe(true)
    })

    it('removes dark class when setting light', () => {
      classList.add('dark')
      setThemeMode('light')
      expect(classList.has('dark')).toBe(false)
    })
  })
})

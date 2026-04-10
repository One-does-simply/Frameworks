import { describe, it, expect, beforeEach, vi } from 'vitest'

// ===========================================================================
// Default app store tests — localStorage persistence
// ===========================================================================

// Mock localStorage since these tests run in node environment
const store: Record<string, string> = {}
const mockLocalStorage = {
  getItem: (key: string) => store[key] ?? null,
  setItem: (key: string, value: string) => { store[key] = value },
  removeItem: (key: string) => { delete store[key] },
  clear: () => { for (const k of Object.keys(store)) delete store[k] },
}

vi.stubGlobal('localStorage', mockLocalStorage)

// Import AFTER mocking localStorage
const { getDefaultAppSlug, setDefaultAppSlug, clearDefaultAppSlug, ensureDefaultApp } = await import('../../../src/engine/default-app-store.ts')

describe('default-app-store', () => {
  beforeEach(() => {
    mockLocalStorage.clear()
  })

  it('returns null when no default app is set', () => {
    expect(getDefaultAppSlug()).toBeNull()
  })

  it('stores and retrieves a default app slug', () => {
    setDefaultAppSlug('my-app')
    expect(getDefaultAppSlug()).toBe('my-app')
  })

  it('overwrites existing default app slug', () => {
    setDefaultAppSlug('first-app')
    setDefaultAppSlug('second-app')
    expect(getDefaultAppSlug()).toBe('second-app')
  })

  it('persists to localStorage', () => {
    setDefaultAppSlug('persisted-app')
    expect(store['ods_default_app_slug']).toBe('persisted-app')
  })

  it('clearDefaultAppSlug removes the stored slug', () => {
    setDefaultAppSlug('to-clear')
    clearDefaultAppSlug()
    expect(getDefaultAppSlug()).toBeNull()
  })

  it('ensureDefaultApp sets slug when none exists', () => {
    ensureDefaultApp('first-app')
    expect(getDefaultAppSlug()).toBe('first-app')
  })

  it('ensureDefaultApp does not overwrite existing slug', () => {
    setDefaultAppSlug('existing-app')
    ensureDefaultApp('new-app')
    expect(getDefaultAppSlug()).toBe('existing-app')
  })
})

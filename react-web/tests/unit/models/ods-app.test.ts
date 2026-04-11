import { describe, it, expect } from 'vitest'
import { parseApp, type OdsApp } from '../../../src/models/ods-app.ts'

// ===========================================================================
// OdsApp model tests
// ===========================================================================

describe('parseApp', () => {
  // -------------------------------------------------------------------------
  // Minimal valid input
  // -------------------------------------------------------------------------

  it('parses minimal valid input with appName, startPage string, and pages', () => {
    const result = parseApp({
      appName: 'My App',
      startPage: 'homePage',
      pages: { homePage: { title: 'Home', components: [] } },
    })
    expect(result.appName).toBe('My App')
    expect(result.startPage).toBe('homePage')
    expect(result.pages).toHaveProperty('homePage')
  })

  // -------------------------------------------------------------------------
  // Role-based startPage
  // -------------------------------------------------------------------------

  it('resolves role-based startPage object to default value', () => {
    const result = parseApp({
      appName: 'RoleApp',
      startPage: { default: 'page1', admin: 'page2' },
      pages: {},
    })
    expect(result.startPage).toBe('page1')
  })

  it('builds startPageByRole from role-based startPage object (excludes default)', () => {
    const result = parseApp({
      appName: 'RoleApp',
      startPage: { default: 'page1', admin: 'page2' },
      pages: {},
    })
    expect(result.startPageByRole).toEqual({ admin: 'page2' })
  })

  it('returns empty map for string startPage', () => {
    const result = parseApp({
      appName: 'App',
      startPage: 'landing',
      pages: {},
    })
    expect(result.startPageByRole).toEqual({})
  })

  it('returns empty map for null startPage', () => {
    const result = parseApp({
      appName: 'App',
      startPage: null,
      pages: {},
    })
    expect(result.startPageByRole).toEqual({})
  })

  it('returns empty map for undefined startPage', () => {
    const result = parseApp({
      appName: 'App',
      pages: {},
    })
    expect(result.startPageByRole).toEqual({})
  })

  it('returns empty string for startPage when startPage is null', () => {
    const result = parseApp({
      appName: 'App',
      startPage: null,
      pages: {},
    })
    expect(result.startPage).toBe('')
  })

  it('returns empty string for startPage when startPage is undefined', () => {
    const result = parseApp({
      appName: 'App',
      pages: {},
    })
    expect(result.startPage).toBe('')
  })

  // -------------------------------------------------------------------------
  // Missing optional fields default to empty arrays/objects
  // -------------------------------------------------------------------------

  it('defaults menu to empty array when not provided', () => {
    const result = parseApp({ appName: 'App', startPage: 'p', pages: {} })
    expect(result.menu).toEqual([])
  })

  it('defaults dataSources to empty object when not provided', () => {
    const result = parseApp({ appName: 'App', startPage: 'p', pages: {} })
    expect(result.dataSources).toEqual({})
  })

  it('defaults settings to empty object when not provided', () => {
    const result = parseApp({ appName: 'App', startPage: 'p', pages: {} })
    expect(result.settings).toEqual({})
  })

  it('defaults tour to empty array when not provided', () => {
    const result = parseApp({ appName: 'App', startPage: 'p', pages: {} })
    expect(result.tour).toEqual([])
  })

  it('defaults pages to empty object when not provided', () => {
    const result = parseApp({ appName: 'App', startPage: 'p' })
    expect(result.pages).toEqual({})
  })

  // -------------------------------------------------------------------------
  // Full spec with all fields
  // -------------------------------------------------------------------------

  it('parses full spec including menu, dataSources, settings, help, tour, auth, branding', () => {
    const result = parseApp({
      appName: 'Full App',
      startPage: 'dashboard',
      pages: {
        dashboard: { title: 'Dashboard', components: [] },
      },
      menu: [
        { label: 'Home', target: 'dashboard' },
      ],
      dataSources: {
        tasks: { url: 'local://tasks', method: 'GET' },
      },
      settings: {
        theme: { key: 'theme', label: 'Theme', type: 'text' },
      },
      help: {
        url: 'https://help.example.com',
      },
      tour: [
        { target: '#welcome', content: 'Welcome!' },
      ],
      auth: {
        provider: 'oauth2',
        roles: ['admin', 'user'],
      },
      branding: {
        theme: 'nord',
        mode: 'dark',
      },
    })
    expect(result.appName).toBe('Full App')
    expect(result.startPage).toBe('dashboard')
    expect(result.menu).toHaveLength(1)
    expect(result.dataSources).toHaveProperty('tasks')
    expect(result.settings).toHaveProperty('theme')
    expect(result.tour).toHaveLength(1)
    expect(result.branding.theme).toBe('nord')
    expect(result.branding.mode).toBe('dark')
  })

  // -------------------------------------------------------------------------
  // Auth and branding defaults
  // -------------------------------------------------------------------------

  it('provides default auth when not specified', () => {
    const result = parseApp({ appName: 'App', startPage: 'p', pages: {} })
    expect(result.auth).toBeDefined()
  })

  it('provides default branding when not specified', () => {
    const result = parseApp({ appName: 'App', startPage: 'p', pages: {} })
    expect(result.branding).toBeDefined()
    expect(result.branding.theme).toBe('indigo')
    expect(result.branding.mode).toBe('system')
  })

  // -------------------------------------------------------------------------
  // startPageByRole filters non-string values
  // -------------------------------------------------------------------------

  it('filters non-string values and default from role-based startPage map', () => {
    const result = parseApp({
      appName: 'App',
      startPage: { default: 'page1', bad: 42, also_bad: null },
      pages: {},
    })
    expect(result.startPageByRole).toEqual({})
  })
})

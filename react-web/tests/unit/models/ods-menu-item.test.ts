import { describe, it, expect } from 'vitest'
import { parseMenuItem } from '../../../src/models/ods-menu-item.ts'

// ===========================================================================
// OdsMenuItem model tests
// ===========================================================================

describe('parseMenuItem', () => {
  // -------------------------------------------------------------------------
  // Basic parsing
  // -------------------------------------------------------------------------

  it('parses label and mapsTo', () => {
    const item = parseMenuItem({ label: 'Dashboard', mapsTo: 'dashboardPage' })
    expect(item.label).toBe('Dashboard')
    expect(item.mapsTo).toBe('dashboardPage')
  })

  it('parses roles array', () => {
    const item = parseMenuItem({
      label: 'Admin',
      mapsTo: 'adminPage',
      roles: ['admin', 'manager'],
    })
    expect(item.roles).toEqual(['admin', 'manager'])
  })

  // -------------------------------------------------------------------------
  // Missing / empty roles
  // -------------------------------------------------------------------------

  it('missing roles is undefined', () => {
    const item = parseMenuItem({ label: 'Home', mapsTo: 'homePage' })
    expect(item.roles).toBeUndefined()
  })

  it('handles empty roles array', () => {
    const item = parseMenuItem({ label: 'Home', mapsTo: 'homePage', roles: [] })
    expect(item.roles).toEqual([])
  })
})

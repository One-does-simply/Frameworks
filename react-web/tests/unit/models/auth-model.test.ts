import { describe, it, expect } from 'vitest'
import { parseAuth, allRoles, type OdsAuth } from '../../../src/models/ods-auth.ts'
import { parseOwnership, type OdsOwnership } from '../../../src/models/ods-ownership.ts'
import { parseApp, type OdsApp } from '../../../src/models/ods-app.ts'
import { parseComponent } from '../../../src/models/ods-component.ts'
import { parseFieldDefinition } from '../../../src/models/ods-field.ts'
import { parseDataSource, type OdsDataSource } from '../../../src/models/ods-data-source.ts'
import { parseMenuItem, type OdsMenuItem } from '../../../src/models/ods-menu-item.ts'
import { parsePage, type OdsPage } from '../../../src/models/ods-page.ts'

// ===========================================================================
// Auth model tests (ported from auth_model_test.dart)
// ===========================================================================

describe('OdsAuth', () => {
  it('defaults to single-user mode', () => {
    const auth = parseAuth(null)
    expect(auth.multiUser).toBe(false)
    expect(auth.multiUserOnly).toBe(false)
    expect(auth.customRoles).toHaveLength(0)
    expect(auth.defaultRole).toBe('user')
  })

  it('parses from null as defaults', () => {
    const auth = parseAuth(null)
    expect(auth.multiUser).toBe(false)
    expect(auth.customRoles).toHaveLength(0)
  })

  it('parses full auth block', () => {
    const auth = parseAuth({
      multiUser: true,
      multiUserOnly: true,
      roles: ['manager', 'viewer'],
      defaultRole: 'viewer',
    })
    expect(auth.multiUser).toBe(true)
    expect(auth.multiUserOnly).toBe(true)
    expect(auth.customRoles).toEqual(['manager', 'viewer'])
    expect(auth.defaultRole).toBe('viewer')
  })

  it('allRoles includes built-ins plus custom', () => {
    const auth = parseAuth({
      multiUser: true,
      roles: ['manager'],
    })
    const roles = allRoles(auth)
    expect(roles).toContain('guest')
    expect(roles).toContain('user')
    expect(roles).toContain('admin')
    expect(roles).toContain('manager')
  })
})

describe('OdsOwnership', () => {
  it('defaults to disabled', () => {
    const ownership = parseOwnership(null)
    expect(ownership.enabled).toBe(false)
    expect(ownership.ownerField).toBe('_owner')
    expect(ownership.adminOverride).toBe(true)
  })

  it('parses from null as defaults', () => {
    const ownership = parseOwnership(null)
    expect(ownership.enabled).toBe(false)
  })

  it('parses full ownership block', () => {
    const ownership = parseOwnership({
      enabled: true,
      ownerField: 'createdBy',
      adminOverride: false,
    })
    expect(ownership.enabled).toBe(true)
    expect(ownership.ownerField).toBe('createdBy')
    expect(ownership.adminOverride).toBe(false)
  })
})

describe('Roles on models', () => {
  it('OdsApp parses auth', () => {
    const a = parseApp({
      appName: 'Test',
      startPage: 'home',
      auth: { multiUser: true, roles: ['manager'] },
      pages: {
        home: { component: 'page', title: 'Home', content: [] },
      },
    })
    expect(a.auth.multiUser).toBe(true)
    expect(a.auth.customRoles).toEqual(['manager'])
  })

  it('OdsApp defaults auth when absent', () => {
    const a = parseApp({
      appName: 'Test',
      startPage: 'home',
      pages: {
        home: { component: 'page', title: 'Home', content: [] },
      },
    })
    expect(a.auth.multiUser).toBe(false)
  })

  it('OdsMenuItem parses roles', () => {
    const item = parseMenuItem({
      label: 'Admin',
      mapsTo: 'adminPage',
      roles: ['admin'],
    })
    expect(item.roles).toEqual(['admin'])
  })

  it('OdsMenuItem roles default to undefined', () => {
    const item = parseMenuItem({
      label: 'Home',
      mapsTo: 'homePage',
    })
    expect(item.roles).toBeUndefined()
  })

  it('OdsPage parses roles', () => {
    const page = parsePage({
      title: 'Admin',
      roles: ['admin', 'manager'],
      content: [],
    })
    expect(page.roles).toEqual(['admin', 'manager'])
  })

  it('OdsTextComponent parses roles', () => {
    const comp = parseComponent({
      component: 'text',
      content: 'Secret',
      roles: ['admin'],
    })
    expect(comp.roles).toEqual(['admin'])
  })

  it('OdsButtonComponent parses roles', () => {
    const comp = parseComponent({
      component: 'button',
      label: 'Delete All',
      onClick: [{ action: 'navigate', target: 'home' }],
      roles: ['admin'],
    })
    expect(comp.roles).toEqual(['admin'])
  })

  it('OdsListColumn parses roles', () => {
    const comp = parseComponent({
      component: 'list',
      dataSource: 'ds',
      columns: [
        { header: 'Salary', field: 'salary', roles: ['admin', 'hr'] },
      ],
    })
    if (comp.component === 'list') {
      expect(comp.columns[0].roles).toEqual(['admin', 'hr'])
    }
  })

  it('OdsRowAction parses roles', () => {
    const comp = parseComponent({
      component: 'list',
      dataSource: 'ds',
      columns: [{ header: 'Name', field: 'name' }],
      rowActions: [
        {
          label: 'Delete',
          action: 'delete',
          dataSource: 'ds',
          roles: ['admin'],
        },
      ],
    })
    if (comp.component === 'list') {
      expect(comp.rowActions[0].roles).toEqual(['admin'])
    }
  })

  it('OdsFieldDefinition parses roles', () => {
    const field = parseFieldDefinition({
      name: 'secret',
      type: 'text',
      roles: ['admin'],
    })
    expect(field.roles).toEqual(['admin'])
  })

  it('OdsDataSource parses ownership', () => {
    const ds = parseDataSource({
      url: 'local://tasks',
      method: 'GET',
      ownership: { enabled: true, adminOverride: true },
    })
    expect(ds.ownership.enabled).toBe(true)
    expect(ds.ownership.adminOverride).toBe(true)
  })

  it('OdsDataSource defaults ownership when absent', () => {
    const ds = parseDataSource({
      url: 'local://tasks',
      method: 'GET',
    })
    expect(ds.ownership.enabled).toBe(false)
  })
})

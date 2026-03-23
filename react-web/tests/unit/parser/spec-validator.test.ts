import { describe, it, expect } from 'vitest'
import { validate, ValidationResult } from '../../../src/parser/spec-validator.ts'
import { parseApp, type OdsApp } from '../../../src/models/ods-app.ts'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function app(json: Record<string, unknown>): OdsApp {
  return parseApp(json)
}

function minimalApp(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    appName: 'Test',
    startPage: 'home',
    pages: {
      home: { component: 'page', title: 'Home', content: [] },
      admin: { component: 'page', title: 'Admin', content: [] },
    },
    ...overrides,
  }
}

// ===========================================================================
// Spec validator tests (ported from spec_validator_test.dart)
// ===========================================================================

describe('SpecValidator', () => {
  describe('Top-level validation', () => {
    it('empty appName is an error', () => {
      const a = app({
        appName: '',
        startPage: 'home',
        pages: {
          home: { component: 'page', title: 'Home', content: [] },
        },
      })
      const result = validate(a)
      expect(result.hasErrors).toBe(true)
      expect(result.errors.some(e => e.message.includes('appName'))).toBe(true)
    })

    it('startPage not in pages is an error', () => {
      const a = app({
        appName: 'Test',
        startPage: 'missing',
        pages: {
          home: { component: 'page', title: 'Home', content: [] },
        },
      })
      const result = validate(a)
      expect(result.hasErrors).toBe(true)
    })

    it('empty pages is an error', () => {
      const a = app({
        appName: 'Test',
        startPage: 'home',
        pages: {},
      })
      const result = validate(a)
      expect(result.hasErrors).toBe(true)
    })

    it('valid minimal app has no errors', () => {
      const a = app({
        appName: 'Test',
        startPage: 'home',
        pages: {
          home: { component: 'page', title: 'Home', content: [] },
        },
      })
      const result = validate(a)
      expect(result.hasErrors).toBe(false)
    })
  })

  describe('Menu validation', () => {
    it('menu item pointing to missing page is a warning', () => {
      const a = app({
        appName: 'Test',
        startPage: 'home',
        menu: [
          { label: 'Bad Link', mapsTo: 'nonexistent' },
        ],
        pages: {
          home: { component: 'page', title: 'Home', content: [] },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('nonexistent'))).toBe(true)
    })

    it('valid menu item produces no warnings', () => {
      const a = app({
        appName: 'Test',
        startPage: 'home',
        menu: [
          { label: 'Home', mapsTo: 'home' },
        ],
        pages: {
          home: { component: 'page', title: 'Home', content: [] },
        },
      })
      const result = validate(a)
      expect(result.warnings).toHaveLength(0)
    })
  })

  describe('List component validation', () => {
    it('list referencing unknown dataSource warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'p',
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'list',
                dataSource: 'missing',
                columns: [
                  { header: 'Name', field: 'name' },
                ],
              },
            ],
          },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('missing'))).toBe(true)
    })

    it('rowColorMap without rowColorField warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'p',
        dataSources: {
          reader: { url: 'local://items', method: 'GET' },
        },
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'list',
                dataSource: 'reader',
                columns: [
                  { header: 'Name', field: 'name' },
                ],
                rowColorMap: { Open: 'green', Closed: 'red' },
              },
            ],
          },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('rowColorMap'))).toBe(true)
    })
  })

  describe('Button action validation', () => {
    it('navigate to missing page warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'p',
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'button',
                label: 'Go',
                onClick: [
                  { action: 'navigate', target: 'nonexistent' },
                ],
              },
            ],
          },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('nonexistent'))).toBe(true)
    })

    it('submit to missing dataSource warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'p',
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'button',
                label: 'Save',
                onClick: [
                  { action: 'submit', dataSource: 'missing', target: 'form1' },
                ],
              },
            ],
          },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('missing'))).toBe(true)
    })

    it('update without matchField warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'p',
        dataSources: {
          store: { url: 'local://items', method: 'PUT' },
        },
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'button',
                label: 'Update',
                onClick: [
                  { action: 'update', dataSource: 'store', target: 'form1' },
                ],
              },
            ],
          },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('matchField'))).toBe(true)
    })
  })

  describe('Form field validation', () => {
    it('unknown field type warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'p',
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'form',
                id: 'f',
                fields: [
                  { name: 'x', type: 'bogus' },
                ],
              },
            ],
          },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('bogus'))).toBe(true)
    })

    it('select without options warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'p',
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'form',
                id: 'f',
                fields: [
                  { name: 'status', type: 'select' },
                ],
              },
            ],
          },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('options'))).toBe(true)
    })

    it('computed field with no dependencies warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'p',
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'form',
                id: 'f',
                fields: [
                  { name: 'total', type: 'number', formula: '42' },
                ],
              },
            ],
          },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('no field references'))).toBe(true)
    })

    it('computed field referencing unknown field warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'p',
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'form',
                id: 'f',
                fields: [
                  { name: 'total', type: 'number', formula: '{missing} * 2' },
                ],
              },
            ],
          },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('missing'))).toBe(true)
    })

    it('required computed field warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'p',
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'form',
                id: 'f',
                fields: [
                  { name: 'a', type: 'number' },
                  { name: 'total', type: 'number', formula: '{a} * 2', required: true },
                ],
              },
            ],
          },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('read-only'))).toBe(true)
    })

    it('visibleWhen referencing unknown sibling warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'p',
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'form',
                id: 'f',
                fields: [
                  {
                    name: 'extra',
                    type: 'text',
                    visibleWhen: { field: 'missing', equals: 'yes' },
                  },
                ],
              },
            ],
          },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('missing'))).toBe(true)
    })

    it('min/max on non-number field warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'p',
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'form',
                id: 'f',
                fields: [
                  {
                    name: 'name',
                    type: 'text',
                    validation: { min: 0, max: 100 },
                  },
                ],
              },
            ],
          },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('min/max'))).toBe(true)
    })
  })

  describe('Chart validation', () => {
    it('chart referencing unknown dataSource warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'p',
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'chart',
                dataSource: 'missing',
                chartType: 'bar',
                labelField: 'name',
                valueField: 'count',
              },
            ],
          },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('missing'))).toBe(true)
    })

    it('unknown chart type warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'p',
        dataSources: {
          reader: { url: 'local://items', method: 'GET' },
        },
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'chart',
                dataSource: 'reader',
                chartType: 'donut',
                labelField: 'name',
                valueField: 'count',
              },
            ],
          },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('donut'))).toBe(true)
    })
  })

  describe('Tabs validation', () => {
    it('empty tabs warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'p',
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              { component: 'tabs', tabs: [] },
            ],
          },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('no tabs'))).toBe(true)
    })

    it('tab with empty content warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'p',
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'tabs',
                tabs: [
                  { label: 'Empty', content: [] },
                ],
              },
            ],
          },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('no content'))).toBe(true)
    })
  })

  describe('Detail component validation', () => {
    it('detail referencing unknown dataSource warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'p',
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              { component: 'detail', dataSource: 'missing' },
            ],
          },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('missing'))).toBe(true)
    })
  })

  describe('Row action validation', () => {
    it('rowAction referencing unknown dataSource warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'p',
        dataSources: {
          reader: { url: 'local://items', method: 'GET' },
        },
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'list',
                dataSource: 'reader',
                columns: [
                  { header: 'Name', field: 'name' },
                ],
                rowActions: [
                  {
                    label: 'Delete',
                    action: 'delete',
                    dataSource: 'missing',
                    matchField: '_id',
                  },
                ],
              },
            ],
          },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('missing'))).toBe(true)
    })

    it('update rowAction with empty values warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'p',
        dataSources: {
          reader: { url: 'local://items', method: 'GET' },
          updater: { url: 'local://items', method: 'PUT' },
        },
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'list',
                dataSource: 'reader',
                columns: [
                  { header: 'Name', field: 'name' },
                ],
                rowActions: [
                  {
                    label: 'Mark Done',
                    action: 'update',
                    dataSource: 'updater',
                    matchField: '_id',
                  },
                ],
              },
            ],
          },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('empty values'))).toBe(true)
    })
  })

  describe('Dependent dropdown validation', () => {
    it('filter.fromField referencing unknown sibling warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'p',
        dataSources: {
          reader: { url: 'local://items', method: 'GET' },
        },
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'form',
                id: 'f',
                fields: [
                  {
                    name: 'sub',
                    type: 'select',
                    optionsFrom: {
                      dataSource: 'reader',
                      valueField: 'name',
                      filter: { field: 'category', fromField: 'nonexistent' },
                    },
                  },
                ],
              },
            ],
          },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('nonexistent'))).toBe(true)
    })
  })
})

// ===========================================================================
// Auth validator tests (ported from auth_validator_test.dart)
// ===========================================================================

describe('Auth validation', () => {
  describe('Auth block validation', () => {
    it('no auth block produces no auth warnings', () => {
      const a = app(minimalApp())
      const result = validate(a)
      expect(result.hasErrors).toBe(false)
      const authWarnings = result.warnings.filter(
        w => w.message.includes('auth') || w.message.includes('role') || w.message.includes('multiUser'),
      )
      expect(authWarnings).toHaveLength(0)
    })

    it('multiUserOnly without multiUser warns', () => {
      const a = app(minimalApp({
        auth: { multiUser: false, multiUserOnly: true },
      }))
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('multiUserOnly'))).toBe(true)
    })

    it('custom role duplicating built-in warns', () => {
      const a = app(minimalApp({
        auth: { multiUser: true, roles: ['admin', 'custom'] },
      }))
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('built-in role "admin"'))).toBe(true)
    })

    it('unknown defaultRole warns', () => {
      const a = app(minimalApp({
        auth: { multiUser: true, defaultRole: 'nonexistent' },
      }))
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('defaultRole'))).toBe(true)
    })

    it('valid custom role does not warn', () => {
      const a = app(minimalApp({
        auth: { multiUser: true, roles: ['manager'], defaultRole: 'user' },
      }))
      const result = validate(a)
      const roleWarnings = result.warnings.filter(
        w => w.message.includes('defaultRole') || w.message.includes('built-in'),
      )
      expect(roleWarnings).toHaveLength(0)
    })
  })

  describe('Role reference validation', () => {
    it('menu item with unknown role warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'home',
        auth: { multiUser: true },
        menu: [
          { label: 'Admin', mapsTo: 'admin', roles: ['superadmin'] },
        ],
        pages: {
          home: { component: 'page', title: 'Home', content: [] },
          admin: { component: 'page', title: 'Admin', content: [] },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('superadmin'))).toBe(true)
    })

    it('page with valid role does not warn', () => {
      const a = app({
        appName: 'Test',
        startPage: 'home',
        auth: { multiUser: true, roles: ['manager'] },
        pages: {
          home: { component: 'page', title: 'Home', content: [] },
          admin: {
            component: 'page',
            title: 'Admin',
            roles: ['admin', 'manager'],
            content: [],
          },
        },
      })
      const result = validate(a)
      const roleWarnings = result.warnings.filter(w => w.message.includes('not defined'))
      expect(roleWarnings).toHaveLength(0)
    })

    it('component with unknown role warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'home',
        auth: { multiUser: true },
        pages: {
          home: {
            component: 'page',
            title: 'Home',
            content: [
              {
                component: 'text',
                content: 'Secret',
                roles: ['nonexistent'],
              },
            ],
          },
        },
      })
      const result = validate(a)
      expect(result.warnings.some(w => w.message.includes('nonexistent'))).toBe(true)
    })
  })

  describe('Ownership validation', () => {
    it('ownership without multiUser warns', () => {
      const a = app({
        appName: 'Test',
        startPage: 'home',
        pages: {
          home: { component: 'page', title: 'Home', content: [] },
        },
        dataSources: {
          reader: {
            url: 'local://items',
            method: 'GET',
            ownership: { enabled: true },
          },
        },
      })
      const result = validate(a)
      expect(
        result.warnings.some(w => w.message.includes('ownership') && w.message.includes('multiUser')),
      ).toBe(true)
    })

    it('ownership with multiUser does not warn', () => {
      const a = app({
        appName: 'Test',
        startPage: 'home',
        auth: { multiUser: true },
        pages: {
          home: { component: 'page', title: 'Home', content: [] },
        },
        dataSources: {
          reader: {
            url: 'local://items',
            method: 'GET',
            ownership: { enabled: true },
          },
        },
      })
      const result = validate(a)
      const ownershipWarnings = result.warnings.filter(w => w.message.includes('ownership'))
      expect(ownershipWarnings).toHaveLength(0)
    })
  })
})

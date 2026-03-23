import { describe, it, expect } from 'vitest'
import { parseSpec, isOk } from '../../../src/parser/spec-parser.ts'
import { isLocal, tableName } from '../../../src/models/ods-data-source.ts'
import { isRecordAction } from '../../../src/models/ods-action.ts'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function parseFromObj(spec: Record<string, unknown>) {
  return parseSpec(JSON.stringify(spec))
}

function minimalSpec(overrides: Record<string, unknown> = {}) {
  return {
    appName: 'Test',
    startPage: 'p',
    pages: {
      p: { component: 'page', title: 'P', content: [] },
    },
    ...overrides,
  }
}

// ===========================================================================
// Main parser tests (ported from spec_parser_test.dart)
// ===========================================================================

describe('SpecParser', () => {
  describe('Invalid JSON', () => {
    it('returns parse error for malformed JSON', () => {
      const result = parseSpec('not json at all')
      expect(isOk(result)).toBe(false)
      expect(result.parseError).not.toBeNull()
    })

    it('returns parse error for JSON array', () => {
      const result = parseSpec('[1, 2, 3]')
      expect(isOk(result)).toBe(false)
    })
  })

  describe('Missing required fields', () => {
    it('missing appName', () => {
      const result = parseSpec(JSON.stringify({
        startPage: 'home',
        pages: {
          home: { component: 'page', title: 'Home', content: [] },
        },
      }))
      expect(isOk(result)).toBe(false)
      expect(result.validation.errors.some(e => e.message.includes('appName'))).toBe(true)
    })

    it('missing startPage', () => {
      const result = parseSpec(JSON.stringify({
        appName: 'Test',
        pages: {
          home: { component: 'page', title: 'Home', content: [] },
        },
      }))
      expect(isOk(result)).toBe(false)
      expect(result.validation.errors.some(e => e.message.includes('startPage'))).toBe(true)
    })

    it('missing pages', () => {
      const result = parseSpec(JSON.stringify({
        appName: 'Test',
        startPage: 'home',
      }))
      expect(isOk(result)).toBe(false)
      expect(result.validation.errors.some(e => e.message.includes('pages'))).toBe(true)
    })
  })

  describe('Valid minimal spec', () => {
    it('parses successfully', () => {
      const result = parseSpec(JSON.stringify({
        appName: 'Test App',
        startPage: 'home',
        pages: {
          home: {
            component: 'page',
            title: 'Home',
            content: [
              { component: 'text', content: 'Hello' },
            ],
          },
        },
      }))
      expect(isOk(result)).toBe(true)
      expect(result.app).not.toBeNull()
      expect(result.app!.appName).toBe('Test App')
      expect(result.app!.startPage).toBe('home')
      expect(Object.keys(result.app!.pages).length).toBe(1)
    })
  })

  describe('Component parsing', () => {
    it('text component', () => {
      const result = parseFromObj({
        appName: 'Test',
        startPage: 'p',
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              { component: 'text', content: 'Hello world' },
            ],
          },
        },
      })
      expect(isOk(result)).toBe(true)
      expect(result.app!.pages['p'].content.length).toBe(1)
    })

    it('form with fields', () => {
      const result = parseFromObj({
        appName: 'Test',
        startPage: 'p',
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'form',
                id: 'myForm',
                fields: [
                  { name: 'email', type: 'email', required: true },
                  { name: 'status', type: 'select', options: ['Open', 'Closed'] },
                ],
              },
            ],
          },
        },
      })
      expect(isOk(result)).toBe(true)
    })

    it('button with onClick actions', () => {
      const result = parseFromObj({
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
                  { action: 'navigate', target: 'p' },
                ],
              },
            ],
          },
        },
      })
      expect(isOk(result)).toBe(true)
    })

    it('list component with columns', () => {
      const result = parseFromObj({
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
              },
            ],
          },
        },
      })
      expect(isOk(result)).toBe(true)
    })
  })

  describe('Data sources', () => {
    it('local data source parsed', () => {
      const result = parseSpec(JSON.stringify({
        appName: 'Test',
        startPage: 'p',
        dataSources: {
          store: { url: 'local://items', method: 'POST' },
          reader: { url: 'local://items', method: 'GET' },
        },
        pages: {
          p: { component: 'page', title: 'P', content: [] },
        },
      }))
      expect(isOk(result)).toBe(true)
      expect(Object.keys(result.app!.dataSources).length).toBe(2)
      expect(result.app!.dataSources['store'].method).toBe('POST')
      expect(isLocal(result.app!.dataSources['reader'])).toBe(true)
    })
  })

  describe('Optional features', () => {
    it('help parsed', () => {
      const result = parseSpec(JSON.stringify({
        appName: 'Test',
        startPage: 'p',
        pages: {
          p: { component: 'page', title: 'P', content: [] },
        },
        help: {
          overview: 'This is a test app.',
          pages: { p: 'This is page P.' },
        },
      }))
      expect(isOk(result)).toBe(true)
      expect(result.app!.help).toBeDefined()
      expect(result.app!.help!.overview).toBe('This is a test app.')
    })

    it('tour parsed', () => {
      const result = parseSpec(JSON.stringify({
        appName: 'Test',
        startPage: 'p',
        pages: {
          p: { component: 'page', title: 'P', content: [] },
        },
        tour: [
          { title: 'Welcome', content: 'Hello!' },
          { title: 'Step 2', content: 'Do this.', page: 'p' },
        ],
      }))
      expect(isOk(result)).toBe(true)
      expect(result.app!.tour).toBeDefined()
      expect(result.app!.tour.length).toBe(2)
    })

    it('settings parsed', () => {
      const result = parseSpec(JSON.stringify({
        appName: 'Test',
        startPage: 'p',
        pages: {
          p: { component: 'page', title: 'P', content: [] },
        },
        settings: {
          theme: {
            label: 'Theme',
            type: 'select',
            default: 'light',
            options: ['light', 'dark'],
          },
        },
      }))
      expect(isOk(result)).toBe(true)
      expect(result.app!.settings).toBeDefined()
      expect('theme' in result.app!.settings).toBe(true)
    })

    it('menu parsed', () => {
      const result = parseSpec(JSON.stringify({
        appName: 'Test',
        startPage: 'p',
        menu: [
          { label: 'Home', mapsTo: 'p' },
        ],
        pages: {
          p: { component: 'page', title: 'P', content: [] },
        },
      }))
      expect(isOk(result)).toBe(true)
      expect(result.app!.menu.length).toBe(1)
      expect(result.app!.menu[0].label).toBe('Home')
    })
  })
})

// ===========================================================================
// Edge case tests (ported from spec_parser_edge_test.dart)
// ===========================================================================

describe('SpecParser edge cases', () => {
  describe('Unknown component types', () => {
    it('unknown component type parses as unknown component', () => {
      const result = parseFromObj({
        appName: 'Test',
        startPage: 'p',
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              { component: 'wizardWidget', data: 'anything' },
            ],
          },
        },
      })
      expect(isOk(result)).toBe(true)
      expect(result.app!.pages['p'].content[0].component).toBe('unknown')
    })
  })

  describe('Empty content', () => {
    it('page with empty content array parses', () => {
      const result = parseFromObj({
        appName: 'Test',
        startPage: 'p',
        pages: {
          p: { component: 'page', title: 'P', content: [] },
        },
      })
      expect(isOk(result)).toBe(true)
      expect(result.app!.pages['p'].content).toHaveLength(0)
    })
  })

  describe('Multiple pages', () => {
    it('multiple pages parsed correctly', () => {
      const result = parseFromObj({
        appName: 'Test',
        startPage: 'home',
        pages: {
          home: { component: 'page', title: 'Home', content: [] },
          add: { component: 'page', title: 'Add', content: [] },
          edit: { component: 'page', title: 'Edit', content: [] },
        },
      })
      expect(isOk(result)).toBe(true)
      expect(Object.keys(result.app!.pages).length).toBe(3)
    })
  })

  describe('All component types', () => {
    it('text component', () => {
      const result = parseFromObj(minimalSpec({
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              { component: 'text', content: 'Hello' },
            ],
          },
        },
      }))
      expect(result.app!.pages['p'].content[0].component).toBe('text')
    })

    it('summary component', () => {
      const result = parseFromObj(minimalSpec({
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              { component: 'summary', label: 'Total', value: '42' },
            ],
          },
        },
      }))
      expect(result.app!.pages['p'].content[0].component).toBe('summary')
    })

    it('tabs component', () => {
      const result = parseFromObj(minimalSpec({
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'tabs',
                tabs: [
                  {
                    label: 'Tab1',
                    content: [
                      { component: 'text', content: 'Inside tab' },
                    ],
                  },
                ],
              },
            ],
          },
        },
      }))
      expect(result.app!.pages['p'].content[0].component).toBe('tabs')
    })

    it('detail component', () => {
      const result = parseFromObj(minimalSpec({
        dataSources: {
          reader: { url: 'local://items', method: 'GET' },
        },
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              { component: 'detail', dataSource: 'reader' },
            ],
          },
        },
      }))
      expect(result.app!.pages['p'].content[0].component).toBe('detail')
    })

    it('chart component', () => {
      const result = parseFromObj(minimalSpec({
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
                chartType: 'bar',
                labelField: 'name',
                valueField: 'count',
              },
            ],
          },
        },
      }))
      expect(result.app!.pages['p'].content[0].component).toBe('chart')
    })
  })

  describe('Field types', () => {
    it('all field types parse', () => {
      const types = ['text', 'email', 'number', 'date', 'datetime', 'multiline', 'select', 'checkbox', 'hidden']
      for (const type of types) {
        const fields: Record<string, unknown>[] = [
          {
            name: 'f',
            type,
            ...(type === 'select' ? { options: ['A', 'B'] } : {}),
          },
        ]
        const result = parseFromObj(minimalSpec({
          pages: {
            p: {
              component: 'page',
              title: 'P',
              content: [
                { component: 'form', id: 'form1', fields },
              ],
            },
          },
        }))
        expect(isOk(result), `Type "${type}" should parse`).toBe(true)
      }
    })
  })

  describe('DataSource features', () => {
    it('explicit fields on dataSource parsed', () => {
      const result = parseFromObj(minimalSpec({
        dataSources: {
          reader: {
            url: 'local://items',
            method: 'GET',
            fields: [
              { name: 'name', type: 'text' },
              { name: 'age', type: 'number' },
            ],
          },
        },
      }))
      expect(result.app!.dataSources['reader'].fields).toBeDefined()
      expect(result.app!.dataSources['reader'].fields!.length).toBe(2)
    })

    it('seedData on dataSource parsed', () => {
      const result = parseFromObj(minimalSpec({
        dataSources: {
          store: {
            url: 'local://items',
            method: 'GET',
            seedData: [
              { name: 'Alice', age: '30' },
              { name: 'Bob', age: '25' },
            ],
          },
        },
      }))
      expect(result.app!.dataSources['store'].seedData).toBeDefined()
      expect(result.app!.dataSources['store'].seedData!.length).toBe(2)
    })

    it('isLocal detection', () => {
      const result = parseFromObj(minimalSpec({
        dataSources: {
          local: { url: 'local://items', method: 'GET' },
          remote: { url: 'https://api.example.com/items', method: 'GET' },
        },
      }))
      expect(isLocal(result.app!.dataSources['local'])).toBe(true)
      expect(isLocal(result.app!.dataSources['remote'])).toBe(false)
    })

    it('tableName extraction', () => {
      const result = parseFromObj(minimalSpec({
        dataSources: {
          store: { url: 'local://my_table', method: 'POST' },
        },
      }))
      expect(tableName(result.app!.dataSources['store'])).toBe('my_table')
    })
  })

  describe('Action parsing', () => {
    it('computedFields on submit action parsed', () => {
      const result = parseFromObj(minimalSpec({
        dataSources: {
          store: { url: 'local://items', method: 'POST' },
        },
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'button',
                label: 'Save',
                onClick: [
                  {
                    action: 'submit',
                    target: 'form1',
                    dataSource: 'store',
                    computedFields: [
                      { field: 'score', expression: "{answer} == {correct} ? '1' : '0'" },
                    ],
                  },
                ],
              },
            ],
          },
        },
      }))
      expect(isOk(result)).toBe(true)
      const btn = result.app!.pages['p'].content[0]
      expect(btn.component).toBe('button')
      if (btn.component === 'button') {
        expect(btn.onClick[0].computedFields.length).toBe(1)
        expect(btn.onClick[0].computedFields[0].field).toBe('score')
      }
    })

    it('showMessage action parsed', () => {
      const result = parseFromObj(minimalSpec({
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'button',
                label: 'Save',
                onClick: [
                  { action: 'showMessage', message: 'Saved!' },
                ],
              },
            ],
          },
        },
      }))
      expect(isOk(result)).toBe(true)
      const btn = result.app!.pages['p'].content[0]
      if (btn.component === 'button') {
        expect(btn.onClick[0].message).toBe('Saved!')
      }
    })

    it('record cursor actions parsed', () => {
      const result = parseFromObj(minimalSpec({
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'button',
                label: 'Next',
                onClick: [
                  {
                    action: 'nextRecord',
                    target: 'quizForm',
                    onEnd: { action: 'navigate', target: 'results' },
                  },
                ],
              },
            ],
          },
        },
      }))
      expect(isOk(result)).toBe(true)
      const btn = result.app!.pages['p'].content[0]
      if (btn.component === 'button') {
        expect(isRecordAction(btn.onClick[0])).toBe(true)
        expect(btn.onClick[0].onEnd).toBeDefined()
        expect(btn.onClick[0].onEnd!.target).toBe('results')
      }
    })
  })

  describe('List features', () => {
    it('defaultSort parsed', () => {
      const result = parseFromObj(minimalSpec({
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
                  { header: 'Date', field: 'date', sortable: true },
                ],
                defaultSort: { field: 'date', direction: 'desc' },
              },
            ],
          },
        },
      }))
      expect(isOk(result)).toBe(true)
      const list = result.app!.pages['p'].content[0]
      if (list.component === 'list') {
        expect(list.defaultSort).toBeDefined()
        expect(list.defaultSort!.field).toBe('date')
        expect(list.defaultSort!.direction).toBe('desc')
      }
    })

    it('card display mode parsed', () => {
      const result = parseFromObj(minimalSpec({
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
                displayAs: 'cards',
              },
            ],
          },
        },
      }))
      expect(isOk(result)).toBe(true)
      const list = result.app!.pages['p'].content[0]
      if (list.component === 'list') {
        expect(list.displayAs).toBe('cards')
      }
    })

    it('row coloring parsed', () => {
      const result = parseFromObj(minimalSpec({
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
                  { header: 'Status', field: 'status' },
                ],
                rowColorField: 'status',
                rowColorMap: { Open: 'green', Closed: 'red' },
              },
            ],
          },
        },
      }))
      expect(isOk(result)).toBe(true)
      const list = result.app!.pages['p'].content[0]
      if (list.component === 'list') {
        expect(list.rowColorField).toBe('status')
        expect(list.rowColorMap).toBeDefined()
        expect(list.rowColorMap!['Open']).toBe('green')
      }
    })
  })
})

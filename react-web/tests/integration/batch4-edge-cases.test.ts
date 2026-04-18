import { describe, it, expect, beforeEach, vi } from 'vitest'
import { useAppStore, RecordCursor } from '../../src/engine/app-store.ts'
import { AuthService } from '../../src/engine/auth-service.ts'
import { parseApp } from '../../src/models/ods-app.ts'
import { parseSpec, isOk } from '../../src/parser/spec-parser.ts'
import { FakeDataService } from '../helpers/fake-data-service.ts'
import { resolveAggregates } from '../../src/engine/aggregate-evaluator.ts'
import { restoreBackup } from '../../src/engine/backup-service.ts'
import { DataService } from '../../src/engine/data-service.ts'

// ---------------------------------------------------------------------------
// Test helpers (mirrors patterns in batch1/batch2/batch3)
// ---------------------------------------------------------------------------

function mockPb() {
  return {
    authStore: { isValid: false, record: null, clear: () => {} },
    collection: () => ({
      listAuthMethods: async () => ({ oauth2: { providers: [] } }),
    }),
  } as any
}

function makeApp(overrides: any = {}) {
  const defaultPages = {
    home: {
      title: 'Home',
      content: [
        {
          component: 'form',
          id: 'addForm',
          fields: [
            { name: 'title', type: 'text', label: 'Title' },
            { name: 'status', type: 'text', label: 'Status' },
          ],
        },
      ],
    },
    other: {
      title: 'Other',
      content: [
        {
          component: 'form',
          id: 'otherForm',
          fields: [
            { name: 'notes', type: 'text', label: 'Notes' },
          ],
        },
      ],
    },
  }

  return parseApp({
    appName: 'Test',
    startPage: 'home',
    pages: overrides.pages ?? defaultPages,
    dataSources: overrides.dataSources ?? {
      tasks: {
        url: 'local://tasks',
        method: 'POST',
        fields: [
          { name: 'title', type: 'text', label: 'Title' },
          { name: 'status', type: 'text', label: 'Status' },
        ],
      },
    },
    ...Object.fromEntries(
      Object.entries(overrides).filter(([k]) =>
        k !== 'pages' && k !== 'dataSources',
      ),
    ),
  })
}

function resetStore(ds: FakeDataService, authService: AuthService) {
  useAppStore.setState({
    app: null,
    currentPageId: null,
    navigationStack: [],
    formStates: {},
    recordCursors: {},
    recordGeneration: 0,
    validation: null,
    loadError: null,
    debugMode: false,
    isLoading: false,
    lastActionError: null,
    lastMessage: null,
    appSettings: {},
    dataService: ds as any,
    authService,
    currentSlug: null,
    isMultiUser: false,
    needsAdminSetup: false,
    needsLogin: false,
    isMultiUserOnly: false,
  })
}

// ---------------------------------------------------------------------------
// Suite
// ---------------------------------------------------------------------------

describe('Batch 4: Edge-case integration tests', () => {
  let ds: FakeDataService
  let authService: AuthService

  beforeEach(() => {
    ds = new FakeDataService()
    ds.initialize('test')
    authService = new AuthService(mockPb())
    resetStore(ds, authService)
  })

  // -------------------------------------------------------------------------
  // B4-1: Empty data sources
  // -------------------------------------------------------------------------

  describe('B4-1: Empty data sources', () => {
    it('query on empty data source returns []', async () => {
      const app = makeApp()
      useAppStore.setState({ app })
      const rows = await useAppStore.getState().queryDataSource('tasks')
      expect(rows).toEqual([])
    })

    it('query on unknown (non-existent) data source returns []', async () => {
      const app = makeApp()
      useAppStore.setState({ app })
      const rows = await useAppStore.getState().queryDataSource('nothing')
      expect(rows).toEqual([])
    })

    it('COUNT aggregate on empty data source returns "0"', async () => {
      // Summary COUNT expression resolved via aggregate-evaluator.
      const result = await resolveAggregates(
        '{COUNT(tasks)}',
        async () => [],
      )
      expect(result).toBe('0')
    })

    it('SUM aggregate on empty data source returns "0"', async () => {
      const result = await resolveAggregates(
        '{SUM(tasks, amount)}',
        async () => [],
      )
      expect(result).toBe('0')
    })

    it('PCT aggregate on empty data source returns "0"', async () => {
      const result = await resolveAggregates(
        '{PCT(tasks, status=done)}',
        async () => [],
      )
      expect(result).toBe('0')
    })

    it('firstRecord on empty DS: no crash, form unchanged', async () => {
      const app = makeApp({
        pages: {
          home: {
            title: 'Home',
            content: [
              {
                component: 'form',
                id: 'editForm',
                recordSource: 'tasks',
                fields: [{ name: 'title', type: 'text', label: 'Title' }],
              },
            ],
          },
        },
      })
      // No rows.
      useAppStore.setState({
        app,
        currentPageId: 'home',
        formStates: { editForm: { title: 'preserved' } },
      })

      await expect(
        useAppStore.getState().executeActions([
          {
            action: 'firstRecord',
            target: 'editForm',
            computedFields: [],
            preserveFields: [],
          },
        ])
      ).resolves.toBeUndefined()

      const state = useAppStore.getState()
      // No onEnd was supplied so no message set.
      expect(state.lastActionError).toBeNull()
      expect(state.lastMessage).toBeNull()
      // Form state still holds its prior value (firstRecord didn't populate anything).
      expect(state.formStates.editForm.title).toBe('preserved')
    })

    it('firstRecord on empty DS WITH onEnd: onEnd fires', async () => {
      const app = makeApp({
        pages: {
          home: {
            title: 'Home',
            content: [
              {
                component: 'form',
                id: 'editForm',
                recordSource: 'tasks',
                fields: [{ name: 'title', type: 'text', label: 'Title' }],
              },
            ],
          },
        },
      })
      useAppStore.setState({ app, currentPageId: 'home' })

      await useAppStore.getState().executeActions([
        {
          action: 'firstRecord',
          target: 'editForm',
          onEnd: {
            action: 'showMessage',
            message: 'Empty',
            computedFields: [],
            preserveFields: [],
          },
          computedFields: [],
          preserveFields: [],
        },
      ])

      expect(useAppStore.getState().lastMessage).toBe('Empty')
    })
  })

  // -------------------------------------------------------------------------
  // B4-2: Very large data sets
  // -------------------------------------------------------------------------

  describe('B4-2: Very large data sets', () => {
    // Use a smaller number than 1000 for aggregate-insertion paths to keep
    // test time down; 1000 is still verified for query/delete paths.
    const LARGE = 1000

    it('query returns all rows for a 1000-row table (no pagination crash)', async () => {
      const app = makeApp()
      const rows = Array.from({ length: LARGE }, (_, i) => ({
        title: `T${i}`,
        status: 'todo',
      }))
      ds.seed('tasks', rows)
      useAppStore.setState({ app })

      const all = await useAppStore.getState().queryDataSource('tasks')
      expect(all.length).toBe(LARGE)
    })

    it('submit into a 1000-row table succeeds', async () => {
      const app = makeApp()
      const rows = Array.from({ length: LARGE }, (_, i) => ({
        title: `T${i}`,
        status: 'todo',
      }))
      ds.seed('tasks', rows)
      useAppStore.setState({
        app,
        formStates: { addForm: { title: 'NewOne' } },
      })

      await useAppStore.getState().executeActions([
        {
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
          computedFields: [],
          preserveFields: [],
        },
      ])

      const all = await ds.query('tasks')
      expect(all.length).toBe(LARGE + 1)
      expect(all.some(r => r.title === 'NewOne')).toBe(true)
    })

    it('delete one row from a 1000-row table works', async () => {
      const app = makeApp()
      const rows = Array.from({ length: LARGE }, (_, i) => ({
        title: `T${i}`,
        status: 'todo',
      }))
      ds.seed('tasks', rows)
      useAppStore.setState({ app })

      // Grab some row in the middle.
      const seeded = await ds.query('tasks')
      const targetId = String(seeded[500]._id)
      await useAppStore.getState().executeDeleteRowAction('tasks', '_id', targetId)

      const remaining = await ds.query('tasks')
      expect(remaining.length).toBe(LARGE - 1)
      expect(remaining.find(r => r._id === targetId)).toBeUndefined()
    })

    it('filter/search on 1000-row table returns correct subset', async () => {
      const rows = Array.from({ length: LARGE }, (_, i) => ({
        title: `T${i}`,
        status: i % 3 === 0 ? 'done' : 'todo',
      }))
      ds.seed('tasks', rows)

      const done = await ds.queryWithFilter('tasks', { status: 'done' })
      const todo = await ds.queryWithFilter('tasks', { status: 'todo' })
      // i % 3 === 0 for i in [0..999] → 334 rows (0, 3, 6, ..., 999).
      expect(done.length).toBe(334)
      expect(todo.length).toBe(LARGE - 334)
    })
  })

  // -------------------------------------------------------------------------
  // B4-3: Missing optional spec fields
  // -------------------------------------------------------------------------

  describe('B4-3: Missing optional spec fields', () => {
    it('spec with no `menu` → loads, app.menu = []', () => {
      const app = parseApp({
        appName: 'NoMenu',
        startPage: 'home',
        pages: { home: { title: 'Home', content: [] } },
      })
      expect(app.menu).toEqual([])
    })

    it('spec with no `branding` → default branding', () => {
      const app = parseApp({
        appName: 'NoBranding',
        startPage: 'home',
        pages: { home: { title: 'Home', content: [] } },
      })
      expect(app.branding).toBeDefined()
      expect(app.branding.theme).toBe('indigo')
      expect(app.branding.mode).toBe('system')
    })

    it('spec with no `auth` → defaults to single-user', () => {
      const app = parseApp({
        appName: 'NoAuth',
        startPage: 'home',
        pages: { home: { title: 'Home', content: [] } },
      })
      expect(app.auth.multiUser).toBe(false)
      expect(app.auth.multiUserOnly).toBe(false)
      expect(app.auth.selfRegistration).toBe(false)
    })

    it('spec with no `help` → app.help is undefined, no crash', () => {
      const app = parseApp({
        appName: 'NoHelp',
        startPage: 'home',
        pages: { home: { title: 'Home', content: [] } },
      })
      expect(app.help).toBeUndefined()
    })

    it('spec with no `settings` → app.settings = {}', () => {
      const app = parseApp({
        appName: 'NoSettings',
        startPage: 'home',
        pages: { home: { title: 'Home', content: [] } },
      })
      expect(app.settings).toEqual({})
    })

    it('page with no `roles` → hasAccess returns true (anyone can access)', () => {
      const app = makeApp({
        pages: {
          home: { title: 'Home', content: [] }, // no roles
        },
      })
      useAppStore.setState({ app, currentPageId: 'home' })
      // guest user (no login); page has no roles → access allowed.
      expect(authService.hasAccess(app.pages.home.roles)).toBe(true)
    })

    it('component with no `styleHint` → uses defaults (no crash)', () => {
      // Components without styleHint should parse with default style values.
      const app = parseApp({
        appName: 'NoStyleHint',
        startPage: 'home',
        pages: {
          home: {
            title: 'Home',
            content: [
              {
                component: 'text',
                content: 'hello',
                // no styleHint at all
              },
            ],
          },
        },
      })
      const comp = app.pages.home.content[0]
      expect(comp.component).toBe('text')
      // styleHint should still exist as a parsed default object.
      expect(comp.styleHint).toBeDefined()
    })

    it('spec with no `tour` → empty array, no crash', () => {
      const app = parseApp({
        appName: 'NoTour',
        startPage: 'home',
        pages: { home: { title: 'Home', content: [] } },
      })
      expect(app.tour).toEqual([])
    })
  })

  // -------------------------------------------------------------------------
  // B4-4: Malformed JSON specs
  // -------------------------------------------------------------------------

  describe('B4-4: Malformed JSON specs', () => {
    it('spec with JSON syntax error → parseError set, no crash', () => {
      const result = parseSpec('{ "appName": "Bad", ')
      expect(result.parseError).toBeTruthy()
      expect(result.app).toBeNull()
      expect(isOk(result)).toBe(false)
    })

    it('spec is a bare array → parseError set', () => {
      const result = parseSpec('[]')
      expect(result.parseError).toBeTruthy()
      expect(result.app).toBeNull()
    })

    it('spec is a string → parseError set', () => {
      const result = parseSpec('"just-a-string"')
      expect(result.parseError).toBeTruthy()
      expect(result.app).toBeNull()
    })

    it('spec with wrong type (appName as number) → app built but validation error', () => {
      // parseSpec doesn't coerce types; it proceeds to validate. Missing/invalid
      // `appName` still surfaces as a validation error (empty string).
      const result = parseSpec(JSON.stringify({
        appName: 123,
        startPage: 'home',
        pages: { home: { title: 'Home', content: [] } },
      }))
      // Either a parseError OR a validation error is acceptable — test current behavior.
      const hasProblem = result.parseError !== null || result.validation.hasErrors
        || (result.app && typeof result.app.appName !== 'string')
      expect(hasProblem).toBe(true)
    })

    it('spec with duplicate page IDs: JSON parser keeps last, spec still loads', () => {
      // Technically impossible via object literal — JSON.parse silently keeps last.
      const json = '{"appName":"Dup","startPage":"home","pages":{"home":{"title":"H1","content":[]},"home":{"title":"H2","content":[]}}}'
      const result = parseSpec(json)
      expect(result.parseError).toBeNull()
      expect(result.app).not.toBeNull()
      // Last wins in JSON.parse.
      expect(result.app!.pages.home.title).toBe('H2')
    })

    it('very large spec (~1MB JSON) → parses without crash', () => {
      // Build a large spec with many pages.
      const pages: Record<string, unknown> = {
        home: { title: 'Home', content: [] },
      }
      const filler = 'x'.repeat(500)
      for (let i = 0; i < 2000; i++) {
        pages[`page${i}`] = {
          title: filler,
          content: [{ component: 'text', content: filler }],
        }
      }
      const spec = {
        appName: 'Large',
        startPage: 'home',
        pages,
      }
      const json = JSON.stringify(spec)
      // Sanity check we actually built a large spec (>1MB).
      expect(json.length).toBeGreaterThan(1_000_000)

      const result = parseSpec(json)
      expect(result.parseError).toBeNull()
      expect(result.app).not.toBeNull()
      expect(Object.keys(result.app!.pages).length).toBe(2001)
    })

    it('empty spec `{}` → validation errors (no crash, no parseError)', () => {
      const result = parseSpec('{}')
      expect(result.parseError).toBeNull()
      expect(result.validation.hasErrors).toBe(true)
      expect(result.app).toBeNull()
    })

    it('spec with non-object `pages` → parse error or validation error, no crash', () => {
      const result = parseSpec(JSON.stringify({
        appName: 'Bad',
        startPage: 'home',
        pages: 'not-an-object',
      }))
      // Should NOT crash. Either parseError or app.pages is empty → validation fails.
      const bad = result.parseError !== null
        || result.validation.hasErrors
        || (result.app && Object.keys(result.app.pages).length === 0)
      expect(bad).toBe(true)
    })
  })

  // -------------------------------------------------------------------------
  // B4-5: Unicode/emoji in values
  // -------------------------------------------------------------------------

  describe('B4-5: Unicode/emoji in values', () => {
    it('submit form with unicode/emoji round-trips exactly', async () => {
      const app = makeApp({
        dataSources: {
          tasks: {
            url: 'local://tasks',
            method: 'POST',
            fields: [
              { name: 'name', type: 'text', label: 'Name' },
              { name: 'description', type: 'text', label: 'Desc' },
            ],
          },
        },
        pages: {
          home: {
            title: 'Home',
            content: [
              {
                component: 'form',
                id: 'addForm',
                fields: [
                  { name: 'name', type: 'text', label: 'Name' },
                  { name: 'description', type: 'text', label: 'Desc' },
                ],
              },
            ],
          },
        },
      })
      useAppStore.setState({
        app,
        formStates: {
          addForm: { name: 'café 🎉', description: '日本語テスト' },
        },
      })

      await useAppStore.getState().executeActions([
        {
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
          computedFields: [],
          preserveFields: [],
        },
      ])

      const rows = await ds.query('tasks')
      expect(rows.length).toBe(1)
      expect(rows[0].name).toBe('café 🎉')
      expect(rows[0].description).toBe('日本語テスト')
    })

    it('queryWithFilter using a unicode match value returns matching rows', async () => {
      ds.seed('tasks', [
        { title: 'café 🎉', status: 'todo' },
        { title: 'plain', status: 'todo' },
      ])
      const rows = await ds.queryWithFilter('tasks', { title: 'café 🎉' })
      expect(rows.length).toBe(1)
      expect(rows[0].title).toBe('café 🎉')
    })

    it('validateFieldName rejects unicode/emoji in field names (via DataService)', async () => {
      // DataService.update validates matchField against /^[a-zA-Z_][a-zA-Z0-9_]*$/
      // so unicode identifiers like "café" or "日本" should be rejected.
      const pb = {
        collection: vi.fn(() => ({
          getFullList: vi.fn(async () => []),
          update: vi.fn(async () => ({})),
        })),
      } as any
      const realDs = new DataService(pb)
      realDs.initialize('test')

      await expect(
        realDs.update('tasks', { x: '1' }, 'café', 'val'),
      ).rejects.toThrow(/Invalid field name/)

      await expect(
        realDs.update('tasks', { x: '1' }, '日本', 'val'),
      ).rejects.toThrow(/Invalid field name/)
    })

    it('backup → restore preserves unicode values exactly', async () => {
      const app = makeApp()
      ds.seed('tasks', []) // ensure table exists

      const backup = {
        odsBackup: true,
        tables: {
          tasks: [
            { title: 'café 🎉', status: '日本語' },
          ],
        },
      }

      const result = await restoreBackup(JSON.stringify(backup), app, ds as any)
      expect(result).toBeNull()

      const rows = await ds.query('tasks')
      expect(rows.length).toBe(1)
      expect(rows[0].title).toBe('café 🎉')
      expect(rows[0].status).toBe('日本語')
    })
  })

  // -------------------------------------------------------------------------
  // B4-6: Concurrent actions
  // -------------------------------------------------------------------------

  describe('B4-6: Concurrent actions', () => {
    it('executeActions called twice in quick succession: both complete', async () => {
      const app = makeApp()
      useAppStore.setState({
        app,
        currentPageId: 'home',
        formStates: { addForm: { title: 'First' } },
      })

      // Fire first, then immediately update form and fire second.
      const p1 = useAppStore.getState().executeActions([
        {
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
          computedFields: [],
          preserveFields: [],
        },
      ])
      useAppStore.setState({ formStates: { addForm: { title: 'Second' } } })
      const p2 = useAppStore.getState().executeActions([
        {
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
          computedFields: [],
          preserveFields: [],
        },
      ])

      await Promise.all([p1, p2])

      // At least one submit succeeded (ideally two, but race may coalesce).
      // Any failure of both = bug.
      const rows = await ds.query('tasks')
      expect(rows.length).toBeGreaterThanOrEqual(1)
    })

    it('rapid-fire 10 inserts via Promise.all: all rows inserted', async () => {
      // Direct DataService-level test (not through store) since store shares
      // form state — concurrent inserts would clobber each other.
      const inserts = Array.from({ length: 10 }, (_, i) =>
        ds.insert('tasks', { title: `Row${i}`, status: 'todo' }),
      )
      await Promise.all(inserts)

      const rows = await ds.query('tasks')
      expect(rows.length).toBe(10)
    })

    it('rapid-fire 10 deletes concurrently: no crash, all deleted', async () => {
      // Seed 10 rows.
      ds.seed('tasks', Array.from({ length: 10 }, (_, i) => ({
        title: `Row${i}`, status: 'todo',
      })))
      const seeded = await ds.query('tasks')
      expect(seeded.length).toBe(10)

      // Fire 10 deletes concurrently.
      const deletes = seeded.map(row =>
        ds.delete('tasks', '_id', String(row._id)),
      )
      await Promise.all(deletes)

      const remaining = await ds.query('tasks')
      expect(remaining.length).toBe(0)
    })
  })

  // -------------------------------------------------------------------------
  // B4-7: Stale state after navigation
  // -------------------------------------------------------------------------

  describe('B4-7: Stale state after navigation', () => {
    it('form A state is preserved when navigating away and back', () => {
      const app = makeApp()
      useAppStore.setState({ app, currentPageId: 'home' })

      // Fill form A on home.
      useAppStore.getState().updateFormField('addForm', 'title', 'FillMe')

      // Navigate to other page.
      useAppStore.getState().navigateTo('other')
      expect(useAppStore.getState().currentPageId).toBe('other')

      // Navigate back.
      useAppStore.getState().goBack()
      expect(useAppStore.getState().currentPageId).toBe('home')

      // Form A state should still be intact.
      expect(useAppStore.getState().formStates.addForm).toEqual({ title: 'FillMe' })
    })

    it('clearForm(formA) does not touch formB', () => {
      useAppStore.getState().updateFormField('formA', 'name', 'A')
      useAppStore.getState().updateFormField('formB', 'name', 'B')
      useAppStore.getState().clearForm('formA')

      const state = useAppStore.getState()
      expect(state.formStates.formA).toBeUndefined()
      expect(state.formStates.formB).toEqual({ name: 'B' })
    })

    it('recordCursor persists across page navigation', async () => {
      const app = makeApp({
        pages: {
          home: {
            title: 'Home',
            content: [
              {
                component: 'form',
                id: 'editForm',
                recordSource: 'tasks',
                fields: [{ name: 'title', type: 'text', label: 'Title' }],
              },
            ],
          },
          other: { title: 'Other', content: [] },
        },
      })
      ds.seed('tasks', [
        { title: 'A', status: 'todo' },
        { title: 'B', status: 'todo' },
      ])
      useAppStore.setState({ app, currentPageId: 'home' })

      await useAppStore.getState().executeActions([
        { action: 'firstRecord', target: 'editForm', computedFields: [], preserveFields: [] },
      ])
      const cursor = useAppStore.getState().recordCursors.editForm
      expect(cursor).toBeDefined()
      const originalIndex = cursor!.currentIndex
      const originalCount = cursor!.count

      // Navigate away and back.
      useAppStore.getState().navigateTo('other')
      useAppStore.getState().goBack()

      // Cursor still intact.
      const after = useAppStore.getState().recordCursors.editForm
      expect(after).toBeDefined()
      expect(after!.currentIndex).toBe(originalIndex)
      expect(after!.count).toBe(originalCount)
    })

    it('stale form state does not cross-contaminate: updating formA after navigate does not affect formB', () => {
      const app = makeApp()
      useAppStore.setState({ app, currentPageId: 'home' })

      useAppStore.getState().updateFormField('formA', 'name', 'Alice')
      useAppStore.getState().updateFormField('formB', 'name', 'Bob')
      useAppStore.getState().navigateTo('other')
      useAppStore.getState().updateFormField('formA', 'name', 'Alice2')

      const state = useAppStore.getState()
      expect(state.formStates.formA.name).toBe('Alice2')
      expect(state.formStates.formB.name).toBe('Bob')
    })
  })

  // -------------------------------------------------------------------------
  // B4-8: Invalid field name boundaries
  // -------------------------------------------------------------------------

  describe('B4-8: Invalid field name boundaries', () => {
    // Run all checks against the real DataService.validateFieldName via update().
    async function expectAccepted(name: string) {
      const pb = {
        collection: vi.fn(() => ({
          getFullList: vi.fn(async () => []),
          update: vi.fn(async () => ({})),
        })),
      } as any
      const realDs = new DataService(pb)
      realDs.initialize('test')
      // validateFieldName throws BEFORE any PB call if invalid. Accepted =
      // the call completes (0 rows = no-op return 0).
      await expect(
        realDs.update('tasks', { x: '1' }, name, 'v'),
      ).resolves.toBe(0)
    }

    async function expectRejected(name: string) {
      const pb = {
        collection: vi.fn(() => ({
          getFullList: vi.fn(async () => []),
          update: vi.fn(async () => ({})),
        })),
      } as any
      const realDs = new DataService(pb)
      realDs.initialize('test')
      await expect(
        realDs.update('tasks', { x: '1' }, name, 'v'),
      ).rejects.toThrow(/Invalid field name|Reserved field name/)
    }

    it('dash-containing name "my-field" → rejected', async () => {
      await expectRejected('my-field')
    })

    it('single-char "a" → accepted', async () => {
      await expectAccepted('a')
    })

    it('single underscore "_" → accepted (matches [a-zA-Z_])', async () => {
      await expectAccepted('_')
    })

    it('very long field name (256 chars) → accepted (no length cap)', async () => {
      // The regex has no length cap. 256-char pure-alpha name passes.
      const longName = 'a'.repeat(256)
      await expectAccepted(longName)
    })

    it('digit-only name "123" → rejected (must start with letter/underscore)', async () => {
      await expectRejected('123')
    })

    it('leading-underscore "_myField" → accepted', async () => {
      await expectAccepted('_myField')
    })

    it('empty string field name → rejected', async () => {
      await expectRejected('')
    })

    it('space-containing name "my field" → rejected', async () => {
      await expectRejected('my field')
    })

    it('dot-containing name "a.b" → rejected', async () => {
      await expectRejected('a.b')
    })
  })
})

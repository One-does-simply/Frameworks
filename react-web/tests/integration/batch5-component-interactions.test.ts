import { describe, it, expect, beforeEach } from 'vitest'
import { useAppStore, RecordCursor } from '../../src/engine/app-store.ts'
import { AuthService } from '../../src/engine/auth-service.ts'
import { parseApp } from '../../src/models/ods-app.ts'
import { FakeDataService } from '../helpers/fake-data-service.ts'
import { resolveAggregates, hasAggregates } from '../../src/engine/aggregate-evaluator.ts'
import { evaluateExpression } from '../../src/engine/expression-evaluator.ts'

// ---------------------------------------------------------------------------
// Test helpers (mirrors batch1/batch2 patterns)
// ---------------------------------------------------------------------------

function mockPb() {
  return {
    authStore: { isValid: false, record: null },
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
            { name: 'price', type: 'number', label: 'Price' },
          ],
        },
      ],
    },
    thanks: { title: 'Thanks', content: [] },
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
          { name: 'price', type: 'number', label: 'Price' },
        ],
      },
    },
    ...Object.fromEntries(
      Object.entries(overrides).filter(([k]) => k !== 'pages' && k !== 'dataSources'),
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

describe('Batch 5: Component interaction tests', () => {
  let ds: FakeDataService
  let authService: AuthService

  beforeEach(() => {
    ds = new FakeDataService()
    ds.initialize('test')
    authService = new AuthService(mockPb())
    resetStore(ds, authService)
  })

  // -------------------------------------------------------------------------
  // B5-1: Form -> List data sync via recordGeneration
  // -------------------------------------------------------------------------

  describe('B5-1: Form -> List data sync', () => {
    it('submit via form bumps recordGeneration', async () => {
      const app = makeApp()
      useAppStore.setState({
        app,
        currentPageId: 'home',
        formStates: { addForm: { title: 'Buy milk', status: 'todo' } },
      })

      const before = useAppStore.getState().recordGeneration

      await useAppStore.getState().executeActions([
        {
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
          computedFields: [],
          preserveFields: [],
        },
      ])

      const after = useAppStore.getState().recordGeneration
      expect(after).toBe(before + 1)

      // List query reflects new row.
      const rows = await ds.query('tasks')
      expect(rows.length).toBe(1)
      expect(rows[0].title).toBe('Buy milk')
    })

    it('delete via store bumps recordGeneration and refreshes list', async () => {
      const app = makeApp()
      ds.seed('tasks', [
        { title: 'A', status: 'todo' },
        { title: 'B', status: 'done' },
      ])
      useAppStore.setState({ app, currentPageId: 'home' })

      const seeded = await ds.query('tasks')
      const idToDelete = String(seeded[0]._id)

      const before = useAppStore.getState().recordGeneration
      await useAppStore.getState().executeDeleteRowAction('tasks', '_id', idToDelete)
      const after = useAppStore.getState().recordGeneration

      expect(after).toBe(before + 1)

      const remaining = await ds.query('tasks')
      expect(remaining.length).toBe(1)
      expect(remaining.find((r) => r._id === idToDelete)).toBeUndefined()
    })

    it('update via action bumps recordGeneration and list shows updated value', async () => {
      const app = makeApp()
      ds.seed('tasks', [{ title: 'Original', status: 'todo' }])
      const seeded = await ds.query('tasks')
      const targetId = String(seeded[0]._id)
      useAppStore.setState({ app, currentPageId: 'home' })

      const before = useAppStore.getState().recordGeneration

      await useAppStore.getState().executeActions([
        {
          action: 'update',
          target: targetId,
          dataSource: 'tasks',
          matchField: '_id',
          withData: { title: 'Updated' },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const after = useAppStore.getState().recordGeneration
      expect(after).toBeGreaterThan(before)

      const rows = await ds.query('tasks')
      expect(rows[0].title).toBe('Updated')
    })

    it('multiple consecutive submits each bump recordGeneration', async () => {
      const app = makeApp()
      useAppStore.setState({
        app,
        currentPageId: 'home',
        formStates: { addForm: { title: 'One' } },
      })

      const start = useAppStore.getState().recordGeneration

      await useAppStore.getState().executeActions([
        { action: 'submit', target: 'addForm', dataSource: 'tasks', computedFields: [], preserveFields: [] },
      ])
      useAppStore.setState({ formStates: { addForm: { title: 'Two' } } })
      await useAppStore.getState().executeActions([
        { action: 'submit', target: 'addForm', dataSource: 'tasks', computedFields: [], preserveFields: [] },
      ])
      useAppStore.setState({ formStates: { addForm: { title: 'Three' } } })
      await useAppStore.getState().executeActions([
        { action: 'submit', target: 'addForm', dataSource: 'tasks', computedFields: [], preserveFields: [] },
      ])

      const end = useAppStore.getState().recordGeneration
      expect(end).toBe(start + 3)

      const rows = await ds.query('tasks')
      expect(rows.length).toBe(3)
    })
  })

  // -------------------------------------------------------------------------
  // B5-2: Parent/child via recordSource (firstRecord / nextRecord / form update)
  // -------------------------------------------------------------------------

  describe('B5-2: Parent/child via recordSource', () => {
    function makeRecordApp() {
      return parseApp({
        appName: 'Test',
        startPage: 'home',
        pages: {
          home: {
            title: 'Home',
            content: [
              {
                component: 'form',
                id: 'editForm',
                recordSource: 'tasks',
                fields: [
                  { name: '_id', type: 'text', label: 'ID' },
                  { name: 'title', type: 'text', label: 'Title' },
                  { name: 'status', type: 'text', label: 'Status' },
                ],
              },
            ],
          },
        },
        dataSources: {
          tasks: {
            url: 'local://tasks',
            method: 'POST',
            fields: [
              { name: 'title', type: 'text', label: 'Title' },
              { name: 'status', type: 'text', label: 'Status' },
            ],
          },
        },
      })
    }

    it('firstRecord populates form with row 1 values', async () => {
      const app = makeRecordApp()
      ds.seed('tasks', [
        { title: 'Alpha', status: 'todo' },
        { title: 'Beta', status: 'done' },
      ])
      useAppStore.setState({ app, currentPageId: 'home' })

      await useAppStore.getState().executeActions([
        { action: 'firstRecord', target: 'editForm', computedFields: [], preserveFields: [] },
      ])

      const form = useAppStore.getState().formStates.editForm
      // FakeDataService.query() returns reversed order => first is Beta.
      expect(form.title).toBe('Beta')
      expect(form.status).toBe('done')
    })

    it('nextRecord navigates through multiple rows', async () => {
      const app = makeRecordApp()
      ds.seed('tasks', [
        { title: 'Alpha', status: 'todo' },
        { title: 'Beta', status: 'todo' },
        { title: 'Gamma', status: 'todo' },
      ])
      useAppStore.setState({ app, currentPageId: 'home' })

      // Reverse-order: first=Gamma, next=Beta, next=Alpha.
      await useAppStore.getState().executeActions([
        { action: 'firstRecord', target: 'editForm', computedFields: [], preserveFields: [] },
      ])
      expect(useAppStore.getState().formStates.editForm.title).toBe('Gamma')

      await useAppStore.getState().executeActions([
        { action: 'nextRecord', target: 'editForm', computedFields: [], preserveFields: [] },
      ])
      expect(useAppStore.getState().formStates.editForm.title).toBe('Beta')

      await useAppStore.getState().executeActions([
        { action: 'nextRecord', target: 'editForm', computedFields: [], preserveFields: [] },
      ])
      expect(useAppStore.getState().formStates.editForm.title).toBe('Alpha')
    })

    it('update via form after navigating updates correct row', async () => {
      const app = makeRecordApp()
      ds.seed('tasks', [
        { title: 'Alpha', status: 'todo' },
        { title: 'Beta', status: 'todo' },
      ])
      useAppStore.setState({ app, currentPageId: 'home' })

      // firstRecord -> Beta (reverse order).
      await useAppStore.getState().executeActions([
        { action: 'firstRecord', target: 'editForm', computedFields: [], preserveFields: [] },
      ])
      const loaded = useAppStore.getState().formStates.editForm
      expect(loaded.title).toBe('Beta')

      // Mutate the form state (like a user typing) and submit update.
      useAppStore.setState({
        formStates: {
          editForm: { ...loaded, status: 'done' },
        },
      })

      await useAppStore.getState().executeActions([
        {
          action: 'update',
          target: 'editForm',
          dataSource: 'tasks',
          matchField: '_id',
          computedFields: [],
          preserveFields: [],
        },
      ])

      // The row originally titled Beta should now have status "done";
      // Alpha should remain "todo".
      const rows = await ds.query('tasks')
      const beta = rows.find((r) => r.title === 'Beta')!
      const alpha = rows.find((r) => r.title === 'Alpha')!
      expect(beta.status).toBe('done')
      expect(alpha.status).toBe('todo')
    })
  })

  // -------------------------------------------------------------------------
  // B5-3: Toggle with autoComplete
  // -------------------------------------------------------------------------

  describe('B5-3: Toggle with autoComplete', () => {
    function makeToggleApp() {
      return parseApp({
        appName: 'Test',
        startPage: 'home',
        pages: { home: { title: 'Home', content: [] } },
        dataSources: {
          lists: {
            url: 'local://lists',
            method: 'POST',
            fields: [
              { name: 'name', type: 'text', label: 'Name' },
              { name: 'status', type: 'text', label: 'Status' },
            ],
          },
          items: {
            url: 'local://items',
            method: 'POST',
            fields: [
              { name: 'title', type: 'text', label: 'Title' },
              { name: 'list', type: 'text', label: 'List' },
              { name: 'done', type: 'text', label: 'Done' },
            ],
          },
        },
      })
    }

    it('simple toggle updates field on a single row', async () => {
      const app = makeToggleApp()
      ds.seed('items', [
        { title: 'A', list: 'groceries', done: 'false' },
      ])
      useAppStore.setState({ app, currentPageId: 'home' })

      const seeded = await ds.query('items')
      const rowId = String(seeded[0]._id)

      await useAppStore.getState().executeToggle({
        dataSourceId: 'items',
        matchField: '_id',
        matchValue: rowId,
        toggleField: 'done',
        currentValue: 'false',
      })

      const rows = await ds.query('items')
      expect(rows[0].done).toBe('true')
    })

    it('toggle bumps recordGeneration so list refreshes', async () => {
      const app = makeToggleApp()
      ds.seed('items', [{ title: 'A', list: 'g', done: 'false' }])
      useAppStore.setState({ app, currentPageId: 'home' })
      const seeded = await ds.query('items')
      const rowId = String(seeded[0]._id)

      const before = useAppStore.getState().recordGeneration
      await useAppStore.getState().executeToggle({
        dataSourceId: 'items',
        matchField: '_id',
        matchValue: rowId,
        toggleField: 'done',
        currentValue: 'false',
      })
      const after = useAppStore.getState().recordGeneration

      expect(after).toBe(before + 1)
    })

    it('toggle child false->true with autoComplete: parent not marked done if a sibling is still false', async () => {
      const app = makeToggleApp()
      ds.seed('lists', [{ name: 'groceries', status: 'active' }])
      ds.seed('items', [
        { title: 'A', list: 'groceries', done: 'false' },
        { title: 'B', list: 'groceries', done: 'false' },
      ])
      useAppStore.setState({ app, currentPageId: 'home' })

      const items = await ds.query('items')
      const firstId = String(items[0]._id)

      await useAppStore.getState().executeToggle({
        dataSourceId: 'items',
        matchField: '_id',
        matchValue: firstId,
        toggleField: 'done',
        currentValue: 'false',
        autoComplete: {
          groupField: 'list',
          groupValue: 'groceries',
          parentDataSource: 'lists',
          parentMatchField: 'name',
          parentValues: { status: 'complete' },
        },
      })

      const lists = await ds.query('lists')
      // Sibling still false -> parent should stay active.
      expect(lists[0].status).toBe('active')
    })

    it('toggling last child true completes parent via autoComplete', async () => {
      const app = makeToggleApp()
      ds.seed('lists', [{ name: 'groceries', status: 'active' }])
      ds.seed('items', [
        { title: 'A', list: 'groceries', done: 'true' },
        { title: 'B', list: 'groceries', done: 'false' },
      ])
      useAppStore.setState({ app, currentPageId: 'home' })

      const items = await ds.query('items')
      // Query returns reversed: items[0] is the LAST seeded, i.e. B (done='false').
      const targetId = String(items.find((r) => r.title === 'B')!._id)

      await useAppStore.getState().executeToggle({
        dataSourceId: 'items',
        matchField: '_id',
        matchValue: targetId,
        toggleField: 'done',
        currentValue: 'false',
        autoComplete: {
          groupField: 'list',
          groupValue: 'groceries',
          parentDataSource: 'lists',
          parentMatchField: 'name',
          parentValues: { status: 'complete' },
        },
      })

      const itemsAfter = await ds.query('items')
      expect(itemsAfter.every((r) => r.done === 'true')).toBe(true)

      const lists = await ds.query('lists')
      expect(lists[0].status).toBe('complete')

      // Store should also set a success message.
      const state = useAppStore.getState()
      expect(state.lastMessage).toMatch(/complete/i)
    })
  })

  // -------------------------------------------------------------------------
  // B5-4: Kanban drag-drop roundtrip (simulated via update action)
  // -------------------------------------------------------------------------

  describe('B5-4: Kanban drag-drop roundtrip', () => {
    it('update with withData: {status: done} updates row status', async () => {
      const app = makeApp()
      ds.seed('tasks', [{ title: 'A', status: 'todo' }])
      const seeded = await ds.query('tasks')
      const rowId = String(seeded[0]._id)
      useAppStore.setState({ app, currentPageId: 'home' })

      await useAppStore.getState().executeActions([
        {
          action: 'update',
          dataSource: 'tasks',
          matchField: '_id',
          target: rowId,
          withData: { status: 'done' },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const rows = await ds.query('tasks')
      expect(rows[0].status).toBe('done')
    })

    it('kanban-style update bumps recordGeneration so list refreshes', async () => {
      const app = makeApp()
      ds.seed('tasks', [{ title: 'A', status: 'todo' }])
      const seeded = await ds.query('tasks')
      const rowId = String(seeded[0]._id)
      useAppStore.setState({ app, currentPageId: 'home' })

      const before = useAppStore.getState().recordGeneration
      await useAppStore.getState().executeActions([
        {
          action: 'update',
          dataSource: 'tasks',
          matchField: '_id',
          target: rowId,
          withData: { status: 'done' },
          computedFields: [],
          preserveFields: [],
        },
      ])
      const after = useAppStore.getState().recordGeneration
      expect(after).toBeGreaterThan(before)
    })

    it('kanban update without cascade does NOT touch unrelated rows', async () => {
      const app = makeApp()
      ds.seed('tasks', [
        { title: 'A', status: 'todo' },
        { title: 'B', status: 'todo' },
        { title: 'C', status: 'in-progress' },
      ])
      const seeded = await ds.query('tasks')
      // Move just one row.
      const target = seeded.find((r) => r.title === 'A')!
      const rowId = String(target._id)
      useAppStore.setState({ app, currentPageId: 'home' })

      await useAppStore.getState().executeActions([
        {
          action: 'update',
          dataSource: 'tasks',
          matchField: '_id',
          target: rowId,
          withData: { status: 'done' },
          // No cascade config — should not cascade.
          computedFields: [],
          preserveFields: [],
        },
      ])

      const rows = await ds.query('tasks')
      const a = rows.find((r) => r.title === 'A')!
      const b = rows.find((r) => r.title === 'B')!
      const c = rows.find((r) => r.title === 'C')!
      expect(a.status).toBe('done')
      expect(b.status).toBe('todo')
      expect(c.status).toBe('in-progress')
    })

    it('kanban drag to same column is harmless (value already set)', async () => {
      const app = makeApp()
      ds.seed('tasks', [{ title: 'A', status: 'done' }])
      const seeded = await ds.query('tasks')
      const rowId = String(seeded[0]._id)
      useAppStore.setState({ app, currentPageId: 'home' })

      await useAppStore.getState().executeActions([
        {
          action: 'update',
          dataSource: 'tasks',
          matchField: '_id',
          target: rowId,
          withData: { status: 'done' },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const rows = await ds.query('tasks')
      expect(rows[0].status).toBe('done')
      expect(useAppStore.getState().lastActionError).toBeNull()
    })
  })

  // -------------------------------------------------------------------------
  // B5-5: Chart aggregation correctness (aggregate-evaluator)
  // -------------------------------------------------------------------------

  describe('B5-5: Chart aggregation correctness', () => {
    async function resolve(expr: string, rowsById: Record<string, Record<string, unknown>[]>) {
      const queryFn = async (id: string) => rowsById[id] ?? []
      return resolveAggregates(expr, queryFn)
    }

    it('COUNT returns row count', async () => {
      const r = await resolve('{COUNT(tasks)}', {
        tasks: [{ title: 'A' }, { title: 'B' }, { title: 'C' }],
      })
      expect(r).toBe('3')
    })

    it('SUM sums a numeric field', async () => {
      const r = await resolve('{SUM(tasks, price)}', {
        tasks: [{ price: 10 }, { price: 20 }, { price: 30 }],
      })
      expect(r).toBe('60')
    })

    it('AVG averages a numeric field', async () => {
      const r = await resolve('{AVG(tasks, price)}', {
        tasks: [{ price: 10 }, { price: 20 }, { price: 30 }],
      })
      expect(r).toBe('20')
    })

    it('MIN returns smallest numeric value', async () => {
      const r = await resolve('{MIN(tasks, price)}', {
        tasks: [{ price: 25 }, { price: 3 }, { price: 10 }],
      })
      expect(r).toBe('3')
    })

    it('MAX returns largest numeric value', async () => {
      const r = await resolve('{MAX(tasks, price)}', {
        tasks: [{ price: 25 }, { price: 3 }, { price: 10 }],
      })
      expect(r).toBe('25')
    })

    it('COUNT on empty data set returns 0', async () => {
      const r = await resolve('{COUNT(tasks)}', { tasks: [] })
      expect(r).toBe('0')
    })

    it('SUM on empty data set returns 0', async () => {
      const r = await resolve('{SUM(tasks, price)}', { tasks: [] })
      expect(r).toBe('0')
    })

    it('AVG on empty data set returns 0 (not NaN or crash)', async () => {
      const r = await resolve('{AVG(tasks, price)}', { tasks: [] })
      expect(r).toBe('0')
    })

    it('MIN on empty data set returns 0', async () => {
      const r = await resolve('{MIN(tasks, price)}', { tasks: [] })
      expect(r).toBe('0')
    })

    it('MAX on empty data set returns 0', async () => {
      const r = await resolve('{MAX(tasks, price)}', { tasks: [] })
      expect(r).toBe('0')
    })

    it('SUM ignores non-numeric values and sums only numerics', async () => {
      const r = await resolve('{SUM(tasks, price)}', {
        tasks: [
          { price: 10 },
          { price: 'banana' },
          { price: 20 },
          { price: null },
          { price: '' },
        ],
      })
      expect(r).toBe('30')
    })

    it('AVG with all non-numeric values returns 0', async () => {
      const r = await resolve('{AVG(tasks, price)}', {
        tasks: [{ price: 'a' }, { price: 'b' }],
      })
      expect(r).toBe('0')
    })

    it('AVG with mix of numeric and non-numeric averages only numerics', async () => {
      const r = await resolve('{AVG(tasks, price)}', {
        tasks: [{ price: 10 }, { price: 'banana' }, { price: 30 }],
      })
      // Average of 10 and 30 = 20.
      expect(r).toBe('20')
    })
  })

  // -------------------------------------------------------------------------
  // B5-6: Summary value expression evaluation
  // -------------------------------------------------------------------------

  describe('B5-6: Summary value expression evaluation', () => {
    async function resolve(expr: string, rowsById: Record<string, Record<string, unknown>[]>) {
      const queryFn = async (id: string) => rowsById[id] ?? []
      return resolveAggregates(expr, queryFn)
    }

    it('hasAggregates detects aggregate references', () => {
      expect(hasAggregates('{COUNT(tasks)}')).toBe(true)
      expect(hasAggregates('Total: {SUM(tasks, price)}')).toBe(true)
      expect(hasAggregates('plain text')).toBe(false)
      expect(hasAggregates('{fieldRef}')).toBe(false)
    })

    it('COUNT(tasks) inside a sentence resolves correctly', async () => {
      const r = await resolve('You have {COUNT(tasks)} tasks.', {
        tasks: [{ t: 1 }, { t: 2 }],
      })
      expect(r).toBe('You have 2 tasks.')
    })

    it('SUM(tasks.price) evaluates to correct total (comma form used by evaluator)', async () => {
      // Evaluator uses `{SUM(ds, field)}` syntax. We verify correctness using
      // the comma form — the dot form is not the canonical syntax.
      const r = await resolve('Total: {SUM(tasks, price)}', {
        tasks: [{ price: 5 }, { price: 15 }],
      })
      expect(r).toBe('Total: 20')
    })

    it('AVG(tasks.price) -> canonical {AVG(tasks, price)} evaluates correctly', async () => {
      const r = await resolve('Avg: {AVG(tasks, price)}', {
        tasks: [{ price: 10 }, { price: 20 }, { price: 30 }],
      })
      expect(r).toBe('Avg: 20')
    })

    it('aggregate on empty data source returns 0', async () => {
      const r = await resolve('Count: {COUNT(tasks)}', { tasks: [] })
      expect(r).toBe('Count: 0')
    })

    it('aggregate on non-existent data source does not throw', async () => {
      // queryFn returns [] for unknown id — evaluator should handle gracefully.
      const r = await resolve('Count: {COUNT(unknownDs)}', {})
      expect(r).toBe('Count: 0')
    })

    it('single field interpolation: evaluateExpression substitutes {field}', () => {
      const r = evaluateExpression('Hello {name}', { name: 'World' })
      expect(r).toBe('Hello World')
    })

    it('math expression: {a} + {b} evaluates to sum', () => {
      const r = evaluateExpression('{a} + {b}', { a: '2', b: '3' })
      expect(r).toBe('5')
    })

    it('math expression with parentheses: ({a} + {b}) * {c}', () => {
      const r = evaluateExpression('({a} + {b}) * {c}', { a: '1', b: '2', c: '4' })
      expect(r).toBe('12')
    })

    it('mixing literal text and field: "Hi {name}!" produces concatenation', () => {
      const r = evaluateExpression('Hi {name}!', { name: 'Bob' })
      expect(r).toBe('Hi Bob!')
    })

    it('multiple aggregates in one string resolve independently', async () => {
      const r = await resolve(
        'Total: {SUM(tasks, price)} across {COUNT(tasks)} items',
        { tasks: [{ price: 10 }, { price: 20 }] },
      )
      expect(r).toBe('Total: 30 across 2 items')
    })
  })
})

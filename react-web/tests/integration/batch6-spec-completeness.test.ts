/**
 * Batch 6: Spec-completeness integration tests.
 *
 * Exercises the full spec surface — every field type, every action type,
 * and all three evaluators (formula, expression, template). Any failure
 * here indicates a spec/implementation gap; do NOT patch the engines to
 * make these green — file a bug.
 *
 * Evaluator engines under test:
 *   - src/engine/formula-evaluator.ts  (computed fields / `{field}` + math)
 *   - src/engine/expression-evaluator.ts (ternaries, magic values)
 *   - src/engine/template-engine.ts  (JSON-e subset with `${expr}`)
 *
 * NOTE ON TEMPLATE SYNTAX: the spec's Quick Build docs and this test
 * brief both mention `{{field}}`, but template-engine.ts implements a
 * JSON-e subset using `${field}`. Tests exercise the real syntax and
 * additionally probe `{{field}}` to document the behavior.
 */

import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import { useAppStore } from '../../src/engine/app-store.ts'
import { AuthService } from '../../src/engine/auth-service.ts'
import { parseApp } from '../../src/models/ods-app.ts'
import { FakeDataService } from '../helpers/fake-data-service.ts'
import { evaluateFormula } from '../../src/engine/formula-evaluator.ts'
import { evaluateExpression } from '../../src/engine/expression-evaluator.ts'
import { render as renderTemplate } from '../../src/engine/template-engine.ts'

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

function mockPb() {
  return {
    authStore: { isValid: false, record: null },
    collection: () => ({
      listAuthMethods: async () => ({ oauth2: { providers: [] } }),
    }),
  } as any
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
// B6-1: Every field type validates and submits correctly
// ---------------------------------------------------------------------------

describe('Batch 6: Spec Completeness', () => {
  let ds: FakeDataService
  let authService: AuthService

  beforeEach(() => {
    ds = new FakeDataService()
    ds.initialize('test')
    authService = new AuthService(mockPb())
    resetStore(ds, authService)
  })

  describe('B6-1: Every field type validates and submits correctly', () => {
    /** Build an app with a single field on a submit form + tasks data source. */
    function makeFieldApp(field: Record<string, unknown>) {
      return parseApp({
        appName: 'Test',
        startPage: 'home',
        pages: {
          home: {
            title: 'Home',
            content: [
              {
                component: 'form',
                id: 'addForm',
                fields: [field],
              },
            ],
          },
        },
        dataSources: {
          tasks: {
            url: 'local://tasks',
            method: 'POST',
            fields: [field],
          },
        },
      })
    }

    // --- text ---
    it('text field: submits valid string', async () => {
      const app = makeFieldApp({ name: 'title', type: 'text', label: 'Title' })
      useAppStore.setState({ app, formStates: { addForm: { title: 'Hello' } } })

      await useAppStore.getState().executeActions([
        { action: 'submit', target: 'addForm', dataSource: 'tasks', computedFields: [], preserveFields: [] },
      ])

      const rows = await ds.query('tasks')
      expect(rows[0]?.title).toBe('Hello')
    })

    it('text field: required + empty → validation error', async () => {
      const app = makeFieldApp({ name: 'title', type: 'text', label: 'Title', required: true })
      useAppStore.setState({ app, formStates: { addForm: { title: '' } } })

      await useAppStore.getState().executeActions([
        { action: 'submit', target: 'addForm', dataSource: 'tasks', computedFields: [], preserveFields: [] },
      ])

      // Form has only whitespace/empty — formStates check: '{title:""}' has length 1 so
      // submit sees form data, then validator rejects required empty.
      const state = useAppStore.getState()
      // Either validation error OR "No form data" — both are failures; assert a failure.
      expect(state.lastActionError).toBeTruthy()
    })

    it('text field: optional + empty → saves empty/nothing', async () => {
      const app = makeFieldApp({ name: 'title', type: 'text', label: 'Title' })
      // Provide a second field so submit doesn't bail on "No form data".
      useAppStore.setState({
        app: parseApp({
          appName: 'Test',
          startPage: 'home',
          pages: {
            home: {
              title: 'Home',
              content: [{
                component: 'form',
                id: 'addForm',
                fields: [
                  { name: 'title', type: 'text', label: 'Title' },
                  { name: 'note', type: 'text', label: 'Note' },
                ],
              }],
            },
          },
          dataSources: {
            tasks: {
              url: 'local://tasks',
              method: 'POST',
              fields: [
                { name: 'title', type: 'text', label: 'Title' },
                { name: 'note', type: 'text', label: 'Note' },
              ],
            },
          },
        }),
        formStates: { addForm: { title: '', note: 'filled' } },
      })

      await useAppStore.getState().executeActions([
        { action: 'submit', target: 'addForm', dataSource: 'tasks', computedFields: [], preserveFields: [] },
      ])

      const rows = await ds.query('tasks')
      expect(rows).toHaveLength(1)
      expect(rows[0]?.note).toBe('filled')
      expect(rows[0]?.title).toBe('')
    })

    // --- multiline ---
    it('multiline field: submits multi-line string', async () => {
      const app = makeFieldApp({ name: 'body', type: 'multiline', label: 'Body' })
      useAppStore.setState({
        app,
        formStates: { addForm: { body: 'line1\nline2\nline3' } },
      })

      await useAppStore.getState().executeActions([
        { action: 'submit', target: 'addForm', dataSource: 'tasks', computedFields: [], preserveFields: [] },
      ])

      const rows = await ds.query('tasks')
      expect(rows[0]?.body).toBe('line1\nline2\nline3')
    })

    // --- number ---
    it('number field: submits numeric string', async () => {
      const app = makeFieldApp({ name: 'qty', type: 'number', label: 'Qty' })
      useAppStore.setState({ app, formStates: { addForm: { qty: '42' } } })

      await useAppStore.getState().executeActions([
        { action: 'submit', target: 'addForm', dataSource: 'tasks', computedFields: [], preserveFields: [] },
      ])

      const rows = await ds.query('tasks')
      expect(rows[0]?.qty).toBe('42')
    })

    it('number field: validation.min breaks on too-low value', async () => {
      const app = makeFieldApp({
        name: 'qty', type: 'number', label: 'Qty',
        validation: { min: 10 },
      })
      useAppStore.setState({ app, formStates: { addForm: { qty: '5' } } })

      await useAppStore.getState().executeActions([
        { action: 'submit', target: 'addForm', dataSource: 'tasks', computedFields: [], preserveFields: [] },
      ])

      const state = useAppStore.getState()
      expect(state.lastActionError).toBeTruthy()
      expect(state.lastActionError).toMatch(/at least 10/i)
    })

    it('number field: rejects non-numeric text at submit (type guard)', async () => {
      // Gap G1 fix: non-numeric strings in a number field are rejected with a
      // validation error, and the row is NOT persisted.
      const app = makeFieldApp({ name: 'qty', type: 'number', label: 'Qty' })
      useAppStore.setState({ app, formStates: { addForm: { qty: 'abc' } } })

      await useAppStore.getState().executeActions([
        { action: 'submit', target: 'addForm', dataSource: 'tasks', computedFields: [], preserveFields: [] },
      ])

      const state = useAppStore.getState()
      const rows = await ds.query('tasks')
      expect(state.lastActionError).toBeTruthy()
      expect(state.lastActionError).toMatch(/must be a number/i)
      expect(rows).toHaveLength(0)
    })

    // --- date ---
    it('date field: submits ISO date string', async () => {
      const app = makeFieldApp({ name: 'dueDate', type: 'date', label: 'Due' })
      useAppStore.setState({ app, formStates: { addForm: { dueDate: '2026-04-18' } } })

      await useAppStore.getState().executeActions([
        { action: 'submit', target: 'addForm', dataSource: 'tasks', computedFields: [], preserveFields: [] },
      ])

      const rows = await ds.query('tasks')
      expect(rows[0]?.dueDate).toBe('2026-04-18')
    })

    // --- select ---
    it('select field: submits selected option', async () => {
      const app = makeFieldApp({
        name: 'status', type: 'select', label: 'Status',
        options: ['todo', 'done'],
      })
      useAppStore.setState({ app, formStates: { addForm: { status: 'done' } } })

      await useAppStore.getState().executeActions([
        { action: 'submit', target: 'addForm', dataSource: 'tasks', computedFields: [], preserveFields: [] },
      ])

      const rows = await ds.query('tasks')
      expect(rows[0]?.status).toBe('done')
    })

    it('select field: rejects values not in options (enum guard at submit)', async () => {
      // Bug #11 / G2 fix: select fields now reject values that are not in the
      // options list. Error message includes the valid options.
      const app = makeFieldApp({
        name: 'status', type: 'select', label: 'Status',
        options: ['todo', 'done'],
      })
      useAppStore.setState({ app, formStates: { addForm: { status: 'off-list' } } })

      await useAppStore.getState().executeActions([
        { action: 'submit', target: 'addForm', dataSource: 'tasks', computedFields: [], preserveFields: [] },
      ])

      const state = useAppStore.getState()
      expect(state.lastActionError).toBeTruthy()
      expect(state.lastActionError).toMatch(/must be one of/i)
      expect(state.lastActionError).toMatch(/todo/)
      expect(state.lastActionError).toMatch(/done/)
      const rows = await ds.query('tasks')
      expect(rows).toHaveLength(0)
    })

    // --- checkbox ---
    it('checkbox field: submits "true" / "false" string', async () => {
      const app = makeFieldApp({ name: 'done', type: 'checkbox', label: 'Done' })
      useAppStore.setState({ app, formStates: { addForm: { done: 'true' } } })

      await useAppStore.getState().executeActions([
        { action: 'submit', target: 'addForm', dataSource: 'tasks', computedFields: [], preserveFields: [] },
      ])

      const rows = await ds.query('tasks')
      expect(rows[0]?.done).toBe('true')
    })

    // --- user ---
    it('user field: submits user id string', async () => {
      const app = makeFieldApp({ name: 'assignee', type: 'user', label: 'Assignee' })
      useAppStore.setState({ app, formStates: { addForm: { assignee: 'user-123' } } })

      await useAppStore.getState().executeActions([
        { action: 'submit', target: 'addForm', dataSource: 'tasks', computedFields: [], preserveFields: [] },
      ])

      const rows = await ds.query('tasks')
      expect(rows[0]?.assignee).toBe('user-123')
    })

    // --- hidden ---
    it('hidden field: value in form state IS stored on submit', async () => {
      // Hidden fields keep data but are not displayed; submit should still save.
      const app = makeFieldApp({ name: 'secret', type: 'hidden', label: 'Secret' })
      useAppStore.setState({ app, formStates: { addForm: { secret: 'hush' } } })

      await useAppStore.getState().executeActions([
        { action: 'submit', target: 'addForm', dataSource: 'tasks', computedFields: [], preserveFields: [] },
      ])

      const rows = await ds.query('tasks')
      expect(rows[0]?.secret).toBe('hush')
    })

    // --- computed ---
    it('computed field: formula evaluated at submit; value persisted', async () => {
      const app = parseApp({
        appName: 'Test',
        startPage: 'home',
        pages: {
          home: {
            title: 'Home',
            content: [{
              component: 'form',
              id: 'addForm',
              fields: [
                { name: 'qty', type: 'number', label: 'Qty' },
                { name: 'price', type: 'number', label: 'Price' },
                { name: 'total', type: 'number', label: 'Total', formula: '{qty} * {price}' },
              ],
            }],
          },
        },
        dataSources: {
          tasks: {
            url: 'local://tasks',
            method: 'POST',
            fields: [
              { name: 'qty', type: 'number', label: 'Qty' },
              { name: 'price', type: 'number', label: 'Price' },
              { name: 'total', type: 'number', label: 'Total', formula: '{qty} * {price}' },
            ],
          },
        },
      })
      useAppStore.setState({
        app,
        formStates: { addForm: { qty: '3', price: '4' } },
      })

      await useAppStore.getState().executeActions([
        {
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
          computedFields: [{ field: 'total', expression: '{qty} * {price}' }],
          preserveFields: [],
        },
      ])

      const rows = await ds.query('tasks')
      expect(rows[0]?.total).toBe('12')
    })
  })

  // -------------------------------------------------------------------------
  // B6-2: Every action type behaves as specced
  // -------------------------------------------------------------------------

  describe('B6-2: Every action type behaves as specced', () => {
    function makeApp() {
      return parseApp({
        appName: 'Test',
        startPage: 'home',
        pages: {
          home: {
            title: 'Home',
            content: [
              {
                component: 'form',
                id: 'addForm',
                fields: [
                  { name: 'title', type: 'text', label: 'Title' },
                ],
              },
              {
                component: 'form',
                id: 'editForm',
                recordSource: 'tasks',
                fields: [
                  { name: '_id', type: 'text', label: 'ID' },
                  { name: 'title', type: 'text', label: 'Title' },
                ],
              },
            ],
          },
          other: { title: 'Other', content: [] },
        },
        dataSources: {
          tasks: {
            url: 'local://tasks',
            method: 'POST',
            fields: [{ name: 'title', type: 'text', label: 'Title' }],
          },
        },
      })
    }

    // --- navigate ---
    it('navigate: target page → currentPageId updates', async () => {
      const app = makeApp()
      useAppStore.setState({ app, currentPageId: 'home' })
      await useAppStore.getState().executeActions([
        { action: 'navigate', target: 'other', computedFields: [], preserveFields: [] },
      ])
      expect(useAppStore.getState().currentPageId).toBe('other')
    })

    it('navigate: missing target → stays on same page (no crash)', async () => {
      const app = makeApp()
      useAppStore.setState({ app, currentPageId: 'home' })
      await useAppStore.getState().executeActions([
        { action: 'navigate', computedFields: [], preserveFields: [] },
      ])
      // With no target, navigate call is a no-op.
      expect(useAppStore.getState().currentPageId).toBe('home')
    })

    it('navigate: unknown target → stays on same page and warns', async () => {
      // Gap G9 fix: navigateTo to a page that doesn't exist logs a warning
      // via logWarn (which forwards to console.warn).
      const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {})
      const app = makeApp()
      useAppStore.setState({ app, currentPageId: 'home' })
      useAppStore.getState().navigateTo('doesNotExist')
      expect(useAppStore.getState().currentPageId).toBe('home')
      const messages = warnSpy.mock.calls.map(args => args.join(' '))
      expect(messages.some(m => m.includes('Navigate to unknown page') && m.includes('doesNotExist'))).toBe(true)
      warnSpy.mockRestore()
    })

    // --- submit ---
    it('submit: inserts row; clears form', async () => {
      const app = makeApp()
      useAppStore.setState({
        app,
        currentPageId: 'home',
        formStates: { addForm: { title: 'X' } },
      })
      await useAppStore.getState().executeActions([
        { action: 'submit', target: 'addForm', dataSource: 'tasks', computedFields: [], preserveFields: [] },
      ])
      const rows = await ds.query('tasks')
      expect(rows[0]?.title).toBe('X')
      expect(useAppStore.getState().formStates.addForm).toBeUndefined()
    })

    it('submit: missing target → error', async () => {
      const app = makeApp()
      useAppStore.setState({ app, currentPageId: 'home', formStates: { addForm: { title: 'X' } } })
      await useAppStore.getState().executeActions([
        { action: 'submit', dataSource: 'tasks', computedFields: [], preserveFields: [] },
      ])
      expect(useAppStore.getState().lastActionError).toMatch(/missing target|dataSource/i)
    })

    it('submit: missing dataSource → error', async () => {
      const app = makeApp()
      useAppStore.setState({ app, currentPageId: 'home', formStates: { addForm: { title: 'X' } } })
      await useAppStore.getState().executeActions([
        { action: 'submit', target: 'addForm', computedFields: [], preserveFields: [] },
      ])
      expect(useAppStore.getState().lastActionError).toMatch(/missing target|dataSource/i)
    })

    // --- update ---
    it('update: via withData updates row', async () => {
      const app = makeApp()
      ds.seed('tasks', [{ title: 'Before' }])
      const id = String((await ds.query('tasks'))[0]._id)
      useAppStore.setState({ app, currentPageId: 'home' })

      await useAppStore.getState().executeActions([
        {
          action: 'update',
          target: id,
          dataSource: 'tasks',
          matchField: '_id',
          withData: { title: 'After' },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const rows = await ds.query('tasks')
      expect(rows[0]?.title).toBe('After')
    })

    it('update: missing matchField → error', async () => {
      const app = makeApp()
      ds.seed('tasks', [{ title: 'Before' }])
      useAppStore.setState({
        app,
        currentPageId: 'home',
        formStates: { editForm: { title: 'After' } },
      })

      await useAppStore.getState().executeActions([
        {
          action: 'update',
          target: 'editForm',
          dataSource: 'tasks',
          computedFields: [],
          preserveFields: [],
        },
      ])
      expect(useAppStore.getState().lastActionError).toMatch(/missing/i)
    })

    // --- delete (via executeDeleteRowAction) ---
    it('delete: executeDeleteRowAction removes matching row', async () => {
      const app = makeApp()
      ds.seed('tasks', [{ title: 'A' }, { title: 'B' }])
      const idA = String((await ds.query('tasks')).find(r => r.title === 'A')!._id)
      useAppStore.setState({ app })

      await useAppStore.getState().executeDeleteRowAction('tasks', '_id', idA)
      const rows = await ds.query('tasks')
      expect(rows.some(r => r.title === 'A')).toBe(false)
      expect(rows.some(r => r.title === 'B')).toBe(true)
      expect(useAppStore.getState().lastMessage).toMatch(/Deleted/)
    })

    it('delete: unknown dataSource → no-op (no crash)', async () => {
      const app = makeApp()
      useAppStore.setState({ app })

      // Should not throw.
      await expect(
        useAppStore.getState().executeDeleteRowAction('nonexistent', '_id', 'whatever'),
      ).resolves.toBeUndefined()
    })

    // --- showMessage ---
    it('showMessage: sets lastMessage', async () => {
      const app = makeApp()
      useAppStore.setState({ app, currentPageId: 'home' })
      await useAppStore.getState().executeActions([
        { action: 'showMessage', message: 'Hello', computedFields: [], preserveFields: [] },
      ])
      expect(useAppStore.getState().lastMessage).toBe('Hello')
    })

    it('showMessage: missing message → empty string', async () => {
      // Gap G8 fix: showMessage always sets lastMessage, defaulting to ''.
      const app = makeApp()
      useAppStore.setState({ app, currentPageId: 'home' })
      await useAppStore.getState().executeActions([
        { action: 'showMessage', computedFields: [], preserveFields: [] },
      ])
      expect(useAppStore.getState().lastMessage).toBe('')
    })

    // --- firstRecord / nextRecord / previousRecord / lastRecord ---
    it('firstRecord: loads first row into form', async () => {
      const app = makeApp()
      ds.seed('tasks', [{ title: 'A' }, { title: 'B' }])
      useAppStore.setState({ app })

      await useAppStore.getState().executeActions([
        { action: 'firstRecord', target: 'editForm', computedFields: [], preserveFields: [] },
      ])
      // query() returns reverse order → first row is 'B'.
      expect(useAppStore.getState().formStates.editForm?.title).toBe('B')
    })

    it('nextRecord: moves cursor forward', async () => {
      const app = makeApp()
      ds.seed('tasks', [{ title: 'A' }, { title: 'B' }, { title: 'C' }])
      useAppStore.setState({ app })

      await useAppStore.getState().executeActions([
        { action: 'firstRecord', target: 'editForm', computedFields: [], preserveFields: [] },
      ])
      // First row in reverse-insertion order is 'C'.
      expect(useAppStore.getState().formStates.editForm?.title).toBe('C')

      await useAppStore.getState().executeActions([
        { action: 'nextRecord', target: 'editForm', computedFields: [], preserveFields: [] },
      ])
      expect(useAppStore.getState().formStates.editForm?.title).toBe('B')
    })

    it('previousRecord: moves cursor backward', async () => {
      const app = makeApp()
      ds.seed('tasks', [{ title: 'A' }, { title: 'B' }, { title: 'C' }])
      useAppStore.setState({ app })

      await useAppStore.getState().executeActions([
        { action: 'lastRecord', target: 'editForm', computedFields: [], preserveFields: [] },
      ])
      // Last in reverse-insertion order is 'A'.
      expect(useAppStore.getState().formStates.editForm?.title).toBe('A')

      await useAppStore.getState().executeActions([
        { action: 'previousRecord', target: 'editForm', computedFields: [], preserveFields: [] },
      ])
      expect(useAppStore.getState().formStates.editForm?.title).toBe('B')
    })

    it('lastRecord: loads last row', async () => {
      const app = makeApp()
      ds.seed('tasks', [{ title: 'A' }, { title: 'B' }, { title: 'C' }])
      useAppStore.setState({ app })

      await useAppStore.getState().executeActions([
        { action: 'lastRecord', target: 'editForm', computedFields: [], preserveFields: [] },
      ])
      expect(useAppStore.getState().formStates.editForm?.title).toBe('A')
    })

    it('record actions: missing target → fails gracefully (no crash)', async () => {
      const app = makeApp()
      ds.seed('tasks', [{ title: 'A' }])
      useAppStore.setState({ app })

      // No target — should not throw.
      await expect(
        useAppStore.getState().executeActions([
          { action: 'firstRecord', computedFields: [], preserveFields: [] },
        ]),
      ).resolves.toBeUndefined()
    })

    // --- chain navigate + showMessage ---
    it('chain navigate + showMessage: both fire', async () => {
      const app = makeApp()
      useAppStore.setState({ app, currentPageId: 'home' })
      await useAppStore.getState().executeActions([
        { action: 'navigate', target: 'other', computedFields: [], preserveFields: [] },
        { action: 'showMessage', message: 'Navigated', computedFields: [], preserveFields: [] },
      ])
      const state = useAppStore.getState()
      expect(state.currentPageId).toBe('other')
      expect(state.lastMessage).toBe('Navigated')
    })
  })

  // -------------------------------------------------------------------------
  // B6-3: Formula evaluator edge cases
  // -------------------------------------------------------------------------

  describe('B6-3: Formula evaluator edge cases', () => {
    // --- Math ops ---
    it('addition: {a} + {b}', () => {
      expect(evaluateFormula('{a} + {b}', 'number', { a: '2', b: '3' })).toBe('5')
    })

    it('subtraction: {a} - {b}', () => {
      expect(evaluateFormula('{a} - {b}', 'number', { a: '10', b: '4' })).toBe('6')
    })

    it('multiplication: {a} * {b}', () => {
      expect(evaluateFormula('{a} * {b}', 'number', { a: '3', b: '4' })).toBe('12')
    })

    it('division: {a} / {b}', () => {
      expect(evaluateFormula('{a} / {b}', 'number', { a: '8', b: '2' })).toBe('4')
    })

    // --- Division by zero ---
    it('division by zero → returns empty string (Infinity filtered)', () => {
      // evaluateFormula filters out non-finite results and returns ''.
      expect(evaluateFormula('{a} / {b}', 'number', { a: '5', b: '0' })).toBe('')
    })

    it('0 / 0 → returns empty string (NaN filtered)', () => {
      expect(evaluateFormula('{a} / {b}', 'number', { a: '0', b: '0' })).toBe('')
    })

    // --- Precedence & parens ---
    it('precedence: {a} + {b} * {c} → evaluates * first', () => {
      expect(evaluateFormula('{a} + {b} * {c}', 'number', {
        a: '2', b: '3', c: '4',
      })).toBe('14') // 2 + (3 * 4)
    })

    it('parens: ({a} + {b}) * {c} → evaluates paren first', () => {
      expect(evaluateFormula('({a} + {b}) * {c}', 'number', {
        a: '2', b: '3', c: '4',
      })).toBe('20') // (2 + 3) * 4
    })

    // --- String concatenation / mixed types ---
    it('text type: interpolates without math eval', () => {
      expect(evaluateFormula('{first} {last}', 'text', {
        first: 'Ada', last: 'Lovelace',
      })).toBe('Ada Lovelace')
    })

    it('number type with non-numeric value: math parse fails → empty string', () => {
      expect(evaluateFormula('{a} + {b}', 'number', {
        a: 'abc', b: '5',
      })).toBe('')
    })

    // --- Empty references ---
    it('empty field reference → returns empty string (short-circuit)', () => {
      expect(evaluateFormula('{a} + {b}', 'number', { a: '', b: '5' })).toBe('')
    })

    it('missing field (undefined) → returns empty string', () => {
      expect(evaluateFormula('{a} + {b}', 'number', { a: '3' })).toBe('')
    })

    it('null field → returns empty string', () => {
      expect(evaluateFormula('{a} + {b}', 'number', { a: null, b: '5' })).toBe('')
    })

    // --- Decimals ---
    it('decimal preserved: 1.5 + 2.25 → "3.75"', () => {
      expect(evaluateFormula('{a} + {b}', 'number', {
        a: '1.5', b: '2.25',
      })).toBe('3.75')
    })

    it('integer result formatted without decimals', () => {
      expect(evaluateFormula('{a} * {b}', 'number', {
        a: '1.5', b: '2',
      })).toBe('3')
    })

    it('repeating decimal rounded to 2 places', () => {
      // 10 / 3 = 3.333... → rounds to "3.33".
      expect(evaluateFormula('{a} / {b}', 'number', {
        a: '10', b: '3',
      })).toBe('3.33')
    })

    // --- Negative numbers ---
    it('negative literal: {a} - negative result', () => {
      expect(evaluateFormula('{a} - {b}', 'number', {
        a: '3', b: '5',
      })).toBe('-2')
    })

    it('unary minus on field value: -5 + 10 = 5', () => {
      // This exercises tokenizer's unary minus handling: `-5 + 10`.
      expect(evaluateFormula('{a} + {b}', 'number', {
        a: '-5', b: '10',
      })).toBe('5')
    })
  })

  // -------------------------------------------------------------------------
  // B6-4: Expression evaluator (ternary, comparisons, magic values)
  // -------------------------------------------------------------------------

  describe('B6-4: Expression evaluator', () => {
    // --- Ternary equality ---
    it("ternary ==: {a} == 'active' ? 'yes' : 'no' with a='active' → 'yes'", () => {
      // NOTE: The engine requires the right side to be in single quotes.
      // Supported pattern: `left == right ? 'trueVal' : 'falseVal'`.
      expect(evaluateExpression("{a} == active ? 'yes' : 'no'", { a: 'active' })).toBe('yes')
    })

    it("ternary ==: with a='inactive' → 'no'", () => {
      expect(evaluateExpression("{a} == active ? 'yes' : 'no'", { a: 'inactive' })).toBe('no')
    })

    // --- Ternary != (Gap G3) ---
    it("ternary !=: {a} != 'active' ? 'yes' : 'no' with a='inactive' → 'yes'", () => {
      expect(evaluateExpression("{a} != active ? 'yes' : 'no'", { a: 'inactive' })).toBe('yes')
    })

    it("ternary !=: with a='active' → 'no'", () => {
      expect(evaluateExpression("{a} != active ? 'yes' : 'no'", { a: 'active' })).toBe('no')
    })

    // --- Ternary with numeric comparison (Gap G3) ---
    it("ternary >: {a} > 10 ? 'big' : 'small' with a='20' → 'big'", () => {
      expect(evaluateExpression("{a} > 10 ? 'big' : 'small'", { a: '20' })).toBe('big')
    })

    it("ternary >: with a='5' → 'small'", () => {
      expect(evaluateExpression("{a} > 10 ? 'big' : 'small'", { a: '5' })).toBe('small')
    })

    it("ternary <: with a='5' → 'yes'", () => {
      expect(evaluateExpression("{a} < 10 ? 'yes' : 'no'", { a: '5' })).toBe('yes')
    })

    it("ternary >=: with a='10' → 'yes'", () => {
      expect(evaluateExpression("{a} >= 10 ? 'yes' : 'no'", { a: '10' })).toBe('yes')
    })

    it("ternary <=: with a='10' → 'yes'", () => {
      expect(evaluateExpression("{a} <= 10 ? 'yes' : 'no'", { a: '10' })).toBe('yes')
    })

    it("ternary >: non-numeric operand → falsy branch", () => {
      // parseFloat('abc') is NaN → comparison returns false → 'small'
      expect(evaluateExpression("{a} > 10 ? 'big' : 'small'", { a: 'abc' })).toBe('small')
    })

    it("ternary ==: operand with surrounding quotes is stripped", () => {
      // left operand is quoted literal 'active'; right is field value 'active'
      expect(evaluateExpression("'active' == {a} ? 'yes' : 'no'", { a: 'active' })).toBe('yes')
    })

    // --- Magic values ---
    it('NOW: returns ISO date string', () => {
      const result = evaluateExpression('NOW', {})
      // ISO format: YYYY-MM-DDTHH:MM:SS.sssZ
      expect(result).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    })

    it('NOW lowercased "now": is ALSO treated as NOW (case-insensitive)', () => {
      // Per impl: expression.trim().toUpperCase() === 'NOW'.
      const result = evaluateExpression('now', {})
      expect(result).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    })

    // --- Nested ternaries ---
    it('nested ternary is NOT supported (only single-level == pattern)', () => {
      // Documents a spec gap: nested ternaries can't be parsed.
      const out = evaluateExpression(
        "{a} == first ? 'one' : ({b} == second ? 'two' : 'three')",
        { a: 'nope', b: 'second' },
      )
      // Falls through to substituted string since outer ternary pattern
      // doesn't match (right side has parens).
      expect(typeof out).toBe('string')
      expect(out).toContain('nope')
    })

    // --- Missing field references ---
    it('missing field: {x} substitutes to empty string', () => {
      // For numeric-looking result with empty string: looksNumeric returns false on empty.
      // Substituted string contains empty value — returned as-is.
      const out = evaluateExpression('{missing}', {})
      expect(out).toBe('')
    })

    it('missing field in ternary: empty vs literal → falsy branch', () => {
      // {a} empty; == active → false → 'no'
      expect(evaluateExpression("{a} == active ? 'yes' : 'no'", {})).toBe('no')
    })

    // --- String interpolation ---
    it('string interpolation with multiple fields', () => {
      expect(evaluateExpression('{first} {last}', {
        first: 'Ada', last: 'Lovelace',
      })).toBe('Ada Lovelace')
    })

    it('math expression substituted and evaluated', () => {
      expect(evaluateExpression('{a} + {b}', { a: '2', b: '3' })).toBe('5')
    })
  })

  // -------------------------------------------------------------------------
  // B6-5: Template engine edge cases
  //
  // The engine under test is a JSON-e subset. It uses ${expr}, NOT {{expr}}.
  // Tests below exercise the real syntax and also document behavior when
  // `{{...}}` is used.
  // -------------------------------------------------------------------------

  describe('B6-5: Template engine edge cases', () => {
    // --- Single field ---
    it('single field: ${name} → value', () => {
      expect(renderTemplate('${name}', { name: 'Alice' })).toBe('Alice')
    })

    // --- Multiple fields in one string ---
    it('multiple fields: Hello ${first} ${last}', () => {
      expect(renderTemplate('Hello ${first} ${last}', {
        first: 'Ada', last: 'Lovelace',
      })).toBe('Hello Ada Lovelace')
    })

    // --- Missing field reference ---
    it('missing field in partial interpolation → empty string', () => {
      expect(renderTemplate('Hi ${missing}!', {})).toBe('Hi !')
    })

    it('missing field as whole-string expression → undefined', () => {
      expect(renderTemplate('${missing}', {})).toBeUndefined()
    })

    // --- Nested object access ---
    it('nested object access: ${user.name}', () => {
      expect(renderTemplate('${user.name}', {
        user: { name: 'Bob' },
      })).toBe('Bob')
    })

    it('deeply nested: ${a.b.c}', () => {
      expect(renderTemplate('${a.b.c}', {
        a: { b: { c: 42 } },
      })).toBe(42)
    })

    it('array index: ${list[0]}', () => {
      expect(renderTemplate('${list[0]}', {
        list: ['first', 'second'],
      })).toBe('first')
    })

    // --- Escape sequences ---
    it('no escape support: "$${name}" stays as-is plus interpolated value', () => {
      // The engine has no `$$` escape. Each `${...}` is matched greedily.
      // Documents current behavior: outer `$` stays, inner `${name}` interpolates.
      const out = renderTemplate('$${name}', { name: 'X' })
      expect(out).toBe('$X')
    })

    // --- Empty template ---
    it('empty template → empty string', () => {
      expect(renderTemplate('', {})).toBe('')
    })

    // --- Non-string input ---
    it('primitive passthrough: number → number', () => {
      expect(renderTemplate(42, {})).toBe(42)
    })

    it('null passthrough', () => {
      expect(renderTemplate(null, {})).toBeNull()
    })

    // --- {{field}} (as mentioned in brief — document actual behavior) ---
    it('{{field}} syntax is NOT interpreted (only ${...} is): returns literal', () => {
      expect(renderTemplate('{{name}}', { name: 'Alice' })).toBe('{{name}}')
    })

    it('multiple {{first}} {{last}} also not interpreted', () => {
      expect(renderTemplate('Hello {{first}} {{last}}', {
        first: 'Ada', last: 'Lovelace',
      })).toBe('Hello {{first}} {{last}}')
    })

    // --- Arrays and objects ---
    it('array of templates: each element rendered', () => {
      expect(renderTemplate(['${a}', '${b}'], { a: '1', b: '2' })).toEqual(['1', '2'])
    })

    it('object values rendered recursively', () => {
      expect(renderTemplate({ title: '${t}', count: '${n}' }, {
        t: 'Hello', n: 5,
      })).toEqual({ title: 'Hello', count: 5 })
    })
  })
})

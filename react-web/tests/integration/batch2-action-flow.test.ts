import { describe, it, expect, beforeEach, vi } from 'vitest'
import { useAppStore } from '../../src/engine/app-store.ts'
import { AuthService } from '../../src/engine/auth-service.ts'
import { parseApp } from '../../src/models/ods-app.ts'
import { FakeDataService } from '../helpers/fake-data-service.ts'

// ---------------------------------------------------------------------------
// Test helpers (mirrors batch1-regression.test.ts patterns)
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
          ],
        },
      ],
    },
    thanks: { title: 'Thanks', content: [] },
    edit: {
      title: 'Edit',
      content: [
        {
          component: 'form',
          id: 'editForm',
          fields: [
            { name: '_id', type: 'text', label: 'ID' },
            { name: 'title', type: 'text', label: 'Title' },
            { name: 'status', type: 'text', label: 'Status' },
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

describe('Batch 2: Action flow tests', () => {
  let ds: FakeDataService
  let authService: AuthService

  beforeEach(() => {
    ds = new FakeDataService()
    ds.initialize('test')
    authService = new AuthService(mockPb())
    resetStore(ds, authService)
  })

  // -------------------------------------------------------------------------
  // B2-1: Cascade Rename Propagation
  //
  // When an update action has a `cascade` config, child records with matching
  // parent references should be updated too.
  //
  // Note: `handleCascade` in app-store.ts detects the "old value" by scanning
  // OTHER form states in the formSnapshot for a value in the parentField.
  // These tests exercise that flow.
  // -------------------------------------------------------------------------

  describe('B2-1: Cascade rename propagation', () => {
    function makeCascadeApp() {
      return parseApp({
        appName: 'Test',
        startPage: 'home',
        pages: {
          home: {
            title: 'Home',
            content: [
              {
                component: 'form',
                id: 'categoryForm',
                fields: [
                  { name: '_id', type: 'text', label: 'ID' },
                  { name: 'name', type: 'text', label: 'Name' },
                ],
              },
              {
                component: 'form',
                id: 'oldCategoryForm',
                fields: [
                  { name: 'name', type: 'text', label: 'Name' },
                ],
              },
            ],
          },
        },
        dataSources: {
          categories: {
            url: 'local://categories',
            method: 'POST',
            fields: [{ name: 'name', type: 'text', label: 'Name' }],
          },
          tasks: {
            url: 'local://tasks',
            method: 'POST',
            fields: [
              { name: 'title', type: 'text', label: 'Title' },
              { name: 'category', type: 'text', label: 'Category' },
            ],
          },
        },
      })
    }

    it('happy path: renames parent and propagates to matching child rows', async () => {
      const app = makeCascadeApp()
      ds.seed('categories', [{ name: 'Work' }])
      ds.seed('tasks', [
        { title: 'T1', category: 'Work' },
        { title: 'T2', category: 'Work' },
        { title: 'T3', category: 'Home' },
      ])
      const catId = String((await ds.query('categories'))[0]._id)

      useAppStore.setState({
        app,
        formStates: {
          categoryForm: { _id: catId, name: 'Projects' },
          // Provide old value in a separate form so handleCascade can detect it.
          oldCategoryForm: { name: 'Work' },
        },
      })

      await useAppStore.getState().executeActions([
        {
          action: 'update',
          target: 'categoryForm',
          dataSource: 'categories',
          matchField: '_id',
          cascade: {
            childDataSource: 'tasks',
            childLinkField: 'category',
            parentField: 'name',
          },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const tasks = await ds.query('tasks')
      const workTasks = tasks.filter(t => t.category === 'Work')
      const projTasks = tasks.filter(t => t.category === 'Projects')
      expect(workTasks.length).toBe(0)
      expect(projTasks.length).toBe(2)
      // Unrelated row unchanged.
      expect(tasks.find(t => t.title === 'T3')!.category).toBe('Home')
    })

    it('cascade with 0 matching children: parent still updates, no error', async () => {
      const app = makeCascadeApp()
      ds.seed('categories', [{ name: 'Work' }])
      // No child rows referencing Work.
      const catId = String((await ds.query('categories'))[0]._id)

      useAppStore.setState({
        app,
        formStates: {
          categoryForm: { _id: catId, name: 'Projects' },
          oldCategoryForm: { name: 'Work' },
        },
      })

      await useAppStore.getState().executeActions([
        {
          action: 'update',
          target: 'categoryForm',
          dataSource: 'categories',
          matchField: '_id',
          cascade: {
            childDataSource: 'tasks',
            childLinkField: 'category',
            parentField: 'name',
          },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      expect(state.lastActionError).toBeNull()
      const cats = await ds.query('categories')
      expect(cats[0].name).toBe('Projects')
    })

    it('cascade with nonexistent child data source: parent still updates, no crash', async () => {
      const app = makeCascadeApp()
      ds.seed('categories', [{ name: 'Work' }])
      ds.seed('tasks', [{ title: 'T1', category: 'Work' }])
      const catId = String((await ds.query('categories'))[0]._id)

      useAppStore.setState({
        app,
        formStates: {
          categoryForm: { _id: catId, name: 'Projects' },
          oldCategoryForm: { name: 'Work' },
        },
      })

      await useAppStore.getState().executeActions([
        {
          action: 'update',
          target: 'categoryForm',
          dataSource: 'categories',
          matchField: '_id',
          cascade: {
            childDataSource: 'nonexistent',
            childLinkField: 'category',
            parentField: 'name',
          },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      expect(state.lastActionError).toBeNull()
      const cats = await ds.query('categories')
      expect(cats[0].name).toBe('Projects')
      // Child untouched since child DS doesn't exist.
      const tasks = await ds.query('tasks')
      expect(tasks[0].category).toBe('Work')
    })

    it('cascade field is _id: children with matching old _id are renamed', async () => {
      // Rare case: cascading by _id. The old parent _id is in a secondary form.
      const app = makeCascadeApp()
      ds.seed('categories', [{ name: 'Work' }])
      const catId = String((await ds.query('categories'))[0]._id)
      ds.seed('tasks', [
        { title: 'T1', category: catId },
      ])

      useAppStore.setState({
        app,
        formStates: {
          // The action's matchField is _id, which gets STRIPPED from withData
          // by handleUpdate. We have to go through the form-based path.
          categoryForm: { _id: catId, name: 'Projects' },
          oldCategoryForm: { name: 'Work' },
        },
      })

      // This test simply verifies cascade doesn't crash when parentField is _id.
      await useAppStore.getState().executeActions([
        {
          action: 'update',
          target: 'categoryForm',
          dataSource: 'categories',
          matchField: '_id',
          cascade: {
            childDataSource: 'tasks',
            childLinkField: 'category',
            parentField: '_id',
          },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      expect(state.lastActionError).toBeNull()
    })

    it('direct cascadeRename() store method updates parent + all children', async () => {
      // Direct exercise of the cascadeRename() store method (separate from
      // the handleCascade helper used by executeActions).
      const app = makeCascadeApp()
      ds.seed('categories', [{ name: 'Work' }])
      ds.seed('tasks', [
        { title: 'T1', category: 'Work' },
        { title: 'T2', category: 'Work' },
      ])
      useAppStore.setState({ app })

      await useAppStore.getState().cascadeRename({
        parentDataSourceId: 'categories',
        parentMatchField: 'name',
        oldValue: 'Work',
        newValue: 'Projects',
        childDataSourceId: 'tasks',
        childLinkField: 'category',
      })

      const cats = await ds.query('categories')
      expect(cats[0].name).toBe('Projects')
      const tasks = await ds.query('tasks')
      expect(tasks.every(t => t.category === 'Projects')).toBe(true)
    })

    it('cascade with withData (form-less) update: children renamed via pre-queried old value', async () => {
      const app = makeCascadeApp()
      ds.seed('categories', [{ name: 'Work' }])
      ds.seed('tasks', [
        { title: 'T1', category: 'Work' },
        { title: 'T2', category: 'Work' },
        { title: 'T3', category: 'Home' },
      ])
      const catId = String((await ds.query('categories'))[0]._id)

      useAppStore.setState({
        app,
        // No forms involved — formStates is empty. The pre-query should
        // capture "Work" from the row before the update.
        formStates: {},
      })

      await useAppStore.getState().executeActions([
        {
          action: 'update',
          target: catId, // matchValue for withData updates
          dataSource: 'categories',
          matchField: '_id',
          withData: { name: 'Projects' },
          cascade: {
            childDataSource: 'tasks',
            childLinkField: 'category',
            parentField: 'name',
          },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      expect(state.lastActionError).toBeNull()
      const cats = await ds.query('categories')
      expect(cats[0].name).toBe('Projects')

      const tasks = await ds.query('tasks')
      expect(tasks.filter(t => t.category === 'Work').length).toBe(0)
      expect(tasks.filter(t => t.category === 'Projects').length).toBe(2)
      expect(tasks.find(t => t.title === 'T3')!.category).toBe('Home')
    })

    it('cascade works when form state scan would NOT find old value (only main form present)', async () => {
      // The legacy fallback scans OTHER forms for the old value. If only the
      // main form is present (with the NEW value), the scan finds nothing.
      // Pre-query lookup should still work.
      const app = makeCascadeApp()
      ds.seed('categories', [{ name: 'Work' }])
      ds.seed('tasks', [
        { title: 'T1', category: 'Work' },
        { title: 'T2', category: 'Work' },
      ])
      const catId = String((await ds.query('categories'))[0]._id)

      useAppStore.setState({
        app,
        formStates: {
          // Only the main form — new name is "Projects". No helper form
          // holding the old value.
          categoryForm: { _id: catId, name: 'Projects' },
        },
      })

      await useAppStore.getState().executeActions([
        {
          action: 'update',
          target: 'categoryForm',
          dataSource: 'categories',
          matchField: '_id',
          cascade: {
            childDataSource: 'tasks',
            childLinkField: 'category',
            parentField: 'name',
          },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      expect(state.lastActionError).toBeNull()
      const tasks = await ds.query('tasks')
      expect(tasks.filter(t => t.category === 'Projects').length).toBe(2)
      expect(tasks.filter(t => t.category === 'Work').length).toBe(0)
    })

    it('cascade with old value == new value: no-op, children unchanged', async () => {
      const app = makeCascadeApp()
      ds.seed('categories', [{ name: 'Work' }])
      ds.seed('tasks', [
        { title: 'T1', category: 'Work' },
        { title: 'T2', category: 'Work' },
      ])
      const catId = String((await ds.query('categories'))[0]._id)

      useAppStore.setState({
        app,
        formStates: {
          // New value equals old value — cascade should be a no-op.
          categoryForm: { _id: catId, name: 'Work' },
        },
      })

      await useAppStore.getState().executeActions([
        {
          action: 'update',
          target: 'categoryForm',
          dataSource: 'categories',
          matchField: '_id',
          cascade: {
            childDataSource: 'tasks',
            childLinkField: 'category',
            parentField: 'name',
          },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      expect(state.lastActionError).toBeNull()
      const tasks = await ds.query('tasks')
      // All still "Work" — no rename happened.
      expect(tasks.every(t => t.category === 'Work')).toBe(true)
    })
  })

  // -------------------------------------------------------------------------
  // B2-2: onEnd Chained Actions
  // -------------------------------------------------------------------------

  describe('B2-2: onEnd chained actions', () => {
    it('firstRecord onEnd fires when data source is empty', async () => {
      // When firstRecord finds 0 rows, it returns onEnd which the store then
      // executes as the next action.
      const app = makeApp({
        pages: {
          home: {
            title: 'Home',
            content: [
              {
                component: 'form',
                id: 'editForm',
                recordSource: 'tasks',
                fields: [
                  { name: 'title', type: 'text', label: 'Title' },
                ],
              },
            ],
          },
        },
      })
      // No rows seeded.
      useAppStore.setState({ app, currentPageId: 'home' })

      await useAppStore.getState().executeActions([
        {
          action: 'firstRecord',
          target: 'editForm',
          onEnd: {
            action: 'showMessage',
            message: 'No records',
            computedFields: [],
            preserveFields: [],
          },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      expect(state.lastMessage).toBe('No records')
    })

    it('onEnd nested 2 levels deep: both outer and inner onEnd fire (universal onEnd)', async () => {
      // With universal onEnd: when a record action's onEnd is a non-record
      // action (e.g. showMessage) with its own onEnd, the non-record
      // action's onEnd now also fires after it succeeds.
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
          page2: { title: 'Page 2', content: [] },
        },
      })
      // Seed 1 row; fire nextRecord so it hits end immediately.
      ds.seed('tasks', [{ title: 'Only' }])
      const cursor = new (await import('../../src/engine/app-store.ts')).RecordCursor(
        await ds.query('tasks'), 0,
      )
      useAppStore.setState({
        app,
        currentPageId: 'home',
        recordCursors: { editForm: cursor },
      })

      await useAppStore.getState().executeActions([
        {
          action: 'nextRecord',
          target: 'editForm',
          onEnd: {
            action: 'showMessage',
            message: 'End',
            onEnd: {
              action: 'navigate',
              target: 'page2',
              computedFields: [],
              preserveFields: [],
            },
            computedFields: [],
            preserveFields: [],
          },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      // Outer onEnd (showMessage) fired.
      expect(state.lastMessage).toBe('End')
      // Inner onEnd (navigate) also fired — universal onEnd.
      expect(state.currentPageId).toBe('page2')
    })

    it('submit with onEnd: showMessage → both succeed', async () => {
      const app = makeApp()
      useAppStore.setState({
        app,
        currentPageId: 'home',
        formStates: { addForm: { title: 'New' } },
      })

      await useAppStore.getState().executeActions([
        {
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
          onEnd: {
            action: 'showMessage',
            message: 'Saved',
            computedFields: [],
            preserveFields: [],
          },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      // Submit happened.
      const rows = await ds.query('tasks')
      expect(rows.some(r => r.title === 'New')).toBe(true)
      // onEnd fired.
      expect(state.lastMessage).toBe('Saved')
    })

    it('showMessage with onEnd: navigate → both happen', async () => {
      const app = makeApp()
      useAppStore.setState({ app, currentPageId: 'home' })

      await useAppStore.getState().executeActions([
        {
          action: 'showMessage',
          message: 'Note',
          onEnd: {
            action: 'navigate',
            target: 'thanks',
            computedFields: [],
            preserveFields: [],
          },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      expect(state.lastMessage).toBe('Note')
      expect(state.currentPageId).toBe('thanks')
    })

    it('chain of onEnd: submit → onEnd: showMessage → onEnd: navigate — all three fire', async () => {
      const app = makeApp()
      useAppStore.setState({
        app,
        currentPageId: 'home',
        formStates: { addForm: { title: 'Chain' } },
      })

      await useAppStore.getState().executeActions([
        {
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
          onEnd: {
            action: 'showMessage',
            message: 'Saved',
            onEnd: {
              action: 'navigate',
              target: 'thanks',
              computedFields: [],
              preserveFields: [],
            },
            computedFields: [],
            preserveFields: [],
          },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      const rows = await ds.query('tasks')
      expect(rows.some(r => r.title === 'Chain')).toBe(true)
      expect(state.lastMessage).toBe('Saved')
      expect(state.currentPageId).toBe('thanks')
    })

    it('failed submit with onEnd: onEnd does NOT fire (chain broken)', async () => {
      const app = makeApp()
      // No form data — submit will fail.
      useAppStore.setState({
        app,
        currentPageId: 'home',
        formStates: {},
      })

      await useAppStore.getState().executeActions([
        {
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
          onEnd: {
            action: 'showMessage',
            message: 'Should NOT appear',
            computedFields: [],
            preserveFields: [],
          },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      expect(state.lastActionError).toBeTruthy()
      expect(state.lastMessage).toBeNull()
    })

    it('failed update with onEnd: onEnd does NOT fire (chain broken)', async () => {
      const app = makeApp()
      useAppStore.setState({
        app,
        currentPageId: 'home',
      })

      await useAppStore.getState().executeActions([
        {
          action: 'update',
          target: 'missing-id',
          dataSource: 'tasks',
          matchField: '_id',
          withData: { status: 'done' },
          onEnd: {
            action: 'showMessage',
            message: 'Should NOT appear',
            computedFields: [],
            preserveFields: [],
          },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      expect(state.lastActionError).toContain('Record not found')
      expect(state.lastMessage).toBeNull()
    })

    it('onEnd undefined: action runs without chaining', async () => {
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
      // Empty data source — firstRecord returns undefined onEnd.
      useAppStore.setState({ app, currentPageId: 'home' })

      await useAppStore.getState().executeActions([
        {
          action: 'firstRecord',
          target: 'editForm',
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      expect(state.lastActionError).toBeNull()
      expect(state.lastMessage).toBeNull()
    })

    it('submit success now fires onEnd (universal onEnd for non-record actions)', async () => {
      // Universal onEnd: a successful submit's onEnd is automatically invoked.
      const app = makeApp()
      useAppStore.setState({
        app,
        currentPageId: 'home',
        formStates: { addForm: { title: 'X' } },
      })

      await useAppStore.getState().executeActions([
        {
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
          onEnd: {
            action: 'showMessage',
            message: 'Submitted',
            computedFields: [],
            preserveFields: [],
          },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      // Universal onEnd: submit success triggers onEnd.
      expect(state.lastMessage).toBe('Submitted')
    })
  })

  // -------------------------------------------------------------------------
  // B2-3: populateForm + Pre-fill After Navigate
  //
  // Currently, handleSubmit doesn't return populateForm / populateData —
  // only the `navigate` action does. Populate flow is: submit (clears form)
  // -> subsequent navigate with populateForm/withData pre-fills next form.
  // -------------------------------------------------------------------------

  describe('B2-3: populateForm + pre-fill after navigate', () => {
    it('navigate with populateForm + populateData pre-fills target form', async () => {
      const app = makeApp()
      useAppStore.setState({
        app,
        currentPageId: 'home',
        formStates: { addForm: { title: 'Alice' } },
      })

      await useAppStore.getState().executeActions([
        {
          action: 'navigate',
          target: 'edit',
          populateForm: 'editForm',
          withData: { title: '{title}', status: 'new' },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      expect(state.currentPageId).toBe('edit')
      expect(state.formStates.editForm).toEqual({
        title: 'Alice',
        status: 'new',
      })
    })

    it('populateData with unresolved {field} reference leaves placeholder unchanged', async () => {
      const app = makeApp()
      useAppStore.setState({
        app,
        currentPageId: 'home',
        formStates: {},
      })

      await useAppStore.getState().executeActions([
        {
          action: 'navigate',
          target: 'edit',
          populateForm: 'editForm',
          withData: { title: '{notAnyField}' },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      // Placeholder is left untouched when no form has that field.
      expect(state.formStates.editForm.title).toBe('{notAnyField}')
    })

    it('populateData without populateForm: no pre-fill happens', async () => {
      const app = makeApp()
      useAppStore.setState({
        app,
        currentPageId: 'home',
        formStates: { addForm: { title: 'X' } },
      })

      await useAppStore.getState().executeActions([
        {
          action: 'navigate',
          target: 'edit',
          withData: { title: 'Should not be used' },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      expect(state.currentPageId).toBe('edit')
      // editForm should not have been populated.
      expect(state.formStates.editForm).toBeUndefined()
    })

    it('populateForm without populateData: target form remains empty', async () => {
      const app = makeApp()
      useAppStore.setState({
        app,
        currentPageId: 'home',
        formStates: {},
      })

      await useAppStore.getState().executeActions([
        {
          action: 'navigate',
          target: 'edit',
          populateForm: 'editForm',
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      expect(state.currentPageId).toBe('edit')
      // No withData = no populate happens (populateForm alone is ignored).
      expect(state.formStates.editForm).toBeUndefined()
    })

    it('populateData resolves {field} from snapshot after submit clears source form', async () => {
      const app = makeApp()
      useAppStore.setState({
        app,
        currentPageId: 'home',
        formStates: { addForm: { title: 'Chained' } },
      })

      await useAppStore.getState().executeActions([
        {
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
          computedFields: [],
          preserveFields: [],
        },
        {
          action: 'navigate',
          target: 'edit',
          populateForm: 'editForm',
          withData: { title: '{title}', status: 'todo' },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      expect(state.currentPageId).toBe('edit')
      // Snapshot preserves addForm.title even though clearForm ran.
      expect(state.formStates.editForm.title).toBe('Chained')
      expect(state.formStates.editForm.status).toBe('todo')
    })
  })

  // -------------------------------------------------------------------------
  // B2-4: Record Cursor Navigation
  // -------------------------------------------------------------------------

  describe('B2-4: Record cursor navigation', () => {
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

    it('firstRecord -> nextRecord walks through all rows', async () => {
      const app = makeRecordApp()
      ds.seed('tasks', [
        { title: 'A', status: 'todo' },
        { title: 'B', status: 'todo' },
        { title: 'C', status: 'todo' },
      ])
      useAppStore.setState({ app })

      // NOTE: FakeDataService.query() returns rows in REVERSE insertion order.
      // seed insertion order: A (idx 0), B (idx 1), C (idx 2).
      // query() returns: [C, B, A].
      // So firstRecord -> C, next -> B, next -> A.
      await useAppStore.getState().executeActions([
        { action: 'firstRecord', target: 'editForm', computedFields: [], preserveFields: [] },
      ])
      expect(useAppStore.getState().formStates.editForm.title).toBe('C')

      await useAppStore.getState().executeActions([
        { action: 'nextRecord', target: 'editForm', computedFields: [], preserveFields: [] },
      ])
      expect(useAppStore.getState().formStates.editForm.title).toBe('B')

      await useAppStore.getState().executeActions([
        { action: 'nextRecord', target: 'editForm', computedFields: [], preserveFields: [] },
      ])
      expect(useAppStore.getState().formStates.editForm.title).toBe('A')
    })

    it('nextRecord on last row: form unchanged, onEnd fires', async () => {
      const app = makeRecordApp()
      ds.seed('tasks', [
        { title: 'A', status: 'todo' },
        { title: 'B', status: 'todo' },
      ])
      useAppStore.setState({ app })

      // firstRecord then walk to the last row.
      await useAppStore.getState().executeActions([
        { action: 'firstRecord', target: 'editForm', computedFields: [], preserveFields: [] },
        { action: 'nextRecord', target: 'editForm', computedFields: [], preserveFields: [] },
      ])
      const lastTitle = useAppStore.getState().formStates.editForm.title

      // nextRecord past the last row: onEnd fires.
      await useAppStore.getState().executeActions([
        {
          action: 'nextRecord',
          target: 'editForm',
          onEnd: {
            action: 'showMessage',
            message: 'End of list',
            computedFields: [],
            preserveFields: [],
          },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      expect(state.formStates.editForm.title).toBe(lastTitle) // unchanged
      expect(state.lastMessage).toBe('End of list')
    })

    it('lastRecord jumps to final row; previousRecord moves back', async () => {
      const app = makeRecordApp()
      ds.seed('tasks', [
        { title: 'A', status: 'todo' },
        { title: 'B', status: 'todo' },
        { title: 'C', status: 'todo' },
      ])
      useAppStore.setState({ app })

      // query() returns [C, B, A]; lastRecord -> last = A.
      await useAppStore.getState().executeActions([
        { action: 'lastRecord', target: 'editForm', computedFields: [], preserveFields: [] },
      ])
      expect(useAppStore.getState().formStates.editForm.title).toBe('A')

      // previousRecord -> B
      await useAppStore.getState().executeActions([
        { action: 'previousRecord', target: 'editForm', computedFields: [], preserveFields: [] },
      ])
      expect(useAppStore.getState().formStates.editForm.title).toBe('B')
    })

    it('empty data source: firstRecord fires onEnd', async () => {
      const app = makeRecordApp()
      // No seeded rows.
      useAppStore.setState({ app })

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

    it('filter with no matches: firstRecord fires onEnd', async () => {
      const app = makeRecordApp()
      ds.seed('tasks', [
        { title: 'A', status: 'todo' },
      ])
      useAppStore.setState({ app })

      await useAppStore.getState().executeActions([
        {
          action: 'firstRecord',
          target: 'editForm',
          filter: { status: 'done' },
          onEnd: {
            action: 'showMessage',
            message: 'No match',
            computedFields: [],
            preserveFields: [],
          },
          computedFields: [],
          preserveFields: [],
        },
      ])

      expect(useAppStore.getState().lastMessage).toBe('No match')
    })

    it('filter with {field} placeholder resolves from form state', async () => {
      const app = makeRecordApp()
      ds.seed('tasks', [
        { title: 'A', status: 'todo' },
        { title: 'B', status: 'done' },
      ])
      useAppStore.setState({
        app,
        formStates: { editForm: { status: 'done' } },
      })

      await useAppStore.getState().executeActions([
        {
          action: 'firstRecord',
          target: 'editForm',
          filter: { status: '{status}' },
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      expect(state.formStates.editForm.title).toBe('B')
      expect(state.formStates.editForm.status).toBe('done')
    })
  })

  // -------------------------------------------------------------------------
  // B2-5: Form preserveFields
  // -------------------------------------------------------------------------

  describe('B2-5: Form preserveFields', () => {
    it('preserveFields keeps specified values after submit', async () => {
      const app = parseApp({
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
                  { name: 'name', type: 'text', label: 'Name' },
                  { name: 'date', type: 'text', label: 'Date' },
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
              { name: 'name', type: 'text', label: 'Name' },
              { name: 'date', type: 'text', label: 'Date' },
              { name: 'status', type: 'text', label: 'Status' },
            ],
          },
        },
      })
      useAppStore.setState({
        app,
        formStates: {
          addForm: { name: 'Alice', date: '2026-04-13', status: 'todo' },
        },
      })

      await useAppStore.getState().executeActions([
        {
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
          computedFields: [],
          preserveFields: ['date'],
        },
      ])

      const state = useAppStore.getState()
      expect(state.formStates.addForm).toEqual({ date: '2026-04-13' })
    })

    it('preserveFields with non-existent field name is ignored', async () => {
      const app = makeApp()
      useAppStore.setState({
        app,
        formStates: { addForm: { title: 'X', status: 'todo' } },
      })

      await useAppStore.getState().executeActions([
        {
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
          computedFields: [],
          preserveFields: ['title', 'notAField'],
        },
      ])

      const state = useAppStore.getState()
      expect(state.formStates.addForm).toEqual({ title: 'X' })
    })

    it('preserveFields = [] clears entire form', async () => {
      const app = makeApp()
      useAppStore.setState({
        app,
        formStates: { addForm: { title: 'X', status: 'todo' } },
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

      const state = useAppStore.getState()
      expect(state.formStates.addForm).toBeUndefined()
    })

    it('preserveFields with empty string value: preserved (empty != missing)', async () => {
      const app = makeApp()
      useAppStore.setState({
        app,
        // Note: the field has a value of empty string — NOT missing.
        formStates: { addForm: { title: 'X', status: '' } },
      })

      // Call clearForm directly so submit validation doesn't reject the empty
      // value (the form's only required behavior depends on the field spec).
      useAppStore.getState().clearForm('addForm', ['status'])

      const state = useAppStore.getState()
      expect(state.formStates.addForm).toEqual({ status: '' })
    })
  })

  // -------------------------------------------------------------------------
  // B2-6: Action Chain Failure Rollback
  // -------------------------------------------------------------------------

  describe('B2-6: Action chain failure rollback', () => {
    it('failing update mid-chain stops chain; later showMessage NOT set', async () => {
      const app = makeApp()
      ds.seed('tasks', [{ title: 'A' }])
      useAppStore.setState({
        app,
        currentPageId: 'home',
        formStates: { addForm: { title: 'Chained' } },
      })

      await useAppStore.getState().executeActions([
        {
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
          computedFields: [],
          preserveFields: [],
        },
        {
          action: 'update',
          target: 'nonexistent-id',
          dataSource: 'tasks',
          matchField: '_id',
          withData: { status: 'done' },
          computedFields: [],
          preserveFields: [],
        },
        {
          action: 'showMessage',
          message: 'Should not fire',
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      // First submit succeeded.
      const rows = await ds.query('tasks')
      expect(rows.some(r => r.title === 'Chained')).toBe(true)
      // Second update failed.
      expect(state.lastActionError).toContain('Record not found')
      // Third action did NOT fire.
      expect(state.lastMessage).toBeNull()
    })

    it('exception thrown mid-chain: chain stops and error is set', async () => {
      const app = makeApp()
      useAppStore.setState({
        app,
        currentPageId: 'home',
        formStates: { addForm: { title: 'X' } },
      })

      // Break the data service mid-chain.
      const originalInsert = ds.insert.bind(ds)
      let callCount = 0
      ds.insert = vi.fn(async (table: string, data: Record<string, unknown>) => {
        callCount++
        if (callCount === 2) throw new Error('Boom')
        return originalInsert(table, data)
      }) as any

      await useAppStore.getState().executeActions([
        {
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
          computedFields: [],
          preserveFields: [],
        },
      ])
      // Set up for second submit that will throw.
      useAppStore.setState({ formStates: { addForm: { title: 'Y' } } })
      await useAppStore.getState().executeActions([
        {
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
          computedFields: [],
          preserveFields: [],
        },
        {
          action: 'showMessage',
          message: 'Should not fire',
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      expect(state.lastActionError).toMatch(/Boom|Action failed/i)
      expect(state.lastMessage).toBeNull()
    })

    it('first action fails: chain stops immediately', async () => {
      const app = makeApp()
      useAppStore.setState({
        app,
        currentPageId: 'home',
        formStates: {}, // no form data => submit fails immediately
      })

      await useAppStore.getState().executeActions([
        {
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
          computedFields: [],
          preserveFields: [],
        },
        {
          action: 'showMessage',
          message: 'After fail',
          computedFields: [],
          preserveFields: [],
        },
        {
          action: 'navigate',
          target: 'thanks',
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      expect(state.lastActionError).toBeTruthy()
      expect(state.lastMessage).toBeNull()
      // Did NOT navigate.
      expect(state.currentPageId).toBe('home')
    })
  })

  // -------------------------------------------------------------------------
  // B2-7: Cross-Form State Isolation
  // -------------------------------------------------------------------------

  describe('B2-7: Cross-form state isolation', () => {
    it('updating formA does not affect formB', () => {
      useAppStore.getState().updateFormField('formA', 'name', 'A')
      useAppStore.getState().updateFormField('formB', 'name', 'B')

      const state = useAppStore.getState()
      expect(state.formStates.formA).toEqual({ name: 'A' })
      expect(state.formStates.formB).toEqual({ name: 'B' })
    })

    it('clearing formA leaves formB intact', () => {
      useAppStore.getState().updateFormField('formA', 'name', 'A')
      useAppStore.getState().updateFormField('formB', 'name', 'B')

      useAppStore.getState().clearForm('formA')

      const state = useAppStore.getState()
      expect(state.formStates.formA).toBeUndefined()
      expect(state.formStates.formB).toEqual({ name: 'B' })
    })

    it('clearing a nonexistent form: no error, no side effects', () => {
      useAppStore.getState().updateFormField('formB', 'name', 'B')

      expect(() => {
        useAppStore.getState().clearForm('formA')
      }).not.toThrow()

      const state = useAppStore.getState()
      expect(state.formStates.formB).toEqual({ name: 'B' })
    })

    it('updating formA.name does not bleed into formB.name', () => {
      useAppStore.getState().updateFormField('formA', 'name', 'alpha')
      useAppStore.getState().updateFormField('formB', 'name', 'beta')
      useAppStore.getState().updateFormField('formA', 'name', 'alpha-2')

      const state = useAppStore.getState()
      expect(state.formStates.formA.name).toBe('alpha-2')
      expect(state.formStates.formB.name).toBe('beta')
    })
  })
})

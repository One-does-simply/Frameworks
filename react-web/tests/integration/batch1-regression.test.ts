import { describe, it, expect, beforeEach, vi } from 'vitest'
import { useAppStore, startPageForRoles } from '../../src/engine/app-store.ts'
import { executeAction } from '../../src/engine/action-handler.ts'
import { AuthService } from '../../src/engine/auth-service.ts'
import { parseApp } from '../../src/models/ods-app.ts'
import { FakeDataService } from '../helpers/fake-data-service.ts'
import { DataService } from '../../src/engine/data-service.ts'
import { restoreBackup } from '../../src/engine/backup-service.ts'

// ---------------------------------------------------------------------------
// Test helpers
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

describe('Batch 1: Regression tests', () => {
  let ds: FakeDataService
  let authService: AuthService

  beforeEach(() => {
    ds = new FakeDataService()
    ds.initialize('test')
    authService = new AuthService(mockPb())
    resetStore(ds, authService)
  })

  // -------------------------------------------------------------------------
  // B1: Submit -> List
  // -------------------------------------------------------------------------

  describe('B1: Submit -> List', () => {
    it('inserts row that appears in subsequent query', async () => {
      const app = makeApp()
      useAppStore.setState({ app, formStates: { addForm: { title: 'Buy milk' } } })

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
      expect(rows[0].title).toBe('Buy milk')
    })

    it('round-trips unicode content exactly', async () => {
      const app = makeApp()
      const unicodeVal = 'Hello 🚀 café'
      useAppStore.setState({ app, formStates: { addForm: { title: unicodeVal } } })

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
      expect(rows[0].title).toBe(unicodeVal)
    })

    it('submit twice produces two rows', async () => {
      const app = makeApp()
      useAppStore.setState({ app, formStates: { addForm: { title: 'First' } } })
      await useAppStore.getState().executeActions([
        {
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
          computedFields: [],
          preserveFields: [],
        },
      ])

      // After submit, form is cleared — set new state
      useAppStore.setState({ formStates: { addForm: { title: 'Second' } } })
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
      expect(rows.length).toBe(2)
    })

    it('submit with no form state sets lastActionError', async () => {
      const app = makeApp()
      useAppStore.setState({ app, formStates: {} })

      await useAppStore.getState().executeActions([
        {
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
          computedFields: [],
          preserveFields: [],
        },
      ])

      const { lastActionError } = useAppStore.getState()
      expect(lastActionError).toBeTruthy()
      expect(lastActionError).toContain('No form data')
    })
  })

  // -------------------------------------------------------------------------
  // B2: Update via withData
  // -------------------------------------------------------------------------

  describe('B2: Update via withData', () => {
    it('updates a matched row', async () => {
      const app = makeApp()
      ds.seed('tasks', [{ title: 'A', status: 'todo' }])
      const seeded = await ds.query('tasks')
      const seededId = String(seeded[0]._id)

      const result = await executeAction({
        action: {
          action: 'update',
          target: seededId,
          dataSource: 'tasks',
          matchField: '_id',
          withData: { status: 'done' },
          computedFields: [],
          preserveFields: [],
        },
        app,
        formStates: {},
        dataService: ds as any,
      })

      expect(result.submitted).toBe(true)
      const updated = await ds.query('tasks')
      expect(updated[0].status).toBe('done')
    })

    it('returns error when target row does not exist', async () => {
      const app = makeApp()
      const result = await executeAction({
        action: {
          action: 'update',
          target: 'non-existent-id',
          dataSource: 'tasks',
          matchField: '_id',
          withData: { status: 'done' },
          computedFields: [],
          preserveFields: [],
        },
        app,
        formStates: {},
        dataService: ds as any,
      })

      expect(result.submitted).toBe(false)
      expect(result.error).toBe('Record not found')
    })

    it('withData containing _id does not overwrite target _id', async () => {
      const app = makeApp()
      ds.seed('tasks', [{ title: 'Original', status: 'todo' }])
      const seeded = await ds.query('tasks')
      const seededId = String(seeded[0]._id)

      await executeAction({
        action: {
          action: 'update',
          target: seededId,
          dataSource: 'tasks',
          matchField: '_id',
          // malicious: tries to overwrite _id with a bogus value
          withData: { status: 'done', _id: 'hijacked' },
          computedFields: [],
          preserveFields: [],
        },
        app,
        formStates: {},
        dataService: ds as any,
      })

      const rows = await ds.query('tasks')
      expect(rows.length).toBe(1)
      // _id should remain unchanged (NOT rewritten to 'hijacked')
      expect(rows[0]._id).toBe(seededId)
      expect(rows[0].status).toBe('done')
    })

    it('withData containing dangerous field name is rejected by real DataService', async () => {
      // Use real DataService to verify validateFieldName runs on matchField.
      const pb = {
        collection: vi.fn(() => ({
          getFullList: vi.fn(async () => []),
          update: vi.fn(async () => ({})),
        })),
      } as any
      const realDs = new DataService(pb)
      realDs.initialize('test')

      await expect(
        realDs.update('tasks', { status: 'done' }, '"; DROP TABLE users; --', 'x'),
      ).rejects.toThrow(/Invalid field name/)
    })
  })

  // -------------------------------------------------------------------------
  // B3: Delete -> recordGeneration bumps
  // -------------------------------------------------------------------------

  describe('B3: Delete -> recordGeneration bumps', () => {
    it('increments recordGeneration on successful delete', async () => {
      const app = makeApp()
      ds.seed('tasks', [
        { title: 'A', status: 'todo' },
        { title: 'B', status: 'todo' },
      ])
      useAppStore.setState({ app })

      const before = useAppStore.getState().recordGeneration
      const seeded = await ds.query('tasks')
      const seededId = String(seeded[0]._id)

      await useAppStore.getState().executeDeleteRowAction('tasks', '_id', seededId)

      const after = useAppStore.getState().recordGeneration
      expect(after).toBe(before + 1)

      const remaining = await ds.query('tasks')
      expect(remaining.length).toBe(1)
    })

    it('still increments recordGeneration when deleting a non-existent row', async () => {
      const app = makeApp()
      ds.seed('tasks', [{ title: 'A', status: 'todo' }])
      useAppStore.setState({ app })

      const before = useAppStore.getState().recordGeneration
      await useAppStore.getState().executeDeleteRowAction('tasks', '_id', 'does-not-exist')
      const after = useAppStore.getState().recordGeneration

      expect(after).toBe(before + 1)
      // Row count unchanged
      const rows = await ds.query('tasks')
      expect(rows.length).toBe(1)
    })

    it('delete all rows leaves query returning empty array', async () => {
      const app = makeApp()
      ds.seed('tasks', [
        { title: 'A', status: 'todo' },
        { title: 'B', status: 'todo' },
        { title: 'C', status: 'todo' },
      ])
      useAppStore.setState({ app })

      const seeded = await ds.query('tasks')
      for (const row of seeded) {
        await useAppStore.getState().executeDeleteRowAction('tasks', '_id', String(row._id))
      }

      const remaining = await ds.query('tasks')
      expect(remaining).toEqual([])
    })
  })

  // -------------------------------------------------------------------------
  // B4: PocketBase superadmin auto-detection
  // -------------------------------------------------------------------------

  describe('B4: PocketBase superadmin auto-detection', () => {
    it('setSuperAdmin(true) grants admin+user roles', () => {
      authService.setSuperAdmin(true)
      expect(authService.currentRoles).toEqual(['admin', 'user'])
    })

    it('hasAccess([admin]) returns true for superadmin', () => {
      authService.setSuperAdmin(true)
      expect(authService.hasAccess(['admin'])).toBe(true)
    })

    it('superadmin reports isLoggedIn true', () => {
      authService.setSuperAdmin(true)
      expect(authService.isLoggedIn).toBe(true)
      expect(authService.isSuperAdmin).toBe(true)
    })

    it('setSuperAdmin(false) reverts to guest', () => {
      authService.setSuperAdmin(true)
      authService.setSuperAdmin(false)
      expect(authService.currentRoles).toEqual(['guest'])
      expect(authService.hasAccess(['admin'])).toBe(false)
    })
  })

  // -------------------------------------------------------------------------
  // B5: Role-based start page
  // -------------------------------------------------------------------------

  describe('B5: Role-based start page', () => {
    it('object startPage with default + admin produces split app fields', () => {
      const app = makeApp({
        startPage: { default: 'home', admin: 'dashboard' },
        pages: {
          home: { title: 'Home', content: [] },
          dashboard: { title: 'Dash', content: [] },
        },
      })
      expect(app.startPage).toBe('home')
      expect(app.startPageByRole).toEqual({ admin: 'dashboard' })
    })

    it('startPageForRoles returns admin page for admin role', () => {
      const app = makeApp({
        startPage: { default: 'home', admin: 'dashboard' },
        pages: {
          home: { title: 'Home', content: [] },
          dashboard: { title: 'Dash', content: [] },
        },
      })
      expect(startPageForRoles(['admin'], app)).toBe('dashboard')
    })

    it('startPageForRoles falls back to default for unknown role', () => {
      const app = makeApp({
        startPage: { default: 'home', admin: 'dashboard' },
        pages: {
          home: { title: 'Home', content: [] },
          dashboard: { title: 'Dash', content: [] },
        },
      })
      expect(startPageForRoles(['user'], app)).toBe('home')
    })

    it('startPageForRoles returns default for empty role list', () => {
      const app = makeApp({
        startPage: { default: 'home', admin: 'dashboard' },
        pages: {
          home: { title: 'Home', content: [] },
          dashboard: { title: 'Dash', content: [] },
        },
      })
      expect(startPageForRoles([], app)).toBe('home')
    })

    it('plain string startPage produces empty startPageByRole', () => {
      const app = makeApp({ startPage: 'home' })
      expect(app.startPage).toBe('home')
      expect(app.startPageByRole).toEqual({})
      expect(startPageForRoles(['admin'], app)).toBe('home')
      expect(startPageForRoles([], app)).toBe('home')
    })
  })

  // -------------------------------------------------------------------------
  // B6: Field name injection
  // -------------------------------------------------------------------------

  describe('B6: Field name injection', () => {
    function trackingPb() {
      const calls: string[] = []
      const pb = {
        calls,
        collection: (_name: string) => ({
          getFullList: (...args: unknown[]) => {
            calls.push(`getFullList:${JSON.stringify(args)}`)
            return Promise.resolve([])
          },
          update: (...args: unknown[]) => {
            calls.push(`update:${JSON.stringify(args)}`)
            return Promise.resolve({})
          },
          delete: (...args: unknown[]) => {
            calls.push(`delete:${JSON.stringify(args)}`)
            return Promise.resolve({})
          },
        }),
      }
      return pb as any
    }

    it('update() rejects matchField with invalid characters', async () => {
      const pb = trackingPb()
      const realDs = new DataService(pb)
      realDs.initialize('test')
      await expect(
        realDs.update('tasks', { x: '1' }, 'name; DROP', 'v'),
      ).rejects.toThrow(/Invalid field name/)
      // Ensure no PB calls were made
      expect(pb.calls.length).toBe(0)
    })

    it('update() rejects reserved __proto__ as matchField', async () => {
      const pb = trackingPb()
      const realDs = new DataService(pb)
      realDs.initialize('test')
      await expect(
        realDs.update('tasks', { x: '1' }, '__proto__', 'v'),
      ).rejects.toThrow(/Reserved field name/)
      expect(pb.calls.length).toBe(0)
    })

    it('delete() rejects malicious matchField', async () => {
      const pb = trackingPb()
      const realDs = new DataService(pb)
      realDs.initialize('test')
      await expect(
        realDs.delete('tasks', 'bad-name-with-dashes', 'v'),
      ).rejects.toThrow(/Invalid field name/)
      expect(pb.calls.length).toBe(0)
    })

    it('queryWithFilter() rejects malicious filter keys', async () => {
      const pb = trackingPb()
      const realDs = new DataService(pb)
      realDs.initialize('test')
      await expect(
        realDs.queryWithFilter('tasks', { 'constructor': 'x' }),
      ).rejects.toThrow(/Reserved field name/)
      expect(pb.calls.length).toBe(0)
    })
  })

  // -------------------------------------------------------------------------
  // B7: Backup round-trip
  // -------------------------------------------------------------------------

  describe('B7: Backup round-trip', () => {
    it('restoreBackup replaces seeded data', async () => {
      const app = makeApp()
      ds.seed('tasks', [
        { title: 'Old1', status: 'todo' },
        { title: 'Old2', status: 'todo' },
        { title: 'Old3', status: 'todo' },
      ])

      const backup = {
        odsBackup: true,
        tables: {
          tasks: [{ title: 'A' }, { title: 'B' }],
        },
      }

      const result = await restoreBackup(JSON.stringify(backup), app, ds as any)
      expect(result).toBeNull()

      const rows = await ds.query('tasks')
      expect(rows.length).toBe(2)
      const titles = rows.map(r => r.title).sort()
      expect(titles).toEqual(['A', 'B'])
    })

    it('sanitizes dangerous field names from backup rows', async () => {
      const app = makeApp()

      const backup = {
        odsBackup: true,
        tables: {
          tasks: [
            { title: 'SafeRow', __proto__: { polluted: true } },
          ],
        },
      }

      const result = await restoreBackup(JSON.stringify(backup), app, ds as any)
      expect(result).toBeNull()

      // Prototype must NOT be polluted
      expect(({} as any).polluted).toBeUndefined()

      const rows = await ds.query('tasks')
      expect(rows.length).toBe(1)
      expect(rows[0].title).toBe('SafeRow')
    })

    it('accepts backup with missing signature and logs a warning', async () => {
      const app = makeApp()
      const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {})

      const backup = {
        odsBackup: true,
        tables: { tasks: [{ title: 'Unsigned' }] },
      }

      const result = await restoreBackup(JSON.stringify(backup), app, ds as any)
      expect(result).toBeNull()
      expect(warnSpy).toHaveBeenCalled()
      const combined = warnSpy.mock.calls.map(c => c.join(' ')).join('\n')
      expect(combined).toMatch(/unsigned|signature/i)

      warnSpy.mockRestore()
    })
  })

  // -------------------------------------------------------------------------
  // B8: Action chain
  // -------------------------------------------------------------------------

  describe('B8: Action chain', () => {
    it('submit + showMessage + navigate all fire', async () => {
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
          action: 'showMessage',
          message: 'Saved!',
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
      // Submit happened
      const rows = await ds.query('tasks')
      expect(rows.length).toBe(1)
      expect(rows[0].title).toBe('Chained')
      // Message shown
      expect(state.lastMessage).toBe('Saved!')
      // Navigation happened
      expect(state.currentPageId).toBe('thanks')
    })

    it('failed submit stops chain — later showMessage is NOT set', async () => {
      const app = makeApp()
      useAppStore.setState({
        app,
        currentPageId: 'home',
        formStates: {}, // no form data -> submit fails
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
          message: 'Should not appear',
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      expect(state.lastActionError).toBeTruthy()
      expect(state.lastMessage).toBeNull()
    })

    it('empty action array is a no-op and does not crash', async () => {
      const app = makeApp()
      useAppStore.setState({ app, currentPageId: 'home' })

      await expect(
        useAppStore.getState().executeActions([]),
      ).resolves.toBeUndefined()

      const state = useAppStore.getState()
      expect(state.lastActionError).toBeNull()
      expect(state.lastMessage).toBeNull()
      expect(state.currentPageId).toBe('home')
    })

    it('navigate to non-existent page does not change page; chain continues', async () => {
      const app = makeApp()
      useAppStore.setState({
        app,
        currentPageId: 'home',
      })

      await useAppStore.getState().executeActions([
        {
          action: 'navigate',
          target: 'does-not-exist',
          computedFields: [],
          preserveFields: [],
        },
        {
          action: 'showMessage',
          message: 'After bad nav',
          computedFields: [],
          preserveFields: [],
        },
      ])

      const state = useAppStore.getState()
      // Page should remain on home — navigate silently ignored.
      expect(state.currentPageId).toBe('home')
      // Message after navigate should still be set (chain continues).
      expect(state.lastMessage).toBe('After bad nav')
    })
  })
})

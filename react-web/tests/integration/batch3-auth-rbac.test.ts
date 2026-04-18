import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import { useAppStore } from '../../src/engine/app-store.ts'
import { AuthService } from '../../src/engine/auth-service.ts'
import { parseApp } from '../../src/models/ods-app.ts'
import { FakeDataService } from '../helpers/fake-data-service.ts'

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/**
 * Build a minimal PocketBase mock. Accepts:
 *  - isValid: whether authStore is valid (logged in)
 *  - record:  user record (roles/email/etc.)
 *  - authWithPassword: optional custom impl (for rate-limit tests)
 */
function mockPb(overrides: {
  isValid?: boolean
  record?: Record<string, unknown> | null
  authWithPassword?: (email: string, password: string) => Promise<unknown>
} = {}) {
  return {
    authStore: {
      isValid: overrides.isValid ?? false,
      record: overrides.record ?? null,
      clear: () => {},
    },
    collection: () => ({
      listAuthMethods: async () => ({ oauth2: { providers: [] } }),
      authWithPassword: overrides.authWithPassword
        ?? (async () => { throw new Error('auth-failed') }),
    }),
  } as any
}

function makeApp(overrides: any = {}) {
  return parseApp({
    appName: 'Test',
    startPage: overrides.startPage ?? 'home',
    pages: overrides.pages ?? {
      home: { title: 'Home', content: [] },
      adminPage: { title: 'Admin', content: [], roles: ['admin'] },
      editorPage: { title: 'Editor', content: [], roles: ['editor'] },
      openPage: { title: 'Open', content: [] },
      emptyRolesPage: { title: 'Empty', content: [], roles: [] },
    },
    dataSources: overrides.dataSources ?? {},
    auth: overrides.auth ?? { multiUser: true, defaultRole: 'user' },
    ...Object.fromEntries(
      Object.entries(overrides).filter(([k]) =>
        k !== 'pages' && k !== 'dataSources' && k !== 'auth' && k !== 'startPage',
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

describe('Batch 3: Auth & RBAC integration tests', () => {
  let ds: FakeDataService
  let authService: AuthService

  beforeEach(() => {
    ds = new FakeDataService()
    ds.initialize('test')
    authService = new AuthService(mockPb())
    resetStore(ds, authService)
  })

  // -------------------------------------------------------------------------
  // B3-1: hasAccess Role Matching
  // -------------------------------------------------------------------------

  describe('B3-1: hasAccess Role Matching', () => {
    it('user with [editor] role → hasAccess([editor]) === true', () => {
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: ['editor'] } })
      const auth = new AuthService(pb)
      expect(auth.hasAccess(['editor'])).toBe(true)
    })

    it('user with [editor] role → hasAccess([admin]) === false', () => {
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: ['editor'] } })
      const auth = new AuthService(pb)
      expect(auth.hasAccess(['admin'])).toBe(false)
    })

    it('hasAccess(undefined) === true (no role requirement)', () => {
      expect(authService.hasAccess(undefined)).toBe(true)
    })

    it('hasAccess([]) === true (empty = open)', () => {
      expect(authService.hasAccess([])).toBe(true)
    })

    it('superAdmin → hasAccess(anything) === true', () => {
      authService.setSuperAdmin(true)
      expect(authService.hasAccess(['admin'])).toBe(true)
      expect(authService.hasAccess(['editor'])).toBe(true)
      expect(authService.hasAccess(['made-up-role'])).toBe(true)
    })

    it('admin role → hasAccess(anything non-empty) === true (admin bypass)', () => {
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: ['admin'] } })
      const auth = new AuthService(pb)
      expect(auth.hasAccess(['editor'])).toBe(true)
      expect(auth.hasAccess(['viewer'])).toBe(true)
      expect(auth.hasAccess(['anything'])).toBe(true)
    })

    it('user with no roles set → treated as defaultRole "user"', () => {
      const pb = mockPb({ isValid: true, record: { id: 'u1' } })
      const auth = new AuthService(pb)
      expect(auth.currentRoles).toEqual(['user'])
      expect(auth.hasAccess(['user'])).toBe(true)
      expect(auth.hasAccess(['admin'])).toBe(false)
    })

    it('case sensitivity: "Admin" role normalizes to lowercase "admin"', () => {
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: ['Admin'] } })
      const auth = new AuthService(pb)
      expect(auth.currentRoles).toEqual(['admin'])
      // Because normalized, isAdmin should be true (admin bypass applies).
      expect(auth.isAdmin).toBe(true)
      expect(auth.hasAccess(['anything'])).toBe(true)
    })

    it('hasAccess with mixed-case required role ["Admin"] — lowercases before comparison', () => {
      // hasAccess now lowercases the required roles to match the normalized
      // currentRoles (which are also lowercased).

      // User has ['user']; required 'Admin' (normalized to 'admin') still
      // doesn't match, so expect false.
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: ['user'] } })
      const auth = new AuthService(pb)
      expect(auth.hasAccess(['Admin'])).toBe(false)

      // User with roles ['admin'] passes via the admin bypass.
      const pb2 = mockPb({ isValid: true, record: { id: 'u1', roles: ['admin'] } })
      const auth2 = new AuthService(pb2)
      expect(auth2.hasAccess(['Admin'])).toBe(true)

      // User with role 'editor' asked for ['Editor'] now PASSES after
      // case-insensitive normalization.
      const pb3 = mockPb({ isValid: true, record: { id: 'u1', roles: ['editor'] } })
      const auth3 = new AuthService(pb3)
      expect(auth3.hasAccess(['Editor'])).toBe(true)
    })

    it('hasAccess lowercases requiredRoles: editor user matches ["Editor"] and ["EDITOR"]', () => {
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: ['editor'] } })
      const auth = new AuthService(pb)
      expect(auth.hasAccess(['Editor'])).toBe(true)
      expect(auth.hasAccess(['EDITOR'])).toBe(true)
      expect(auth.hasAccess(['EdItOr'])).toBe(true)
    })

    it('hasAccess with mixed-case required list matches any role (normalized)', () => {
      // User has ['user']; required ['Admin', 'User'] should match via 'user'.
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: ['user'] } })
      const auth = new AuthService(pb)
      expect(auth.hasAccess(['Admin', 'User'])).toBe(true)
      expect(auth.hasAccess(['ADMIN', 'USER'])).toBe(true)
      // None match: still false.
      expect(auth.hasAccess(['Manager', 'Viewer'])).toBe(false)
    })

    it('multiple required roles: user with any matching role → true', () => {
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: ['editor'] } })
      const auth = new AuthService(pb)
      expect(auth.hasAccess(['editor', 'viewer'])).toBe(true)
      expect(auth.hasAccess(['viewer', 'editor'])).toBe(true)
    })

    it('user with multiple roles matches any required role', () => {
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: ['viewer', 'editor'] } })
      const auth = new AuthService(pb)
      expect(auth.hasAccess(['editor'])).toBe(true)
      expect(auth.hasAccess(['viewer'])).toBe(true)
      expect(auth.hasAccess(['manager', 'viewer'])).toBe(true)
      expect(auth.hasAccess(['manager'])).toBe(false)
    })
  })

  // -------------------------------------------------------------------------
  // B3-2: Role-Based Page Navigation Guard
  // -------------------------------------------------------------------------

  describe('B3-2: Role-Based Page Navigation Guard', () => {
    it('user with "user" role → navigateTo(adminPage) is blocked', () => {
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: ['user'] } })
      authService = new AuthService(pb)
      const app = makeApp()
      resetStore(ds, authService)
      useAppStore.setState({ app, currentPageId: 'home', isMultiUser: true })

      useAppStore.getState().navigateTo('adminPage')
      expect(useAppStore.getState().currentPageId).toBe('home')
    })

    it('user with "admin" role → navigateTo(adminPage) succeeds', () => {
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: ['admin'] } })
      authService = new AuthService(pb)
      const app = makeApp()
      resetStore(ds, authService)
      useAppStore.setState({ app, currentPageId: 'home', isMultiUser: true })

      useAppStore.getState().navigateTo('adminPage')
      expect(useAppStore.getState().currentPageId).toBe('adminPage')
    })

    it('superAdmin → can navigate anywhere', () => {
      authService.setSuperAdmin(true)
      const app = makeApp()
      useAppStore.setState({ app, currentPageId: 'home', isMultiUser: true })

      useAppStore.getState().navigateTo('adminPage')
      expect(useAppStore.getState().currentPageId).toBe('adminPage')

      useAppStore.getState().navigateTo('editorPage')
      expect(useAppStore.getState().currentPageId).toBe('editorPage')
    })

    it('page with no roles field → anyone can navigate', () => {
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: ['user'] } })
      authService = new AuthService(pb)
      const app = makeApp()
      resetStore(ds, authService)
      useAppStore.setState({ app, currentPageId: 'home', isMultiUser: true })

      useAppStore.getState().navigateTo('openPage')
      expect(useAppStore.getState().currentPageId).toBe('openPage')
    })

    it('page with empty roles [] → anyone can navigate', () => {
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: ['user'] } })
      authService = new AuthService(pb)
      const app = makeApp()
      resetStore(ds, authService)
      useAppStore.setState({ app, currentPageId: 'home', isMultiUser: true })

      useAppStore.getState().navigateTo('emptyRolesPage')
      expect(useAppStore.getState().currentPageId).toBe('emptyRolesPage')
    })

    it('multiUser: false → role guard bypassed entirely', () => {
      // Guest (no roles) in a single-user app should be able to reach adminPage.
      const app = makeApp({ auth: { multiUser: false, defaultRole: 'user' } })
      useAppStore.setState({ app, currentPageId: 'home', isMultiUser: false })

      useAppStore.getState().navigateTo('adminPage')
      expect(useAppStore.getState().currentPageId).toBe('adminPage')
    })

    it('logged-out guest user → blocked from role-restricted pages', () => {
      // authService is a fresh guest (no record, not valid).
      const app = makeApp()
      useAppStore.setState({ app, currentPageId: 'home', isMultiUser: true })

      useAppStore.getState().navigateTo('adminPage')
      expect(useAppStore.getState().currentPageId).toBe('home')
    })
  })

  // -------------------------------------------------------------------------
  // B3-3: Session Timeout
  // -------------------------------------------------------------------------

  describe('B3-3: Session Timeout', () => {
    it('fresh auth → isSessionExpired() === false', () => {
      expect(authService.isSessionExpired()).toBe(false)
    })

    it('recordActivity() updates _lastActivity timestamp', () => {
      const before = (authService as any)._lastActivity as number
      // Advance real time slightly using fake timers.
      vi.useFakeTimers()
      vi.setSystemTime(Date.now() + 5000)
      authService.recordActivity()
      const after = (authService as any)._lastActivity as number
      expect(after).toBeGreaterThan(before)
      vi.useRealTimers()
    })

    it('manually set _lastActivity to 31 min ago → isSessionExpired() === true', () => {
      ;(authService as any)._lastActivity = Date.now() - 31 * 60 * 1000
      expect(authService.isSessionExpired()).toBe(true)
    })

    it('29 min ago → session NOT yet expired (boundary)', () => {
      ;(authService as any)._lastActivity = Date.now() - 29 * 60 * 1000
      expect(authService.isSessionExpired()).toBe(false)
    })

    it('session expired + recordActivity → not expired again', () => {
      ;(authService as any)._lastActivity = Date.now() - 40 * 60 * 1000
      expect(authService.isSessionExpired()).toBe(true)
      authService.recordActivity()
      expect(authService.isSessionExpired()).toBe(false)
    })

    it('reset auth service → activity timestamp reset', () => {
      ;(authService as any)._lastActivity = Date.now() - 40 * 60 * 1000
      expect(authService.isSessionExpired()).toBe(true)
      authService.reset()
      expect(authService.isSessionExpired()).toBe(false)
    })
  })

  // -------------------------------------------------------------------------
  // B3-4: Login Rate Limiting
  // -------------------------------------------------------------------------

  describe('B3-4: Login Rate Limiting', () => {
    beforeEach(() => {
      // Silence [SECURITY] info logs during these tests.
      vi.spyOn(console, 'info').mockImplementation(() => {})
    })

    afterEach(() => {
      vi.restoreAllMocks()
    })

    it('5 failed logins → 6th throws "Too many attempts"', async () => {
      const failAuth = vi.fn(async () => { throw new Error('bad creds') })
      const pb = mockPb({ authWithPassword: failAuth })
      const auth = new AuthService(pb)

      for (let i = 0; i < 5; i++) {
        const ok = await auth.login('user@x.com', 'wrong')
        expect(ok).toBe(false)
      }

      await expect(auth.login('user@x.com', 'wrong'))
        .rejects.toThrow(/Too many attempts/)
    })

    it('successful login clears the counter', async () => {
      let shouldFail = true
      const authFn = vi.fn(async () => {
        if (shouldFail) throw new Error('bad creds')
        return { record: { id: 'u1' } }
      })
      const pb = mockPb({ authWithPassword: authFn })
      const auth = new AuthService(pb)

      // 4 failures
      for (let i = 0; i < 4; i++) {
        await auth.login('user@x.com', 'wrong')
      }

      // Succeed — counter resets
      shouldFail = false
      const success = await auth.login('user@x.com', 'correct')
      expect(success).toBe(true)

      // Now we can fail 5 more times without hitting the limit on attempt #6.
      shouldFail = true
      for (let i = 0; i < 5; i++) {
        const ok = await auth.login('user@x.com', 'wrong')
        expect(ok).toBe(false)
      }
      // 6th should throw
      await expect(auth.login('user@x.com', 'wrong'))
        .rejects.toThrow(/Too many attempts/)
    })

    it('attempts reset after 5 min delay (time-mocked)', async () => {
      vi.useFakeTimers()
      try {
        const failAuth = vi.fn(async () => { throw new Error('bad creds') })
        const pb = mockPb({ authWithPassword: failAuth })
        const auth = new AuthService(pb)

        // Record 5 failed attempts at t0.
        for (let i = 0; i < 5; i++) {
          await auth.login('user@x.com', 'wrong')
        }
        // 6th should throw
        await expect(auth.login('user@x.com', 'wrong'))
          .rejects.toThrow(/Too many attempts/)

        // Advance clock 6 minutes — prior attempts should roll off.
        vi.setSystemTime(Date.now() + 6 * 60 * 1000)

        // Now the 7th call should NOT throw — just return false.
        const ok = await auth.login('user@x.com', 'wrong')
        expect(ok).toBe(false)
      } finally {
        vi.useRealTimers()
      }
    })

    it('different emails tracked independently', async () => {
      const failAuth = vi.fn(async () => { throw new Error('bad creds') })
      const pb = mockPb({ authWithPassword: failAuth })
      const auth = new AuthService(pb)

      // 5 failed for user A
      for (let i = 0; i < 5; i++) {
        await auth.login('a@x.com', 'wrong')
      }
      // user A is rate limited
      await expect(auth.login('a@x.com', 'wrong'))
        .rejects.toThrow(/Too many attempts/)

      // user B still has a clean slate
      const ok = await auth.login('b@x.com', 'wrong')
      expect(ok).toBe(false) // failed but not rate-limited
    })

    it('case-insensitive email tracking: User@X.com & user@x.com share counter', async () => {
      const failAuth = vi.fn(async () => { throw new Error('bad creds') })
      const pb = mockPb({ authWithPassword: failAuth })
      const auth = new AuthService(pb)

      // 3 failures as User@X.com
      for (let i = 0; i < 3; i++) {
        await auth.login('User@X.com', 'wrong')
      }
      // 2 more as user@x.com — total should be 5
      for (let i = 0; i < 2; i++) {
        await auth.login('user@x.com', 'wrong')
      }
      // 6th attempt in any casing should trip the limiter
      await expect(auth.login('USER@x.COM', 'wrong'))
        .rejects.toThrow(/Too many attempts/)
    })
  })

  // -------------------------------------------------------------------------
  // B3-5: Rate Limit Security Logging
  // -------------------------------------------------------------------------

  describe('B3-5: Rate Limit Security Logging', () => {
    let infoSpy: ReturnType<typeof vi.spyOn>

    beforeEach(() => {
      infoSpy = vi.spyOn(console, 'info').mockImplementation(() => {})
    })

    afterEach(() => {
      infoSpy.mockRestore()
    })

    it('rate limit triggers a [SECURITY] Rate limit triggered: console.info', async () => {
      const failAuth = vi.fn(async () => { throw new Error('bad creds') })
      const pb = mockPb({ authWithPassword: failAuth })
      const auth = new AuthService(pb)

      for (let i = 0; i < 5; i++) {
        await auth.login('user@x.com', 'wrong')
      }

      infoSpy.mockClear()
      await expect(auth.login('user@x.com', 'wrong'))
        .rejects.toThrow(/Too many attempts/)

      const combined = infoSpy.mock.calls.map(c => c.join(' ')).join('\n')
      expect(combined).toMatch(/\[SECURITY\]\s+Rate limit triggered/i)
    })

    it('login success logs [SECURITY] Login success:', async () => {
      const authFn = vi.fn(async () => ({ record: { id: 'u1' } }))
      const pb = mockPb({ authWithPassword: authFn })
      const auth = new AuthService(pb)

      await auth.login('user@x.com', 'correct')

      const combined = infoSpy.mock.calls.map(c => c.join(' ')).join('\n')
      expect(combined).toMatch(/\[SECURITY\]\s+Login success/i)
    })

    it('login failure logs [SECURITY] Login failure:', async () => {
      const authFn = vi.fn(async () => { throw new Error('bad creds') })
      const pb = mockPb({ authWithPassword: authFn })
      const auth = new AuthService(pb)

      await auth.login('user@x.com', 'wrong')

      const combined = infoSpy.mock.calls.map(c => c.join(' ')).join('\n')
      expect(combined).toMatch(/\[SECURITY\]\s+Login failure/i)
    })
  })

  // -------------------------------------------------------------------------
  // B3-6: Current Roles with Invalid Data
  // -------------------------------------------------------------------------

  describe('B3-6: Current Roles with Invalid Data', () => {
    it('array of strings in PB record → returned as-is, lowercased', () => {
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: ['admin', 'editor'] } })
      const auth = new AuthService(pb)
      expect(auth.currentRoles).toEqual(['admin', 'editor'])
    })

    it('JSON string \'["admin"]\' → parsed and returned lowercased', () => {
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: '["admin"]' } })
      const auth = new AuthService(pb)
      expect(auth.currentRoles).toEqual(['admin'])
    })

    it('non-JSON string "admin" → falls back to ["user"]', () => {
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: 'admin' } })
      const auth = new AuthService(pb)
      expect(auth.currentRoles).toEqual(['user'])
    })

    it('null roles → ["user"] default', () => {
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: null } })
      const auth = new AuthService(pb)
      expect(auth.currentRoles).toEqual(['user'])
    })

    it('undefined roles (missing field) → ["user"] default', () => {
      const pb = mockPb({ isValid: true, record: { id: 'u1' } })
      const auth = new AuthService(pb)
      expect(auth.currentRoles).toEqual(['user'])
    })

    it('superadmin → ["admin","user"] regardless of record state', () => {
      // Even with weird record data, superadmin short-circuits.
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: ['weird'] } })
      const auth = new AuthService(pb)
      auth.setSuperAdmin(true)
      expect(auth.currentRoles).toEqual(['admin', 'user'])
    })

    it('guest (not logged in) → ["guest"]', () => {
      const pb = mockPb({ isValid: false, record: null })
      const auth = new AuthService(pb)
      expect(auth.currentRoles).toEqual(['guest'])
    })

    it('roles array with non-string values [1, true, "admin"] → filtered to ["admin"]', () => {
      const pb = mockPb({
        isValid: true,
        record: { id: 'u1', roles: [1, true, 'admin', null, undefined, {}, 'editor'] },
      })
      const auth = new AuthService(pb)
      expect(auth.currentRoles).toEqual(['admin', 'editor'])
    })

    it('empty array roles: [] → returned as-is (empty)', () => {
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: [] } })
      const auth = new AuthService(pb)
      expect(auth.currentRoles).toEqual([])
    })

    it('roles with mixed case ["Admin", "USER"] → normalized to ["admin", "user"]', () => {
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: ['Admin', 'USER'] } })
      const auth = new AuthService(pb)
      expect(auth.currentRoles).toEqual(['admin', 'user'])
    })

    it('JSON string with mixed-case roles normalizes to lowercase', () => {
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: '["Admin","Viewer"]' } })
      const auth = new AuthService(pb)
      expect(auth.currentRoles).toEqual(['admin', 'viewer'])
    })

    it('JSON string that parses to a non-array (e.g. "42") → ["user"] fallback', () => {
      const pb = mockPb({ isValid: true, record: { id: 'u1', roles: '42' } })
      const auth = new AuthService(pb)
      expect(auth.currentRoles).toEqual(['user'])
    })
  })
})

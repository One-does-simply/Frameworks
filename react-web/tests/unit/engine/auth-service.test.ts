import { describe, it, expect, beforeEach } from 'vitest'
import { AuthService } from '../../../src/engine/auth-service.ts'

// ===========================================================================
// AuthService unit tests — role checks and access control
//
// Uses a minimal PocketBase mock: just authStore with record and isValid.
// ===========================================================================

function mockPb(overrides: {
  isValid?: boolean
  record?: Record<string, unknown> | null
} = {}) {
  return {
    authStore: {
      isValid: overrides.isValid ?? false,
      record: overrides.record ?? null,
    },
    collection: () => ({
      listAuthMethods: async () => ({ oauth2: { providers: [] } }),
      getList: async () => ({ items: [] }),
      authWithPassword: async () => { throw new Error('mock') },
    }),
  } as any
}

describe('AuthService', () => {
  let auth: AuthService

  beforeEach(() => {
    auth = new AuthService(mockPb())
  })

  // -------------------------------------------------------------------------
  // SuperAdmin
  // -------------------------------------------------------------------------

  describe('superAdmin', () => {
    it('defaults to not superAdmin', () => {
      expect(auth.isSuperAdmin).toBe(false)
    })

    it('can be set to superAdmin', () => {
      auth.setSuperAdmin(true)
      expect(auth.isSuperAdmin).toBe(true)
    })

    it('superAdmin is logged in', () => {
      auth.setSuperAdmin(true)
      expect(auth.isLoggedIn).toBe(true)
    })

    it('superAdmin username is admin', () => {
      auth.setSuperAdmin(true)
      expect(auth.currentUsername).toBe('admin')
    })

    it('superAdmin display name is Admin', () => {
      auth.setSuperAdmin(true)
      expect(auth.currentDisplayName).toBe('Admin')
    })

    it('superAdmin has admin and user roles', () => {
      auth.setSuperAdmin(true)
      expect(auth.currentRoles).toEqual(['admin', 'user'])
    })

    it('superAdmin is admin', () => {
      auth.setSuperAdmin(true)
      expect(auth.isAdmin).toBe(true)
    })
  })

  // -------------------------------------------------------------------------
  // Guest (no auth)
  // -------------------------------------------------------------------------

  describe('guest', () => {
    it('guest is not logged in', () => {
      expect(auth.isLoggedIn).toBe(false)
    })

    it('guest is guest', () => {
      expect(auth.isGuest).toBe(true)
    })

    it('guest username is guest', () => {
      expect(auth.currentUsername).toBe('guest')
    })

    it('guest has guest role', () => {
      expect(auth.currentRoles).toEqual(['guest'])
    })

    it('guest is not admin', () => {
      expect(auth.isAdmin).toBe(false)
    })
  })

  // -------------------------------------------------------------------------
  // Authenticated user
  // -------------------------------------------------------------------------

  describe('authenticated user', () => {
    it('logged-in user with valid auth store', () => {
      const pb = mockPb({
        isValid: true,
        record: { id: 'user1', username: 'jane', email: 'jane@test.com', roles: ['user'] },
      })
      auth = new AuthService(pb)
      expect(auth.isLoggedIn).toBe(true)
      expect(auth.isGuest).toBe(false)
    })

    it('reads roles from record array', () => {
      const pb = mockPb({
        isValid: true,
        record: { id: 'u1', roles: ['admin', 'editor'] },
      })
      auth = new AuthService(pb)
      expect(auth.currentRoles).toEqual(['admin', 'editor'])
    })

    it('parses roles from JSON string', () => {
      const pb = mockPb({
        isValid: true,
        record: { id: 'u1', roles: '["viewer","admin"]' },
      })
      auth = new AuthService(pb)
      expect(auth.currentRoles).toEqual(['viewer', 'admin'])
    })

    it('defaults to user role when roles field is missing', () => {
      const pb = mockPb({
        isValid: true,
        record: { id: 'u1' },
      })
      auth = new AuthService(pb)
      expect(auth.currentRoles).toEqual(['user'])
    })

    it('defaults to user role for invalid JSON string roles', () => {
      const pb = mockPb({
        isValid: true,
        record: { id: 'u1', roles: 'not-json' },
      })
      auth = new AuthService(pb)
      expect(auth.currentRoles).toEqual(['user'])
    })

    it('reads username from record', () => {
      const pb = mockPb({
        isValid: true,
        record: { id: 'u1', username: 'janedoe' },
      })
      auth = new AuthService(pb)
      expect(auth.currentUsername).toBe('janedoe')
    })

    it('reads email from record', () => {
      const pb = mockPb({
        isValid: true,
        record: { id: 'u1', email: 'jane@test.com' },
      })
      auth = new AuthService(pb)
      expect(auth.currentEmail).toBe('jane@test.com')
    })

    it('reads currentUserId from record', () => {
      const pb = mockPb({
        isValid: true,
        record: { id: 'user123' },
      })
      auth = new AuthService(pb)
      expect(auth.currentUserId).toBe('user123')
    })
  })

  // -------------------------------------------------------------------------
  // hasAccess — role-based access control
  // -------------------------------------------------------------------------

  describe('hasAccess', () => {
    it('grants access when no roles required', () => {
      expect(auth.hasAccess(undefined)).toBe(true)
      expect(auth.hasAccess([])).toBe(true)
    })

    it('superAdmin always has access', () => {
      auth.setSuperAdmin(true)
      expect(auth.hasAccess(['admin'])).toBe(true)
      expect(auth.hasAccess(['editor'])).toBe(true)
      expect(auth.hasAccess(['anything'])).toBe(true)
    })

    it('admin role grants access to any role-restricted resource', () => {
      const pb = mockPb({
        isValid: true,
        record: { id: 'u1', roles: ['admin'] },
      })
      auth = new AuthService(pb)
      expect(auth.hasAccess(['editor'])).toBe(true)
      expect(auth.hasAccess(['viewer'])).toBe(true)
    })

    it('regular user with matching role has access', () => {
      const pb = mockPb({
        isValid: true,
        record: { id: 'u1', roles: ['editor'] },
      })
      auth = new AuthService(pb)
      expect(auth.hasAccess(['editor'])).toBe(true)
    })

    it('regular user without matching role is denied', () => {
      const pb = mockPb({
        isValid: true,
        record: { id: 'u1', roles: ['viewer'] },
      })
      auth = new AuthService(pb)
      expect(auth.hasAccess(['admin'])).toBe(false)
    })

    it('guest is denied access to role-restricted resource', () => {
      expect(auth.hasAccess(['user'])).toBe(false)
    })

    it('user with multiple roles, one matching', () => {
      const pb = mockPb({
        isValid: true,
        record: { id: 'u1', roles: ['viewer', 'editor'] },
      })
      auth = new AuthService(pb)
      expect(auth.hasAccess(['editor', 'manager'])).toBe(true)
    })

    it('user with multiple roles, none matching', () => {
      const pb = mockPb({
        isValid: true,
        record: { id: 'u1', roles: ['viewer'] },
      })
      auth = new AuthService(pb)
      expect(auth.hasAccess(['editor', 'manager'])).toBe(false)
    })
  })

  // -------------------------------------------------------------------------
  // Initialization
  // -------------------------------------------------------------------------

  describe('initialization', () => {
    it('is not initialized by default', () => {
      expect(auth.isInitialized).toBe(false)
    })

    it('isAdminSetUp defaults to false', () => {
      expect(auth.isAdminSetUp).toBe(false)
    })

    it('oauthProviders defaults to empty', () => {
      expect(auth.oauthProviders).toEqual([])
    })
  })
})

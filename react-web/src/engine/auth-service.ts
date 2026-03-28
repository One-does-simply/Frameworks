import type PocketBase from 'pocketbase'

/**
 * Authentication and role-based access control using PocketBase auth.
 *
 * ODS Ethos: The framework handles all auth complexity. Builders just add
 * `"roles": ["admin"]` to their spec elements, and AuthService makes it work.
 *
 * PocketBase handles password hashing, tokens, and sessions natively.
 * ODS roles are stored as a JSON array field on the user record.
 */
export class AuthService {
  private pb: PocketBase
  private _isAdminSetUp = false
  private _isInitialized = false
  /** When true, the PocketBase superadmin is running this app — bypass all role checks. */
  private _isSuperAdmin = false

  constructor(pb: PocketBase) {
    this.pb = pb
  }

  /** Mark that the PocketBase superadmin is operating this app. */
  setSuperAdmin(value: boolean): void {
    this._isSuperAdmin = value
  }

  get isSuperAdmin(): boolean { return this._isSuperAdmin }

  // ---------------------------------------------------------------------------
  // Public getters
  // ---------------------------------------------------------------------------

  get isInitialized(): boolean { return this._isInitialized }
  get isLoggedIn(): boolean { return this._isSuperAdmin || this.pb.authStore.isValid }
  get isGuest(): boolean { return !this.isLoggedIn }

  get currentUserId(): string | undefined {
    return this.pb.authStore.record?.id
  }

  get currentUsername(): string {
    if (this._isSuperAdmin) return 'admin'
    return (this.pb.authStore.record?.['username'] as string) ?? 'guest'
  }

  get currentDisplayName(): string {
    if (this._isSuperAdmin) return 'Admin'
    return (this.pb.authStore.record?.['displayName'] as string) ?? this.currentUsername
  }

  get currentEmail(): string {
    if (this._isSuperAdmin) {
      return (this.pb.authStore.record?.['email'] as string)
        ?? localStorage.getItem('ods_pb_admin_email')
        ?? ''
    }
    return (this.pb.authStore.record?.['email'] as string) ?? ''
  }

  get currentRoles(): string[] {
    if (this._isSuperAdmin) return ['admin', 'user']
    if (this.isGuest) return ['guest']
    const roles = this.pb.authStore.record?.['roles']
    if (Array.isArray(roles)) return roles as string[]
    if (typeof roles === 'string') {
      try { return JSON.parse(roles) } catch { return ['user'] }
    }
    return ['user']
  }

  get isAdmin(): boolean {
    return this.currentRoles.includes('admin')
  }

  get isAdminSetUp(): boolean {
    return this._isAdminSetUp
  }

  // ---------------------------------------------------------------------------
  // Core permission check
  // ---------------------------------------------------------------------------

  /**
   * Checks whether the current user has access to an element with the given
   * role restriction.
   *
   * Returns true when:
   *   - requiredRoles is null/undefined or empty (no restriction)
   *   - The current user is an admin (admin bypasses all restrictions)
   *   - The current user has at least one matching role
   */
  hasAccess(requiredRoles: string[] | undefined): boolean {
    if (!requiredRoles || requiredRoles.length === 0) return true
    if (this._isSuperAdmin) return true
    if (this.isAdmin) return true
    return this.currentRoles.some(r => requiredRoles.includes(r))
  }

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /**
   * Initializes the auth service: ensures users collection has roles field,
   * and checks if an admin user exists.
   */
  async initialize(): Promise<void> {
    try {
      // Check if any user with admin role exists
      const admins = await this.pb.collection('users').getFullList({
        filter: 'roles ~ "admin"',
      })
      this._isAdminSetUp = admins.length > 0
    } catch {
      // Users collection may not exist or roles field may not be set up
      this._isAdminSetUp = false
    }
    this._isInitialized = true
  }

  // ---------------------------------------------------------------------------
  // Authentication operations
  // ---------------------------------------------------------------------------

  /** Attempt to log in with username + password. Returns true on success. */
  async login(username: string, password: string): Promise<boolean> {
    try {
      await this.pb.collection('users').authWithPassword(username, password)
      return true
    } catch {
      return false
    }
  }

  /** Log out the current user. */
  logout(): void {
    this.pb.authStore.clear()
  }

  /**
   * Create the initial admin account. Called from the admin setup wizard.
   * Creates a PocketBase user with admin + user roles.
   */
  async setupAdmin(username: string, password: string): Promise<boolean> {
    try {
      await this.pb.collection('users').create({
        username,
        password,
        passwordConfirm: password,
        email: `${username}@ods.local`,
        displayName: username,
        roles: JSON.stringify(['admin', 'user']),
      })

      // Auto-login as the new admin
      await this.pb.collection('users').authWithPassword(username, password)
      this._isAdminSetUp = true
      return true
    } catch (e) {
      console.error('ODS AuthService: Admin setup failed:', e)
      return false
    }
  }

  /** Register a new user with the given role. Returns user ID on success. */
  async registerUser(params: {
    username: string
    password: string
    role: string
    displayName?: string
  }): Promise<string | null> {
    try {
      const roles = [params.role]
      if (params.role !== 'user' && params.role !== 'guest') {
        roles.push('user')
      }

      const record = await this.pb.collection('users').create({
        username: params.username,
        password: params.password,
        passwordConfirm: params.password,
        email: `${params.username}@ods.local`,
        displayName: params.displayName ?? params.username,
        roles: JSON.stringify(roles),
      })

      return record.id
    } catch (e) {
      console.error('ODS AuthService: Registration failed:', e)
      return null
    }
  }

  /** Change password for a user. */
  async changePassword(userId: string, newPassword: string): Promise<boolean> {
    try {
      await this.pb.collection('users').update(userId, {
        password: newPassword,
        passwordConfirm: newPassword,
      })
      return true
    } catch {
      return false
    }
  }

  /** List all users (admin operation). */
  async listUsers(): Promise<Record<string, unknown>[]> {
    try {
      const records = await this.pb.collection('users').getFullList({ sort: 'created' })
      return records.map(r => ({
        _id: r.id,
        username: r['username'],
        displayName: r['displayName'] ?? r['username'],
        roles: (() => {
          const roles = r['roles']
          if (Array.isArray(roles)) return roles
          if (typeof roles === 'string') {
            try { return JSON.parse(roles) } catch { return [] }
          }
          return []
        })(),
        _createdAt: r.created,
      }))
    } catch {
      return []
    }
  }

  /** Delete a user by ID. */
  async deleteUser(userId: string): Promise<void> {
    await this.pb.collection('users').delete(userId)
  }

  /** Assign a role to a user. */
  async assignRole(userId: string, role: string): Promise<void> {
    const user = await this.pb.collection('users').getOne(userId)
    let roles: string[] = []
    try { roles = JSON.parse(user['roles'] as string) } catch { /* empty */ }
    if (!roles.includes(role)) {
      roles.push(role)
      await this.pb.collection('users').update(userId, {
        roles: JSON.stringify(roles),
      })
    }
  }

  /** Remove a role from a user. */
  async removeRole(userId: string, role: string): Promise<void> {
    const user = await this.pb.collection('users').getOne(userId)
    let roles: string[] = []
    try { roles = JSON.parse(user['roles'] as string) } catch { /* empty */ }
    roles = roles.filter(r => r !== role)
    await this.pb.collection('users').update(userId, {
      roles: JSON.stringify(roles),
    })
  }

  /** Reset to initial state. */
  reset(): void {
    this.pb.authStore.clear()
    this._isAdminSetUp = false
    this._isInitialized = false
  }
}

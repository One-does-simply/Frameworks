import type PocketBase from 'pocketbase'
import { warn, error } from './log-service.ts'

/**
 * Authentication and role-based access control using PocketBase auth.
 *
 * ODS Ethos: The framework handles all auth complexity. Builders just add
 * `"roles": ["admin"]` to their spec elements, and AuthService makes it work.
 *
 * PocketBase handles password hashing, tokens, and sessions natively.
 * ODS roles are stored as a JSON array field on the user record.
 *
 * Login uses email as the primary identifier. OAuth2 providers configured
 * in PocketBase are automatically discovered and shown on the login screen.
 */
export class AuthService {
  private pb: PocketBase
  private _isAdminSetUp = false
  private _isInitialized = false
  /** When true, the PocketBase superadmin is running this app — bypass all role checks. */
  private _isSuperAdmin = false
  /** Cached list of OAuth2 providers configured in PocketBase. */
  private _oauthProviders: OAuthProvider[] = []

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
    return (this.pb.authStore.record?.['displayName'] as string)
      ?? (this.pb.authStore.record?.['name'] as string)
      ?? this.currentEmail
      ?? this.currentUsername
  }

  get currentEmail(): string {
    if (this._isSuperAdmin) {
      return (this.pb.authStore.record?.['email'] as string) ?? ''
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

  /** Returns the list of OAuth2 providers configured in PocketBase. */
  get oauthProviders(): OAuthProvider[] {
    return this._oauthProviders
  }

  // ---------------------------------------------------------------------------
  // Core permission check
  // ---------------------------------------------------------------------------

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
   * Initializes the auth service: discovers OAuth2 providers,
   * checks if an admin user exists.
   */
  async initialize(): Promise<void> {
    // Check if any user with admin role exists.
    // The roles filter may 400 if the field doesn't exist yet — fall back
    // to listing all users and checking manually.
    try {
      let foundAdmin = false
      try {
        const admins = await this.pb.collection('users').getFullList({
          filter: 'roles ~ "admin"',
          requestKey: null,
        })
        foundAdmin = admins.length > 0
      } catch {
        // roles field may not exist — check all users manually
        try {
          const allUsers = await this.pb.collection('users').getFullList({ requestKey: null })
          foundAdmin = allUsers.some((u) => {
            const roles = u['roles']
            if (typeof roles === 'string') return roles.includes('admin')
            if (Array.isArray(roles)) return (roles as string[]).includes('admin')
            return false
          })
        } catch {
          // Users collection may not exist
        }
      }
      this._isAdminSetUp = foundAdmin
    } catch {
      this._isAdminSetUp = false
    }

    // Discover OAuth2 providers configured in PocketBase
    try {
      const methods = await this.pb.collection('users').listAuthMethods({ requestKey: null } as Record<string, unknown>)
      this._oauthProviders = (methods.oauth2?.providers ?? []).map((p) => ({
        name: p.name as string,
        displayName: p.displayName as string ?? p.name as string,
        state: p.state as string,
        authURL: p.authURL as string,
        codeVerifier: p.codeVerifier as string,
        codeChallenge: p.codeChallenge as string,
        codeChallengeMethod: p.codeChallengeMethod as string,
      }))
    } catch {
      this._oauthProviders = []
    }

    this._isInitialized = true
  }

  // ---------------------------------------------------------------------------
  // Authentication operations
  // ---------------------------------------------------------------------------

  /** Attempt to log in with email + password. Returns true on success. */
  async login(email: string, password: string): Promise<boolean> {
    try {
      await this.pb.collection('users').authWithPassword(email, password)
      return true
    } catch {
      return false
    }
  }

  /**
   * Start OAuth2 redirect flow. Saves state to localStorage and redirects
   * the browser to the provider's auth URL. After the user authenticates,
   * PocketBase redirects back to our app where completeOAuth2() finishes
   * the flow.
   */
  async startOAuth2Redirect(providerName: string): Promise<void> {
    try {
      const methods = await this.pb.collection('users').listAuthMethods({ requestKey: null } as Record<string, unknown>)
      const provider = (methods.oauth2?.providers ?? []).find(
        (p) => p.name === providerName,
      )
      if (!provider) {
        warn('AuthService', `OAuth2 provider "${providerName}" not found`)
        return
      }

      // Save provider state for the callback
      localStorage.setItem('ods_oauth2_provider', providerName)
      localStorage.setItem('ods_oauth2_state', provider.state as string)
      localStorage.setItem('ods_oauth2_codeVerifier', provider.codeVerifier as string)
      localStorage.setItem('ods_oauth2_returnUrl', window.location.href)

      // Redirect to provider — use our app's callback URL (not PB's built-in one)
      const redirectUrl = `${window.location.origin}/oauth2-callback`
      const authUrl = (provider.authURL as string) + encodeURIComponent(redirectUrl)

      window.location.href = authUrl
    } catch (e) {
      error('AuthService', 'OAuth2 redirect failed', e)
    }
  }

  /**
   * Complete the OAuth2 flow after the provider redirects back.
   * Extracts the code from URL params and exchanges it for a PB auth token.
   * Returns true on success.
   */
  async completeOAuth2(code: string, state: string): Promise<boolean> {
    try {
      const savedProvider = localStorage.getItem('ods_oauth2_provider') ?? ''
      const savedState = localStorage.getItem('ods_oauth2_state') ?? ''
      const codeVerifier = localStorage.getItem('ods_oauth2_codeVerifier') ?? ''

      if (state !== savedState) {
        warn('AuthService', 'OAuth2 state mismatch')
        return false
      }

      const redirectUrl = `${window.location.origin}/oauth2-callback`

      const result = await this.pb.collection('users').authWithOAuth2Code(
        savedProvider,
        code,
        codeVerifier,
        redirectUrl,
        {},  // createData
        {},  // body
        { requestKey: null },  // prevent auto-cancellation
      )

      // Ensure the OAuth user has roles set (new users won't have them)
      const roles = result.record['roles']
      if (!roles || roles === '[]' || roles === '') {
        await this.pb.collection('users').update(result.record.id, {
          roles: JSON.stringify(['user']),
        })
        await this.pb.collection('users').authRefresh()
      }

      // Clean up localStorage
      localStorage.removeItem('ods_oauth2_provider')
      localStorage.removeItem('ods_oauth2_state')
      localStorage.removeItem('ods_oauth2_codeVerifier')

      return true
    } catch (e) {
      error('AuthService', 'OAuth2 code exchange failed', e)
      return false
    }
  }

  /** Get the saved return URL after OAuth2 callback. */
  static getOAuth2ReturnUrl(): string | null {
    const url = localStorage.getItem('ods_oauth2_returnUrl')
    localStorage.removeItem('ods_oauth2_returnUrl')
    return url
  }

  /** Log out the current user. */
  logout(): void {
    this.pb.authStore.clear()
  }

  /**
   * Create the initial admin account. Called from the admin setup wizard.
   * Creates a PocketBase user with admin + user roles.
   */
  async setupAdmin(email: string, password: string, displayName?: string): Promise<boolean> {
    try {
      // Reject if email matches PocketBase superadmin — they are separate identity stores
      const pbAdminEmail = (this.pb.authStore.record?.['email'] as string) ?? ''
      if (pbAdminEmail && email.toLowerCase() === pbAdminEmail.toLowerCase()) {
        warn('AuthService', 'Cannot create app user with same email as PocketBase superadmin')
        return false
      }

      // Generate a username from the email (before @)
      const username = email.split('@')[0].replace(/[^\w]/g, '_').toLowerCase()

      await this.pb.collection('users').create({
        username,
        password,
        passwordConfirm: password,
        email,
        displayName: displayName ?? username,
        roles: JSON.stringify(['admin', 'user']),
      })

      // Auto-login as the new admin
      await this.pb.collection('users').authWithPassword(email, password)
      this._isAdminSetUp = true
      return true
    } catch (e) {
      error('AuthService', 'Admin setup failed', e)
      return false
    }
  }

  /** Register a new user with the given role. Returns user ID on success. */
  async registerUser(params: {
    email: string
    password: string
    role: string
    displayName?: string
  }): Promise<string | null> {
    try {
      // Reject if email matches PocketBase superadmin
      const pbAdminEmail = (this.pb.authStore.record?.['email'] as string) ?? ''
      if (pbAdminEmail && params.email.toLowerCase() === pbAdminEmail.toLowerCase()) {
        warn('AuthService', 'Cannot register with PocketBase superadmin email')
        return null
      }

      const roles = [params.role]
      if (params.role !== 'user' && params.role !== 'guest') {
        roles.push('user')
      }

      // Generate username from email
      const username = params.email.split('@')[0].replace(/[^\w]/g, '_').toLowerCase()
        + '_' + Math.random().toString(36).slice(2, 6)

      const record = await this.pb.collection('users').create({
        username,
        password: params.password,
        passwordConfirm: params.password,
        email: params.email,
        displayName: params.displayName ?? params.email.split('@')[0],
        roles: JSON.stringify(roles),
      })

      return record.id
    } catch (e) {
      error('AuthService', 'Registration failed', e)
      return null
    }
  }

  /**
   * Validate a password against PocketBase requirements.
   * Returns null if valid, or an error message string.
   */
  static validatePassword(password: string): string | null {
    if (password.length < 8) return 'Password must be at least 8 characters.'
    if (password.length > 72) return 'Password must be 72 characters or fewer.'
    return null
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
      const records = await this.pb.collection('users').getFullList({ sort: 'created', requestKey: null })
      return records.map(r => ({
        _id: r.id,
        username: r['username'],
        email: r['email'] ?? '',
        displayName: r['displayName'] ?? r['name'] ?? r['email'] ?? r['username'],
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
    this._isSuperAdmin = false
    this._oauthProviders = []
  }
}

/** Describes an OAuth2 provider discovered from PocketBase. */
export interface OAuthProvider {
  name: string
  displayName: string
  state: string
  authURL: string
  codeVerifier: string
  codeChallenge: string
  codeChallengeMethod: string
}

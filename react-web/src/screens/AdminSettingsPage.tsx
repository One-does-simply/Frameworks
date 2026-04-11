import { useState, useEffect, useCallback } from 'react'
import { useNavigate } from 'react-router'
import { AuthService } from '@/engine/auth-service.ts'
import pb from '@/lib/pocketbase.ts'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Separator } from '@/components/ui/separator'
import {
  Table,
  TableHeader,
  TableBody,
  TableHead,
  TableRow,
  TableCell,
} from '@/components/ui/table'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { ThemePicker } from '@/components/ThemePicker.tsx'
import {
  getThemeMode,
  setThemeMode,
  type ThemeMode,
} from '@/engine/theme-store.ts'
import {
  getBackupSettings,
  setBackupSettings,
  type BackupSettings,
} from '@/engine/backup-service.ts'
import {
  getLogSettings,
  setLogSettings,
  downloadLogs,
  clearLogs,
  exportLogsAsText,
  getLogCount,
  logError,
  type LogSettings,
  type LogLevel,
} from '@/engine/log-service.ts'
import {
  getDefaultAppSlug,
  setDefaultAppSlug,
} from '@/engine/default-app-store.ts'
import { AppRegistry, type AppRecord } from '@/engine/app-registry.ts'
import { toast } from 'sonner'
import {
  ArrowLeft,
  Sun,
  Moon,
  Monitor,
  ExternalLink,
  Database,
  Loader2,
  UserPlus,
  KeyRound,
  Trash2,
  Shield,
} from 'lucide-react'
import {
  AlertDialog,
  AlertDialogContent,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogAction,
  AlertDialogCancel,
} from '@/components/ui/alert-dialog'

// ---------------------------------------------------------------------------
// AdminSettingsPage — full settings page with framework, PB, and user sections
// ---------------------------------------------------------------------------

interface UserRecord {
  _id: string
  username: string
  email: string
  displayName: string
  roles: string[]
}

export function AdminSettingsPage() {
  const navigate = useNavigate()

  // Theme
  const [theme, setTheme] = useState<ThemeMode>(getThemeMode)

  // Backup
  const [backupSettings, setBackupState] = useState<BackupSettings>(getBackupSettings)

  // Logging
  const [logSettingsState, setLogSettingsState] = useState<LogSettings>(getLogSettings)
  const [logCount, setLogCount] = useState(getLogCount)

  // PocketBase
  const pbUrl = import.meta.env.VITE_POCKETBASE_URL ?? 'http://127.0.0.1:8090'
  const [newPbUrl, setNewPbUrl] = useState('')
  const [showPbDialog, setShowPbDialog] = useState(false)

  // Default app
  const [apps, setApps] = useState<AppRecord[]>([])
  const [defaultSlug, setDefaultSlugState] = useState<string | null>(getDefaultAppSlug)

  // Users
  const [authService] = useState(() => new AuthService(pb))
  const [users, setUsers] = useState<UserRecord[]>([])
  const [isLoadingUsers, setIsLoadingUsers] = useState(true)
  const [showAddUser, setShowAddUser] = useState(false)
  const [newEmail, setNewEmail] = useState('')
  const [newPassword, setNewPassword] = useState('')
  const [newRole, setNewRole] = useState('user')
  const [deleteTarget, setDeleteTarget] = useState<UserRecord | null>(null)
  const [resetTarget, setResetTarget] = useState<UserRecord | null>(null)
  const [resetPassword, setResetPassword] = useState('')

  // OAuth2 providers
  const [oauthProviders, setOauthProviders] = useState<OAuthProviderConfig[]>([])
  const [isLoadingOAuth, setIsLoadingOAuth] = useState(true)
  const [editingProvider, setEditingProvider] = useState<string | null>(null)
  const [providerClientId, setProviderClientId] = useState('')
  const [providerClientSecret, setProviderClientSecret] = useState('')

  const availableRoles = ['admin', 'user']

  // -------------------------------------------------------------------------
  // Load data
  // -------------------------------------------------------------------------

  const loadApps = useCallback(async () => {
    const registry = new AppRegistry(pb)
    const list = await registry.listApps()
    setApps(list.filter((a) => a.status === 'active'))
  }, [])

  const loadUsers = useCallback(async () => {
    setIsLoadingUsers(true)
    try {
      await authService.initialize()
      const rawUsers = await authService.listUsers()
      setUsers(
        rawUsers.map((u) => ({
          _id: u._id as string,
          username: (u.username as string) ?? '',
          email: (u.email as string) ?? '',
          displayName: (u.displayName as string) ?? (u.email as string) ?? (u.username as string) ?? '?',
          roles: (u.roles as string[]) ?? [],
        })),
      )
    } catch {
      setUsers([])
    }
    setIsLoadingUsers(false)
  }, [authService])

  const loadOAuthProviders = useCallback(async () => {
    setIsLoadingOAuth(true)
    try {
      // PocketBase 0.23+: OAuth2 providers are on the users collection, not global settings
      const collection = await pb.collections.getOne('users', { requestKey: null })
      const oauth2 = (collection as Record<string, unknown>)['oauth2'] as Record<string, unknown> | undefined
      const configuredProviders = (oauth2?.['providers'] ?? []) as Array<Record<string, unknown>>

      const providers: OAuthProviderConfig[] = KNOWN_OAUTH_PROVIDERS.map((known) => {
        const configured = configuredProviders.find((p) => p['name'] === known.id)
        return {
          id: known.id,
          displayName: known.displayName,
          enabled: !!configured?.['clientId'],
          clientId: (configured?.['clientId'] as string) ?? '',
          // PB doesn't return clientSecret in reads — if provider exists with clientId,
          // assume secret was set (user configured it via our dialog)
          hasSecret: !!configured?.['clientId'],
        }
      })
      setOauthProviders(providers)
    } catch (e) {
      logError('AdminSettings', 'Failed to load OAuth2 providers', e)
      setOauthProviders([])
    }
    setIsLoadingOAuth(false)
  }, [])

  useEffect(() => {
    loadApps()
    loadUsers()
    loadOAuthProviders()
  }, [loadApps, loadUsers, loadOAuthProviders])

  // -------------------------------------------------------------------------
  // Handlers
  // -------------------------------------------------------------------------

  function handleThemeChange(mode: ThemeMode) {
    setTheme(mode)
    setThemeMode(mode)
  }

  function handleDefaultAppChange(slug: string) {
    setDefaultAppSlug(slug)
    setDefaultSlugState(slug)
    toast.success('Default app updated')
  }

  function handleSwitchPb() {
    if (!newPbUrl.trim()) return
    // Store in localStorage so next page load uses this URL
    localStorage.setItem('ods_custom_pb_url', newPbUrl.trim())
    toast.success('PocketBase URL updated. Reloading...')
    setShowPbDialog(false)
    setTimeout(() => window.location.reload(), 500)
  }

  // OAuth2 handlers — read the full collection, modify oauth2, write back.
  // PocketBase stores oauth2 config at the collection level. We log the
  // shape on first read so we can debug mismatches across PB versions.

  // PocketBase does NOT return clientSecret in reads (security). So when
  // saving, we must only include clientSecret if the user entered a new one.
  // Otherwise PB keeps the existing secret untouched.

  async function getCollectionOAuth2(): Promise<{
    collectionId: string
    oauth2: Record<string, unknown>
    providers: Array<Record<string, unknown>>
  }> {
    const collection = await pb.collections.getOne('users', { requestKey: null })
    const raw = collection as Record<string, unknown>
    const oauth2 = (raw['oauth2'] ?? {}) as Record<string, unknown>
    const providers = ((oauth2['providers'] ?? []) as Array<Record<string, unknown>>).slice()
    return { collectionId: collection.id, oauth2, providers }
  }

  async function saveCollectionOAuth2(
    collectionId: string,
    oauth2Base: Record<string, unknown>,
    providers: Array<Record<string, unknown>>,
  ) {
    const hasProviders = providers.some((p) => !!p['clientId'])
    const updated = {
      ...oauth2Base,
      enabled: hasProviders,
      providers,
    }
    await pb.collections.update(collectionId, { oauth2: updated }, { requestKey: null })
  }

  async function handleSaveOAuthProvider() {
    if (!editingProvider) return
    try {
      const { collectionId, oauth2, providers } = await getCollectionOAuth2()
      const idx = providers.findIndex((p) => p['name'] === editingProvider)

      // Build the provider entry — only include clientSecret if user entered one
      const entry: Record<string, unknown> = {
        name: editingProvider,
        clientId: providerClientId,
      }
      if (providerClientSecret) {
        entry.clientSecret = providerClientSecret
      }
      // Keep all other existing fields (pkce, authURL, etc.) from the current entry
      if (idx >= 0) {
        providers[idx] = { ...providers[idx], ...entry }
      } else {
        providers.push(entry)
      }

      await saveCollectionOAuth2(collectionId, oauth2, providers)
      toast.success(`${editingProvider} provider configured`)
      setEditingProvider(null)
      setProviderClientId('')
      setProviderClientSecret('')
      await loadOAuthProviders()
    } catch (e) {
      logError('AdminSettings', 'OAuth2 save error', e)
      toast.error(`Failed to configure provider: ${e instanceof Error ? e.message : e}`)
    }
  }

  async function handleToggleOAuthProvider(providerId: string, enabled: boolean) {
    try {
      const { collectionId, oauth2, providers } = await getCollectionOAuth2()
      if (!enabled) {
        const idx = providers.findIndex((p) => p['name'] === providerId)
        if (idx >= 0) providers.splice(idx, 1)
      }
      await saveCollectionOAuth2(collectionId, oauth2, providers)
      toast.success(`${providerId} ${enabled ? 'enabled' : 'disabled'}`)
      await loadOAuthProviders()
    } catch (e) {
      logError('AdminSettings', 'OAuth2 toggle error', e)
      toast.error(`Failed to update provider: ${e instanceof Error ? e.message : e}`)
    }
  }

  // User management handlers
  async function handleAddUser() {
    if (!newEmail.trim() || !newPassword) return
    const pwError = AuthService.validatePassword(newPassword)
    if (pwError) { toast.error(pwError); return }
    const userId = await authService.registerUser({
      email: newEmail.trim(),
      password: newPassword,
      role: newRole,
    })
    if (userId) {
      setShowAddUser(false)
      setNewEmail('')
      setNewPassword('')
      setNewRole('user')
      await loadUsers()
      toast.success(`User "${newEmail.trim()}" created.`)
    } else {
      toast.error('Failed to create user. Email may already be in use.')
    }
  }

  async function handleDeleteUser() {
    if (!deleteTarget) return
    if (deleteTarget._id === authService.currentUserId) {
      toast.error('You cannot delete your own account.')
      setDeleteTarget(null)
      return
    }
    await authService.deleteUser(deleteTarget._id)
    setDeleteTarget(null)
    await loadUsers()
    toast.success(`User "${deleteTarget.username}" deleted.`)
  }

  async function handleResetPassword() {
    if (!resetTarget || !resetPassword) return
    const pwError = AuthService.validatePassword(resetPassword)
    if (pwError) { toast.error(pwError); return }
    const success = await authService.changePassword(resetTarget._id, resetPassword)
    if (success) {
      toast.success(`Password reset for ${resetTarget.username}.`)
    } else {
      toast.error('Failed to reset password.')
    }
    setResetTarget(null)
    setResetPassword('')
  }

  // Check if a user looks like the PocketBase superadmin
  const pbAdminEmail = (pb.authStore.record?.['email'] as string) ?? ''

  return (
    <div className="min-h-screen bg-background">
      {/* Top bar */}
      <header className="sticky top-0 z-40 flex h-14 items-center gap-3 border-b bg-background/95 px-4 supports-backdrop-filter:backdrop-blur-sm">
        <Button variant="ghost" size="icon-sm" onClick={() => navigate('/admin')}>
          <ArrowLeft className="size-5" />
        </Button>
        <h1 className="flex-1 text-base font-semibold">Settings</h1>
      </header>

      <div className="mx-auto max-w-3xl space-y-6 p-6">
        {/* ---- Framework Settings ---- */}
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Framework Settings</CardTitle>
            <CardDescription>ODS React Web Framework preferences</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {/* Light/Dark Mode */}
            <div className="flex items-center justify-between gap-4">
              <Label>Mode</Label>
              <div className="flex gap-1 rounded-lg border p-0.5">
                {([
                  { mode: 'light' as ThemeMode, icon: Sun, label: 'Light' },
                  { mode: 'system' as ThemeMode, icon: Monitor, label: 'System' },
                  { mode: 'dark' as ThemeMode, icon: Moon, label: 'Dark' },
                ]).map(({ mode, icon: Icon, label }) => (
                  <button
                    key={mode}
                    onClick={() => handleThemeChange(mode)}
                    className={`flex items-center gap-1.5 rounded-md px-3 py-1 text-xs font-medium transition-colors ${
                      theme === mode
                        ? 'bg-primary text-primary-foreground'
                        : 'text-muted-foreground hover:text-foreground'
                    }`}
                  >
                    <Icon className="size-3.5" />
                    {label}
                  </button>
                ))}
              </div>
            </div>

            <Separator />

            {/* Default Theme for Quick Build */}
            <div className="flex items-center justify-between gap-4">
              <div>
                <Label>Default Theme</Label>
                <p className="text-xs text-muted-foreground">Used as the initial theme when building new apps</p>
              </div>
              <ThemePicker
                value={localStorage.getItem('ods_default_theme') ?? 'indigo'}
                onValueChange={(v) => {
                  localStorage.setItem('ods_default_theme', v)
                  toast.success(`Default theme set to ${v}`)
                }}
              />
            </div>

            <Separator />

            {/* Default App */}
            <div className="flex items-center justify-between gap-4">
              <div>
                <Label>Default App</Label>
                <p className="text-xs text-muted-foreground">Non-admin users visiting the root URL will be redirected here</p>
              </div>
              {apps.length > 0 ? (
                <Select
                  value={defaultSlug ?? ''}
                  onValueChange={(v) => { if (v !== null) handleDefaultAppChange(v) }}
                >
                  <SelectTrigger className="w-48">
                    <SelectValue placeholder="Select app..." />
                  </SelectTrigger>
                  <SelectContent>
                    {apps.map((app) => (
                      <SelectItem key={app.slug} value={app.slug}>
                        {app.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              ) : (
                <span className="text-sm text-muted-foreground">No apps loaded</span>
              )}
            </div>

            <Separator />

            {/* Backup */}
            <div className="flex items-center justify-between">
              <Label htmlFor="auto-backup">Auto-Backup</Label>
              <input
                type="checkbox"
                id="auto-backup"
                checked={backupSettings.autoBackup}
                onChange={(e) => {
                  const updated = { ...backupSettings, autoBackup: e.target.checked }
                  setBackupState(updated)
                  setBackupSettings(updated)
                }}
                className="h-4 w-4 rounded border-input accent-primary"
              />
            </div>

            {backupSettings.autoBackup && (
              <div className="flex items-center justify-between gap-4">
                <Label>Keep snapshots</Label>
                <Select
                  value={String(backupSettings.retention)}
                  onValueChange={(v) => {
                    const updated = { ...backupSettings, retention: Number(v) }
                    setBackupState(updated)
                    setBackupSettings(updated)
                  }}
                >
                  <SelectTrigger className="w-24">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {[1, 3, 5, 10, 20].map((n) => (
                      <SelectItem key={n} value={String(n)}>
                        {n}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            )}
          </CardContent>
        </Card>

        {/* ---- Logging ---- */}
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Logging</CardTitle>
            <CardDescription>
              Configure diagnostic logging. Logs can be exported and shared for troubleshooting.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {/* Log Level */}
            <div className="flex items-center justify-between gap-4">
              <div>
                <Label>Log Level</Label>
                <p className="text-xs text-muted-foreground">Minimum severity to capture</p>
              </div>
              <Select
                value={logSettingsState.level}
                onValueChange={(v) => {
                  const updated = { ...logSettingsState, level: v as LogLevel }
                  setLogSettingsState(updated)
                  setLogSettings(updated)
                  toast.success(`Log level set to ${v}`)
                }}
              >
                <SelectTrigger className="w-28">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {(['debug', 'info', 'warn', 'error'] as const).map((lvl) => (
                    <SelectItem key={lvl} value={lvl}>
                      {lvl.charAt(0).toUpperCase() + lvl.slice(1)}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            {/* Retention */}
            <div className="flex items-center justify-between gap-4">
              <div>
                <Label>Retention</Label>
                <p className="text-xs text-muted-foreground">Auto-delete logs older than</p>
              </div>
              <Select
                value={String(logSettingsState.retentionDays)}
                onValueChange={(v) => {
                  const updated = { ...logSettingsState, retentionDays: Number(v) }
                  setLogSettingsState(updated)
                  setLogSettings(updated)
                  toast.success(`Log retention set to ${v} days`)
                }}
              >
                <SelectTrigger className="w-28">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {[1, 3, 7, 14, 30].map((n) => (
                    <SelectItem key={n} value={String(n)}>
                      {n} {n === 1 ? 'day' : 'days'}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <Separator />

            {/* Export actions */}
            <div className="flex items-center justify-between gap-4">
              <div>
                <Label>Export Logs</Label>
                <p className="text-xs text-muted-foreground">{logCount} entries stored</p>
              </div>
              <div className="flex gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => {
                    navigator.clipboard.writeText(exportLogsAsText())
                    toast.success('Logs copied to clipboard')
                  }}
                >
                  Copy
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => {
                    downloadLogs()
                    toast.success('Log file downloaded')
                  }}
                >
                  Download
                </Button>
              </div>
            </div>

            {/* Clear */}
            <div className="flex items-center justify-between gap-4">
              <div>
                <Label>Clear Logs</Label>
                <p className="text-xs text-muted-foreground">Permanently delete all stored log entries</p>
              </div>
              <Button
                variant="ghost"
                size="sm"
                className="text-destructive hover:text-destructive"
                onClick={() => {
                  clearLogs()
                  setLogCount(0)
                  toast.success('Logs cleared')
                }}
              >
                Clear All
              </Button>
            </div>
          </CardContent>
        </Card>

        {/* ---- PocketBase / Admin Settings ---- */}
        <Card>
          <CardHeader>
            <CardTitle className="text-base">PocketBase</CardTitle>
            <CardDescription>Database backend configuration</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {/* Current PB URL */}
            <div className="flex items-center justify-between gap-4">
              <div className="min-w-0 flex-1">
                <Label>Current Database</Label>
                <p className="mt-0.5 truncate text-sm font-mono text-muted-foreground">{pbUrl}</p>
              </div>
              <Button variant="outline" size="sm" onClick={() => { setNewPbUrl(pbUrl); setShowPbDialog(true) }}>
                <Database className="mr-2 size-3.5" />
                Switch
              </Button>
            </div>

            {pbAdminEmail && (
              <div className="flex items-center justify-between gap-4">
                <div>
                  <Label>Admin Account</Label>
                  <p className="text-xs text-muted-foreground">{pbAdminEmail}</p>
                </div>
                <Badge variant="outline">
                  <Shield className="mr-1 size-3" />
                  Superadmin
                </Badge>
              </div>
            )}

            <Separator />

            {/* Link to PocketBase admin */}
            <a
              href={`${pbUrl}/_/`}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 rounded-lg border px-3 py-2 text-sm font-medium text-foreground transition-colors hover:bg-muted"
            >
              <ExternalLink className="size-4" />
              Open PocketBase Admin
            </a>
          </CardContent>
        </Card>

        {/* ---- OAuth2 Providers ---- */}
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Authentication Providers</CardTitle>
            <CardDescription>Configure OAuth2 sign-in options for app users</CardDescription>
          </CardHeader>
          <CardContent>
            {isLoadingOAuth ? (
              <div className="flex items-center justify-center gap-2 py-6 text-muted-foreground">
                <Loader2 className="size-4 animate-spin" />
                Loading providers...
              </div>
            ) : oauthProviders.length === 0 ? (
              <p className="text-sm text-muted-foreground py-4">
                Could not load OAuth2 settings. Ensure you are logged in as PocketBase superadmin.
              </p>
            ) : (
              <div className="space-y-3">
                {oauthProviders.map((provider) => (
                  <div key={provider.id} className="flex items-center justify-between gap-4 rounded-lg border px-4 py-3">
                    <div className="flex items-center gap-3">
                      <input
                        type="checkbox"
                        checked={provider.enabled}
                        onChange={(e) => handleToggleOAuthProvider(provider.id, e.target.checked)}
                        className="h-4 w-4 rounded border-input accent-primary"
                        disabled={!provider.clientId && !provider.enabled}
                        title={!provider.clientId ? 'Configure credentials first' : ''}
                      />
                      <div>
                        <div className="text-sm font-medium">{provider.displayName}</div>
                        {provider.clientId ? (
                          <div className="text-xs text-muted-foreground font-mono truncate max-w-48">
                            {provider.clientId.slice(0, 20)}...
                          </div>
                        ) : (
                          <div className="text-xs text-muted-foreground">Not configured</div>
                        )}
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      {provider.enabled && (
                        <Badge variant="default" className="bg-green-600 hover:bg-green-600 text-xs">Active</Badge>
                      )}
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => {
                          setEditingProvider(provider.id)
                          setProviderClientId(provider.clientId)
                          setProviderClientSecret('')
                        }}
                      >
                        Configure
                      </Button>
                    </div>
                  </div>
                ))}
                <p className="text-xs text-muted-foreground pt-2">
                  Get OAuth2 credentials from each provider's developer console. Redirect URI:
                  <code className="ml-1 rounded bg-muted px-1 py-0.5">{window.location.origin}/oauth2-callback</code>
                </p>
              </div>
            )}
          </CardContent>
        </Card>

        {/* ---- User Management ---- */}
        <Card>
          <CardHeader>
            <div className="flex items-center justify-between">
              <div>
                <CardTitle className="text-base">Users</CardTitle>
                <CardDescription>Manage PocketBase application users</CardDescription>
              </div>
              <Button size="sm" onClick={() => setShowAddUser(true)}>
                <UserPlus className="mr-2 size-4" />
                Add User
              </Button>
            </div>
          </CardHeader>
          <CardContent>
            {isLoadingUsers ? (
              <div className="flex items-center justify-center gap-2 py-8 text-muted-foreground">
                <Loader2 className="size-4 animate-spin" />
                Loading users...
              </div>
            ) : users.length === 0 ? (
              <div className="rounded-lg border border-dashed py-8 text-center text-muted-foreground text-sm">
                No users found. Users are created per-app when multi-user mode is enabled.
              </div>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>User</TableHead>
                    <TableHead>Roles</TableHead>
                    <TableHead className="w-24 text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {/* Show PocketBase superadmin info row */}
                  {pbAdminEmail && (
                    <TableRow className="bg-muted/30">
                      <TableCell>
                        <div className="flex items-center gap-2">
                          <div className="flex size-8 items-center justify-center rounded-full bg-amber-100 text-xs font-medium text-amber-700 dark:bg-amber-900 dark:text-amber-300">
                            <Shield className="size-4" />
                          </div>
                          <div>
                            <div className="font-medium">{pbAdminEmail}</div>
                            <div className="text-xs text-muted-foreground">PocketBase Superadmin</div>
                          </div>
                        </div>
                      </TableCell>
                      <TableCell>
                        <Badge className="bg-amber-500 hover:bg-amber-500">superadmin</Badge>
                      </TableCell>
                      <TableCell className="text-right">
                        <span className="text-xs text-muted-foreground">Managed in PB</span>
                      </TableCell>
                    </TableRow>
                  )}
                  {users.map((user) => (
                    <TableRow key={user._id}>
                      <TableCell>
                        <div className="flex items-center gap-2">
                          <div className="flex size-8 items-center justify-center rounded-full bg-primary/10 text-xs font-medium text-primary">
                            {(user.displayName || user.email || '?')[0]?.toUpperCase() ?? '?'}
                          </div>
                          <div>
                            <div className="font-medium">{user.displayName}</div>
                            {user.email && (
                              <div className="text-xs text-muted-foreground">{user.email}</div>
                            )}
                          </div>
                        </div>
                      </TableCell>
                      <TableCell>
                        <div className="flex flex-wrap gap-1">
                          {user.roles.map((role) => (
                            <Badge
                              key={role}
                              variant={role === 'admin' ? 'default' : 'outline'}
                            >
                              {role}
                            </Badge>
                          ))}
                        </div>
                      </TableCell>
                      <TableCell className="text-right">
                        <div className="flex justify-end gap-1">
                          <Button
                            variant="ghost"
                            size="icon-sm"
                            onClick={() => {
                              setResetTarget(user)
                              setResetPassword('')
                            }}
                            title="Reset Password"
                          >
                            <KeyRound className="size-4" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon-sm"
                            onClick={() => setDeleteTarget(user)}
                            title="Delete User"
                            className="text-destructive hover:text-destructive"
                          >
                            <Trash2 className="size-4" />
                          </Button>
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      </div>

      {/* ---- Switch PocketBase Dialog ---- */}
      <Dialog open={showPbDialog} onOpenChange={setShowPbDialog}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Switch PocketBase Database</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <p className="text-sm text-muted-foreground">
              Enter the URL of a different PocketBase instance. The page will reload to connect.
            </p>
            <div className="space-y-2">
              <Label htmlFor="pb-url">PocketBase URL</Label>
              <Input
                id="pb-url"
                value={newPbUrl}
                onChange={(e) => setNewPbUrl(e.target.value)}
                placeholder="http://127.0.0.1:8090"
                onKeyDown={(e) => e.key === 'Enter' && handleSwitchPb()}
              />
            </div>
            <p className="text-xs text-muted-foreground">
              Tip: For a permanent change, set <code className="rounded bg-muted px-1 py-0.5">VITE_POCKETBASE_URL</code> in your .env file.
            </p>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowPbDialog(false)}>Cancel</Button>
            <Button onClick={handleSwitchPb} disabled={!newPbUrl.trim()}>Connect</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ---- Add User Dialog ---- */}
      <Dialog open={showAddUser} onOpenChange={setShowAddUser}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>Add User</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="settings-add-email">Email</Label>
              <Input
                id="settings-add-email"
                type="email"
                value={newEmail}
                onChange={(e) => setNewEmail(e.target.value)}
                placeholder="user@example.com"
                autoFocus
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="settings-add-password">Password</Label>
              <Input
                id="settings-add-password"
                type="password"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label>Role</Label>
              <Select value={newRole} onValueChange={(v) => setNewRole(v ?? 'user')}>
                <SelectTrigger className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {availableRoles.map((role) => (
                    <SelectItem key={role} value={role}>
                      {role}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowAddUser(false)}>Cancel</Button>
            <Button onClick={handleAddUser} disabled={!newEmail.trim() || !newPassword}>Add</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ---- Delete Confirmation ---- */}
      <AlertDialog open={!!deleteTarget} onOpenChange={(v) => !v && setDeleteTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete User</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to delete &quot;{deleteTarget?.username}&quot;? This cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleDeleteUser}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* ---- Reset Password Dialog ---- */}
      <Dialog
        open={!!resetTarget}
        onOpenChange={(v) => {
          if (!v) {
            setResetTarget(null)
            setResetPassword('')
          }
        }}
      >
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>Reset Password for {resetTarget?.username}</DialogTitle>
          </DialogHeader>
          <div className="space-y-2">
            <Label htmlFor="settings-reset-password">New Password</Label>
            <Input
              id="settings-reset-password"
              type="password"
              value={resetPassword}
              onChange={(e) => setResetPassword(e.target.value)}
              placeholder="Min. 8 characters"
              autoFocus
              onKeyDown={(e) => {
                if (e.key === 'Enter') handleResetPassword()
              }}
            />
            <p className="text-xs text-muted-foreground">Must be at least 8 characters.</p>
          </div>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => {
                setResetTarget(null)
                setResetPassword('')
              }}
            >
              Cancel
            </Button>
            <Button onClick={handleResetPassword} disabled={!resetPassword}>
              Reset
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ---- Configure OAuth Provider Dialog ---- */}
      {(() => {
        const providerInfo = KNOWN_OAUTH_PROVIDERS.find((p) => p.id === editingProvider)
        return (
          <Dialog open={!!editingProvider} onOpenChange={(v) => { if (!v) setEditingProvider(null) }}>
            <DialogContent className="sm:max-w-lg">
              <DialogHeader>
                <DialogTitle>
                  Configure {providerInfo?.displayName ?? editingProvider}
                </DialogTitle>
              </DialogHeader>
              <div className="max-h-[70vh] space-y-4 overflow-y-auto">
                {/* Setup instructions */}
                {providerInfo && (
                  <div className="rounded-lg border bg-muted/30 p-4 space-y-2">
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Setup Steps</span>
                      <a
                        href={providerInfo.consoleUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline"
                      >
                        <ExternalLink className="size-3" />
                        Open {providerInfo.displayName} Console
                      </a>
                    </div>
                    <ol className="list-decimal list-inside space-y-1.5 text-sm text-muted-foreground">
                      {providerInfo.steps.map((step, i) => (
                        <li key={i}>{step}</li>
                      ))}
                    </ol>
                  </div>
                )}

                {/* Redirect URI (show prominently) */}
                <div className="space-y-1">
                  <Label className="text-xs">Redirect URI (copy this into the provider's console)</Label>
                  <div
                    className="flex items-center gap-2 rounded-md border bg-muted px-3 py-2 font-mono text-xs cursor-pointer hover:bg-muted/80 transition-colors"
                    onClick={() => {
                      navigator.clipboard.writeText(`${window.location.origin}/oauth2-callback`)
                      toast.success('Redirect URI copied to clipboard')
                    }}
                    title="Click to copy"
                  >
                    <span className="flex-1 break-all">{window.location.origin}/oauth2-callback</span>
                    <span className="shrink-0 text-muted-foreground text-[10px]">click to copy</span>
                  </div>
                </div>

                <Separator />

                {/* Credentials */}
                <div className="space-y-2">
                  <Label htmlFor="oauth-client-id">Client ID</Label>
                  <Input
                    id="oauth-client-id"
                    value={providerClientId}
                    onChange={(e) => setProviderClientId(e.target.value)}
                    placeholder="Paste client ID here"
                    autoFocus
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="oauth-client-secret">Client Secret</Label>
                  <Input
                    id="oauth-client-secret"
                    type="password"
                    value={providerClientSecret}
                    onChange={(e) => setProviderClientSecret(e.target.value)}
                    placeholder={oauthProviders.find((p) => p.id === editingProvider)?.hasSecret ? '(unchanged — enter new to replace)' : 'Paste client secret here'}
                  />
                </div>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setEditingProvider(null)}>Cancel</Button>
                <Button onClick={handleSaveOAuthProvider} disabled={!providerClientId.trim()}>
                  Save &amp; Enable
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        )
      })()}
    </div>
  )
}

// ---------------------------------------------------------------------------
// OAuth2 provider types and known providers
// ---------------------------------------------------------------------------

interface OAuthProviderConfig {
  id: string
  displayName: string
  enabled: boolean
  clientId: string
  hasSecret: boolean
}

const KNOWN_OAUTH_PROVIDERS: {
  id: string
  displayName: string
  consoleUrl: string
  steps: string[]
}[] = [
  {
    id: 'google',
    displayName: 'Google',
    consoleUrl: 'https://console.cloud.google.com/apis/credentials',
    steps: [
      'Go to Google Cloud Console — if you don\'t have a project yet, click "Create Project" first',
      'Navigate to APIs & Services > OAuth consent screen and configure it (External, add your app name and email)',
      'Go to APIs & Services > Credentials and click "Create Credentials" > "OAuth client ID"',
      'Choose "Web application" as the application type',
      'Add the redirect URI shown below under "Authorized redirect URIs"',
      'Copy the Client ID and Client Secret',
    ],
  },
  {
    id: 'microsoft',
    displayName: 'Microsoft',
    consoleUrl: 'https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationsListBlade',
    steps: [
      'Go to Azure Portal > App registrations > New registration',
      'Set "Supported account types" to "Accounts in any org directory + personal Microsoft accounts"',
      'Under "Redirect URI", select "Web" and add the redirect URI shown below',
      'After creation, copy the "Application (client) ID" — this is your Client ID',
      'Go to Certificates & secrets > New client secret, copy the secret value',
    ],
  },
  {
    id: 'github',
    displayName: 'GitHub',
    consoleUrl: 'https://github.com/settings/developers',
    steps: [
      'Go to GitHub > Settings > Developer settings > OAuth Apps > New OAuth App',
      'Set "Authorization callback URL" to the redirect URI shown below',
      'After creation, copy the Client ID from the app page',
      'Click "Generate a new client secret" and copy it',
    ],
  },
  {
    id: 'apple',
    displayName: 'Apple',
    consoleUrl: 'https://developer.apple.com/account/resources/identifiers/list/serviceId',
    steps: [
      'Go to Apple Developer > Certificates, Identifiers & Profiles',
      'Register a new Services ID (this becomes your Client ID)',
      'Enable "Sign in with Apple" and configure the domain and redirect URI',
      'Create a key for Sign in with Apple under Keys — download the .p8 file',
      'The Client Secret is generated from the key file (see Apple docs for the JWT format)',
    ],
  },
  {
    id: 'facebook',
    displayName: 'Facebook',
    consoleUrl: 'https://developers.facebook.com/apps/',
    steps: [
      'Go to Meta for Developers > My Apps > Create App',
      'Choose "Consumer" or "Business" app type',
      'Add the "Facebook Login" product and configure the redirect URI',
      'Go to Settings > Basic to find your App ID (Client ID) and App Secret (Client Secret)',
    ],
  },
  {
    id: 'discord',
    displayName: 'Discord',
    consoleUrl: 'https://discord.com/developers/applications',
    steps: [
      'Go to Discord Developer Portal > Applications > New Application',
      'Go to OAuth2 in the sidebar',
      'Add the redirect URI shown below under "Redirects"',
      'Copy the Client ID and Client Secret from the OAuth2 page',
    ],
  },
  {
    id: 'gitlab',
    displayName: 'GitLab',
    consoleUrl: 'https://gitlab.com/-/user_settings/applications',
    steps: [
      'Go to GitLab > Preferences > Applications > Add new application',
      'Set the redirect URI to the value shown below',
      'Select scopes: "read_user", "openid", "profile", "email"',
      'After creation, copy the Application ID (Client ID) and Secret',
    ],
  },
  {
    id: 'twitter',
    displayName: 'Twitter / X',
    consoleUrl: 'https://developer.twitter.com/en/portal/projects-and-apps',
    steps: [
      'Go to Twitter Developer Portal > Projects & Apps > Create App',
      'Under "User authentication settings", enable OAuth 2.0',
      'Set type to "Web App" and add the redirect URI shown below',
      'Copy the Client ID and Client Secret from the Keys and Tokens tab',
    ],
  },
]

import { useState, useEffect, useCallback } from 'react'
import { useNavigate } from 'react-router'
import { AuthService } from '@/engine/auth-service.ts'
import { DataService } from '@/engine/data-service.ts'
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
  displayName: string
  roles: string[]
}

export function AdminSettingsPage() {
  const navigate = useNavigate()

  // Theme
  const [theme, setTheme] = useState<ThemeMode>(getThemeMode)

  // Backup
  const [backupSettings, setBackupState] = useState<BackupSettings>(getBackupSettings)

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
          username: u.username as string,
          displayName: (u.displayName as string) ?? (u.username as string),
          roles: (u.roles as string[]) ?? [],
        })),
      )
    } catch {
      setUsers([])
    }
    setIsLoadingUsers(false)
  }, [authService])

  useEffect(() => {
    loadApps()
    loadUsers()
  }, [loadApps, loadUsers])

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

  // User management handlers
  async function handleAddUser() {
    if (!newEmail.trim() || !newPassword) return
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
  const pbAdminEmail = localStorage.getItem('ods_pb_admin_email') ?? ''

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
            {/* Theme */}
            <div className="flex items-center justify-between gap-4">
              <Label>Theme</Label>
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

            {/* Default App */}
            <div className="flex items-center justify-between gap-4">
              <div>
                <Label>Default App</Label>
                <p className="text-xs text-muted-foreground">Non-admin users visiting the root URL will be redirected here</p>
              </div>
              {apps.length > 0 ? (
                <Select
                  value={defaultSlug ?? ''}
                  onValueChange={handleDefaultAppChange}
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
                            {user.username[0]?.toUpperCase() ?? '?'}
                          </div>
                          <div>
                            <div className="font-medium">{user.displayName}</div>
                            {user.displayName !== user.username && (
                              <div className="text-xs text-muted-foreground">@{user.username}</div>
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
              autoFocus
              onKeyDown={(e) => {
                if (e.key === 'Enter') handleResetPassword()
              }}
            />
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
    </div>
  )
}

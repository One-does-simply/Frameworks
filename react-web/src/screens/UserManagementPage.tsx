import { useState, useEffect, useCallback } from 'react'
import { useNavigate } from 'react-router'
import { AuthService } from '@/engine/auth-service.ts'
import pb from '@/lib/pocketbase.ts'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
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
  AlertDialog,
  AlertDialogContent,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogAction,
  AlertDialogCancel,
} from '@/components/ui/alert-dialog'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { toast } from 'sonner'
import { ArrowLeft, UserPlus, KeyRound, Trash2, Loader2 } from 'lucide-react'

// ---------------------------------------------------------------------------
// UserManagementPage — full-page user management (admin route)
// ---------------------------------------------------------------------------

interface UserRecord {
  _id: string
  username: string
  email: string
  displayName: string
  roles: string[]
}

export function UserManagementPage() {
  const navigate = useNavigate()

  // We create a fresh AuthService for the page. It uses the shared pb singleton.
  const [authService] = useState(() => new AuthService(pb))
  const [users, setUsers] = useState<UserRecord[]>([])
  const [isLoading, setIsLoading] = useState(true)

  // Add user form state
  const [showAddUser, setShowAddUser] = useState(false)
  const [newEmail, setNewEmail] = useState('')
  const [newDisplayName, setNewDisplayName] = useState('')
  const [newPassword, setNewPassword] = useState('')
  const [newRole, setNewRole] = useState('user')

  // Delete confirmation state
  const [deleteTarget, setDeleteTarget] = useState<UserRecord | null>(null)

  // Password reset state
  const [resetTarget, setResetTarget] = useState<UserRecord | null>(null)
  const [resetPassword, setResetPassword] = useState('')

  const availableRoles = ['admin', 'user']

  const loadUsers = useCallback(async () => {
    setIsLoading(true)
    try {
      await authService.initialize()
      const rawUsers = await authService.listUsers()
      setUsers(
        rawUsers.map((u) => ({
          _id: u._id as string,
          username: u.username as string,
          email: (u.email as string) ?? '',
          displayName: (u.displayName as string) ?? (u.email as string) ?? (u.username as string),
          roles: (u.roles as string[]) ?? [],
        })),
      )
    } catch {
      // Auth service might not be initialized if no app is loaded
      setUsers([])
    }
    setIsLoading(false)
  }, [authService])

  useEffect(() => {
    loadUsers()
  }, [loadUsers])

  // ---- Add User ----

  async function handleAddUser() {
    if (!newEmail.trim() || !newPassword) return
    const pwError = AuthService.validatePassword(newPassword)
    if (pwError) { toast.error(pwError); return }

    const userId = await authService.registerUser({
      email: newEmail.trim(),
      password: newPassword,
      role: newRole,
      displayName: newDisplayName.trim() || undefined,
    })

    if (userId) {
      setShowAddUser(false)
      setNewEmail('')
      setNewDisplayName('')
      setNewPassword('')
      setNewRole('user')
      await loadUsers()
      toast.success(`User "${newEmail.trim()}" created.`)
    } else {
      toast.error('Failed to create user. Email may already be in use.')
    }
  }

  // ---- Delete User ----

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

  // ---- Reset Password ----

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

  return (
    <div className="min-h-screen bg-background">
      {/* Top bar */}
      <header className="sticky top-0 z-40 flex h-14 items-center gap-3 border-b bg-background/95 px-4 supports-backdrop-filter:backdrop-blur-sm">
        <Button variant="ghost" size="icon-sm" onClick={() => navigate('/admin')}>
          <ArrowLeft className="size-5" />
        </Button>
        <h1 className="flex-1 text-base font-semibold">User Management</h1>
        <Button size="sm" onClick={() => setShowAddUser(true)}>
          <UserPlus className="mr-2 size-4" />
          Add User
        </Button>
      </header>

      <div className="mx-auto max-w-3xl p-6">
        {isLoading ? (
          <div className="flex items-center justify-center gap-2 py-12 text-muted-foreground">
            <Loader2 className="size-4 animate-spin" />
            Loading users...
          </div>
        ) : users.length === 0 ? (
          <div className="rounded-lg border border-dashed py-12 text-center text-muted-foreground">
            No users found. PocketBase user collections are created per-app when multi-user mode
            is enabled.
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
              {users.map((user) => (
                <TableRow key={user._id}>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <div className="flex size-8 items-center justify-center rounded-full bg-primary/10 text-xs font-medium text-primary">
                        {user.username[0]?.toUpperCase() ?? '?'}
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
      </div>

      {/* ---- Add User Dialog ---- */}
      <Dialog open={showAddUser} onOpenChange={setShowAddUser}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>Add User</DialogTitle>
          </DialogHeader>

          <div className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="add-email">Email</Label>
              <Input
                id="add-email"
                type="email"
                value={newEmail}
                onChange={(e) => setNewEmail(e.target.value)}
                placeholder="user@example.com"
                autoFocus
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="add-displayname">Display Name (optional)</Label>
              <Input
                id="add-displayname"
                value={newDisplayName}
                onChange={(e) => setNewDisplayName(e.target.value)}
                placeholder="User's name"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="add-password">Password</Label>
              <Input
                id="add-password"
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
            <Button variant="outline" onClick={() => setShowAddUser(false)}>
              Cancel
            </Button>
            <Button
              onClick={handleAddUser}
              disabled={!newEmail.trim() || !newPassword}
            >
              Add
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ---- Delete Confirmation ---- */}
      <AlertDialog open={!!deleteTarget} onOpenChange={(v) => !v && setDeleteTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete User</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to delete &quot;{deleteTarget?.username}&quot;? This cannot
              be undone.
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
            <Label htmlFor="reset-password">New Password</Label>
            <Input
              id="reset-password"
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
    </div>
  )
}

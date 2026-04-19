import { useState, useEffect, useCallback } from 'react'
import { Outlet } from 'react-router'
import { DataService } from '@/engine/data-service.ts'
import { AppRegistry } from '@/engine/app-registry.ts'
import { AuthService } from '@/engine/auth-service.ts'
import pb from '@/lib/pocketbase.ts'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Loader2 } from 'lucide-react'

// ---------------------------------------------------------------------------
// AdminGuard — PocketBase superadmin auth gate for admin routes
// ---------------------------------------------------------------------------

export function AdminGuard() {
  const [status, setStatus] = useState<'loading' | 'authenticated' | 'login'>('loading')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [authError, setAuthError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  const tryAuth = useCallback(async () => {
    const ds = new DataService(pb)
    const restored = await ds.tryRestoreAdminAuth()
    if (restored) {
      // Ensure framework-level collections exist (_ods_apps for the app
      // registry, users for the per-app sign-up flow).
      const registry = new AppRegistry(pb)
      await registry.ensureCollection()
      await new AuthService(pb).ensureUsersCollection()
      setStatus('authenticated')
    } else {
      setStatus('login')
    }
  }, [])

  useEffect(() => {
    tryAuth()
  }, [tryAuth])

  async function handleLogin(e: React.FormEvent) {
    e.preventDefault()
    setAuthError(null)
    setSubmitting(true)

    const ds = new DataService(pb)
    const success = await ds.authenticateAdmin(email, password)

    if (success) {
      const registry = new AppRegistry(pb)
      await registry.ensureCollection()
      await new AuthService(pb).ensureUsersCollection()
      setStatus('authenticated')
    } else {
      setAuthError(
        'Invalid PocketBase admin credentials. Check the email and password you used when setting up PocketBase.',
      )
    }
    setSubmitting(false)
  }

  if (status === 'loading') {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background">
        <div className="flex items-center gap-2 text-muted-foreground">
          <Loader2 className="size-5 animate-spin" />
          <span>Connecting to PocketBase...</span>
        </div>
      </div>
    )
  }

  if (status === 'login') {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center bg-background p-4">
        <Card className="w-full max-w-sm">
          <CardHeader>
            <CardTitle>ODS Admin Login</CardTitle>
            <CardDescription>
              Enter the PocketBase superadmin credentials. If this is your first time, create a superadmin at <code className="rounded bg-muted px-1">http://127.0.0.1:8090/_/</code> using <strong>admin@ods.local</strong> as the email.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleLogin} className="space-y-4">
              {authError && (
                <div className="rounded-lg border border-destructive/50 bg-destructive/10 px-3 py-2 text-sm text-destructive">
                  {authError}
                </div>
              )}

              <div className="space-y-2">
                <Label htmlFor="admin-email">Admin Email</Label>
                <Input
                  id="admin-email"
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="admin@ods.local"
                  autoFocus
                  disabled={submitting}
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="admin-password">Admin Password</Label>
                <Input
                  id="admin-password"
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="Password"
                  disabled={submitting}
                />
              </div>

              <Button type="submit" className="w-full" disabled={submitting}>
                {submitting && <Loader2 className="mr-2 size-4 animate-spin" />}
                Connect to PocketBase
              </Button>
            </form>
          </CardContent>
        </Card>

        <p className="mt-4 text-center text-xs text-muted-foreground">
          ODS React Web Framework
        </p>
      </div>
    )
  }

  // Authenticated — render child routes
  return <Outlet />
}

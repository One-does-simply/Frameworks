import { useState, useEffect, useCallback } from 'react'
import { useNavigate } from 'react-router'
import { DataService } from '@/engine/data-service.ts'
import pb from '@/lib/pocketbase.ts'
import { getDefaultAppSlug } from '@/engine/default-app-store.ts'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Loader2, Shield, User, Info } from 'lucide-react'

// ---------------------------------------------------------------------------
// RootRedirect — landing page at /
//
// Shows a login screen that allows:
//   1. PocketBase admin login → /admin dashboard
//   2. Regular user → redirect to default app
//   3. Guest (if allowed) → redirect to default app
// ---------------------------------------------------------------------------

export function RootRedirect() {
  const navigate = useNavigate()
  const [status, setStatus] = useState<'loading' | 'login'>('loading')
  const [mode, setMode] = useState<'choose' | 'admin' | 'user'>('choose')

  // Admin login state
  const [adminEmail, setAdminEmail] = useState('')
  const [adminPassword, setAdminPassword] = useState('')
  const [adminError, setAdminError] = useState<string | null>(null)
  const [adminSubmitting, setAdminSubmitting] = useState(false)

  // User login state
  const [userEmail, setUserEmail] = useState('')
  const [password, setPassword] = useState('')
  const [userError, setUserError] = useState<string | null>(null)
  const [userSubmitting, setUserSubmitting] = useState(false)

  const defaultSlug = getDefaultAppSlug()

  // Try to auto-restore admin session
  const tryAutoAuth = useCallback(async () => {
    const ds = new DataService(pb)
    const restored = await ds.tryRestoreAdminAuth()
    if (restored) {
      navigate('/admin', { replace: true })
    } else {
      setStatus('login')
    }
  }, [navigate])

  useEffect(() => {
    tryAutoAuth()
  }, [tryAutoAuth])

  // ---- Admin login ----
  async function handleAdminLogin(e: React.FormEvent) {
    e.preventDefault()
    setAdminError(null)
    setAdminSubmitting(true)

    const ds = new DataService(pb)
    const success = await ds.authenticateAdmin(adminEmail, adminPassword)

    if (success) {
      navigate('/admin', { replace: true })
    } else {
      setAdminError('Invalid PocketBase admin credentials.')
    }
    setAdminSubmitting(false)
  }

  // ---- User login ----
  async function handleUserLogin(e: React.FormEvent) {
    e.preventDefault()
    setUserError(null)

    if (!userEmail.trim()) {
      setUserError('Email is required')
      return
    }
    if (!password) {
      setUserError('Password is required')
      return
    }

    setUserSubmitting(true)

    try {
      await pb.collection('users').authWithPassword(userEmail.trim(), password)
      // Redirect to default app or admin
      if (defaultSlug) {
        navigate(`/${defaultSlug}`, { replace: true })
      } else {
        setUserError('No default app configured. Please contact an administrator.')
      }
    } catch {
      setUserError('Invalid username or password')
    }
    setUserSubmitting(false)
  }

  function handleGuestAccess() {
    if (defaultSlug) {
      navigate(`/${defaultSlug}`, { replace: true })
    }
  }

  if (status === 'loading') {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background">
        <div className="flex items-center gap-2 text-muted-foreground">
          <Loader2 className="size-5 animate-spin" />
          <span>Connecting...</span>
        </div>
      </div>
    )
  }

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-background p-4">
      {/* Header */}
      <div className="mb-8 text-center">
        <h1 className="text-2xl font-extrabold tracking-tight bg-gradient-to-r from-indigo-600 to-violet-600 bg-clip-text text-transparent">
          One Does Simply
        </h1>
        <p className="mt-1 text-sm font-medium text-muted-foreground">
          Vibe Coding with Guardrails
        </p>
      </div>

      {mode === 'choose' && (
        <Card className="w-full max-w-sm">
          <CardHeader>
            <CardTitle>Welcome</CardTitle>
            <CardDescription>How would you like to sign in?</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <Button
              variant="default"
              className="w-full justify-start gap-3"
              onClick={() => setMode('admin')}
            >
              <Shield className="size-4" />
              Administrator
            </Button>
            <Button
              variant="outline"
              className="w-full justify-start gap-3"
              onClick={() => setMode('user')}
            >
              <User className="size-4" />
              App User
            </Button>
            {defaultSlug && (
              <Button
                variant="ghost"
                className="w-full"
                onClick={handleGuestAccess}
              >
                Continue as Guest
              </Button>
            )}
          </CardContent>
        </Card>
      )}

      {mode === 'admin' && (
        <Card className="w-full max-w-sm">
          <CardHeader>
            <CardTitle>Admin Login</CardTitle>
            <CardDescription>
              PocketBase superadmin credentials
            </CardDescription>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleAdminLogin} className="space-y-4">
              {adminError && (
                <div className="rounded-lg border border-destructive/50 bg-destructive/10 px-3 py-2 text-sm text-destructive">
                  {adminError}
                </div>
              )}
              <div className="space-y-2">
                <Label htmlFor="root-admin-email">Admin Email</Label>
                <Input
                  id="root-admin-email"
                  type="email"
                  value={adminEmail}
                  onChange={(e) => setAdminEmail(e.target.value)}
                  placeholder="admin@localhost"
                  autoFocus
                  disabled={adminSubmitting}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="root-admin-password">Password</Label>
                <Input
                  id="root-admin-password"
                  type="password"
                  value={adminPassword}
                  onChange={(e) => setAdminPassword(e.target.value)}
                  disabled={adminSubmitting}
                />
              </div>
              <Button type="submit" className="w-full" disabled={adminSubmitting}>
                {adminSubmitting && <Loader2 className="mr-2 size-4 animate-spin" />}
                Sign In as Admin
              </Button>
              <Button type="button" variant="ghost" className="w-full" onClick={() => setMode('choose')}>
                Back
              </Button>
            </form>
          </CardContent>
        </Card>
      )}

      {mode === 'user' && (
        <Card className="w-full max-w-sm">
          <CardHeader>
            <CardTitle>Sign In</CardTitle>
            <CardDescription>
              {defaultSlug
                ? `Sign in to access your apps`
                : 'Sign in with your account'}
            </CardDescription>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleUserLogin} className="space-y-4">
              {userError && (
                <div className="rounded-lg border border-destructive/50 bg-destructive/10 px-3 py-2 text-sm text-destructive">
                  {userError}
                </div>
              )}
              <div className="space-y-2">
                <Label htmlFor="root-email">Email</Label>
                <Input
                  id="root-email"
                  type="email"
                  autoComplete="email"
                  value={userEmail}
                  onChange={(e) => setUserEmail(e.target.value)}
                  placeholder="you@example.com"
                  autoFocus
                  disabled={userSubmitting}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="root-password">Password</Label>
                <Input
                  id="root-password"
                  type="password"
                  autoComplete="current-password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  disabled={userSubmitting}
                />
              </div>
              <Button type="submit" className="w-full" disabled={userSubmitting}>
                {userSubmitting && <Loader2 className="mr-2 size-4 animate-spin" />}
                Sign In
              </Button>
              <Button type="button" variant="ghost" className="w-full" onClick={() => setMode('choose')}>
                Back
              </Button>
            </form>
          </CardContent>
        </Card>
      )}

      {/* Learn more link */}
      <a
        href="https://one-does-simply.github.io/Specification/"
        target="_blank"
        rel="noopener noreferrer"
        className="mt-6 inline-flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
      >
        <Info className="size-3.5" />
        Learn more about ODS
      </a>

      <p className="mt-2 text-center text-xs text-muted-foreground/50">
        ODS React Web Framework
      </p>
    </div>
  )
}

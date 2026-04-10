import { useState, useEffect, useCallback } from 'react'
import { useNavigate } from 'react-router'
import { AuthService } from '@/engine/auth-service.ts'
import { DataService } from '@/engine/data-service.ts'
import pb from '@/lib/pocketbase.ts'
import { getDefaultAppSlug } from '@/engine/default-app-store.ts'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Separator } from '@/components/ui/separator'
import { Loader2, Shield, User, Info } from 'lucide-react'

/** Known OAuth2 provider button styles. */
const OAUTH_STYLES: Record<string, { label: string; bg: string; hover: string }> = {
  google: { label: 'Continue with Google', bg: 'bg-white text-gray-800 border', hover: 'hover:bg-gray-50' },
  microsoft: { label: 'Continue with Microsoft', bg: 'bg-[#2F2F2F] text-white', hover: 'hover:bg-[#1a1a1a]' },
  github: { label: 'Continue with GitHub', bg: 'bg-[#24292f] text-white', hover: 'hover:bg-[#1b1f23]' },
  apple: { label: 'Continue with Apple', bg: 'bg-black text-white', hover: 'hover:bg-gray-900' },
  facebook: { label: 'Continue with Facebook', bg: 'bg-[#1877F2] text-white', hover: 'hover:bg-[#166FE5]' },
  discord: { label: 'Continue with Discord', bg: 'bg-[#5865F2] text-white', hover: 'hover:bg-[#4752C4]' },
}

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

  // OAuth2 providers
  const [oauthProviders, setOauthProviders] = useState<{ name: string; displayName: string }[]>([])

  const defaultSlug = getDefaultAppSlug()

  // Check for existing session or redirect to /admin on fresh install
  const tryAutoAuth = useCallback(async () => {
    // If already authenticated in this session, go straight to admin
    if (pb.authStore.isValid) {
      navigate('/admin', { replace: true })
      return
    }

    // Fresh install: no default app configured → send to /admin for setup
    const hasDefaultApp = !!getDefaultAppSlug()
    if (!hasDefaultApp) {
      navigate('/admin', { replace: true })
      return
    }

    setStatus('login')
  }, [navigate])

  useEffect(() => {
    tryAutoAuth()
  }, [tryAutoAuth])

  // Discover OAuth2 providers when entering user login mode
  useEffect(() => {
    if (mode !== 'user') return
    pb.collection('users').listAuthMethods({ requestKey: null } as Record<string, unknown>)
      .then((methods) => {
        const providers = (methods.oauth2?.providers ?? []).map((p) => ({
          name: p.name as string,
          displayName: (p.displayName as string) ?? (p.name as string),
        }))
        setOauthProviders(providers)
      })
      .catch(() => setOauthProviders([]))
  }, [mode])

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

  async function handleOAuth2(providerName: string) {
    setUserError(null)
    setUserSubmitting(true)
    // Redirect flow — saves state and navigates to provider
    const authService = new AuthService(pb)
    await authService.startOAuth2Redirect(providerName)
    // Browser will redirect — loading state stays true
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
                  placeholder="admin@ods.local"
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
            <div className="space-y-4">
              {userError && (
                <div className="rounded-lg border border-destructive/50 bg-destructive/10 px-3 py-2 text-sm text-destructive">
                  {userError}
                </div>
              )}

              {/* OAuth2 providers */}
              {oauthProviders.length > 0 && (
                <>
                  <div className="space-y-2">
                    {oauthProviders.map((provider) => {
                      const style = OAUTH_STYLES[provider.name] ?? {
                        label: `Continue with ${provider.displayName}`,
                        bg: 'bg-secondary text-secondary-foreground',
                        hover: 'hover:bg-secondary/80',
                      }
                      return (
                        <button
                          key={provider.name}
                          type="button"
                          disabled={userSubmitting}
                          onClick={() => handleOAuth2(provider.name)}
                          className={`flex w-full items-center justify-center gap-2 rounded-md px-4 py-2.5 text-sm font-medium transition-colors ${style.bg} ${style.hover} disabled:opacity-50`}
                        >
                          {style.label}
                        </button>
                      )
                    })}
                  </div>
                  <div className="relative">
                    <Separator />
                    <span className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 bg-card px-2 text-xs text-muted-foreground">
                      or
                    </span>
                  </div>
                </>
              )}

            <form onSubmit={handleUserLogin} className="space-y-4">
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
            </div>
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

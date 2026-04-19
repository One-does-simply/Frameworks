import { useState } from 'react'
import { useAppStore } from '@/engine/app-store.ts'
import pb from '@/lib/pocketbase.ts'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Separator } from '@/components/ui/separator'
import { Loader2, Shield } from 'lucide-react'

// ---------------------------------------------------------------------------
// LoginScreen — email/password + OAuth2 login for multi-user apps
// Supports self-registration when auth.selfRegistration is enabled in spec.
// ---------------------------------------------------------------------------

/** Map of known OAuth2 provider names to display labels and colors. */
const OAUTH_STYLES: Record<string, { label: string; bg: string; hover: string }> = {
  google: { label: 'Continue with Google', bg: 'bg-white text-gray-800 border', hover: 'hover:bg-gray-50' },
  microsoft: { label: 'Continue with Microsoft', bg: 'bg-[#2F2F2F] text-white', hover: 'hover:bg-[#1a1a1a]' },
  github: { label: 'Continue with GitHub', bg: 'bg-[#24292f] text-white', hover: 'hover:bg-[#1b1f23]' },
  apple: { label: 'Continue with Apple', bg: 'bg-black text-white', hover: 'hover:bg-gray-900' },
  facebook: { label: 'Continue with Facebook', bg: 'bg-[#1877F2] text-white', hover: 'hover:bg-[#166FE5]' },
  discord: { label: 'Continue with Discord', bg: 'bg-[#5865F2] text-white', hover: 'hover:bg-[#4752C4]' },
}

export function LoginScreen() {
  const app = useAppStore((s) => s.app)!
  const authService = useAppStore((s) => s.authService)!
  const dataService = useAppStore((s) => s.dataService)

  const [isSignUp, setIsSignUp] = useState(false)
  const [isAdminSetup, setIsAdminSetup] = useState(false)
  const needsAdminSetup = useAppStore((s) => s.needsAdminSetup)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [displayName, setDisplayName] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  const allowSelfRegistration = app.auth.selfRegistration
  const isMultiUserOnly = app.auth.multiUserOnly
  const pbSuperAdminAvailable = dataService?.isAdminAuthenticated ?? false
  const oauthProviders = authService.oauthProviders ?? []

  // ---- Login ----
  async function handleLogin(e: React.FormEvent) {
    e.preventDefault()
    setError(null)

    if (!email.trim()) {
      setError('Email is required')
      return
    }
    if (!password) {
      setError('Password is required')
      return
    }

    setLoading(true)
    const success = await authService.login(email.trim(), password)
    setLoading(false)

    if (success) {
      useAppStore.setState({ needsLogin: false })
    } else {
      setError('Invalid email or password')
    }
  }

  // ---- OAuth2 (redirect flow) ----
  async function handleOAuth2(providerName: string) {
    setError(null)
    setLoading(true)
    await authService.startOAuth2Redirect(providerName)
    // Browser will redirect — loading state stays true
  }

  // ---- Sign Up ----
  async function handleSignUp(e: React.FormEvent) {
    e.preventDefault()
    setError(null)

    if (!email.trim()) {
      setError('Email is required')
      return
    }
    if (password.length < 8) {
      setError('Password must be at least 8 characters')
      return
    }
    if (password !== confirmPassword) {
      setError('Passwords do not match')
      return
    }

    // Check for PB superadmin email conflict
    const pbAdminEmail = (pb.authStore.record?.['email'] as string) ?? ''
    if (pbAdminEmail && email.trim().toLowerCase() === pbAdminEmail.toLowerCase()) {
      setError('This email is reserved for the system administrator. Please use a different email.')
      return
    }

    setLoading(true)
    const userId = await authService.registerUser({
      email: email.trim(),
      password,
      role: app.auth.defaultRole,
      displayName: displayName.trim() || undefined,
    })

    if (userId) {
      const loginSuccess = await authService.login(email.trim(), password)
      setLoading(false)

      if (loginSuccess) {
        // Clear both gates: the user is now logged in, and self-registration
        // is a valid path even when no admin has been set up yet.
        useAppStore.setState({ needsLogin: false, needsAdminSetup: false })
      } else {
        setError('Account created but login failed. Please try signing in.')
        setIsSignUp(false)
      }
    } else {
      setLoading(false)
      setError('Failed to create account. Email may already be in use.')
    }
  }

  // ---- Admin / Guest ----
  function handleContinueAsAdmin() {
    if (pbSuperAdminAvailable) {
      // PB superadmin — bypass directly
      authService.setSuperAdmin(true)
      useAppStore.setState({ needsLogin: false, needsAdminSetup: false })
    } else if (needsAdminSetup && !authService.isAdminSetUp) {
      // No admin user exists anywhere — show admin creation form
      setIsAdminSetup(true)
      setError(null)
    } else {
      // Admin user exists but we're not authenticated — show login form
      setError(null)
    }
  }

  async function handleAdminSetup(e: React.FormEvent) {
    e.preventDefault()
    setError(null)

    if (!email.trim()) { setError('Email is required'); return }
    if (password.length < 8) { setError('Password must be at least 8 characters'); return }
    if (password !== confirmPassword) { setError('Passwords do not match'); return }

    const pbAdminEmail = (pb.authStore.record?.['email'] as string) ?? ''
    if (pbAdminEmail && email.trim().toLowerCase() === pbAdminEmail.toLowerCase()) {
      setError('This email is used by the PocketBase superadmin. Please use a different email.')
      return
    }

    setLoading(true)
    const success = await authService.setupAdmin(email.trim(), password, displayName.trim() || undefined)
    setLoading(false)

    if (success) {
      useAppStore.setState({ needsAdminSetup: false, needsLogin: false })
    } else {
      setError('Failed to create admin account. Please try again.')
    }
  }

  function handleContinueAsGuest() {
    authService.setSuperAdmin(false)
    useAppStore.setState({ needsLogin: false, needsAdminSetup: false })
  }

  // =========================================================================
  // Admin Setup View (only when no admin exists and user chose to create one)
  // =========================================================================

  if (isAdminSetup) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center bg-background p-4">
        <Card className="w-full max-w-sm">
          <CardHeader>
            <CardTitle>Create Admin Account</CardTitle>
            <CardDescription>Set up the administrator account for {app.appName}.</CardDescription>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleAdminSetup} className="space-y-4">
              {error && (
                <div className="rounded-lg border border-destructive/50 bg-destructive/10 px-3 py-2 text-sm text-destructive">
                  {error}
                </div>
              )}
              <div className="space-y-2">
                <Label htmlFor="admin-setup-email">Email</Label>
                <Input id="admin-setup-email" type="email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="admin@example.com" disabled={loading} autoFocus />
              </div>
              <div className="space-y-2">
                <Label htmlFor="admin-setup-name">Display Name (optional)</Label>
                <Input id="admin-setup-name" type="text" value={displayName} onChange={(e) => setDisplayName(e.target.value)} placeholder="Your name" disabled={loading} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="admin-setup-pw">Password</Label>
                <Input id="admin-setup-pw" type="password" autoComplete="new-password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="Minimum 8 characters" disabled={loading} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="admin-setup-confirm">Confirm Password</Label>
                <Input id="admin-setup-confirm" type="password" autoComplete="new-password" value={confirmPassword} onChange={(e) => setConfirmPassword(e.target.value)} placeholder="Re-enter password" disabled={loading} />
              </div>
              <Button type="submit" className="w-full" disabled={loading}>
                {loading && <Loader2 className="mr-2 size-4 animate-spin" />}
                Create Admin &amp; Continue
              </Button>
              <Button type="button" variant="ghost" className="w-full" onClick={() => { setIsAdminSetup(false); setError(null) }} disabled={loading}>
                Back
              </Button>
            </form>
          </CardContent>
        </Card>
      </div>
    )
  }

  // =========================================================================
  // Sign Up View
  // =========================================================================

  if (isSignUp) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center bg-background p-4">
        <Card className="w-full max-w-sm">
          <CardHeader>
            <CardTitle>Sign Up</CardTitle>
            <CardDescription>Create an account for {app.appName}</CardDescription>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {error && (
                <div className="rounded-lg border border-destructive/50 bg-destructive/10 px-3 py-2 text-sm text-destructive">
                  {error}
                </div>
              )}

              {/* OAuth2 — works for sign-up too (PB auto-creates the user) */}
              {oauthProviders.length > 0 && (
                <>
                  <div className="space-y-2">
                    {oauthProviders.map((provider) => {
                      const style = OAUTH_STYLES[provider.name] ?? {
                        label: `Sign up with ${provider.displayName}`,
                        bg: 'bg-secondary text-secondary-foreground',
                        hover: 'hover:bg-secondary/80',
                      }
                      return (
                        <button
                          key={provider.name}
                          type="button"
                          disabled={loading}
                          onClick={() => handleOAuth2(provider.name)}
                          className={`flex w-full items-center justify-center gap-2 rounded-md px-4 py-2.5 text-sm font-medium transition-colors ${style.bg} ${style.hover} disabled:opacity-50`}
                        >
                          Sign up with {provider.displayName}
                        </button>
                      )
                    })}
                  </div>

                  <div className="relative">
                    <Separator />
                    <span className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 bg-card px-2 text-xs text-muted-foreground">
                      or sign up with email
                    </span>
                  </div>
                </>
              )}

            <form onSubmit={handleSignUp} className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="signup-email">Email</Label>
                <Input
                  id="signup-email"
                  type="email"
                  autoComplete="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="you@example.com"
                  disabled={loading}
                  autoFocus
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="signup-displayname">Display Name (optional)</Label>
                <Input
                  id="signup-displayname"
                  type="text"
                  value={displayName}
                  onChange={(e) => setDisplayName(e.target.value)}
                  placeholder="Your name"
                  disabled={loading}
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="signup-password">Password</Label>
                <Input
                  id="signup-password"
                  type="password"
                  autoComplete="new-password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="Minimum 8 characters"
                  disabled={loading}
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="signup-confirm">Confirm Password</Label>
                <Input
                  id="signup-confirm"
                  type="password"
                  autoComplete="new-password"
                  value={confirmPassword}
                  onChange={(e) => setConfirmPassword(e.target.value)}
                  placeholder="Re-enter password"
                  disabled={loading}
                />
              </div>

              <Button type="submit" className="w-full" disabled={loading}>
                {loading && <Loader2 className="mr-2 size-4 animate-spin" />}
                Create Account
              </Button>

              <Button
                type="button"
                variant="ghost"
                className="w-full"
                onClick={() => { setIsSignUp(false); setError(null) }}
                disabled={loading}
              >
                Already have an account? Sign In
              </Button>
            </form>
            </div>
          </CardContent>
        </Card>
      </div>
    )
  }

  // =========================================================================
  // Sign In View
  // =========================================================================

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-background p-4">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle>Sign In</CardTitle>
          <CardDescription>Sign in to {app.appName}</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {error && (
              <div className="rounded-lg border border-destructive/50 bg-destructive/10 px-3 py-2 text-sm text-destructive">
                {error}
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
                        disabled={loading}
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

            {/* Email/password form */}
            <form onSubmit={handleLogin} className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="login-email">Email</Label>
                <Input
                  id="login-email"
                  type="email"
                  autoComplete="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="you@example.com"
                  disabled={loading}
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="login-password">Password</Label>
                <Input
                  id="login-password"
                  type="password"
                  autoComplete="current-password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="Enter password"
                  disabled={loading}
                />
              </div>

              <Button type="submit" className="w-full" disabled={loading}>
                {loading && <Loader2 className="mr-2 size-4 animate-spin" />}
                Sign In
              </Button>
            </form>

            {/* Self-registration */}
            {allowSelfRegistration && (
              <Button
                type="button"
                variant="outline"
                className="w-full"
                onClick={() => { setIsSignUp(true); setError(null) }}
                disabled={loading}
              >
                Don&apos;t have an account? Sign Up
              </Button>
            )}

            {/* Continue as Admin (PB superadmin or first-time admin setup) */}
            {(pbSuperAdminAvailable || needsAdminSetup) && (
              <Button
                type="button"
                variant="outline"
                className="w-full"
                onClick={handleContinueAsAdmin}
                disabled={loading}
              >
                <Shield className="mr-2 size-4" />
                Continue as Admin
              </Button>
            )}

            {/* Continue as Guest */}
            {!isMultiUserOnly && (
              <Button
                type="button"
                variant="ghost"
                className="w-full"
                onClick={handleContinueAsGuest}
                disabled={loading}
              >
                Continue as Guest
              </Button>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

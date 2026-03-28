import { useState } from 'react'
import { useAppStore } from '@/engine/app-store.ts'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Loader2, Shield } from 'lucide-react'

// ---------------------------------------------------------------------------
// LoginScreen — username/password login for multi-user apps
// Supports self-registration when auth.selfRegistration is enabled in spec.
// ---------------------------------------------------------------------------

export function LoginScreen() {
  const app = useAppStore((s) => s.app)!
  const authService = useAppStore((s) => s.authService)!
  const dataService = useAppStore((s) => s.dataService)

  const [isSignUp, setIsSignUp] = useState(false)
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [displayName, setDisplayName] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  const allowSelfRegistration = app.auth.selfRegistration
  const isMultiUserOnly = app.auth.multiUserOnly
  const pbSuperAdminAvailable = dataService?.isAdminAuthenticated ?? false

  async function handleLogin(e: React.FormEvent) {
    e.preventDefault()
    setError(null)

    if (!username.trim()) {
      setError('Username is required')
      return
    }
    if (!password) {
      setError('Password is required')
      return
    }

    setLoading(true)
    const success = await authService.login(username.trim(), password)
    setLoading(false)

    if (success) {
      // Refresh store state to pass the auth gate
      useAppStore.setState({
        needsLogin: false,
      })
    } else {
      setError('Invalid username or password')
    }
  }

  async function handleSignUp(e: React.FormEvent) {
    e.preventDefault()
    setError(null)

    if (!username.trim()) {
      setError('Username is required')
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

    setLoading(true)
    const userId = await authService.registerUser({
      username: username.trim(),
      password,
      role: app.auth.defaultRole,
      displayName: displayName.trim() || undefined,
    })

    if (userId) {
      // Auto-login after registration
      const loginSuccess = await authService.login(username.trim(), password)
      setLoading(false)

      if (loginSuccess) {
        useAppStore.setState({
          needsLogin: false,
        })
      } else {
        setError('Account created but login failed. Please try signing in.')
        setIsSignUp(false)
      }
    } else {
      setLoading(false)
      setError('Failed to create account. Username may already be taken.')
    }
  }

  function handleContinueAsAdmin() {
    authService.setSuperAdmin(true)
    useAppStore.setState({
      needsLogin: false,
    })
  }

  function handleContinueAsGuest() {
    authService.setSuperAdmin(false)
    useAppStore.setState({
      needsLogin: false,
    })
  }

  if (isSignUp) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center bg-background p-4">
        <Card className="w-full max-w-sm">
          <CardHeader>
            <CardTitle>Sign Up</CardTitle>
            <CardDescription>
              Create an account for {app.appName}
            </CardDescription>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleSignUp} className="space-y-4">
              {error && (
                <div className="rounded-lg border border-destructive/50 bg-destructive/10 px-3 py-2 text-sm text-destructive">
                  {error}
                </div>
              )}

              <div className="space-y-2">
                <Label htmlFor="signup-username">Username</Label>
                <Input
                  id="signup-username"
                  type="text"
                  autoComplete="username"
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  placeholder="Choose a username"
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
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-background p-4">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle>Sign In</CardTitle>
          <CardDescription>
            Sign in to {app.appName}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleLogin} className="space-y-4">
            {/* Error message */}
            {error && (
              <div className="rounded-lg border border-destructive/50 bg-destructive/10 px-3 py-2 text-sm text-destructive">
                {error}
              </div>
            )}

            {/* Username */}
            <div className="space-y-2">
              <Label htmlFor="login-username">Username</Label>
              <Input
                id="login-username"
                type="text"
                autoComplete="username"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                placeholder="Enter username"
                disabled={loading}
              />
            </div>

            {/* Password */}
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

            {/* Login button */}
            <Button type="submit" className="w-full" disabled={loading}>
              {loading && <Loader2 className="mr-2 size-4 animate-spin" />}
              Sign In
            </Button>

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

            {/* Continue as Admin (PB superadmin) */}
            {pbSuperAdminAvailable && (
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
          </form>
        </CardContent>
      </Card>
    </div>
  )
}

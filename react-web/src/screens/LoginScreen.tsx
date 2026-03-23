import { useState } from 'react'
import { useAppStore } from '@/engine/app-store.ts'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Loader2 } from 'lucide-react'

// ---------------------------------------------------------------------------
// LoginScreen — username/password login for multi-user apps
// ---------------------------------------------------------------------------

export function LoginScreen() {
  const app = useAppStore((s) => s.app)!
  const authService = useAppStore((s) => s.authService)!

  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

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

  function handleContinueAsGuest() {
    // Skip login — user proceeds without auth
    useAppStore.setState({
      needsLogin: false,
    })
  }

  const isMultiUserOnly = app.auth.multiUserOnly

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

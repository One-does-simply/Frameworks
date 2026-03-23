import { useState } from 'react'
import { useAppStore } from '@/engine/app-store.ts'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Loader2 } from 'lucide-react'

// ---------------------------------------------------------------------------
// AdminSetupScreen — first-run admin account creation
// ---------------------------------------------------------------------------

export function AdminSetupScreen() {
  const app = useAppStore((s) => s.app)!
  const authService = useAppStore((s) => s.authService)!
  const isMultiUserOnly = useAppStore((s) => s.isMultiUserOnly)

  const [username, setUsername] = useState('admin')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  async function handleSetup(e: React.FormEvent) {
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
    const success = await authService.setupAdmin(username.trim(), password)
    setLoading(false)

    if (success) {
      // Refresh store state to pass the auth gate
      useAppStore.setState({
        needsAdminSetup: false,
        needsLogin: false,
      })
    } else {
      setError('Failed to create admin account. Please try again.')
    }
  }

  function handleSkip() {
    // Skip admin setup — proceed without auth
    useAppStore.setState({
      needsAdminSetup: false,
      needsLogin: false,
      isMultiUser: false,
    })
  }

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-background p-4">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle>Create Admin Account</CardTitle>
          <CardDescription>
            Set up the administrator account for {app.appName}.
            This is a one-time setup.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSetup} className="space-y-4">
            {/* Error message */}
            {error && (
              <div className="rounded-lg border border-destructive/50 bg-destructive/10 px-3 py-2 text-sm text-destructive">
                {error}
              </div>
            )}

            {/* Username */}
            <div className="space-y-2">
              <Label htmlFor="admin-username">Username</Label>
              <Input
                id="admin-username"
                type="text"
                autoComplete="username"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                disabled={loading}
              />
            </div>

            {/* Password */}
            <div className="space-y-2">
              <Label htmlFor="admin-password">Password</Label>
              <Input
                id="admin-password"
                type="password"
                autoComplete="new-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Minimum 8 characters"
                disabled={loading}
              />
            </div>

            {/* Confirm Password */}
            <div className="space-y-2">
              <Label htmlFor="admin-confirm-password">Confirm Password</Label>
              <Input
                id="admin-confirm-password"
                type="password"
                autoComplete="new-password"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                placeholder="Re-enter password"
                disabled={loading}
              />
            </div>

            {/* Create button */}
            <Button type="submit" className="w-full" disabled={loading}>
              {loading && <Loader2 className="mr-2 size-4 animate-spin" />}
              Create Admin &amp; Continue
            </Button>

            {/* Skip for now */}
            {!isMultiUserOnly && (
              <Button
                type="button"
                variant="ghost"
                className="w-full"
                onClick={handleSkip}
                disabled={loading}
              >
                Skip for now
              </Button>
            )}
          </form>
        </CardContent>
      </Card>
    </div>
  )
}

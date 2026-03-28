import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router'
import { AuthService } from '@/engine/auth-service.ts'
import pb from '@/lib/pocketbase.ts'
import { Loader2 } from 'lucide-react'

// ---------------------------------------------------------------------------
// OAuth2Callback — handles the redirect back from OAuth2 providers
//
// React strict mode fires effects twice in dev. Since OAuth2 auth codes are
// single-use, we guard with a ref to ensure only one exchange attempt.
// ---------------------------------------------------------------------------

export function OAuth2Callback() {
  const navigate = useNavigate()
  const [error, setError] = useState<string | null>(null)
  const handledRef = useRef(false)

  useEffect(() => {
    if (handledRef.current) return
    handledRef.current = true

    async function handleCallback() {
      const params = new URLSearchParams(window.location.search)
      const code = params.get('code')
      const state = params.get('state')

      if (!code || !state) {
        setError('Missing OAuth2 authorization code. Please try again.')
        return
      }

      const authService = new AuthService(pb)
      const success = await authService.completeOAuth2(code, state)

      if (success) {
        const returnUrl = AuthService.getOAuth2ReturnUrl()
        if (returnUrl) {
          window.location.href = returnUrl
        } else {
          navigate('/', { replace: true })
        }
      } else {
        setError('OAuth2 sign-in failed. Please try again.')
      }
    }

    handleCallback()
  }, [navigate])

  if (error) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center bg-background p-4 gap-4">
        <div className="rounded-lg border border-destructive/50 bg-destructive/10 px-4 py-3 text-sm text-destructive max-w-sm text-center">
          {error}
        </div>
        <button
          onClick={() => navigate('/', { replace: true })}
          className="text-sm text-muted-foreground hover:text-foreground"
        >
          Back to login
        </button>
      </div>
    )
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-background">
      <div className="flex items-center gap-2 text-muted-foreground">
        <Loader2 className="size-5 animate-spin" />
        <span>Completing sign in...</span>
      </div>
    </div>
  )
}

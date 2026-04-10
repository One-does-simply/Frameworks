import { useEffect, useRef, useState } from 'react'
import { useParams, useLocation } from 'react-router'
import { useAppStore } from '@/engine/app-store.ts'
import { AppRegistry } from '@/engine/app-registry.ts'
import { DataService } from '@/engine/data-service.ts'
import { AuthService } from '@/engine/auth-service.ts'
import { LoginScreen } from '@/screens/LoginScreen.tsx'
import { AppShell } from '@/screens/AppShell.tsx'
import { NotFoundScreen } from '@/screens/NotFoundScreen.tsx'
import pb from '@/lib/pocketbase.ts'
import { Loader2, ArchiveIcon } from 'lucide-react'
import { Link } from 'react-router'

// ---------------------------------------------------------------------------
// AppLoader — route component for /:slug/*
// Fetches app from registry, loads into store, then renders auth gate + shell
// ---------------------------------------------------------------------------

export function AppLoader() {
  const { slug } = useParams<{ slug: string }>()
  const location = useLocation()
  const app = useAppStore((s) => s.app)
  const currentSlug = useAppStore((s) => s.currentSlug)
  const needsAdminSetup = useAppStore((s) => s.needsAdminSetup)
  const needsLogin = useAppStore((s) => s.needsLogin)
  const loadSpec = useAppStore((s) => s.loadSpec)
  const navigateTo = useAppStore((s) => s.navigateTo)
  const reset = useAppStore((s) => s.reset)

  const [status, setStatus] = useState<'loading' | 'ready' | 'not-found' | 'archived'>('loading')
  const loadingRef = useRef(false)

  // Extract pageId from the nested wildcard portion of the URL
  // e.g., /my-app/some-page -> pageId = "some-page"
  const pathAfterSlug = slug ? location.pathname.slice(`/${slug}`.length).replace(/^\//, '') : ''
  const pageIdFromUrl = pathAfterSlug || null

  // -------------------------------------------------------------------------
  // Load app when slug changes
  // -------------------------------------------------------------------------

  useEffect(() => {
    if (!slug) {
      setStatus('not-found')
      return
    }

    // Already loaded this app
    if (currentSlug === slug && app) {
      setStatus('ready')
      return
    }

    if (loadingRef.current) return
    loadingRef.current = true

    async function load() {
      // Check if we have a valid PocketBase session from admin login
      const ds = new DataService(pb)
      if (pb.authStore.isValid) {
        await ds.tryRestoreAdminAuth()
      }

      const registry = new AppRegistry(pb)
      const record = await registry.getAppBySlug(slug!)

      if (!record) {
        setStatus('not-found')
        loadingRef.current = false
        return
      }

      if (record.status === 'archived') {
        setStatus('archived')
        loadingRef.current = false
        return
      }

      // Reset previous app state
      reset()

      const authService = new AuthService(pb)
      const success = await loadSpec(record.specJson, ds, authService, slug!)

      if (success) {
        setStatus('ready')
      } else {
        setStatus('not-found')
      }
      loadingRef.current = false
    }

    load()
  }, [slug, currentSlug, app, loadSpec, reset])

  // -------------------------------------------------------------------------
  // Navigate to pageId from URL after app is loaded
  // -------------------------------------------------------------------------

  useEffect(() => {
    if (status === 'ready' && app && pageIdFromUrl && app.pages[pageIdFromUrl]) {
      const currentPageId = useAppStore.getState().currentPageId
      if (currentPageId !== pageIdFromUrl) {
        navigateTo(pageIdFromUrl)
      }
    }
  }, [status, app, pageIdFromUrl, navigateTo])

  // -------------------------------------------------------------------------
  // Render states
  // -------------------------------------------------------------------------

  if (status === 'loading') {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background">
        <div className="flex items-center gap-2 text-muted-foreground">
          <Loader2 className="size-5 animate-spin" />
          <span>Loading app...</span>
        </div>
      </div>
    )
  }

  if (status === 'not-found') {
    return <NotFoundScreen slug={slug} />
  }

  if (status === 'archived') {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-4 bg-background p-4">
        <ArchiveIcon className="size-12 text-muted-foreground" />
        <h1 className="text-2xl font-bold">App Unavailable</h1>
        <p className="text-muted-foreground">
          The app at <code className="rounded bg-muted px-1.5 py-0.5">/{slug}</code> has been
          archived by an administrator.
        </p>
        <Link to="/admin" className="inline-flex items-center justify-center rounded-md border border-input bg-background px-4 py-2 text-sm font-medium hover:bg-accent">Back to Admin</Link>
      </div>
    )
  }

  // App is loaded — auth gate.
  // Show login screen first (lets users choose admin/guest/sign-in).
  // Admin setup only shows if explicitly needed AND no login bypass.
  if (needsLogin || needsAdminSetup) {
    return <LoginScreen />
  }

  return <AppShell />
}

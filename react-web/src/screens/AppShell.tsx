import { useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router'
import { useAppStore } from '@/engine/app-store.ts'
import { PageRenderer } from '@/renderer/PageRenderer.tsx'
import { Button } from '@/components/ui/button'
import { Separator } from '@/components/ui/separator'
import {
  Sheet,
  SheetContent,
  SheetClose,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from '@/components/ui/sheet'
import { toast } from 'sonner'
import {
  Menu,
  ArrowLeft,
  HelpCircle,
  Settings,
  Users,
  LogOut,
  X,
  Download,
} from 'lucide-react'
import { SettingsDialog } from './SettingsDialog.tsx'
import { HelpScreen } from './HelpScreen.tsx'
import { UserManagementScreen } from './UserManagementScreen.tsx'
import { DataExportDialog } from './DataExportDialog.tsx'
import { TourDialog } from './TourDialog.tsx'
import { DebugPanel } from './DebugPanel.tsx'

// ---------------------------------------------------------------------------
// AppShell — the running-app layout with top bar, sidebar nav, and content
// ---------------------------------------------------------------------------

export function AppShell() {
  const routerNavigate = useNavigate()
  const { slug } = useParams<{ slug: string }>()

  const app = useAppStore((s) => s.app)!
  const currentPageId = useAppStore((s) => s.currentPageId)
  const canGoBack = useAppStore((s) => s.canGoBack)
  const goBack = useAppStore((s) => s.goBack)
  const storeNavigateTo = useAppStore((s) => s.navigateTo)
  const reset = useAppStore((s) => s.reset)
  const lastMessage = useAppStore((s) => s.lastMessage)
  const lastActionError = useAppStore((s) => s.lastActionError)
  const isMultiUser = useAppStore((s) => s.isMultiUser)
  const authService = useAppStore((s) => s.authService)
  const debugMode = useAppStore((s) => s.debugMode)

  // Wrap navigateTo to also update the URL
  const navigateTo = (pageId: string) => {
    storeNavigateTo(pageId)
    if (slug) {
      routerNavigate(`/${slug}/${pageId}`, { replace: true })
    }
  }

  const [menuOpen, setMenuOpen] = useState(false)
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [helpOpen, setHelpOpen] = useState(false)
  const [usersOpen, setUsersOpen] = useState(false)
  const [exportOpen, setExportOpen] = useState(false)

  const currentPage = currentPageId ? app.pages[currentPageId] : null
  const pageTitle = currentPage?.title ?? app.appName

  // Help text for the current page
  const pageHelp = currentPageId && app.help?.pages?.[currentPageId]
    ? app.help.pages[currentPageId]
    : null

  // -------------------------------------------------------------------------
  // Toast notifications for store messages/errors
  // -------------------------------------------------------------------------

  const lastMessageRef = useRef(lastMessage)
  const lastErrorRef = useRef(lastActionError)

  useEffect(() => {
    if (lastMessage && lastMessage !== lastMessageRef.current) {
      toast.success(lastMessage)
    }
    lastMessageRef.current = lastMessage
  }, [lastMessage])

  useEffect(() => {
    if (lastActionError && lastActionError !== lastErrorRef.current) {
      toast.error(lastActionError)
    }
    lastErrorRef.current = lastActionError
  }, [lastActionError])

  // -------------------------------------------------------------------------
  // Menu item filtering by role
  // -------------------------------------------------------------------------

  const visibleMenuItems = app.menu.filter((item) => {
    if (!isMultiUser || !authService) return true
    return authService.hasAccess(item.roles)
  })

  // -------------------------------------------------------------------------
  // Handlers
  // -------------------------------------------------------------------------

  function handleNavItem(pageId: string) {
    setMenuOpen(false)
    navigateTo(pageId)
  }

  function handleSignOut() {
    setMenuOpen(false)
    authService?.logout()
    // Force a re-render by resetting auth-related state
    useAppStore.setState({
      needsLogin: true,
    })
  }

  function handleCloseApp() {
    setMenuOpen(false)
    reset()
    routerNavigate('/admin')
  }

  // -------------------------------------------------------------------------
  // Render
  // -------------------------------------------------------------------------

  return (
    <div className="flex min-h-screen flex-col bg-background">
      {/* Top bar */}
      <header className="sticky top-0 z-40 flex h-14 items-center gap-2 border-b bg-background/95 px-4 supports-backdrop-filter:backdrop-blur-sm">
        {/* Menu button */}
        <Button
          variant="ghost"
          size="icon-sm"
          onClick={() => setMenuOpen(true)}
          aria-label="Open menu"
        >
          <Menu className="size-5" />
        </Button>

        {/* Back button */}
        {canGoBack() && (
          <Button
            variant="ghost"
            size="icon-sm"
            onClick={() => goBack()}
            aria-label="Go back"
          >
            <ArrowLeft className="size-5" />
          </Button>
        )}

        {/* Page title */}
        <h1 className="flex-1 truncate text-base font-semibold">{pageTitle}</h1>

        {/* Help button */}
        {app.help && (
          <Button
            variant="ghost"
            size="icon-sm"
            aria-label="Help"
            onClick={() => setHelpOpen(true)}
          >
            <HelpCircle className="size-5" />
          </Button>
        )}
      </header>

      {/* Page help banner */}
      {pageHelp && (
        <div className="border-b bg-blue-50 px-4 py-2 text-sm text-blue-800 dark:bg-blue-950 dark:text-blue-200">
          {pageHelp}
        </div>
      )}

      {/* Main content */}
      <main className="flex-1">
        {currentPage ? (
          <PageRenderer page={currentPage} />
        ) : (
          <div className="flex items-center justify-center p-8 text-muted-foreground">
            Page not found
          </div>
        )}
      </main>

      {/* Debug panel (shown when debug mode is on) */}
      {debugMode && <DebugPanel />}

      {/* Navigation drawer (Sheet from left) */}
      <Sheet open={menuOpen} onOpenChange={setMenuOpen}>
        <SheetContent side="left">
          <SheetHeader>
            <SheetTitle>{app.appName}</SheetTitle>
            {app.help && (
              <SheetDescription className="line-clamp-2">
                {app.help.overview}
              </SheetDescription>
            )}
          </SheetHeader>

          <nav className="mt-4 flex flex-1 flex-col gap-1 overflow-y-auto">
            {/* Navigation section label */}
            {visibleMenuItems.length > 0 && (
              <span className="px-2 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                Navigation
              </span>
            )}

            {/* Menu items */}
            {visibleMenuItems.map((item) => {
              const isActive = item.mapsTo === currentPageId
              return (
                <button
                  key={item.mapsTo}
                  onClick={() => handleNavItem(item.mapsTo)}
                  className={`flex w-full items-center rounded-lg px-3 py-2 text-left text-sm transition-colors ${
                    isActive
                      ? 'bg-primary/10 font-medium text-primary'
                      : 'text-foreground hover:bg-muted'
                  }`}
                >
                  {item.label}
                </button>
              )
            })}

            <Separator className="my-2" />

            {/* Settings */}
            <button
              onClick={() => {
                setMenuOpen(false)
                setSettingsOpen(true)
              }}
              className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-sm text-foreground hover:bg-muted"
            >
              <Settings className="size-4" />
              Settings
            </button>

            {/* Export Data */}
            <button
              onClick={() => {
                setMenuOpen(false)
                setExportOpen(true)
              }}
              className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-sm text-foreground hover:bg-muted"
            >
              <Download className="size-4" />
              Export Data
            </button>

            {/* Multi-user section */}
            {isMultiUser && authService?.isLoggedIn && (
              <>
                <Separator className="my-2" />

                {/* Current user info */}
                <div className="px-3 py-1 text-xs text-muted-foreground">
                  Signed in as {authService.currentUsername}
                </div>

                {/* Admin: Manage Users */}
                {authService.isAdmin && (
                  <button
                    onClick={() => {
                      setMenuOpen(false)
                      setUsersOpen(true)
                    }}
                    className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-sm text-foreground hover:bg-muted"
                  >
                    <Users className="size-4" />
                    Manage Users
                  </button>
                )}

                {/* Sign Out */}
                <button
                  onClick={handleSignOut}
                  className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-sm text-foreground hover:bg-muted"
                >
                  <LogOut className="size-4" />
                  Sign Out
                </button>
              </>
            )}

            <Separator className="my-2" />

            {/* Close App */}
            <SheetClose
              render={
                <button
                  onClick={handleCloseApp}
                  className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-sm text-foreground hover:bg-muted"
                />
              }
            >
              <X className="size-4" />
              Close App
            </SheetClose>
          </nav>
        </SheetContent>
      </Sheet>

      {/* Dialogs */}
      <SettingsDialog open={settingsOpen} onOpenChange={setSettingsOpen} />
      {app.help && <HelpScreen open={helpOpen} onOpenChange={setHelpOpen} />}
      <UserManagementScreen open={usersOpen} onOpenChange={setUsersOpen} />
      <DataExportDialog open={exportOpen} onOpenChange={setExportOpen} />

      {/* Tour dialog — auto-shows on first launch if tour is defined */}
      <TourDialog />
    </div>
  )
}

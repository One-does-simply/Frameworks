import { useEffect, useRef, useState, useCallback } from 'react'
import { useNavigate, useParams } from 'react-router'
import { useAppStore } from '@/engine/app-store.ts'
import { PageRenderer } from '@/renderer/PageRenderer.tsx'
import { Button } from '@/components/ui/button'
import { Separator } from '@/components/ui/separator'
import {
  Sheet,
  SheetContent,
  SheetClose,
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
  LogIn,
  X,
  Save,
  Upload,
  User,
} from 'lucide-react'
import { SettingsDialog } from './SettingsDialog.tsx'
import { HelpScreen } from './HelpScreen.tsx'
import { UserManagementScreen } from './UserManagementScreen.tsx'
import { downloadBackup, restoreBackup } from '@/engine/backup-service.ts'
import { logError } from '@/engine/log-service.ts'
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

  const dataService = useAppStore((s) => s.dataService)

  const [menuOpen, setMenuOpen] = useState(false)
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [helpOpen, setHelpOpen] = useState(false)
  const [usersOpen, setUsersOpen] = useState(false)
  const restoreInputRef = useRef<HTMLInputElement>(null)

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

  // If the current page is role-restricted and the user can't access it,
  // redirect to the first accessible page (e.g., guest on an admin startPage).
  useEffect(() => {
    if (!currentPageId || !isMultiUser || !authService) return
    const page = app.pages[currentPageId]
    if (page?.roles && page.roles.length > 0 && !authService.hasAccess(page.roles)) {
      const fallback = visibleMenuItems[0]?.mapsTo
      if (fallback && fallback !== currentPageId) {
        storeNavigateTo(fallback)
      }
    }
  }, [currentPageId, isMultiUser, authService, app.pages, visibleMenuItems, storeNavigateTo])

  // -------------------------------------------------------------------------
  // Handlers
  // -------------------------------------------------------------------------

  function handleNavItem(pageId: string) {
    setMenuOpen(false)
    navigateTo(pageId)
  }

  function handleSignOut() {
    setMenuOpen(false)
    // Clear all auth state — superadmin flag, PB auth, form data
    authService?.setSuperAdmin(false)
    authService?.logout()
    useAppStore.setState({
      needsLogin: true,
      formStates: {},
      recordCursors: {},
    })
  }

  function handleCloseApp() {
    setMenuOpen(false)
    reset()
    routerNavigate('/admin')
  }

  async function handleBackup() {
    if (!dataService) return
    setMenuOpen(false)
    try {
      await downloadBackup(app, dataService)
      toast.success('Backup downloaded')
    } catch (e) {
      toast.error('Backup failed')
      logError('AppShell', 'Backup failed', e)
    }
  }

  const handleRestoreFile = useCallback(async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file || !dataService) return

    const text = await file.text()
    const error = await restoreBackup(text, app, dataService)
    if (error) {
      toast.error(error)
    } else {
      toast.success('Data restored from backup')
      // Bump generation to refresh lists
      useAppStore.setState({ recordGeneration: useAppStore.getState().recordGeneration + 1 })
    }

    if (restoreInputRef.current) restoreInputRef.current.value = ''
  }, [app, dataService])

  // -------------------------------------------------------------------------
  // Render
  // -------------------------------------------------------------------------

  return (
    <div className="flex min-h-screen flex-col bg-background">
      {/* Top bar — respects branding.headerStyle */}
      <header className={`sticky top-0 z-40 flex h-14 items-center gap-2 px-4 ${
        app.branding.headerStyle === 'solid'
          ? 'bg-primary text-primary-foreground border-b border-primary/20'
          : app.branding.headerStyle === 'transparent'
            ? ''
            : 'border-b bg-background/95 supports-backdrop-filter:backdrop-blur-sm'
      }`}>
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

        {/* User indicator / login button */}
        {isMultiUser && authService && (
          authService.isSuperAdmin ? (
            <div className="flex items-center gap-1.5 rounded-md px-2 py-1 text-xs text-muted-foreground">
              <User className="size-3.5" />
              <span>Admin</span>
            </div>
          ) : authService.isLoggedIn ? (
            <div className="flex items-center gap-1.5 rounded-md px-2 py-1 text-xs text-muted-foreground">
              <User className="size-3.5" />
              <span className="max-w-24 truncate">{authService.currentDisplayName}</span>
            </div>
          ) : (
            <Button
              variant="ghost"
              size="sm"
              className="text-xs"
              onClick={() => {
                useAppStore.setState({ needsLogin: true })
              }}
            >
              <LogIn className="mr-1.5 size-3.5" />
              Sign In
            </Button>
          )
        )}

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
          {/* Drawer header — branded with primaryColor or gradient */}
          <div className="-mx-6 -mt-6 mb-2 rounded-b-xl bg-primary px-6 py-5">
            {app.branding.logo ? (
              <img src={app.branding.logo} alt={app.appName} className="mb-2 h-8 object-contain object-left" />
            ) : null}
            <SheetTitle className="text-lg font-bold text-primary-foreground">{app.appName}</SheetTitle>
            {app.help && (
              <SheetDescription className="mt-1 line-clamp-2 text-primary-foreground/75">
                {app.help.overview}
              </SheetDescription>
            )}
          </div>

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

            {/* Admin-only drawer items: settings, backup, restore */}
            {(!isMultiUser || authService?.isAdmin) && (
              <>
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

                {/* Backup */}
                <button
                  onClick={handleBackup}
                  className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-sm text-foreground hover:bg-muted"
                >
                  <Save className="size-4" />
                  Backup Data
                </button>

                {/* Restore */}
                <button
                  onClick={() => {
                    setMenuOpen(false)
                    restoreInputRef.current?.click()
                  }}
                  className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-sm text-foreground hover:bg-muted"
                >
                  <Upload className="size-4" />
                  Restore Data
                </button>

                {/* Hidden file input for restore */}
                <input
                  ref={restoreInputRef}
                  type="file"
                  accept=".json,application/json"
                  className="hidden"
                  onChange={handleRestoreFile}
                />
              </>
            )}

            {/* Multi-user section */}
            {isMultiUser && (
              <>
                <Separator className="my-2" />

                {authService?.isLoggedIn ? (
                  <>
                    {/* Current user info */}
                    <div className="px-3 py-1 text-xs text-muted-foreground">
                      Signed in as {authService.currentDisplayName}
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
                ) : (
                  <>
                    {/* Guest — show sign in option */}
                    <div className="px-3 py-1 text-xs text-muted-foreground">
                      Browsing as Guest
                    </div>
                    <button
                      onClick={() => {
                        setMenuOpen(false)
                        useAppStore.setState({ needsLogin: true, formStates: {}, recordCursors: {} })
                      }}
                      className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-sm text-foreground hover:bg-muted"
                    >
                      <LogIn className="size-4" />
                      Sign In
                    </button>
                  </>
                )}
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

      {/* Tour dialog — auto-shows on first launch if tour is defined */}
      <TourDialog />
    </div>
  )
}

import { useAppStore } from '@/engine/app-store.ts'
import { WelcomeScreen } from '@/screens/WelcomeScreen.tsx'
import { AdminSetupScreen } from '@/screens/AdminSetupScreen.tsx'
import { LoginScreen } from '@/screens/LoginScreen.tsx'
import { AppShell } from '@/screens/AppShell.tsx'
import { Toaster } from '@/components/ui/sonner'

// ---------------------------------------------------------------------------
// App — root component with auth gate routing
// ---------------------------------------------------------------------------

export default function App() {
  const app = useAppStore((s) => s.app)
  const needsAdminSetup = useAppStore((s) => s.needsAdminSetup)
  const needsLogin = useAppStore((s) => s.needsLogin)

  let content: React.ReactNode

  if (!app) {
    content = <WelcomeScreen />
  } else if (needsAdminSetup) {
    content = <AdminSetupScreen />
  } else if (needsLogin) {
    content = <LoginScreen />
  } else {
    content = <AppShell />
  }

  return (
    <>
      {content}
      <Toaster position="bottom-right" richColors closeButton />
    </>
  )
}

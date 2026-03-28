import { Routes, Route } from 'react-router'
import { AdminGuard } from '@/screens/AdminGuard.tsx'
import { AdminDashboard } from '@/screens/AdminDashboard.tsx'
import { AdminSettingsPage } from '@/screens/AdminSettingsPage.tsx'
import { UserManagementPage } from '@/screens/UserManagementPage.tsx'
import { AppEditor } from '@/screens/AppEditor.tsx'
import { EditWithAiScreen } from '@/screens/EditWithAiScreen.tsx'
import { QuickBuildScreen } from '@/screens/QuickBuildScreen.tsx'
import { AppLoader } from '@/screens/AppLoader.tsx'
import { RootRedirect } from '@/screens/RootRedirect.tsx'
import { OAuth2Callback } from '@/screens/OAuth2Callback.tsx'
import { Toaster } from '@/components/ui/sonner'

// ---------------------------------------------------------------------------
// App — root component with React Router multi-app routing
// ---------------------------------------------------------------------------

export default function App() {
  return (
    <>
      <Routes>
        <Route path="/admin" element={<AdminGuard />}>
          <Route index element={<AdminDashboard />} />
          <Route path="users" element={<UserManagementPage />} />
          <Route path="settings" element={<AdminSettingsPage />} />
          <Route path="apps/:appId/edit" element={<AppEditor />} />
          <Route path="apps/:appId/edit-ai" element={<EditWithAiScreen />} />
          <Route path="quick-build" element={<QuickBuildScreen />} />
        </Route>
        <Route path="/oauth2-callback" element={<OAuth2Callback />} />
        <Route path="/:slug/*" element={<AppLoader />} />
        <Route path="/" element={<RootRedirect />} />
      </Routes>
      <Toaster position="bottom-right" richColors closeButton />
    </>
  )
}

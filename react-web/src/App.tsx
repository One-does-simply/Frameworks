import { Routes, Route, Navigate } from 'react-router'
import { AdminGuard } from '@/screens/AdminGuard.tsx'
import { AdminDashboard } from '@/screens/AdminDashboard.tsx'
import { UserManagementPage } from '@/screens/UserManagementPage.tsx'
import { AppEditor } from '@/screens/AppEditor.tsx'
import { AppLoader } from '@/screens/AppLoader.tsx'
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
          <Route path="apps/:appId/edit" element={<AppEditor />} />
        </Route>
        <Route path="/:slug/*" element={<AppLoader />} />
        <Route path="/" element={<Navigate to="/admin" replace />} />
      </Routes>
      <Toaster position="bottom-right" richColors closeButton />
    </>
  )
}

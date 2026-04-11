import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router'
import './index.css'
import App from './App.tsx'
import { applyTheme, listenForSystemThemeChanges } from './engine/theme-store.ts'
import { initLogService, logError } from './engine/log-service.ts'

// Initialize logging before anything else
initLogService()

// Capture unhandled errors globally
window.addEventListener('error', (e) => {
  logError('Window', `Unhandled error: ${e.message}`, {
    filename: e.filename,
    lineno: e.lineno,
    colno: e.colno,
    error: e.error,
  })
})

window.addEventListener('unhandledrejection', (e) => {
  logError('Window', 'Unhandled promise rejection', e.reason)
})

// Apply persisted theme before first paint
applyTheme()
const cleanupThemeListener = listenForSystemThemeChanges()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </StrictMode>,
)

// Cleanup on HMR (Vite dev)
if (import.meta.hot) {
  import.meta.hot.dispose(() => cleanupThemeListener())
}

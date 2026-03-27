import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router'
import './index.css'
import App from './App.tsx'
import { applyTheme, listenForSystemThemeChanges } from './engine/theme-store.ts'

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

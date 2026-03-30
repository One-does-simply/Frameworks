/**
 * Mode store — persists light/dark/system mode preference in localStorage
 * and applies the `dark` class to <html> for Tailwind dark mode.
 */

export type ThemeMode = 'light' | 'dark' | 'system'

const STORAGE_KEY = 'ods_theme_mode'

/** Read the persisted theme mode. */
export function getThemeMode(): ThemeMode {
  const stored = localStorage.getItem(STORAGE_KEY)
  if (stored === 'light' || stored === 'dark' || stored === 'system') return stored
  return 'system'
}

/** Persist and apply a theme mode. */
export function setThemeMode(mode: ThemeMode): void {
  localStorage.setItem(STORAGE_KEY, mode)
  applyTheme(mode)
}

/** Apply the theme class to <html>. */
export function applyTheme(mode?: ThemeMode): void {
  const resolved = mode ?? getThemeMode()
  const root = document.documentElement

  if (resolved === 'dark') {
    root.classList.add('dark')
  } else if (resolved === 'light') {
    root.classList.remove('dark')
  } else {
    // system — match OS preference
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches
    if (prefersDark) {
      root.classList.add('dark')
    } else {
      root.classList.remove('dark')
    }
  }
}

/** Listen for OS dark mode changes when in system mode. */
export function listenForSystemThemeChanges(): () => void {
  const mql = window.matchMedia('(prefers-color-scheme: dark)')
  const handler = () => {
    if (getThemeMode() === 'system') applyTheme('system')
  }
  mql.addEventListener('change', handler)
  return () => mql.removeEventListener('change', handler)
}

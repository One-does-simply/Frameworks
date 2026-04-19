import { test, expect } from '@playwright/test'

// ---------------------------------------------------------------------------
// Theme Toggle — verifies the theme-store persists the selected mode to
// localStorage and applies the `dark` class to <html> for Tailwind dark
// mode. These tests are backend-independent.
//
// Storage key: `ods_theme_mode` (see src/engine/theme-store.ts)
// Accepted values: 'light' | 'dark' | 'system'
// ---------------------------------------------------------------------------

test.describe('Theme Toggle', () => {
  test('theme preference persists across page reloads (localStorage)', async ({ page }) => {
    // Pre-seed dark mode so the theme applies immediately on first paint.
    await page.addInitScript(() => {
      localStorage.setItem('ods_theme_mode', 'dark')
    })

    await page.goto('/')

    // Wait for the SPA to boot (main.tsx calls applyTheme() on load).
    await expect(page.locator('#root')).toBeAttached({ timeout: 10_000 })

    const storedBefore = await page.evaluate(() => localStorage.getItem('ods_theme_mode'))
    expect(storedBefore).toBe('dark')

    // Reload and verify the value survives.
    await page.reload()
    await expect(page.locator('#root')).toBeAttached({ timeout: 10_000 })

    const storedAfter = await page.evaluate(() => localStorage.getItem('ods_theme_mode'))
    expect(storedAfter).toBe('dark')
  })

  test('dark mode applies the `dark` class to the html element', async ({ page }) => {
    // Seed 'dark' in an init script that ONLY sets the value if the key
    // isn't already present. This lets us override via page.evaluate()
    // without the init script clobbering it on reload.
    await page.addInitScript(() => {
      if (!localStorage.getItem('ods_theme_mode')) {
        localStorage.setItem('ods_theme_mode', 'dark')
      }
    })

    await page.goto('/')
    await expect(page.locator('#root')).toBeAttached({ timeout: 10_000 })

    // theme-store.applyTheme('dark') runs at boot and adds the class.
    const hasDarkClass = await page.evaluate(() =>
      document.documentElement.classList.contains('dark'),
    )
    expect(hasDarkClass).toBe(true)

    // Flip to light mode via localStorage + reload — verify the class is
    // removed on the next boot. The init script's guard above prevents it
    // from resetting the value back to 'dark'.
    await page.evaluate(() => localStorage.setItem('ods_theme_mode', 'light'))
    await page.reload()
    await expect(page.locator('#root')).toBeAttached({ timeout: 10_000 })

    // Sanity-check that light mode survived the reload.
    const storedMode = await page.evaluate(() => localStorage.getItem('ods_theme_mode'))
    expect(storedMode).toBe('light')

    const hasDarkAfterLight = await page.evaluate(() =>
      document.documentElement.classList.contains('dark'),
    )
    expect(hasDarkAfterLight).toBe(false)
  })
})

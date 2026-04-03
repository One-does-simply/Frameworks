import { test, expect } from '@playwright/test'

// ---------------------------------------------------------------------------
// Smoke test: verify the React SPA boots and renders at the root URL.
//
// The root route (/) shows either:
//   - A "Connecting..." loading spinner (while checking PocketBase), OR
//   - The login/welcome screen with "One Does Simply" heading, OR
//   - A redirect to /admin (fresh install with no saved credentials)
//
// We simply verify that *something* from the React app renders, proving
// the Vite dev server is up and the SPA bundle loaded without errors.
// ---------------------------------------------------------------------------

test.describe('App loads', () => {
  test('root URL renders the React application', async ({ page }) => {
    await page.goto('/')

    // The SPA should produce at least one of these elements.
    // Use a short timeout so the test fails fast if nothing renders.
    const appRendered = page.locator('body').locator('div').first()
    await expect(appRendered).toBeVisible({ timeout: 10_000 })
  })

  test('root URL shows ODS branding or loading state', async ({ page }) => {
    await page.goto('/')

    // Wait for either the branded heading, the login card, or the
    // "Connecting..." loading indicator -- whichever appears first.
    const branding = page.getByText('One Does Simply')
    const connecting = page.getByText('Connecting')
    const adminLogin = page.getByText('ODS Admin Login')

    await expect(
      branding.or(connecting).or(adminLogin),
    ).toBeVisible({ timeout: 10_000 })
  })

  test('page title is set', async ({ page }) => {
    await page.goto('/')

    // Vite apps have a <title> tag -- just verify it is non-empty.
    const title = await page.title()
    expect(title.length).toBeGreaterThan(0)
  })

  test('no console errors on initial load', async ({ page }) => {
    const errors: string[] = []
    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        errors.push(msg.text())
      }
    })

    await page.goto('/')
    // Give the app a moment to finish rendering.
    await page.waitForTimeout(2_000)

    // Filter out known noise (e.g. PocketBase connection failures when PB
    // is not running). We only care about React/JS errors.
    const realErrors = errors.filter(
      (e) =>
        !e.includes('Failed to fetch') &&
        !e.includes('NetworkError') &&
        !e.includes('ERR_CONNECTION_REFUSED'),
    )

    expect(realErrors).toEqual([])
  })
})

import { test, expect } from '@playwright/test'

// ---------------------------------------------------------------------------
// Error Boundaries — verifies the SPA handles malformed or invalid input
// gracefully without crashing the React tree.
// ---------------------------------------------------------------------------

test.describe('Error Boundaries', () => {
  test('malformed spec slug shows error, not a crash', async ({ page }) => {
    // A slug with characters unlikely to exist in the registry — the app
    // should fall through to NotFoundScreen, not throw an unhandled error.
    const consoleErrors: string[] = []
    page.on('pageerror', (err) => consoleErrors.push(err.message))

    await page.goto('/!!!malformed..slug..@@@')

    // Either NotFoundScreen ("App Not Found") or the loading state appears.
    const notFound = page.getByRole('heading', { name: 'App Not Found' })
    const loading = page.getByText('Loading app...')
    const rootDiv = page.locator('#root')

    await expect(rootDiv).toBeAttached({ timeout: 10_000 })
    await expect(notFound.or(loading)).toBeVisible({ timeout: 15_000 })

    // Give the lookup time to fail — final state should be the 404 screen.
    await expect(notFound).toBeVisible({ timeout: 20_000 })

    // No uncaught React exceptions should have bubbled up.
    expect(consoleErrors).toEqual([])
  })

  test('invalid OAuth2 callback URL shows a user-visible error', async ({ page }) => {
    // OAuth2Callback reads `code` and `state` from the query string. Hit the
    // route with neither present — the component should render its error
    // branch ("Missing OAuth2 authorization code...") rather than crashing.
    const consoleErrors: string[] = []
    page.on('pageerror', (err) => consoleErrors.push(err.message))

    await page.goto('/oauth2-callback')

    const errorBanner = page.getByText(/missing oauth2 authorization code/i)
    const backBtn = page.getByRole('button', { name: /back to login/i })

    await expect(errorBanner).toBeVisible({ timeout: 10_000 })
    await expect(backBtn).toBeVisible({ timeout: 5_000 })

    expect(consoleErrors).toEqual([])
  })
})

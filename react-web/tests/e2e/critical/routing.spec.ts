import { test, expect } from '@playwright/test'

// ---------------------------------------------------------------------------
// Routing — verifies React Router resolves routes correctly and the
// RootRedirect component applies the right redirect logic.
//
// These tests mostly exercise client-side routing and do not require a
// working PocketBase instance.
// ---------------------------------------------------------------------------

test.describe('Routing', () => {
  test('visiting a non-existent slug shows App Not Found', async ({ page }) => {
    await page.goto('/definitely-not-a-real-app-slug-xyz')

    // AppLoader should render NotFoundScreen once the registry lookup fails.
    // It may briefly show "Loading app..." first. Accept either, but expect
    // "App Not Found" eventually.
    const notFound = page.getByRole('heading', { name: 'App Not Found' })
    const loading = page.getByText('Loading app...')

    await expect(notFound.or(loading)).toBeVisible({ timeout: 10_000 })

    // Give the registry call time to fail before asserting the final state.
    await expect(notFound).toBeVisible({ timeout: 20_000 })
  })

  test('visiting / redirects based on RootRedirect logic', async ({ page }) => {
    // RootRedirect will:
    //   - redirect to /admin if no default app is configured, OR
    //   - show the welcome login chooser if a default exists
    //
    // We seed NO default slug to guarantee the redirect path, then assert
    // either the admin login card or the "Welcome" chooser is visible.
    await page.context().clearCookies()
    await page.addInitScript(() => {
      localStorage.removeItem('ods_default_app_slug')
    })

    await page.goto('/')

    const adminLogin = page.getByText('ODS Admin Login')
    const connecting = page.getByText('Connecting')
    const welcome = page.getByRole('heading', { name: 'Welcome' })

    await expect(adminLogin.or(connecting).or(welcome)).toBeVisible({
      timeout: 15_000,
    })
  })

  test('direct URL to /admin/settings respects the admin guard', async ({ page }) => {
    await page.goto('/admin/settings')

    // Without auth, AdminGuard intercepts and shows the login card.
    const adminLogin = page.getByText('ODS Admin Login')
    const connecting = page.getByText('Connecting to PocketBase')
    const settingsHeading = page.getByRole('heading', { name: /settings/i })

    await expect(
      adminLogin.or(connecting).or(settingsHeading),
    ).toBeVisible({ timeout: 10_000 })

    // Once the PB probe resolves, the guard should land on the login card
    // (since we have no valid session).
    await expect(adminLogin).toBeVisible({ timeout: 15_000 })
  })

  test('browser back button works across page transitions', async ({ page }) => {
    // Navigate through a short history stack and verify `goBack` works.
    await page.goto('/admin')
    await expect(page.locator('#root')).toBeAttached({ timeout: 10_000 })

    await page.goto('/admin/settings')
    await expect(page.locator('#root')).toBeAttached({ timeout: 10_000 })

    await page.goto('/admin/quick-build')
    await expect(page.locator('#root')).toBeAttached({ timeout: 10_000 })

    // Go back once — should land on /admin/settings.
    await page.goBack()
    await expect(page).toHaveURL(/\/admin\/settings$/, { timeout: 5_000 })

    // Go back again — should land on /admin.
    await page.goBack()
    await expect(page).toHaveURL(/\/admin$/, { timeout: 5_000 })

    // Forward once — back to /admin/settings.
    await page.goForward()
    await expect(page).toHaveURL(/\/admin\/settings$/, { timeout: 5_000 })
  })
})

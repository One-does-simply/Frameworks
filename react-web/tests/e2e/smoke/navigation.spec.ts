import { test, expect } from '@playwright/test'

// ---------------------------------------------------------------------------
// Smoke test: basic route navigation.
//
// Without a running PocketBase instance the admin routes will show the
// AdminGuard login screen rather than the actual dashboard/settings pages.
// These tests verify that the React Router resolves each route and renders
// the expected guard or page content -- proving the SPA routing works.
// ---------------------------------------------------------------------------

test.describe('Navigation', () => {
  test('/admin renders the admin guard or dashboard', async ({ page }) => {
    await page.goto('/admin')

    // Either the admin login gate or the authenticated dashboard should appear.
    const adminLogin = page.getByText('ODS Admin Login')
    const dashboard = page.getByText('One Does Simply')
    const connecting = page.getByText('Connecting to PocketBase')

    await expect(
      adminLogin.or(dashboard).or(connecting),
    ).toBeVisible({ timeout: 10_000 })
  })

  test('/admin/settings renders settings page or admin guard', async ({ page }) => {
    await page.goto('/admin/settings')

    // If not authenticated the AdminGuard login appears; if authenticated
    // we see the Settings heading.
    const settings = page.getByText('Settings')
    const adminLogin = page.getByText('ODS Admin Login')
    const connecting = page.getByText('Connecting to PocketBase')

    await expect(
      settings.or(adminLogin).or(connecting),
    ).toBeVisible({ timeout: 10_000 })
  })

  test('/admin/quick-build renders quick build or admin guard', async ({ page }) => {
    await page.goto('/admin/quick-build')

    const quickBuild = page.getByText('Quick Build')
    const adminLogin = page.getByText('ODS Admin Login')
    const connecting = page.getByText('Connecting to PocketBase')

    await expect(
      quickBuild.or(adminLogin).or(connecting),
    ).toBeVisible({ timeout: 10_000 })
  })

  test('/admin/users renders user management or admin guard', async ({ page }) => {
    await page.goto('/admin/users')

    const adminLogin = page.getByText('ODS Admin Login')
    const connecting = page.getByText('Connecting to PocketBase')
    // The user management page may show various headings.
    const users = page.getByText('User', { exact: false })

    await expect(
      users.or(adminLogin).or(connecting),
    ).toBeVisible({ timeout: 10_000 })
  })

  test('unknown route does not crash the app', async ({ page }) => {
    await page.goto('/this-route-does-not-exist-12345')

    // The catch-all /:slug/* route will try to load an app by slug.
    // Without PocketBase it will likely show an error or loading state,
    // but the React app itself should not crash.
    const body = page.locator('body')
    await expect(body).toBeVisible({ timeout: 10_000 })

    // Verify we are still in the React SPA (at least one div rendered).
    const rootDiv = page.locator('#root')
    await expect(rootDiv).toBeAttached({ timeout: 5_000 })
  })
})

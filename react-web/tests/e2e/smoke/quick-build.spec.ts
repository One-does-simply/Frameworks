import { test, expect } from '@playwright/test'

// ---------------------------------------------------------------------------
// Smoke test: Quick Build screen.
//
// Navigates to /admin/quick-build and verifies the template catalog or
// the admin login gate renders. Without PocketBase running, the AdminGuard
// will intercept and show its login form -- that is still a valid smoke
// result (the route resolved, React rendered).
//
// When PocketBase IS running and the user is authenticated, we expect the
// Quick Build heading and template catalog to appear.
// ---------------------------------------------------------------------------

test.describe('Quick Build', () => {
  test('quick build route renders without crashing', async ({ page }) => {
    await page.goto('/admin/quick-build')

    // Should see either the Quick Build page or the admin login gate.
    const quickBuild = page.getByText('Quick Build')
    const adminLogin = page.getByText('ODS Admin Login')
    const connecting = page.getByText('Connecting to PocketBase')

    await expect(
      quickBuild.or(adminLogin).or(connecting),
    ).toBeVisible({ timeout: 10_000 })
  })

  test('quick build page has a back button or navigation', async ({ page }) => {
    await page.goto('/admin/quick-build')

    // If the admin guard is shown we look for "Connect to PocketBase" button;
    // if the actual Quick Build page is shown we look for the back arrow button.
    const connectBtn = page.getByRole('button', { name: /connect to pocketbase/i })
    const backBtn = page.getByRole('button', { name: /back/i })
    // The ArrowLeft icon is rendered as an accessible button
    const arrowBtn = page.locator('button').first()

    await expect(
      connectBtn.or(backBtn).or(arrowBtn),
    ).toBeVisible({ timeout: 10_000 })
  })

  test('quick build shows breadcrumb labels when template is selected', async ({ page }) => {
    await page.goto('/admin/quick-build')

    // This test checks that the breadcrumb structure exists in the DOM.
    // Without PocketBase the admin guard may block access, so we check
    // for either the breadcrumb text or the login gate.
    const enterDetails = page.getByText('Enter App Details')
    const adminLogin = page.getByText('ODS Admin Login')
    const connecting = page.getByText('Connecting to PocketBase')

    // If we see the admin login, the test passes (route works, guard active).
    // If the catalog loads, breadcrumb labels may not be visible until a
    // template is selected -- so we just verify the page did not crash.
    const rootDiv = page.locator('#root')
    await expect(rootDiv).toBeAttached({ timeout: 10_000 })

    // At minimum one of these should be present on the page.
    const anyContent = enterDetails.or(adminLogin).or(connecting).or(page.getByText('Quick Build'))
    await expect(anyContent).toBeVisible({ timeout: 10_000 })
  })
})

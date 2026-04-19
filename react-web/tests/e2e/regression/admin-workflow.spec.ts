import { test, expect } from '../helpers/fixtures'
import { clearSeededApps, seedApp } from '../helpers/app-seed'

// ---------------------------------------------------------------------------
// Admin workflow — tests that exercise the real admin authenticated flow
// against a live PocketBase instance. These supersede the PB-absent smoke
// tests in critical/admin-guard.spec.ts for happy-path coverage.
// ---------------------------------------------------------------------------

test.describe('Admin login (real PB)', () => {
  test('unauthenticated /admin shows login card', async ({ page }) => {
    await page.goto('/admin')
    await expect(page.getByText('ODS Admin Login')).toBeVisible({ timeout: 15_000 })
  })

  test('admin can sign in via the login card and land past the gate', async ({
    page,
  }) => {
    await page.goto('/admin')
    await expect(page.getByText('ODS Admin Login')).toBeVisible({ timeout: 15_000 })

    await page.locator('#admin-email').fill('admin@e2e.local')
    await page.locator('#admin-password').fill('e2e-test-pass-1234')
    await page.getByRole('button', { name: /connect to pocketbase/i }).click()

    // Either the dashboard or onboarding (first-run empty-state) is OK.
    const dashboard = page.getByRole('heading', { name: /my apps/i })
    const onboarding = page.getByRole('heading', { name: /welcome to ods/i })
    await expect(dashboard.or(onboarding)).toBeVisible({ timeout: 20_000 })
  })

  test('admin with wrong password stays on login card', async ({ page }) => {
    await page.goto('/admin')
    await expect(page.getByText('ODS Admin Login')).toBeVisible({ timeout: 15_000 })

    await page.locator('#admin-email').fill('admin@e2e.local')
    await page.locator('#admin-password').fill('definitely-wrong')
    await page.getByRole('button', { name: /connect to pocketbase/i }).click()

    // Give the request time to fail and the UI to settle back to the card.
    await page.waitForTimeout(500)
    await expect(page.getByText('ODS Admin Login')).toBeVisible()
    await expect(page.getByRole('heading', { name: /my apps/i })).toHaveCount(0)
  })
})

test.describe('Admin dashboard (authenticated)', () => {
  test('dashboard shows seeded apps', async ({ adminPage }) => {
    await clearSeededApps()
    await seedApp('Sample One')
    await seedApp('Sample Two')

    // Re-authenticate so the dashboard re-fetches against the seeded state.
    await adminPage.goto('/admin')
    await expect(adminPage.getByRole('heading', { name: /my apps/i })).toBeVisible({
      timeout: 20_000,
    })

    await expect(adminPage.getByText('Sample One')).toBeVisible({ timeout: 10_000 })
    await expect(adminPage.getByText('Sample Two')).toBeVisible({ timeout: 10_000 })
  })

  test('empty dashboard renders without an error screen', async ({ adminPage }) => {
    await clearSeededApps()
    await adminPage.goto('/admin')
    // With no apps seeded, the admin lands on either the onboarding
    // screen or the empty "My Apps" dashboard — both are valid
    // non-error states.
    const dashboard = adminPage.getByRole('heading', { name: /my apps/i })
    const onboarding = adminPage.getByRole('heading', { name: /welcome to ods/i })
    await expect(dashboard.or(onboarding)).toBeVisible({ timeout: 20_000 })
    await expect(adminPage.getByText(/failed to load|something went wrong/i)).toHaveCount(0)
  })

  test('admin can reach the quick-build route from the dashboard', async ({
    adminPage,
  }) => {
    await adminPage.goto('/admin/quick-build')
    await expect(
      adminPage
        .getByRole('heading', { name: /quick build/i })
        .or(adminPage.getByText(/quick build/i).first()),
    ).toBeVisible({ timeout: 10_000 })
  })
})

import { test as base, type Page, expect } from '@playwright/test'
import { clearSeededApps } from './app-seed'
import { E2E_SUPERADMIN } from './pocketbase-admin'
import { PB_URL } from './pb-client'

/**
 * Shared Playwright fixtures for ODS E2E tests.
 *
 * - `adminPage`: a Page already past the AdminGuard. The app intentionally
 *   clears `pb.authStore` on every module load (see src/lib/pocketbase.ts),
 *   so we have to go through the real login card rather than seeding
 *   localStorage — each test pays ~1 form submit to reach the dashboard.
 * - `cleanSlate`: opt-in side effect that clears the _ods_apps collection
 *   before a test runs.
 */

async function authenticateAsSuperadmin(page: Page): Promise<void> {
  await page.goto('/admin')
  await expect(page.getByText('ODS Admin Login')).toBeVisible({ timeout: 20_000 })
  await page.locator('#admin-email').fill(E2E_SUPERADMIN.email)
  await page.locator('#admin-password').fill(E2E_SUPERADMIN.password)
  await page.getByRole('button', { name: /connect to pocketbase/i }).click()
  // "Past-the-gate" is either the empty-state onboarding (when no apps
  // exist yet) or the "My Apps" dashboard heading. Either counts as a
  // successful login.
  const dashboard = page.getByRole('heading', { name: /my apps/i })
  const onboarding = page.getByRole('heading', { name: /welcome to ods/i })
  await expect(dashboard.or(onboarding)).toBeVisible({ timeout: 20_000 })
  // If onboarding is up, dismiss it so tests land on the real dashboard.
  if (await onboarding.isVisible()) {
    await page.getByRole('button', { name: /skip/i }).click()
    await expect(dashboard).toBeVisible({ timeout: 10_000 })
  }
}

export interface OdsFixtures {
  /**
   * A Page with the superadmin already authenticated. The admin dashboard
   * is NOT navigated to — call `adminPage.goto('/admin')` yourself so you
   * can assert the initial load.
   */
  adminPage: Page
  /** Resets the seeded apps before this test runs. */
  cleanSlate: void
}

export const test = base.extend<OdsFixtures>({
  adminPage: async ({ page }, use) => {
    await authenticateAsSuperadmin(page)
    await use(page)
  },
  cleanSlate: [
    async ({}, use) => {
      await clearSeededApps()
      await use()
    },
    { auto: false },
  ],
})

export { expect } from '@playwright/test'
export { PB_URL }

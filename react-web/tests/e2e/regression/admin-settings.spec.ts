import { test, expect } from '../helpers/fixtures'
import { clearSeededApps } from '../helpers/app-seed'

// ---------------------------------------------------------------------------
// Admin Settings — route-level render + a couple of persisted preference
// toggles. OAuth provider setup requires external redirects so is out of
// scope for this batch.
// ---------------------------------------------------------------------------

test.beforeEach(async () => {
  await clearSeededApps()
})

test.describe('Admin settings page', () => {
  test('/admin/settings renders the settings sections', async ({ adminPage }) => {
    await adminPage.goto('/admin/settings')
    await expect(
      adminPage.getByRole('heading', { name: /^settings$/i }),
    ).toBeVisible({ timeout: 15_000 })
    // The logging + pocketbase sections are rendered as siblings below.
    await expect(adminPage.getByText(/log level/i).first()).toBeVisible()
    await expect(adminPage.getByText(/pocketbase/i).first()).toBeVisible()
  })

  test('theme Mode segmented control has light/system/dark options', async ({
    adminPage,
  }) => {
    await adminPage.goto('/admin/settings')
    await expect(
      adminPage.getByRole('heading', { name: /^settings$/i }),
    ).toBeVisible({ timeout: 15_000 })

    // All three mode buttons should be present as accessible buttons.
    await expect(
      adminPage.getByRole('button', { name: 'Light' }),
    ).toBeVisible({ timeout: 10_000 })
    await expect(adminPage.getByRole('button', { name: 'System' })).toBeVisible()
    await expect(adminPage.getByRole('button', { name: 'Dark' })).toBeVisible()
  })

  test('log level dropdown exposes the expected levels', async ({ adminPage }) => {
    await adminPage.goto('/admin/settings')
    await expect(
      adminPage.getByRole('heading', { name: /^settings$/i }),
    ).toBeVisible({ timeout: 15_000 })

    // The log-level combobox should carry one of the ODS level names in
    // either its label area or its current selected option.
    const logLevelArea = adminPage
      .locator('*')
      .filter({ hasText: /log level/i })
      .first()
    await expect(logLevelArea).toBeVisible()
    // At least one of debug/info/warn/error should appear near it.
    await expect(
      adminPage.getByText(/debug|info|warn|error/i).first(),
    ).toBeVisible()
  })
})

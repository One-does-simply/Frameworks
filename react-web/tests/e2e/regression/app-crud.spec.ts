import { test, expect } from '../helpers/fixtures'
import { clearSeededApps, seedApp, minimalTodoSpec, helloSpec } from '../helpers/app-seed'

// ---------------------------------------------------------------------------
// App CRUD — seeded-app navigation, form submit, list refresh, archive,
// and the context-menu-driven operations on the admin dashboard.
// ---------------------------------------------------------------------------

test.beforeEach(async () => {
  await clearSeededApps()
})

test.describe('App slug routing', () => {
  test('active app loads at its slug URL', async ({ page }) => {
    const { slug } = await seedApp('Route Test', helloSpec())
    await page.goto(`/${slug}`)
    await expect(
      page.getByText('Hello from the seeded app'),
    ).toBeVisible({ timeout: 15_000 })
  })

  test('unknown slug shows a "not found" screen, not a crash', async ({ page }) => {
    await page.goto('/definitely-does-not-exist')
    await expect(
      page.getByRole('heading', { name: /app not found/i }),
    ).toBeVisible({ timeout: 15_000 })
  })

  test('archived app shows an archived notice instead of loading', async ({
    adminPage,
  }) => {
    const { slug, id } = await seedApp('Archived One', minimalTodoSpec())
    // Flip to archived via superadmin REST update.
    const { withSuperadmin } = await import('../helpers/pb-client')
    await withSuperadmin(async (pb) => {
      await pb.collection('_ods_apps').update(id, { status: 'archived' })
    })
    await adminPage.goto(`/${slug}`)
    await expect(
      adminPage.getByRole('heading', { name: /app unavailable/i }),
    ).toBeVisible({ timeout: 15_000 })
  })
})

test.describe('Form submit → list refresh', () => {
  test('submitting a form adds a row that appears in the list', async ({
    page,
  }) => {
    await seedApp('Todo Flow', minimalTodoSpec())
    await page.goto('/todo-flow')

    // Form label visible.
    await expect(page.getByText('Title').first()).toBeVisible({ timeout: 15_000 })

    // Fill the Title field (first textbox), then click the Save Task button.
    await page.getByRole('textbox').first().fill('Buy milk')
    await page.getByRole('button', { name: /save task/i }).click()

    // The new row should appear in the list table.
    await expect(
      page.locator('td', { hasText: 'Buy milk' }).first(),
    ).toBeVisible({ timeout: 15_000 })
  })
})

test.describe('Dashboard context menu', () => {
  test('app card shows the context-menu options', async ({ adminPage }) => {
    await seedApp('Menu Test', minimalTodoSpec())
    await adminPage.goto('/admin')
    await expect(adminPage.getByRole('heading', { name: /my apps/i })).toBeVisible({
      timeout: 20_000,
    })

    const card = adminPage.getByText('Menu Test').first()
    await expect(card).toBeVisible()

    // The 3-dot button lives inside the card tile. Scope to within the
    // card container by clicking the closest ancestor that holds both
    // the app name and the menu trigger.
    const cardRow = adminPage
      .locator('div')
      .filter({ hasText: 'Menu Test' })
      .filter({ has: adminPage.locator('button') })
      .last()
    await cardRow.getByRole('button').last().click()

    await expect(adminPage.getByText(/edit json spec/i)).toBeVisible()
    await expect(adminPage.getByText(/archive/i).first()).toBeVisible()
    await expect(adminPage.getByText(/delete/i).first()).toBeVisible()
  })

  test('archive action moves the app into the archived section', async ({
    adminPage,
  }) => {
    await seedApp('Archive Me', minimalTodoSpec())
    await adminPage.goto('/admin')
    await expect(adminPage.getByRole('heading', { name: /my apps/i })).toBeVisible({
      timeout: 20_000,
    })

    const cardRow = adminPage
      .locator('div')
      .filter({ hasText: 'Archive Me' })
      .filter({ has: adminPage.locator('button') })
      .last()
    await cardRow.getByRole('button').last().click()

    await adminPage.getByText(/^archive$/i).first().click()

    // Confirm if there's a confirmation dialog.
    const confirm = adminPage.getByRole('button', { name: /^archive$/i })
    if (await confirm.isVisible()) await confirm.click()

    // The card should no longer appear in the active "My Apps" section.
    await expect(adminPage.getByText('Archive Me')).toHaveCount(0, { timeout: 10_000 })
  })
})

import { test, expect } from '../helpers/fixtures'
import { clearSeededApps, seedApp, seedRows, readRow } from '../helpers/app-seed'

// ---------------------------------------------------------------------------
// Data interactions — kanban rendering and the data-export dialog.
// Drag-and-drop is intentionally not covered; it's flaky in Playwright
// without a dedicated dnd helper and low-value for regression.
// ---------------------------------------------------------------------------

function kanbanSpec(): object {
  return {
    appName: 'Kanban App',
    startPage: 'home',
    pages: {
      home: {
        component: 'page',
        title: 'Home',
        content: [
          {
            component: 'kanban',
            dataSource: 'cards',
            titleField: 'title',
            statusField: 'status',
          },
        ],
      },
    },
    dataSources: {
      cards: {
        url: 'local://cards',
        method: 'POST',
        fields: [
          { name: 'title', type: 'text' },
          {
            name: 'status',
            type: 'select',
            options: ['todo', 'doing', 'done'],
          },
        ],
      },
    },
  }
}

test.beforeEach(async () => {
  await clearSeededApps()
})

test.describe('Kanban', () => {
  test('kanban renders a column per status option', async ({ page }) => {
    await seedApp('Board', kanbanSpec())
    await page.goto('/board')

    // Each status option becomes a column header.
    await expect(page.getByText('todo').first()).toBeVisible({ timeout: 15_000 })
    await expect(page.getByText('doing').first()).toBeVisible()
    await expect(page.getByText('done').first()).toBeVisible()
  })

  test('kanban with no cards still renders its columns (no crash)', async ({
    page,
  }) => {
    await seedApp('Empty Board', kanbanSpec())
    await page.goto('/empty-board')
    // Verify columns exist. Zero-cards state is a fine outcome — the test
    // is mainly making sure the component handles an empty dataSource.
    await expect(page.getByText('todo').first()).toBeVisible({ timeout: 15_000 })
  })

  test('dragging a card to another column persists the new status', async ({
    page,
  }) => {
    // `seedRows` derives the PB collection name from the spec's
    // `appName` — which is 'Kanban App' in kanbanSpec — not the
    // seedApp(name, ...) argument (used only for the slug).
    await seedApp('Drag Board', kanbanSpec())
    const specAppName = 'Kanban App'
    const [cardId] = await seedRows(specAppName, 'cards', [
      { title: 'Move Me', status: 'todo' },
    ])

    await page.goto('/drag-board')
    const card = page.locator(`[data-ods-kanban-card="${cardId}"]`)
    const doneCol = page.locator('[data-ods-kanban-column="done"]')
    await expect(card).toBeVisible({ timeout: 15_000 })
    await expect(doneCol).toBeVisible()

    // Try Playwright's built-in dragTo first. Synthetic HTML5 dnd is
    // usually reliable here because KanbanComponent's drop handler
    // reads state from dataTransfer and doesn't depend on hover state.
    await card.dragTo(doneCol)

    // Confirm the row's status was updated in PB.
    await expect
      .poll(
        async () => {
          const row = await readRow(specAppName, 'cards', cardId)
          return row['status'] as string
        },
        { timeout: 10_000, intervals: [500, 500, 1000] },
      )
      .toBe('done')
  })
})

test.describe('Data export', () => {
  test('export dialog opens from the app card context menu', async ({
    adminPage,
  }) => {
    await seedApp('Export Source', kanbanSpec())
    await adminPage.goto('/admin')
    await expect(adminPage.getByRole('heading', { name: /my apps/i })).toBeVisible({
      timeout: 20_000,
    })

    const cardRow = adminPage
      .locator('div')
      .filter({ hasText: 'Export Source' })
      .filter({ has: adminPage.locator('button') })
      .last()
    await cardRow.getByRole('button').last().click()
    await adminPage.getByText(/export data/i).first().click()

    // All three format options should be present.
    await expect(adminPage.getByRole('heading', { name: /export data/i })).toBeVisible({
      timeout: 10_000,
    })
    await expect(adminPage.getByText('JSON').first()).toBeVisible()
    await expect(adminPage.getByText('CSV').first()).toBeVisible()
    await expect(adminPage.getByText('SQL').first()).toBeVisible()
  })
})

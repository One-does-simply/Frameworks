import { test, expect } from '../helpers/fixtures'
import { clearSeededApps, seedApp, ensureUsersCollection } from '../helpers/app-seed'

// ---------------------------------------------------------------------------
// Multi-user — LoginScreen flows (login, self-registration, guest) for apps
// that declare `auth.multiUser: true`.
// ---------------------------------------------------------------------------

/** Spec that forces the LoginScreen to appear. */
function multiUserSpec(selfRegistration: boolean): object {
  return {
    appName: 'Multi User',
    startPage: 'home',
    auth: {
      multiUser: true,
      selfRegistration,
      roles: ['admin', 'user'],
      defaultRole: 'user',
    },
    pages: {
      home: {
        component: 'page',
        title: 'Home',
        content: [
          { component: 'text', content: 'Authenticated home page' },
        ],
      },
    },
    dataSources: {},
  }
}

test.beforeEach(async () => {
  await clearSeededApps()
})

test.describe('LoginScreen (multi-user app)', () => {
  test('multi-user app shows the login screen to guests', async ({ page }) => {
    await seedApp('MU Login', multiUserSpec(true))
    await page.goto('/mu-login')
    await expect(
      page.getByRole('button', { name: /sign in/i }).first(),
    ).toBeVisible({ timeout: 15_000 })
  })

  test('self-registration form appears when selfRegistration=true', async ({
    page,
  }) => {
    await seedApp('MU Signup', multiUserSpec(true))
    await page.goto('/mu-signup')
    await expect(
      page.getByRole('button', { name: /sign in/i }).first(),
    ).toBeVisible({ timeout: 15_000 })

    // Toggle to the sign-up view.
    await page.getByText(/don't have an account\? sign up/i).click()

    // Sign-up fields are uniquely id'd as signup-*.
    await expect(page.locator('#signup-email')).toBeVisible({ timeout: 10_000 })
    await expect(page.locator('#signup-password')).toBeVisible()
    await expect(page.locator('#signup-confirm')).toBeVisible()
    await expect(page.getByRole('button', { name: /create account/i })).toBeVisible()
  })

  test('self-registration is hidden when selfRegistration=false', async ({ page }) => {
    await seedApp('MU NoSignup', multiUserSpec(false))
    await page.goto('/mu-nosignup')
    await expect(
      page.getByRole('button', { name: /sign in/i }).first(),
    ).toBeVisible({ timeout: 15_000 })
    // No "Sign Up" switch link should be visible.
    await expect(page.getByText(/don't have an account\? sign up/i)).toHaveCount(0)
  })

  test('password mismatch on signup blocks account creation', async ({ page }) => {
    await seedApp('MU Mismatch', multiUserSpec(true))
    await page.goto('/mu-mismatch')
    await page.getByText(/don't have an account\? sign up/i).click()

    await page.locator('#signup-email').fill('newuser@e2e.local')
    await page.locator('#signup-password').fill('password123')
    await page.locator('#signup-confirm').fill('different123')
    await page.getByRole('button', { name: /create account/i }).click()

    // Look for an inline error; precise wording differs, so match loosely.
    await expect(
      page.getByText(/match|do not match|mismatch/i).first(),
    ).toBeVisible({ timeout: 5_000 })
  })

  test('sign-up creates a user and auto-logs into the app home', async ({
    page,
  }) => {
    // The PB `users` auth collection isn't auto-created by superuser
    // upsert. Seed it here so the guest sign-up flow has somewhere to
    // land. (In production this happens automatically on first admin
    // login — see AuthService.ensureUsersCollection / AdminGuard.)
    await ensureUsersCollection()
    await seedApp('MU Full', multiUserSpec(true))

    await page.goto('/mu-full')
    await page.getByText(/don't have an account\? sign up/i).click()

    const email = `mu-${Date.now()}@e2e.local`
    await page.locator('#signup-email').fill(email)
    await page.locator('#signup-password').fill('password-e2e-123')
    await page.locator('#signup-confirm').fill('password-e2e-123')
    await page.getByRole('button', { name: /create account/i }).click()

    await expect(page.getByText('Authenticated home page')).toBeVisible({
      timeout: 20_000,
    })
  })
})

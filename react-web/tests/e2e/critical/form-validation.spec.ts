import { test, expect } from '@playwright/test'

// ---------------------------------------------------------------------------
// Form Validation — exercises the login forms which live on /, /admin and
// are reachable without PocketBase (they render client-side on network
// failure). We validate that client-side checks fire before a network call
// is attempted (e.g. empty email, missing password).
//
// The "valid form submit proceeds" case is skipped because a true happy-path
// submit requires a running PocketBase instance returning success.
// ---------------------------------------------------------------------------

test.describe('Form Validation', () => {
  test('admin login: empty submit surfaces an invalid credentials error', async ({ page }) => {
    await page.goto('/admin')

    const loginHeading = page.getByText('ODS Admin Login')
    await expect(loginHeading).toBeVisible({ timeout: 15_000 })

    // Submit the form with both email and password blank. HTML5 required
    // validation OR the server-side rejection will surface an error.
    const submitBtn = page.getByRole('button', { name: /connect to pocketbase/i })
    await submitBtn.click()

    // Either the browser's native validity tooltip fires (form won't submit
    // and the focused input is marked invalid), OR the submit proceeds and
    // the app shows its own invalid-credentials banner. We check for the
    // input's `:invalid` state as the primary signal.
    const emailInput = page.locator('#admin-email')
    const isInvalid = await emailInput.evaluate((el: HTMLInputElement) => !el.validity.valid)

    // If native validation passed (unlikely — email is required-ish via the
    // form), fall back to the server error banner.
    if (!isInvalid) {
      const invalidBanner = page.getByText(/invalid.*credentials/i)
      await expect(invalidBanner).toBeVisible({ timeout: 10_000 })
    } else {
      expect(isInvalid).toBe(true)
    }
  })

  test('admin login: non-email text in email field is flagged', async ({ page }) => {
    await page.goto('/admin')
    await expect(page.getByText('ODS Admin Login')).toBeVisible({ timeout: 15_000 })

    const emailInput = page.locator('#admin-email')
    const passwordInput = page.locator('#admin-password')

    await emailInput.fill('not-an-email')
    await passwordInput.fill('some-password')

    await page.getByRole('button', { name: /connect to pocketbase/i }).click()

    // The <Input type="email"> triggers browser validity. Check the validity
    // state on the input directly — resilient across browsers.
    const valid = await emailInput.evaluate((el: HTMLInputElement) => el.validity.valid)
    expect(valid).toBe(false)
  })

  test('root user login: empty email shows "Email is required" error', async ({ page }) => {
    // Seed a default slug so RootRedirect renders the login chooser instead
    // of redirecting us to /admin.
    await page.addInitScript(() => {
      localStorage.setItem('ods_default_app_slug', 'test-default-app')
    })

    await page.goto('/')

    // Navigate into the "App User" mode.
    const userBtn = page.getByRole('button', { name: /app user/i })
    await expect(userBtn).toBeVisible({ timeout: 15_000 })
    await userBtn.click()

    // Click sign in with empty fields.
    await page.getByRole('button', { name: /^sign in$/i }).click()

    // The handler should report the email-required error synchronously.
    const emailRequired = page.getByText('Email is required')
    await expect(emailRequired).toBeVisible({ timeout: 5_000 })
  })

  test('valid form submit proceeds (skipped — requires PocketBase)', async () => {
    test.skip(
      true,
      'A successful submit requires a running PocketBase instance returning real auth. Skipping to keep the suite hermetic.',
    )
  })
})

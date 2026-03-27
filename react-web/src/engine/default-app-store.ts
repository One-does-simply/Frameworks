/**
 * Default App store — persists the default app slug in localStorage.
 *
 * When a non-admin user hits the root URL (/), they are redirected to the
 * default app. The first app loaded automatically becomes the default,
 * but admins can change it from the dashboard.
 */

const STORAGE_KEY = 'ods_default_app_slug'

/** Get the currently configured default app slug. */
export function getDefaultAppSlug(): string | null {
  return localStorage.getItem(STORAGE_KEY)
}

/** Set the default app slug. */
export function setDefaultAppSlug(slug: string): void {
  localStorage.setItem(STORAGE_KEY, slug)
}

/** Clear the default app slug. */
export function clearDefaultAppSlug(): void {
  localStorage.removeItem(STORAGE_KEY)
}

/**
 * Ensure a default app is set. If none is configured, sets the given slug.
 * Called when apps are first loaded.
 */
export function ensureDefaultApp(slug: string): void {
  if (!getDefaultAppSlug()) {
    setDefaultAppSlug(slug)
  }
}

import PocketBase from 'pocketbase'
import { PB_URL } from './pocketbase-server'
import { E2E_SUPERADMIN } from './pocketbase-admin'

/**
 * Creates a standalone PocketBase SDK client pointed at the E2E server.
 * Each call returns a fresh client so tests don't share auth state.
 */
export function newPbClient(): PocketBase {
  return new PocketBase(PB_URL)
}

/** Logs in an SDK client as the E2E superadmin. */
export async function pbLoginSuperadmin(pb: PocketBase): Promise<void> {
  await pb
    .collection('_superusers')
    .authWithPassword(E2E_SUPERADMIN.email, E2E_SUPERADMIN.password)
}

/**
 * Superadmin token wrapper — creates a client, logs it in, runs the
 * callback, and clears auth. Use for one-off privileged operations.
 */
export async function withSuperadmin<T>(
  fn: (pb: PocketBase) => Promise<T>,
): Promise<T> {
  const pb = newPbClient()
  await pbLoginSuperadmin(pb)
  try {
    return await fn(pb)
  } finally {
    pb.authStore.clear()
  }
}

export { PB_URL }

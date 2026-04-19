import { spawnSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

/**
 * Credentials the E2E suite assumes are set up by globalSetup. Tests can
 * import these directly so the whole suite shares one source of truth.
 */
export const E2E_SUPERADMIN = {
  email: 'admin@e2e.local',
  password: 'e2e-test-pass-1234',
}

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)
const E2E_ROOT = resolve(__dirname, '..')
const PB_DIR = join(E2E_ROOT, '.pb-e2e')
const PB_DATA_DIR = join(PB_DIR, 'pb_data')

function binaryPath(): string {
  const name = process.platform === 'win32' ? 'pocketbase.exe' : 'pocketbase'
  const p = join(PB_DIR, name)
  if (!existsSync(p)) {
    throw new Error(`PocketBase binary not found at ${p} — run startPocketBase first`)
  }
  return p
}

/**
 * Upserts the E2E superadmin account via the `pocketbase superuser upsert`
 * CLI. Must run while the server is stopped OR against the data dir the
 * server is using — the CLI locks its own DB, so the typical pattern is
 * to call this BEFORE `pocketbase serve`.
 *
 * We run it after the server is up (the CLI opens the DB in read/write and
 * the running server handles it gracefully, since they use the same SQLite
 * file with shared-cache). If that ever proves flaky, switch the order in
 * globalSetup so CLI upsert happens before serve.
 */
export function upsertSuperadmin(): void {
  const result = spawnSync(
    binaryPath(),
    [
      'superuser',
      'upsert',
      E2E_SUPERADMIN.email,
      E2E_SUPERADMIN.password,
      '--dir',
      PB_DATA_DIR,
    ],
    { stdio: 'inherit' },
  )
  if (result.status !== 0) {
    throw new Error('Failed to upsert E2E superadmin')
  }
}

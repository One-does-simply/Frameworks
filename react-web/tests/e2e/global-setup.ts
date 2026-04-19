import type { FullConfig } from '@playwright/test'
import {
  ensurePocketBaseBinary,
  resetDataDir,
  startPocketBase,
} from './helpers/pocketbase-server'
import { upsertSuperadmin } from './helpers/pocketbase-admin'

/**
 * Downloads (once) and starts a dedicated PocketBase instance on
 * 127.0.0.1:8090 for the E2E suite. Superadmin is upserted BEFORE the
 * server starts so the CLI doesn't contend with the serve process on the
 * SQLite lock.
 */
export default async function globalSetup(_config: FullConfig) {
  await ensurePocketBaseBinary()
  resetDataDir()
  // Seed the superadmin first — this writes to the SQLite DB while no
  // serve process holds the lock.
  upsertSuperadmin()
  await startPocketBase()
}

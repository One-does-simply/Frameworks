import type { FullConfig } from '@playwright/test'
import { stopPocketBase } from './helpers/pocketbase-server'

export default async function globalTeardown(_config: FullConfig) {
  await stopPocketBase()
}

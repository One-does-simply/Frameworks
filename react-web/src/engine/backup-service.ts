/**
 * Backup service for ODS React Web.
 *
 * Auto-backup serializes all app data (all local tables) to a JSON blob
 * and stores it in localStorage. Users can manually trigger a download
 * or restore from a backup file.
 *
 * Since browsers can't write to the filesystem automatically, auto-backup
 * stores snapshots in localStorage and prunes old ones by retention count.
 */

import type { DataService } from './data-service.ts'
import type { OdsApp } from '@/models/ods-app.ts'
import { isLocal, tableName } from '@/models/ods-data-source.ts'

// ---------------------------------------------------------------------------
// Settings persistence (localStorage)
// ---------------------------------------------------------------------------

const SETTINGS_KEY = 'ods_backup_settings'
const BACKUP_PREFIX = 'ods_backup_'

export interface BackupSettings {
  autoBackup: boolean
  retention: number // number of snapshots to keep per app
}

const DEFAULT_SETTINGS: BackupSettings = {
  autoBackup: false,
  retention: 5,
}

export function getBackupSettings(): BackupSettings {
  try {
    const raw = localStorage.getItem(SETTINGS_KEY)
    if (raw) return { ...DEFAULT_SETTINGS, ...JSON.parse(raw) }
  } catch { /* use defaults */ }
  return { ...DEFAULT_SETTINGS }
}

export function setBackupSettings(settings: BackupSettings): void {
  localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings))
}

// ---------------------------------------------------------------------------
// Backup data format
// ---------------------------------------------------------------------------

interface BackupSnapshot {
  odsBackup: true
  appName: string
  timestamp: string
  tables: Record<string, Record<string, unknown>[]>
}

// ---------------------------------------------------------------------------
// Auto-backup: store snapshot in localStorage
// ---------------------------------------------------------------------------

/** Run auto-backup if enabled. Call this after a spec loads successfully. */
export async function runAutoBackup(
  app: OdsApp,
  dataService: DataService,
): Promise<void> {
  const settings = getBackupSettings()
  if (!settings.autoBackup) return

  try {
    const snapshot = await createSnapshot(app, dataService)
    const key = `${BACKUP_PREFIX}${sanitize(app.appName)}_${Date.now()}`
    localStorage.setItem(key, JSON.stringify(snapshot))
    pruneBackups(app.appName, settings.retention)
  } catch (e) {
    // Best-effort — don't break the app if backup fails
    console.warn('ODS auto-backup failed:', e)
  }
}

/** Create a snapshot of all local data sources. */
async function createSnapshot(
  app: OdsApp,
  dataService: DataService,
): Promise<BackupSnapshot> {
  const tables: Record<string, Record<string, unknown>[]> = {}

  for (const [, ds] of Object.entries(app.dataSources)) {
    if (isLocal(ds)) {
      const name = tableName(ds)
      tables[name] = await dataService.query(name)
    }
  }

  return {
    odsBackup: true,
    appName: app.appName,
    timestamp: new Date().toISOString(),
    tables,
  }
}

/** Remove old auto-backup snapshots beyond the retention count. */
function pruneBackups(appName: string, retention: number): void {
  const prefix = `${BACKUP_PREFIX}${sanitize(appName)}_`
  const keys: string[] = []

  for (let i = 0; i < localStorage.length; i++) {
    const key = localStorage.key(i)
    if (key?.startsWith(prefix)) keys.push(key)
  }

  // Sort newest first (timestamp is in the key)
  keys.sort().reverse()

  // Delete excess
  for (let i = retention; i < keys.length; i++) {
    localStorage.removeItem(keys[i])
  }
}

// ---------------------------------------------------------------------------
// Manual backup: download as file
// ---------------------------------------------------------------------------

/** Download a full backup of the app's data as a JSON file. */
export async function downloadBackup(
  app: OdsApp,
  dataService: DataService,
): Promise<void> {
  const snapshot = await createSnapshot(app, dataService)
  const json = JSON.stringify(snapshot, null, 2)
  const safeName = sanitize(app.appName)
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-')
  const filename = `ods_backup_${safeName}_${timestamp}.json`

  const blob = new Blob([json], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
}

// ---------------------------------------------------------------------------
// Restore from backup file
// ---------------------------------------------------------------------------

/** Validate and restore data from a backup JSON string. Returns error string or null on success. */
export async function restoreBackup(
  jsonString: string,
  app: OdsApp,
  dataService: DataService,
): Promise<string | null> {
  let backup: BackupSnapshot
  try {
    backup = JSON.parse(jsonString)
  } catch {
    return 'Invalid JSON — could not parse backup file.'
  }

  if (!backup.odsBackup && !backup.tables) {
    return 'This does not appear to be a valid ODS backup file.'
  }

  if (!backup.tables || typeof backup.tables !== 'object') {
    return 'Backup file has no tables data.'
  }

  // Clear existing data and re-insert
  try {
    for (const [tbl, rows] of Object.entries(backup.tables)) {
      // Delete all existing rows
      const existing = await dataService.query(tbl)
      for (const row of existing) {
        const id = String(row['_id'] ?? '')
        if (id) {
          await dataService.delete(tbl, '_id', id)
        }
      }

      // Insert backup rows
      for (const row of rows) {
        const insertRow = { ...row }
        delete insertRow['_id']
        delete insertRow['id']
        delete insertRow['collectionId']
        delete insertRow['collectionName']
        await dataService.insert(tbl, insertRow)
      }
    }
  } catch (e) {
    return `Restore failed: ${e instanceof Error ? e.message : String(e)}`
  }

  return null
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function sanitize(name: string): string {
  return name.replace(/[^\w]/g, '_').toLowerCase()
}

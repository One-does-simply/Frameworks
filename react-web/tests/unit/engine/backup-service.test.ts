import { describe, it, expect, beforeEach, vi } from 'vitest'
import { getBackupSettings, setBackupSettings, restoreBackup } from '../../../src/engine/backup-service.ts'
import { FakeDataService } from '../../helpers/fake-data-service.ts'

// ===========================================================================
// Backup service tests
//
// Tests settings persistence (via mocked localStorage) and restore logic
// (via FakeDataService). Auto-backup and download are browser-dependent.
// ===========================================================================

// Mock localStorage
const store: Record<string, string> = {}
const mockLocalStorage = {
  getItem: (key: string) => store[key] ?? null,
  setItem: (key: string, value: string) => { store[key] = value },
  removeItem: (key: string) => { delete store[key] },
  clear: () => { for (const k of Object.keys(store)) delete store[k] },
  get length() { return Object.keys(store).length },
  key: (i: number) => Object.keys(store)[i] ?? null,
}
vi.stubGlobal('localStorage', mockLocalStorage)

describe('BackupSettings', () => {
  beforeEach(() => {
    mockLocalStorage.clear()
  })

  // -------------------------------------------------------------------------
  // getBackupSettings
  // -------------------------------------------------------------------------

  it('returns defaults when nothing stored', () => {
    const settings = getBackupSettings()
    expect(settings.autoBackup).toBe(false)
    expect(settings.retention).toBe(5)
  })

  it('returns stored settings', () => {
    store['ods_backup_settings'] = JSON.stringify({ autoBackup: true, retention: 10 })
    const settings = getBackupSettings()
    expect(settings.autoBackup).toBe(true)
    expect(settings.retention).toBe(10)
  })

  it('merges partial stored settings with defaults', () => {
    store['ods_backup_settings'] = JSON.stringify({ autoBackup: true })
    const settings = getBackupSettings()
    expect(settings.autoBackup).toBe(true)
    expect(settings.retention).toBe(5)
  })

  it('returns defaults for corrupted JSON', () => {
    store['ods_backup_settings'] = 'not-json'
    const settings = getBackupSettings()
    expect(settings.autoBackup).toBe(false)
    expect(settings.retention).toBe(5)
  })

  // -------------------------------------------------------------------------
  // setBackupSettings
  // -------------------------------------------------------------------------

  it('persists settings to localStorage', () => {
    setBackupSettings({ autoBackup: true, retention: 3 })
    const raw = JSON.parse(store['ods_backup_settings'])
    expect(raw.autoBackup).toBe(true)
    expect(raw.retention).toBe(3)
  })

  it('round-trips through get/set', () => {
    setBackupSettings({ autoBackup: true, retention: 7 })
    const settings = getBackupSettings()
    expect(settings.autoBackup).toBe(true)
    expect(settings.retention).toBe(7)
  })
})

// ===========================================================================
// restoreBackup
// ===========================================================================

describe('restoreBackup', () => {
  const minimalApp = {
    appName: 'Test',
    startPage: 'home',
    startPageByRole: {},
    menu: [],
    pages: {},
    dataSources: {},
    tour: [],
    settings: {},
    auth: { multiUser: false, selfRegistration: false, defaultRole: 'user' },
    branding: { theme: 'indigo', mode: 'system', headerStyle: 'light' },
  } as any

  it('returns error for invalid JSON', async () => {
    const ds = new FakeDataService()
    const result = await restoreBackup('not json', minimalApp, ds as any)
    expect(result).toContain('Invalid JSON')
  })

  it('returns error for non-backup object', async () => {
    const ds = new FakeDataService()
    const result = await restoreBackup('{"foo": "bar"}', minimalApp, ds as any)
    expect(result).toContain('not appear to be a valid ODS backup')
  })

  it('returns error when tables is missing', async () => {
    const ds = new FakeDataService()
    const result = await restoreBackup(JSON.stringify({ odsBackup: true }), minimalApp, ds as any)
    expect(result).toContain('no tables data')
  })

  it('restores data from valid backup', async () => {
    const ds = new FakeDataService()
    const backup = {
      odsBackup: true,
      appName: 'Test',
      timestamp: '2026-01-01T00:00:00Z',
      tables: {
        tasks: [
          { _id: 'old1', title: 'Restored Task' },
        ],
      },
    }
    const result = await restoreBackup(JSON.stringify(backup), minimalApp, ds as any)
    expect(result).toBeNull()

    // Verify data was inserted
    const rows = await ds.query('tasks')
    expect(rows.length).toBe(1)
    expect(rows[0]['title']).toBe('Restored Task')
  })

  it('clears existing data before restoring', async () => {
    const ds = new FakeDataService()
    // Seed existing data
    await ds.insert('tasks', { title: 'Old Task' })
    expect((await ds.query('tasks')).length).toBe(1)

    const backup = {
      odsBackup: true,
      appName: 'Test',
      timestamp: '2026-01-01T00:00:00Z',
      tables: {
        tasks: [
          { _id: 'new1', title: 'New Task' },
        ],
      },
    }
    const result = await restoreBackup(JSON.stringify(backup), minimalApp, ds as any)
    expect(result).toBeNull()

    const rows = await ds.query('tasks')
    expect(rows.length).toBe(1)
    expect(rows[0]['title']).toBe('New Task')
  })

  it('strips PocketBase metadata fields during restore', async () => {
    const ds = new FakeDataService()
    const backup = {
      odsBackup: true,
      appName: 'Test',
      timestamp: '2026-01-01T00:00:00Z',
      tables: {
        items: [
          { _id: 'x', id: 'pb123', collectionId: 'col1', collectionName: '_items', name: 'Keep Me' },
        ],
      },
    }
    const result = await restoreBackup(JSON.stringify(backup), minimalApp, ds as any)
    expect(result).toBeNull()

    const rows = await ds.query('items')
    expect(rows.length).toBe(1)
    expect(rows[0]['name']).toBe('Keep Me')
    expect(rows[0]['collectionId']).toBeUndefined()
    expect(rows[0]['collectionName']).toBeUndefined()
  })
})

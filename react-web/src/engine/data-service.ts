import type PocketBase from 'pocketbase'
import type { OdsFieldDefinition } from '../models/ods-field.ts'
import type { OdsDataSource } from '../models/ods-data-source.ts'
import { isLocal, tableName } from '../models/ods-data-source.ts'

/**
 * PocketBase-backed data service for ODS apps.
 *
 * Replaces Flutter's SQLite DataStore. Each `local://tableName` maps to a
 * PocketBase collection. Collections are auto-created on first use.
 *
 * ODS Ethos: The builder describes *what* data they want stored, and the
 * framework handles *how*. No database config, no connection strings,
 * no migrations — just PocketBase collections managed automatically.
 */
export class DataService {
  private pb: PocketBase
  private knownCollections = new Set<string>()
  private debugLog: string[] = []
  /** App name prefix for collection isolation between apps. */
  private appPrefix = ''
  /** Whether we've authenticated as PocketBase superadmin for schema management. */
  private _isAdminAuthenticated = false

  constructor(pb: PocketBase) {
    this.pb = pb
  }

  get isAdminAuthenticated(): boolean {
    return this._isAdminAuthenticated
  }

  /** Initialize for a specific app. Sets the collection name prefix. */
  initialize(appName: string) {
    this.appPrefix = appName.replace(/[^\w]/g, '_').toLowerCase()
    this.knownCollections.clear()
    this.debugLog = []
    this.log(`DataService initialized for app "${appName}" (prefix: ${this.appPrefix})`)
  }

  /**
   * Authenticate as PocketBase superadmin. Required before creating collections.
   * Credentials are stored in localStorage so the user only enters them once.
   */
  async authenticateAdmin(email: string, password: string): Promise<boolean> {
    try {
      await this.pb.collection('_superusers').authWithPassword(email, password)
      this._isAdminAuthenticated = true
      // Save credentials for next session
      localStorage.setItem('ods_pb_admin_email', email)
      localStorage.setItem('ods_pb_admin_password', password)
      this.log('PocketBase admin authenticated')
      return true
    } catch (e) {
      this.log(`PocketBase admin auth failed: ${e}`)
      return false
    }
  }

  /**
   * Try to restore admin authentication from saved credentials.
   * Returns true if successfully authenticated.
   */
  async tryRestoreAdminAuth(): Promise<boolean> {
    const email = localStorage.getItem('ods_pb_admin_email')
    const password = localStorage.getItem('ods_pb_admin_password')
    if (!email || !password) return false
    return this.authenticateAdmin(email, password)
  }

  /** Returns the prefixed collection name for isolation between apps. */
  collectionName(table: string): string {
    return `${this.appPrefix}_${table}`
  }

  // ---------------------------------------------------------------------------
  // Schema management — auto-create collections from field definitions
  // ---------------------------------------------------------------------------

  /**
   * Ensures a PocketBase collection exists with the given fields.
   * Creates if missing, adds missing fields if already exists.
   */
  async ensureCollection(table: string, fields: OdsFieldDefinition[]): Promise<void> {
    const name = this.collectionName(table)

    if (this.knownCollections.has(name)) return

    try {
      // Check if collection exists
      await this.pb.collections.getOne(name)
      this.knownCollections.add(name)
      this.log(`Collection "${name}" already exists`)
    } catch {
      // Collection doesn't exist — create it
      try {
        const schema = fields.map(f => ({
          name: f.name,
          type: 'text', // All fields stored as text (matching Flutter approach)
          required: false,
        }))

        await this.pb.collections.create({
          name,
          type: 'base',
          schema,
        })
        this.knownCollections.add(name)
        this.log(`Created collection "${name}" with ${fields.length} fields`)
      } catch (createErr) {
        this.log(`Failed to create collection "${name}": ${createErr}`)
        throw createErr
      }
    }
  }

  /**
   * Sets up all local:// data sources: creates collections and seeds data.
   */
  async setupDataSources(dataSources: Record<string, OdsDataSource>): Promise<void> {
    for (const [, ds] of Object.entries(dataSources)) {
      if (!isLocal(ds)) continue
      const table = tableName(ds)

      if (ds.fields && ds.fields.length > 0) {
        await this.ensureCollection(table, ds.fields)
      }

      // Seed data into empty collections (first-run only).
      if (ds.seedData && ds.seedData.length > 0) {
        const count = await this.getRowCount(table)
        if (count === 0) {
          for (const row of ds.seedData) {
            await this.insert(table, row)
          }
          this.log(`Seeded ${ds.seedData.length} rows into "${table}"`)
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // CRUD operations
  // ---------------------------------------------------------------------------

  /** Insert a new record. Returns the created record's ID. */
  async insert(table: string, data: Record<string, unknown>): Promise<string> {
    const name = this.collectionName(table)
    const record = await this.pb.collection(name).create(data)
    this.log(`INSERT into "${name}": id=${record.id}`)
    return record.id
  }

  /** Update a record matched by field value. Returns count of affected rows. */
  async update(
    table: string,
    data: Record<string, unknown>,
    matchField: string,
    matchValue: string,
  ): Promise<number> {
    const name = this.collectionName(table)
    try {
      const records = await this.pb.collection(name).getFullList({
        filter: `${matchField} = "${this.escapeFilter(matchValue)}"`,
      })
      if (records.length === 0) return 0

      // Update data — remove match field from update payload
      const updateData = { ...data }
      delete updateData[matchField]

      for (const record of records) {
        await this.pb.collection(name).update(record.id, updateData)
      }
      this.log(`UPDATE "${name}" SET ... WHERE ${matchField}="${matchValue}" → ${records.length} rows`)
      return records.length
    } catch (e) {
      this.log(`UPDATE error on "${name}": ${e}`)
      return 0
    }
  }

  /** Delete records matched by field value. Returns count of deleted rows. */
  async delete(
    table: string,
    matchField: string,
    matchValue: string,
  ): Promise<number> {
    const name = this.collectionName(table)
    try {
      const records = await this.pb.collection(name).getFullList({
        filter: `${matchField} = "${this.escapeFilter(matchValue)}"`,
      })
      for (const record of records) {
        await this.pb.collection(name).delete(record.id)
      }
      this.log(`DELETE from "${name}" WHERE ${matchField}="${matchValue}" → ${records.length} rows`)
      return records.length
    } catch (e) {
      this.log(`DELETE error on "${name}": ${e}`)
      return 0
    }
  }

  /** Query all records, ordered by most recent first. */
  async query(table: string): Promise<Record<string, unknown>[]> {
    const name = this.collectionName(table)
    try {
      const records = await this.pb.collection(name).getFullList({
        sort: '-created',
      })
      this.log(`SELECT from "${name}": ${records.length} rows`)
      return records.map(r => this.normalizeRecord(r))
    } catch {
      return []
    }
  }

  /** Query with a filter map (field=value AND conditions). */
  async queryWithFilter(
    table: string,
    filter: Record<string, string>,
  ): Promise<Record<string, unknown>[]> {
    const name = this.collectionName(table)
    const filterStr = Object.entries(filter)
      .map(([k, v]) => `${k} = "${this.escapeFilter(v)}"`)
      .join(' && ')

    try {
      const records = await this.pb.collection(name).getFullList({
        filter: filterStr,
        sort: 'created',
      })
      this.log(`SELECT FILTERED from "${name}" WHERE ${filterStr}: ${records.length} rows`)
      return records.map(r => this.normalizeRecord(r))
    } catch {
      return []
    }
  }

  /** Query with ownership filtering. */
  async queryWithOwnership(
    table: string,
    ownerField: string,
    ownerId: string | undefined,
    isAdmin: boolean,
    adminOverride: boolean,
  ): Promise<Record<string, unknown>[]> {
    if (!ownerId || (isAdmin && adminOverride)) {
      return this.query(table)
    }

    const name = this.collectionName(table)
    try {
      const records = await this.pb.collection(name).getFullList({
        filter: `${ownerField} = "${this.escapeFilter(ownerId)}"`,
        sort: '-created',
      })
      this.log(`SELECT OWNED from "${name}" WHERE ${ownerField}="${ownerId}": ${records.length} rows`)
      return records.map(r => this.normalizeRecord(r))
    } catch {
      return []
    }
  }

  /** Get total row count for a table. */
  async getRowCount(table: string): Promise<number> {
    const name = this.collectionName(table)
    try {
      const result = await this.pb.collection(name).getList(1, 1)
      return result.totalItems
    } catch {
      return 0
    }
  }

  // ---------------------------------------------------------------------------
  // Settings storage — uses a special _ods_settings collection
  // ---------------------------------------------------------------------------

  async getAppSetting(key: string): Promise<string | undefined> {
    const name = this.collectionName('_ods_settings')
    try {
      const records = await this.pb.collection(name).getFullList({
        filter: `key = "${this.escapeFilter(key)}"`,
      })
      return records.length > 0 ? (records[0]['value'] as string) : undefined
    } catch {
      return undefined
    }
  }

  async setAppSetting(key: string, value: string): Promise<void> {
    const name = this.collectionName('_ods_settings')
    try {
      const existing = await this.pb.collection(name).getFullList({
        filter: `key = "${this.escapeFilter(key)}"`,
      })
      if (existing.length > 0) {
        await this.pb.collection(name).update(existing[0].id, { value })
      } else {
        await this.pb.collection(name).create({ key, value })
      }
    } catch {
      // Settings collection may not exist yet
    }
  }

  async getAllAppSettings(): Promise<Record<string, string>> {
    const name = this.collectionName('_ods_settings')
    try {
      const records = await this.pb.collection(name).getFullList()
      const settings: Record<string, string> = {}
      for (const r of records) {
        settings[r['key'] as string] = r['value'] as string
      }
      return settings
    } catch {
      return {}
    }
  }

  // ---------------------------------------------------------------------------
  // Debug log
  // ---------------------------------------------------------------------------

  getDebugLog(): readonly string[] {
    return this.debugLog
  }

  private log(message: string) {
    this.debugLog.push(`[${new Date().toISOString()}] ${message}`)
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /** Normalize a PocketBase record to ODS format (id → _id, created → _createdAt). */
  private normalizeRecord(record: Record<string, unknown>): Record<string, unknown> {
    const normalized: Record<string, unknown> = {}
    for (const [key, value] of Object.entries(record)) {
      if (key === 'id') {
        normalized['_id'] = value
      } else if (key === 'created') {
        normalized['_createdAt'] = value
      } else if (key === 'updated' || key === 'collectionId' || key === 'collectionName') {
        // Skip PocketBase internal fields
      } else {
        normalized[key] = value
      }
    }
    return normalized
  }

  /** Escape a value for use in PocketBase filter strings. */
  private escapeFilter(value: string): string {
    return value.replace(/"/g, '\\"')
  }
}

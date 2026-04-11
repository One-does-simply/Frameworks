import type PocketBase from 'pocketbase'
import type { OdsFieldDefinition } from '../models/ods-field.ts'
import type { OdsDataSource } from '../models/ods-data-source.ts'
import { isLocal, tableName } from '../models/ods-data-source.ts'
import { logDebug, logInfo, logWarn, logError } from './log-service.ts'

// ---------------------------------------------------------------------------
// Field name validation — prevents filter injection and prototype pollution
// ---------------------------------------------------------------------------

const VALID_FIELD_NAME = /^[a-zA-Z_][a-zA-Z0-9_]*$/
const RESERVED_NAMES = new Set(['__proto__', 'constructor', 'prototype'])

/** Validates that a field/table name is safe. Throws on invalid input. */
function validateFieldName(name: string): void {
  if (!VALID_FIELD_NAME.test(name)) {
    throw new Error(`Invalid field name: "${name}" — must match /^[a-zA-Z_][a-zA-Z0-9_]*$/`)
  }
  if (RESERVED_NAMES.has(name)) {
    throw new Error(`Reserved field name: "${name}"`)
  }
}

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
    logInfo('DataService', `Initialized for app "${appName}" (prefix: ${this.appPrefix})`)
  }

  /**
   * Authenticate as PocketBase superadmin. Required before creating collections.
   * Credentials are stored in localStorage so the user only enters them once.
   */
  async authenticateAdmin(email: string, password: string): Promise<boolean> {
    try {
      await this.pb.collection('_superusers').authWithPassword(email, password)
      this._isAdminAuthenticated = true
      logInfo('DataService', 'PocketBase admin authenticated')
      console.info('[SECURITY] Admin auth success:', email)
      return true
    } catch (e) {
      logWarn('DataService', `PocketBase admin auth failed: ${e}`)
      console.info('[SECURITY] Admin auth failure:', email)
      return false
    }
  }

  /**
   * Check if the current PocketBase session has valid superadmin auth.
   * Does NOT restore from stored credentials — login is required each session.
   */
  async tryRestoreAdminAuth(): Promise<boolean> {
    if (!this.pb.authStore.isValid) return false

    // Check if the current auth token belongs to a superadmin.
    // PocketBase SDK stores the collection name on the auth record.
    const record = this.pb.authStore.record
    const collectionName = record?.['collectionName'] ?? record?.['collectionId'] ?? ''
    if (collectionName === '_superusers' || collectionName === '_admins') {
      this._isAdminAuthenticated = true
      logInfo('DataService', 'PocketBase superadmin session detected from auth store')
      console.info('[SECURITY] Admin auth restore: superadmin session detected')
      return true
    }

    // Fallback: try refreshing the superadmin token
    try {
      await this.pb.collection('_superusers').authRefresh()
      this._isAdminAuthenticated = true
      logInfo('DataService', 'PocketBase admin session refreshed')
      return true
    } catch {
      logInfo('DataService', 'tryRestoreAdminAuth: authRefresh failed, not a superadmin session')
      return false
    }
  }

  /** Returns the prefixed collection name for isolation between apps. */
  collectionName(table: string): string {
    validateFieldName(table)
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
      // Check if collection exists AND is usable (try a simple query).
      await this.pb.collection(name).getList(1, 1, { requestKey: null })
      this.knownCollections.add(name)
      logDebug('DataService', `Collection "${name}" already exists`)
    } catch {
      // Collection doesn't exist or is broken — (re)create it.
      try {
        // Try to delete a broken collection first (silently ignore if not found).
        try { await this.pb.collections.delete(name) } catch { /* ignore */ }

        // Validate all field names before creating the collection.
        for (const f of fields) {
          validateFieldName(f.name)
        }

        const pbFields = fields.map(f => ({
          name: f.name,
          type: 'text',
          required: false,
        }))

        await this.pb.collections.create({
          name,
          type: 'base',
          fields: pbFields,
          // Set permissive API rules so any authenticated or anonymous user
          // can CRUD. ODS handles its own RBAC at the application layer.
          listRule: '',
          viewRule: '',
          createRule: '',
          updateRule: '',
          deleteRule: '',
        })
        this.knownCollections.add(name)
        logInfo('DataService', `Created collection "${name}" with ${fields.length} fields`)
      } catch (createErr) {
        logError('DataService', `Failed to create collection "${name}"`, createErr)
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
          logInfo('DataService', `Seeded ${ds.seedData.length} rows into "${table}"`)
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
    try {
      const record = await this.pb.collection(name).create(data)
      logDebug('DataService', `INSERT into "${name}": id=${record.id}`)
      return record.id
    } catch (e) {
      logError('DataService', `INSERT failed for "${name}"`, { error: e, data })
      throw e
    }
  }

  /** Update a record matched by field value. Returns count of affected rows. */
  async update(
    table: string,
    data: Record<string, unknown>,
    matchField: string,
    matchValue: string,
  ): Promise<number> {
    validateFieldName(matchField)
    const pbField = this.denormalizeField(matchField)
    const name = this.collectionName(table)
    try {
      const records = await this.pb.collection(name).getFullList({
        filter: `${pbField} = "${this.escapeFilter(matchValue)}"`,
        requestKey: null,
      })
      if (records.length === 0) return 0

      // Update data — remove match field from update payload
      const updateData = { ...data }
      delete updateData[matchField]

      for (const record of records) {
        await this.pb.collection(name).update(record.id, updateData)
      }
      logDebug('DataService', `UPDATE "${name}" WHERE ${matchField}="${matchValue}" → ${records.length} rows`)
      return records.length
    } catch (e) {
      logWarn('DataService', `UPDATE error on "${name}"`, e)
      return 0
    }
  }

  /** Delete records matched by field value. Returns count of deleted rows. */
  async delete(
    table: string,
    matchField: string,
    matchValue: string,
  ): Promise<number> {
    validateFieldName(matchField)
    const pbField = this.denormalizeField(matchField)
    const name = this.collectionName(table)
    try {
      const records = await this.pb.collection(name).getFullList({
        filter: `${pbField} = "${this.escapeFilter(matchValue)}"`,
        requestKey: null,
      })
      for (const record of records) {
        await this.pb.collection(name).delete(record.id)
      }
      logDebug('DataService', `DELETE from "${name}" WHERE ${matchField}="${matchValue}" → ${records.length} rows`)
      return records.length
    } catch (e) {
      logWarn('DataService', `DELETE error on "${name}"`, e)
      return 0
    }
  }

  /** Query all records, ordered by most recent first. */
  async query(table: string): Promise<Record<string, unknown>[]> {
    const name = this.collectionName(table)
    try {
      const records = await this.pb.collection(name).getFullList({
        requestKey: null,
      })
      logDebug('DataService', `SELECT from "${name}": ${records.length} rows`)
      return records.map(r => this.normalizeRecord(r))
    } catch (e) {
      logError('DataService', `SELECT failed for "${name}"`, e)
      return []
    }
  }

  /** Query with a filter map (field=value AND conditions). */
  async queryWithFilter(
    table: string,
    filter: Record<string, string>,
  ): Promise<Record<string, unknown>[]> {
    // Validate all filter field names before building the query.
    for (const k of Object.keys(filter)) {
      validateFieldName(k)
    }
    const name = this.collectionName(table)
    const filterStr = Object.entries(filter)
      .map(([k, v]) => `${k} = "${this.escapeFilter(v)}"`)
      .join(' && ')

    try {
      const records = await this.pb.collection(name).getFullList({
        filter: filterStr,
        requestKey: null,
      })
      logDebug('DataService', `SELECT FILTERED from "${name}" WHERE ${filterStr}: ${records.length} rows`)
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
    validateFieldName(ownerField)
    if (!ownerId || (isAdmin && adminOverride)) {
      return this.query(table)
    }

    const name = this.collectionName(table)
    try {
      const records = await this.pb.collection(name).getFullList({
        filter: `${ownerField} = "${this.escapeFilter(ownerId)}"`,
        requestKey: null,
      })
      logDebug('DataService', `SELECT OWNED from "${name}" WHERE ${ownerField}="${ownerId}": ${records.length} rows`)
      return records.map(r => this.normalizeRecord(r))
    } catch {
      return []
    }
  }

  /** Get total row count for a table. */
  async getRowCount(table: string): Promise<number> {
    const name = this.collectionName(table)
    try {
      const result = await this.pb.collection(name).getList(1, 1, {
        requestKey: `count_${name}_${Date.now()}`,
      })
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
        requestKey: null,
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
        requestKey: null,
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
      const records = await this.pb.collection(name).getFullList({ requestKey: null })
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
  // Helpers
  // ---------------------------------------------------------------------------

  /** Reverse-map ODS field names back to PocketBase names for queries. */
  private denormalizeField(field: string): string {
    if (field === '_id') return 'id'
    if (field === '_createdAt') return 'created'
    return field
  }

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

  // ---------------------------------------------------------------------------
  // Bulk export / import — used for data backup & restore across frameworks
  // ---------------------------------------------------------------------------

  /** Export all data from all known collections for this app. */
  async exportAllData(dataSources: Record<string, OdsDataSource>): Promise<Record<string, Record<string, unknown>[]>> {
    const result: Record<string, Record<string, unknown>[]> = {}
    for (const [, ds] of Object.entries(dataSources)) {
      if (isLocal(ds)) {
        const name = tableName(ds)
        try {
          result[name] = await this.query(name)
        } catch {
          result[name] = []
        }
      }
    }
    return result
  }

  /** Import data into collections, clearing existing data first. */
  async importAllData(
    data: Record<string, Record<string, unknown>[]>,
    dataSources: Record<string, OdsDataSource>,
  ): Promise<{ tables: number; rows: number }> {
    let totalRows = 0
    let totalTables = 0

    for (const [name, rows] of Object.entries(data)) {
      // Find matching dataSource to get field definitions for ensureCollection
      const matchingDs = Object.values(dataSources).find(
        ds => isLocal(ds) && tableName(ds) === name
      )
      if (!matchingDs) continue

      // Delete existing rows
      const existing = await this.query(name)
      for (const row of existing) {
        const id = String(row['_id'] ?? '')
        if (id) await this.delete(name, '_id', id)
      }

      // Insert new rows (strip framework fields)
      for (const row of rows) {
        const insertRow = { ...row }
        delete insertRow['_id']
        delete insertRow['_createdAt']
        delete insertRow['collectionId']
        delete insertRow['collectionName']
        await this.insert(name, insertRow)
      }

      totalTables++
      totalRows += rows.length
    }

    return { tables: totalTables, rows: totalRows }
  }

  /** Escape a value for use in PocketBase filter strings. */
  private escapeFilter(value: string): string {
    return value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')
  }
}

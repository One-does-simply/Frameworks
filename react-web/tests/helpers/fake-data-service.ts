/**
 * In-memory fake DataService for unit tests.
 * Mimics the real DataService interface without needing PocketBase.
 */
export class FakeDataService {
  private tables: Record<string, Record<string, unknown>[]> = {}
  private nextId = 1
  private appPrefix = 'test'
  insertedData: Record<string, unknown>[] = []

  initialize(appName: string) {
    this.appPrefix = appName.replace(/[^\w]/g, '_').toLowerCase()
    this.tables = {}
    this.insertedData = []
    this.nextId = 1
  }

  collectionName(table: string): string {
    return `${this.appPrefix}_${table}`
  }

  async ensureCollection(_table: string, _fields: unknown[]): Promise<void> {
    // No-op for fake
  }

  async setupDataSources(_dataSources: Record<string, unknown>): Promise<void> {
    // No-op for fake
  }

  async insert(table: string, data: Record<string, unknown>): Promise<string> {
    const id = String(this.nextId++)
    const row = { ...data, _id: id, _createdAt: new Date().toISOString() }
    if (!this.tables[table]) this.tables[table] = []
    this.tables[table].push(row)
    this.insertedData.push(row)
    return id
  }

  async update(
    table: string,
    data: Record<string, unknown>,
    matchField: string,
    matchValue: string,
  ): Promise<number> {
    const rows = this.tables[table] ?? []
    let count = 0
    for (const row of rows) {
      if (String(row[matchField]) === matchValue) {
        Object.assign(row, data)
        count++
      }
    }
    return count
  }

  async delete(table: string, matchField: string, matchValue: string): Promise<number> {
    if (!this.tables[table]) return 0
    const before = this.tables[table].length
    this.tables[table] = this.tables[table].filter(
      row => String(row[matchField]) !== matchValue
    )
    return before - this.tables[table].length
  }

  async query(table: string): Promise<Record<string, unknown>[]> {
    return [...(this.tables[table] ?? [])].reverse()
  }

  async queryWithFilter(
    table: string,
    filter: Record<string, string>,
  ): Promise<Record<string, unknown>[]> {
    const rows = this.tables[table] ?? []
    return rows.filter(row =>
      Object.entries(filter).every(([k, v]) => String(row[k]) === v)
    )
  }

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
    return this.queryWithFilter(table, { [ownerField]: ownerId })
  }

  async getRowCount(table: string): Promise<number> {
    return (this.tables[table] ?? []).length
  }

  async getAppSetting(_key: string): Promise<string | undefined> {
    return undefined
  }

  async setAppSetting(_key: string, _value: string): Promise<void> {
    // No-op
  }

  async getAllAppSettings(): Promise<Record<string, string>> {
    return {}
  }

  getDebugLog(): readonly string[] {
    return []
  }

  /** Test helper: seed data directly into a table. */
  seed(table: string, rows: Record<string, unknown>[]) {
    this.tables[table] = rows.map((row, i) => ({
      ...row,
      _id: String(this.nextId++),
      _createdAt: new Date(Date.now() - (rows.length - i) * 1000).toISOString(),
    }))
  }
}

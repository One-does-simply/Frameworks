import { describe, it, expect } from 'vitest'
import {
  parseDataSource,
  isLocal,
  tableName,
  type OdsDataSource,
} from '../../../src/models/ods-data-source.ts'

// ===========================================================================
// OdsDataSource model tests
// ===========================================================================

describe('parseDataSource', () => {
  // -------------------------------------------------------------------------
  // Local URL
  // -------------------------------------------------------------------------

  it('parses a data source with local:// URL', () => {
    const result = parseDataSource({ url: 'local://tasks', method: 'GET' })
    expect(result.url).toBe('local://tasks')
    expect(result.method).toBe('GET')
  })

  // -------------------------------------------------------------------------
  // External URL
  // -------------------------------------------------------------------------

  it('parses a data source with external URL', () => {
    const result = parseDataSource({ url: 'https://api.example.com/tasks', method: 'POST' })
    expect(result.url).toBe('https://api.example.com/tasks')
    expect(result.method).toBe('POST')
  })

  // -------------------------------------------------------------------------
  // Fields array
  // -------------------------------------------------------------------------

  it('parses data source with fields array', () => {
    const result = parseDataSource({
      url: 'local://items',
      method: 'GET',
      fields: [
        { name: 'id', type: 'text' },
        { name: 'title', type: 'text' },
      ],
    })
    expect(result.fields).toBeDefined()
    expect(result.fields).toHaveLength(2)
  })

  it('sets fields to undefined when not provided', () => {
    const result = parseDataSource({ url: 'local://items', method: 'GET' })
    expect(result.fields).toBeUndefined()
  })

  it('sets fields to undefined when fields is not an array', () => {
    const result = parseDataSource({ url: 'local://items', method: 'GET', fields: 'not-array' })
    expect(result.fields).toBeUndefined()
  })

  // -------------------------------------------------------------------------
  // Seed data
  // -------------------------------------------------------------------------

  it('parses data source with seedData', () => {
    const result = parseDataSource({
      url: 'local://tasks',
      method: 'GET',
      seedData: [
        { id: '1', title: 'Task 1' },
        { id: '2', title: 'Task 2' },
      ],
    })
    expect(result.seedData).toBeDefined()
    expect(result.seedData).toHaveLength(2)
    expect(result.seedData![0]).toEqual({ id: '1', title: 'Task 1' })
  })

  it('sets seedData to undefined when not provided', () => {
    const result = parseDataSource({ url: 'local://tasks', method: 'GET' })
    expect(result.seedData).toBeUndefined()
  })

  // -------------------------------------------------------------------------
  // Ownership config
  // -------------------------------------------------------------------------

  it('parses data source with ownership config', () => {
    const result = parseDataSource({
      url: 'local://tasks',
      method: 'GET',
      ownership: { enabled: true, ownerField: 'createdBy', adminOverride: false },
    })
    expect(result.ownership.enabled).toBe(true)
    expect(result.ownership.ownerField).toBe('createdBy')
    expect(result.ownership.adminOverride).toBe(false)
  })

  it('provides default ownership when not specified', () => {
    const result = parseDataSource({ url: 'local://tasks', method: 'GET' })
    expect(result.ownership.enabled).toBe(false)
    expect(result.ownership.ownerField).toBe('_owner')
    expect(result.ownership.adminOverride).toBe(true)
  })
})

// ===========================================================================
// isLocal helper
// ===========================================================================

describe('isLocal', () => {
  it('returns true for local:// URLs', () => {
    const ds = parseDataSource({ url: 'local://tasks', method: 'GET' })
    expect(isLocal(ds)).toBe(true)
  })

  it('returns false for http:// URLs', () => {
    const ds = parseDataSource({ url: 'http://api.example.com/tasks', method: 'GET' })
    expect(isLocal(ds)).toBe(false)
  })

  it('returns false for https:// URLs', () => {
    const ds = parseDataSource({ url: 'https://api.example.com/tasks', method: 'GET' })
    expect(isLocal(ds)).toBe(false)
  })
})

// ===========================================================================
// tableName helper
// ===========================================================================

describe('tableName', () => {
  it('extracts table name from local:// URL', () => {
    const ds = parseDataSource({ url: 'local://myTable', method: 'GET' })
    expect(tableName(ds)).toBe('myTable')
  })

  it('extracts table name with complex name', () => {
    const ds = parseDataSource({ url: 'local://user_records_v2', method: 'GET' })
    expect(tableName(ds)).toBe('user_records_v2')
  })

  it('returns empty string for non-local sources', () => {
    const ds = parseDataSource({ url: 'https://api.example.com/data', method: 'GET' })
    expect(tableName(ds)).toBe('')
  })

  it('returns empty string for http:// sources', () => {
    const ds = parseDataSource({ url: 'http://api.example.com/data', method: 'GET' })
    expect(tableName(ds)).toBe('')
  })
})

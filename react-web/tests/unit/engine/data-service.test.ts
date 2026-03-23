import { describe, it, expect } from 'vitest'
import { FakeDataService } from '../../helpers/fake-data-service.ts'

describe('FakeDataService (mirrors DataService interface)', () => {
  let ds: FakeDataService

  beforeEach(() => {
    ds = new FakeDataService()
    ds.initialize('testApp')
  })

  describe('insert', () => {
    it('inserts a row and returns an ID', async () => {
      const id = await ds.insert('tasks', { name: 'Buy milk', status: 'open' })
      expect(id).toBeTruthy()
    })

    it('inserted row appears in query', async () => {
      await ds.insert('tasks', { name: 'Buy milk' })
      const rows = await ds.query('tasks')
      expect(rows).toHaveLength(1)
      expect(rows[0]['name']).toBe('Buy milk')
    })

    it('auto-adds _id and _createdAt', async () => {
      await ds.insert('tasks', { name: 'Test' })
      const rows = await ds.query('tasks')
      expect(rows[0]['_id']).toBeTruthy()
      expect(rows[0]['_createdAt']).toBeTruthy()
    })
  })

  describe('update', () => {
    it('updates matching rows', async () => {
      await ds.insert('tasks', { name: 'Task1', status: 'open' })
      const count = await ds.update('tasks', { status: 'done' }, 'name', 'Task1')
      expect(count).toBe(1)

      const rows = await ds.query('tasks')
      expect(rows[0]['status']).toBe('done')
    })

    it('returns 0 for no matches', async () => {
      await ds.insert('tasks', { name: 'Task1' })
      const count = await ds.update('tasks', { status: 'done' }, 'name', 'Missing')
      expect(count).toBe(0)
    })
  })

  describe('delete', () => {
    it('deletes matching rows', async () => {
      await ds.insert('tasks', { name: 'Task1' })
      await ds.insert('tasks', { name: 'Task2' })
      const count = await ds.delete('tasks', 'name', 'Task1')
      expect(count).toBe(1)

      const rows = await ds.query('tasks')
      expect(rows).toHaveLength(1)
      expect(rows[0]['name']).toBe('Task2')
    })
  })

  describe('query', () => {
    it('returns empty array for unknown table', async () => {
      const rows = await ds.query('nonexistent')
      expect(rows).toEqual([])
    })

    it('returns rows in reverse insertion order (newest first)', async () => {
      await ds.insert('tasks', { name: 'First' })
      await ds.insert('tasks', { name: 'Second' })
      const rows = await ds.query('tasks')
      expect(rows[0]['name']).toBe('Second')
      expect(rows[1]['name']).toBe('First')
    })
  })

  describe('queryWithFilter', () => {
    it('filters by field value', async () => {
      await ds.insert('tasks', { name: 'A', status: 'open' })
      await ds.insert('tasks', { name: 'B', status: 'done' })
      await ds.insert('tasks', { name: 'C', status: 'open' })

      const rows = await ds.queryWithFilter('tasks', { status: 'open' })
      expect(rows).toHaveLength(2)
    })
  })

  describe('queryWithOwnership', () => {
    it('filters by owner when enabled', async () => {
      ds.seed('tasks', [
        { name: 'Mine', _owner: 'user1' },
        { name: 'Theirs', _owner: 'user2' },
      ])

      const rows = await ds.queryWithOwnership('tasks', '_owner', 'user1', false, true)
      expect(rows).toHaveLength(1)
      expect(rows[0]['name']).toBe('Mine')
    })

    it('admin sees all when adminOverride is true', async () => {
      ds.seed('tasks', [
        { name: 'Mine', _owner: 'user1' },
        { name: 'Theirs', _owner: 'user2' },
      ])

      const rows = await ds.queryWithOwnership('tasks', '_owner', 'admin', true, true)
      expect(rows).toHaveLength(2)
    })

    it('admin filtered when adminOverride is false', async () => {
      ds.seed('tasks', [
        { name: 'Mine', _owner: 'admin' },
        { name: 'Theirs', _owner: 'user2' },
      ])

      const rows = await ds.queryWithOwnership('tasks', '_owner', 'admin', true, false)
      expect(rows).toHaveLength(1)
    })
  })

  describe('getRowCount', () => {
    it('returns 0 for empty/unknown table', async () => {
      expect(await ds.getRowCount('nothing')).toBe(0)
    })

    it('returns correct count', async () => {
      await ds.insert('tasks', { name: 'A' })
      await ds.insert('tasks', { name: 'B' })
      expect(await ds.getRowCount('tasks')).toBe(2)
    })
  })
})

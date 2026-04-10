import { describe, it, expect } from 'vitest'
import { parsePage, type OdsPage } from '../../../src/models/ods-page.ts'

// ===========================================================================
// OdsPage model tests
// ===========================================================================

describe('parsePage', () => {
  // -------------------------------------------------------------------------
  // Basic parsing
  // -------------------------------------------------------------------------

  it('parses title and content array', () => {
    const page = parsePage({
      title: 'Home',
      content: [{ component: 'text', content: 'Welcome' }],
    })
    expect(page.title).toBe('Home')
    expect(page.content).toHaveLength(1)
  })

  it('parses with empty content', () => {
    const page = parsePage({ title: 'Empty', content: [] })
    expect(page.title).toBe('Empty')
    expect(page.content).toEqual([])
  })

  it('defaults content to empty array when missing', () => {
    const page = parsePage({ title: 'No Content' })
    expect(page.content).toEqual([])
  })

  // -------------------------------------------------------------------------
  // Roles
  // -------------------------------------------------------------------------

  it('parses roles', () => {
    const page = parsePage({
      title: 'Admin Panel',
      content: [],
      roles: ['admin', 'manager'],
    })
    expect(page.roles).toEqual(['admin', 'manager'])
  })

  it('roles is undefined when not provided', () => {
    const page = parsePage({ title: 'Public', content: [] })
    expect(page.roles).toBeUndefined()
  })

  // -------------------------------------------------------------------------
  // Content component parsing
  // -------------------------------------------------------------------------

  it('parses multiple components in content', () => {
    const page = parsePage({
      title: 'Dashboard',
      content: [
        { component: 'text', content: 'Hello' },
        { component: 'list', dataSource: 'tasks', columns: [] },
        { component: 'button', label: 'Add', onClick: [] },
      ],
    })
    expect(page.content).toHaveLength(3)
    expect(page.content[0].component).toBe('text')
    expect(page.content[1].component).toBe('list')
    expect(page.content[2].component).toBe('button')
  })

  it('fully parses content components (not raw JSON)', () => {
    const page = parsePage({
      title: 'Test',
      content: [
        { component: 'text', content: 'Parsed', format: 'markdown' },
      ],
    })
    const comp = page.content[0]
    expect(comp.component).toBe('text')
    if (comp.component === 'text') {
      expect(comp.content).toBe('Parsed')
      expect(comp.format).toBe('markdown')
    }
  })

  it('parses content component with styleHint and roles', () => {
    const page = parsePage({
      title: 'Test',
      content: [
        {
          component: 'summary',
          label: 'Count',
          value: '10',
          roles: ['admin'],
          styleHint: { variant: 'outlined' },
        },
      ],
    })
    const comp = page.content[0]
    expect(comp.roles).toEqual(['admin'])
    expect(comp.styleHint).toEqual({ variant: 'outlined' })
  })
})

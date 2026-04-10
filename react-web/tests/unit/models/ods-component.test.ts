import { describe, it, expect } from 'vitest'
import { parseComponent, hideWhenMatches, type OdsRowActionHideWhen } from '../../../src/models/ods-component.ts'

// ===========================================================================
// OdsComponent model tests
// ===========================================================================

describe('parseComponent', () => {
  // -------------------------------------------------------------------------
  // Text component
  // -------------------------------------------------------------------------

  describe('text', () => {
    it('parses content', () => {
      const comp = parseComponent({ component: 'text', content: 'Hello world' })
      expect(comp.component).toBe('text')
      if (comp.component === 'text') {
        expect(comp.content).toBe('Hello world')
      }
    })

    it('defaults format to plain', () => {
      const comp = parseComponent({ component: 'text', content: 'Hello' })
      if (comp.component === 'text') {
        expect(comp.format).toBe('plain')
      }
    })

    it('parses explicit format', () => {
      const comp = parseComponent({ component: 'text', content: '# Title', format: 'markdown' })
      if (comp.component === 'text') {
        expect(comp.format).toBe('markdown')
      }
    })
  })

  // -------------------------------------------------------------------------
  // List component
  // -------------------------------------------------------------------------

  describe('list', () => {
    it('parses dataSource', () => {
      const comp = parseComponent({ component: 'list', dataSource: 'tasks', columns: [] })
      expect(comp.component).toBe('list')
      if (comp.component === 'list') {
        expect(comp.dataSource).toBe('tasks')
      }
    })

    it('parses columns', () => {
      const comp = parseComponent({
        component: 'list',
        dataSource: 'ds',
        columns: [
          { header: 'Name', field: 'name' },
          { header: 'Age', field: 'age', sortable: true },
        ],
      })
      if (comp.component === 'list') {
        expect(comp.columns).toHaveLength(2)
        expect(comp.columns[0].header).toBe('Name')
        expect(comp.columns[0].field).toBe('name')
        expect(comp.columns[0].sortable).toBe(false)
        expect(comp.columns[1].sortable).toBe(true)
      }
    })

    it('defaults columns to empty array when missing', () => {
      const comp = parseComponent({ component: 'list', dataSource: 'ds' })
      if (comp.component === 'list') {
        expect(comp.columns).toEqual([])
      }
    })

    it('parses rowActions', () => {
      const comp = parseComponent({
        component: 'list',
        dataSource: 'ds',
        columns: [],
        rowActions: [
          { label: 'Delete', action: 'delete', dataSource: 'ds' },
        ],
      })
      if (comp.component === 'list') {
        expect(comp.rowActions).toHaveLength(1)
        expect(comp.rowActions[0].label).toBe('Delete')
        expect(comp.rowActions[0].action).toBe('delete')
      }
    })

    it('defaults rowActions to empty array when missing', () => {
      const comp = parseComponent({ component: 'list', dataSource: 'ds', columns: [] })
      if (comp.component === 'list') {
        expect(comp.rowActions).toEqual([])
      }
    })

    it('parses summary rules', () => {
      const comp = parseComponent({
        component: 'list',
        dataSource: 'ds',
        columns: [],
        summary: [
          { column: 'amount', function: 'sum', label: 'Total' },
        ],
      })
      if (comp.component === 'list') {
        expect(comp.summary).toHaveLength(1)
        expect(comp.summary[0].column).toBe('amount')
        expect(comp.summary[0].function).toBe('sum')
        expect(comp.summary[0].label).toBe('Total')
      }
    })

    it('defaults summary to empty array when missing', () => {
      const comp = parseComponent({ component: 'list', dataSource: 'ds', columns: [] })
      if (comp.component === 'list') {
        expect(comp.summary).toEqual([])
      }
    })

    it('parses onRowTap', () => {
      const comp = parseComponent({
        component: 'list',
        dataSource: 'ds',
        columns: [],
        onRowTap: { target: 'detailPage', populateForm: 'editForm' },
      })
      if (comp.component === 'list') {
        expect(comp.onRowTap).toBeDefined()
        expect(comp.onRowTap!.target).toBe('detailPage')
        expect(comp.onRowTap!.populateForm).toBe('editForm')
      }
    })

    it('onRowTap is undefined when missing', () => {
      const comp = parseComponent({ component: 'list', dataSource: 'ds', columns: [] })
      if (comp.component === 'list') {
        expect(comp.onRowTap).toBeUndefined()
      }
    })

    it('defaults searchable to false', () => {
      const comp = parseComponent({ component: 'list', dataSource: 'ds', columns: [] })
      if (comp.component === 'list') {
        expect(comp.searchable).toBe(false)
      }
    })

    it('parses searchable true', () => {
      const comp = parseComponent({ component: 'list', dataSource: 'ds', columns: [], searchable: true })
      if (comp.component === 'list') {
        expect(comp.searchable).toBe(true)
      }
    })

    it('defaults displayAs to table', () => {
      const comp = parseComponent({ component: 'list', dataSource: 'ds', columns: [] })
      if (comp.component === 'list') {
        expect(comp.displayAs).toBe('table')
      }
    })

    it('parses displayAs cards', () => {
      const comp = parseComponent({ component: 'list', dataSource: 'ds', columns: [], displayAs: 'cards' })
      if (comp.component === 'list') {
        expect(comp.displayAs).toBe('cards')
      }
    })

    it('parses defaultSort', () => {
      const comp = parseComponent({
        component: 'list',
        dataSource: 'ds',
        columns: [],
        defaultSort: { field: 'name', direction: 'desc' },
      })
      if (comp.component === 'list') {
        expect(comp.defaultSort).toBeDefined()
        expect(comp.defaultSort!.field).toBe('name')
        expect(comp.defaultSort!.direction).toBe('desc')
      }
    })

    it('defaultSort defaults direction to asc', () => {
      const comp = parseComponent({
        component: 'list',
        dataSource: 'ds',
        columns: [],
        defaultSort: { field: 'name' },
      })
      if (comp.component === 'list') {
        expect(comp.defaultSort!.direction).toBe('asc')
      }
    })

    it('defaultSort is undefined when missing', () => {
      const comp = parseComponent({ component: 'list', dataSource: 'ds', columns: [] })
      if (comp.component === 'list') {
        expect(comp.defaultSort).toBeUndefined()
      }
    })

    it('parses rowColorField and rowColorMap', () => {
      const comp = parseComponent({
        component: 'list',
        dataSource: 'ds',
        columns: [],
        rowColorField: 'status',
        rowColorMap: { active: 'green', inactive: 'red' },
      })
      if (comp.component === 'list') {
        expect(comp.rowColorField).toBe('status')
        expect(comp.rowColorMap).toEqual({ active: 'green', inactive: 'red' })
      }
    })

    it('rowColorField and rowColorMap are undefined when missing', () => {
      const comp = parseComponent({ component: 'list', dataSource: 'ds', columns: [] })
      if (comp.component === 'list') {
        expect(comp.rowColorField).toBeUndefined()
        expect(comp.rowColorMap).toBeUndefined()
      }
    })

    it('parses column with colorMap and displayMap', () => {
      const comp = parseComponent({
        component: 'list',
        dataSource: 'ds',
        columns: [
          {
            header: 'Status',
            field: 'status',
            colorMap: { open: 'blue', closed: 'gray' },
            displayMap: { open: 'Open', closed: 'Closed' },
          },
        ],
      })
      if (comp.component === 'list') {
        expect(comp.columns[0].colorMap).toEqual({ open: 'blue', closed: 'gray' })
        expect(comp.columns[0].displayMap).toEqual({ open: 'Open', closed: 'Closed' })
      }
    })

    it('column defaults filterable and currency to false', () => {
      const comp = parseComponent({
        component: 'list',
        dataSource: 'ds',
        columns: [{ header: 'Name', field: 'name' }],
      })
      if (comp.component === 'list') {
        expect(comp.columns[0].filterable).toBe(false)
        expect(comp.columns[0].currency).toBe(false)
      }
    })
  })

  // -------------------------------------------------------------------------
  // Form component
  // -------------------------------------------------------------------------

  describe('form', () => {
    it('parses id', () => {
      const comp = parseComponent({ component: 'form', id: 'myForm', fields: [] })
      expect(comp.component).toBe('form')
      if (comp.component === 'form') {
        expect(comp.id).toBe('myForm')
      }
    })

    it('parses fields array', () => {
      const comp = parseComponent({
        component: 'form',
        id: 'f1',
        fields: [
          { name: 'email', type: 'email' },
          { name: 'age', type: 'number' },
        ],
      })
      if (comp.component === 'form') {
        expect(comp.fields).toHaveLength(2)
        expect(comp.fields[0].name).toBe('email')
        expect(comp.fields[1].name).toBe('age')
      }
    })

    it('defaults fields to empty array when missing', () => {
      const comp = parseComponent({ component: 'form', id: 'f1' })
      if (comp.component === 'form') {
        expect(comp.fields).toEqual([])
      }
    })

    it('parses recordSource', () => {
      const comp = parseComponent({ component: 'form', id: 'f1', fields: [], recordSource: 'tasks' })
      if (comp.component === 'form') {
        expect(comp.recordSource).toBe('tasks')
      }
    })

    it('recordSource is undefined when missing', () => {
      const comp = parseComponent({ component: 'form', id: 'f1', fields: [] })
      if (comp.component === 'form') {
        expect(comp.recordSource).toBeUndefined()
      }
    })
  })

  // -------------------------------------------------------------------------
  // Button component
  // -------------------------------------------------------------------------

  describe('button', () => {
    it('parses label', () => {
      const comp = parseComponent({
        component: 'button',
        label: 'Submit',
        onClick: [{ action: 'navigate', target: 'home' }],
      })
      expect(comp.component).toBe('button')
      if (comp.component === 'button') {
        expect(comp.label).toBe('Submit')
      }
    })

    it('parses onClick actions array', () => {
      const comp = parseComponent({
        component: 'button',
        label: 'Save',
        onClick: [
          { action: 'save', dataSource: 'ds', form: 'f1' },
          { action: 'navigate', target: 'list' },
        ],
      })
      if (comp.component === 'button') {
        expect(comp.onClick).toHaveLength(2)
        expect(comp.onClick[0].action).toBe('save')
        expect(comp.onClick[1].action).toBe('navigate')
      }
    })

    it('defaults onClick to empty array when missing', () => {
      const comp = parseComponent({ component: 'button', label: 'Click' })
      if (comp.component === 'button') {
        expect(comp.onClick).toEqual([])
      }
    })
  })

  // -------------------------------------------------------------------------
  // Chart component
  // -------------------------------------------------------------------------

  describe('chart', () => {
    it('parses dataSource and fields', () => {
      const comp = parseComponent({
        component: 'chart',
        dataSource: 'sales',
        labelField: 'month',
        valueField: 'amount',
      })
      expect(comp.component).toBe('chart')
      if (comp.component === 'chart') {
        expect(comp.dataSource).toBe('sales')
        expect(comp.labelField).toBe('month')
        expect(comp.valueField).toBe('amount')
      }
    })

    it('defaults chartType to bar', () => {
      const comp = parseComponent({
        component: 'chart',
        dataSource: 'ds',
        labelField: 'x',
        valueField: 'y',
      })
      if (comp.component === 'chart') {
        expect(comp.chartType).toBe('bar')
      }
    })

    it('parses explicit chartType', () => {
      const comp = parseComponent({
        component: 'chart',
        dataSource: 'ds',
        chartType: 'pie',
        labelField: 'x',
        valueField: 'y',
      })
      if (comp.component === 'chart') {
        expect(comp.chartType).toBe('pie')
      }
    })

    it('normalizes aggregate count', () => {
      const comp = parseComponent({
        component: 'chart',
        dataSource: 'ds',
        labelField: 'x',
        valueField: 'y',
        aggregate: 'count',
      })
      if (comp.component === 'chart') {
        expect(comp.aggregate).toBe('count')
      }
    })

    it('normalizes aggregate average to avg', () => {
      const comp = parseComponent({
        component: 'chart',
        dataSource: 'ds',
        labelField: 'x',
        valueField: 'y',
        aggregate: 'average',
      })
      if (comp.component === 'chart') {
        expect(comp.aggregate).toBe('avg')
      }
    })

    it('normalizes aggregate avg', () => {
      const comp = parseComponent({
        component: 'chart',
        dataSource: 'ds',
        labelField: 'x',
        valueField: 'y',
        aggregate: 'avg',
      })
      if (comp.component === 'chart') {
        expect(comp.aggregate).toBe('avg')
      }
    })

    it('normalizes aggregate sum', () => {
      const comp = parseComponent({
        component: 'chart',
        dataSource: 'ds',
        labelField: 'x',
        valueField: 'y',
        aggregate: 'sum',
      })
      if (comp.component === 'chart') {
        expect(comp.aggregate).toBe('sum')
      }
    })

    it('defaults aggregate to sum when labelField differs from valueField', () => {
      const comp = parseComponent({
        component: 'chart',
        dataSource: 'ds',
        labelField: 'category',
        valueField: 'amount',
      })
      if (comp.component === 'chart') {
        expect(comp.aggregate).toBe('sum')
      }
    })

    it('defaults aggregate to count when labelField equals valueField', () => {
      const comp = parseComponent({
        component: 'chart',
        dataSource: 'ds',
        labelField: 'status',
        valueField: 'status',
      })
      if (comp.component === 'chart') {
        expect(comp.aggregate).toBe('count')
      }
    })

    it('parses title', () => {
      const comp = parseComponent({
        component: 'chart',
        dataSource: 'ds',
        labelField: 'x',
        valueField: 'y',
        title: 'Sales Report',
      })
      if (comp.component === 'chart') {
        expect(comp.title).toBe('Sales Report')
      }
    })
  })

  // -------------------------------------------------------------------------
  // Summary component
  // -------------------------------------------------------------------------

  describe('summary', () => {
    it('parses label and value', () => {
      const comp = parseComponent({
        component: 'summary',
        label: 'Total',
        value: '{{count}}',
      })
      expect(comp.component).toBe('summary')
      if (comp.component === 'summary') {
        expect(comp.label).toBe('Total')
        expect(comp.value).toBe('{{count}}')
      }
    })

    it('parses icon', () => {
      const comp = parseComponent({
        component: 'summary',
        label: 'Revenue',
        value: '$1M',
        icon: 'dollar',
      })
      if (comp.component === 'summary') {
        expect(comp.icon).toBe('dollar')
      }
    })

    it('icon is undefined when missing', () => {
      const comp = parseComponent({
        component: 'summary',
        label: 'Count',
        value: '42',
      })
      if (comp.component === 'summary') {
        expect(comp.icon).toBeUndefined()
      }
    })
  })

  // -------------------------------------------------------------------------
  // Tabs component
  // -------------------------------------------------------------------------

  describe('tabs', () => {
    it('parses tabs with recursive content', () => {
      const comp = parseComponent({
        component: 'tabs',
        tabs: [
          {
            label: 'Overview',
            content: [
              { component: 'text', content: 'Welcome' },
            ],
          },
          {
            label: 'Data',
            content: [
              { component: 'list', dataSource: 'ds', columns: [] },
            ],
          },
        ],
      })
      expect(comp.component).toBe('tabs')
      if (comp.component === 'tabs') {
        expect(comp.tabs).toHaveLength(2)
        expect(comp.tabs[0].label).toBe('Overview')
        expect(comp.tabs[0].content).toHaveLength(1)
        expect(comp.tabs[0].content[0].component).toBe('text')
        expect(comp.tabs[1].label).toBe('Data')
        expect(comp.tabs[1].content[0].component).toBe('list')
      }
    })

    it('defaults tabs to empty array when missing', () => {
      const comp = parseComponent({ component: 'tabs' })
      if (comp.component === 'tabs') {
        expect(comp.tabs).toEqual([])
      }
    })

    it('defaults tab content to empty array when missing', () => {
      const comp = parseComponent({
        component: 'tabs',
        tabs: [{ label: 'Empty Tab' }],
      })
      if (comp.component === 'tabs') {
        expect(comp.tabs[0].content).toEqual([])
      }
    })
  })

  // -------------------------------------------------------------------------
  // Detail component
  // -------------------------------------------------------------------------

  describe('detail', () => {
    it('parses dataSource', () => {
      const comp = parseComponent({
        component: 'detail',
        dataSource: 'tasks',
      })
      expect(comp.component).toBe('detail')
      if (comp.component === 'detail') {
        expect(comp.dataSource).toBe('tasks')
      }
    })

    it('defaults dataSource to empty string when missing', () => {
      const comp = parseComponent({ component: 'detail' })
      if (comp.component === 'detail') {
        expect(comp.dataSource).toBe('')
      }
    })

    it('parses fields array', () => {
      const comp = parseComponent({
        component: 'detail',
        dataSource: 'ds',
        fields: ['name', 'email', 'phone'],
      })
      if (comp.component === 'detail') {
        expect(comp.fields).toEqual(['name', 'email', 'phone'])
      }
    })

    it('fields is undefined when missing', () => {
      const comp = parseComponent({ component: 'detail', dataSource: 'ds' })
      if (comp.component === 'detail') {
        expect(comp.fields).toBeUndefined()
      }
    })

    it('parses labels', () => {
      const comp = parseComponent({
        component: 'detail',
        dataSource: 'ds',
        labels: { name: 'Full Name', email: 'Email Address' },
      })
      if (comp.component === 'detail') {
        expect(comp.labels).toEqual({ name: 'Full Name', email: 'Email Address' })
      }
    })

    it('labels is undefined when missing', () => {
      const comp = parseComponent({ component: 'detail', dataSource: 'ds' })
      if (comp.component === 'detail') {
        expect(comp.labels).toBeUndefined()
      }
    })

    it('parses fromForm', () => {
      const comp = parseComponent({
        component: 'detail',
        dataSource: 'ds',
        fromForm: 'editForm',
      })
      if (comp.component === 'detail') {
        expect(comp.fromForm).toBe('editForm')
      }
    })

    it('fromForm is undefined when missing', () => {
      const comp = parseComponent({ component: 'detail', dataSource: 'ds' })
      if (comp.component === 'detail') {
        expect(comp.fromForm).toBeUndefined()
      }
    })
  })

  // -------------------------------------------------------------------------
  // Kanban component
  // -------------------------------------------------------------------------

  describe('kanban', () => {
    it('parses dataSource and statusField', () => {
      const comp = parseComponent({
        component: 'kanban',
        dataSource: 'tasks',
        statusField: 'status',
        cardFields: ['title', 'assignee'],
      })
      expect(comp.component).toBe('kanban')
      if (comp.component === 'kanban') {
        expect(comp.dataSource).toBe('tasks')
        expect(comp.statusField).toBe('status')
      }
    })

    it('defaults statusField to empty string when missing', () => {
      const comp = parseComponent({ component: 'kanban', dataSource: 'ds', cardFields: [] })
      if (comp.component === 'kanban') {
        expect(comp.statusField).toBe('')
      }
    })

    it('parses cardFields', () => {
      const comp = parseComponent({
        component: 'kanban',
        dataSource: 'ds',
        statusField: 'status',
        cardFields: ['title', 'priority', 'assignee'],
      })
      if (comp.component === 'kanban') {
        expect(comp.cardFields).toEqual(['title', 'priority', 'assignee'])
      }
    })

    it('defaults cardFields to empty array when missing', () => {
      const comp = parseComponent({ component: 'kanban', dataSource: 'ds', statusField: 'status' })
      if (comp.component === 'kanban') {
        expect(comp.cardFields).toEqual([])
      }
    })

    it('parses rowActions', () => {
      const comp = parseComponent({
        component: 'kanban',
        dataSource: 'ds',
        statusField: 'status',
        cardFields: [],
        rowActions: [{ label: 'Archive', action: 'update', dataSource: 'ds' }],
      })
      if (comp.component === 'kanban') {
        expect(comp.rowActions).toHaveLength(1)
        expect(comp.rowActions[0].label).toBe('Archive')
      }
    })

    it('defaults rowActions to empty array when missing', () => {
      const comp = parseComponent({ component: 'kanban', dataSource: 'ds', statusField: 'status', cardFields: [] })
      if (comp.component === 'kanban') {
        expect(comp.rowActions).toEqual([])
      }
    })

    it('defaults searchable to false', () => {
      const comp = parseComponent({ component: 'kanban', dataSource: 'ds', statusField: 'status', cardFields: [] })
      if (comp.component === 'kanban') {
        expect(comp.searchable).toBe(false)
      }
    })

    it('parses searchable true', () => {
      const comp = parseComponent({
        component: 'kanban',
        dataSource: 'ds',
        statusField: 'status',
        cardFields: [],
        searchable: true,
      })
      if (comp.component === 'kanban') {
        expect(comp.searchable).toBe(true)
      }
    })

    it('parses defaultSort', () => {
      const comp = parseComponent({
        component: 'kanban',
        dataSource: 'ds',
        statusField: 'status',
        cardFields: [],
        defaultSort: { field: 'priority', direction: 'desc' },
      })
      if (comp.component === 'kanban') {
        expect(comp.defaultSort).toBeDefined()
        expect(comp.defaultSort!.field).toBe('priority')
        expect(comp.defaultSort!.direction).toBe('desc')
      }
    })
  })

  // -------------------------------------------------------------------------
  // Unknown component
  // -------------------------------------------------------------------------

  describe('unknown', () => {
    it('returns unknown for unrecognized component type', () => {
      const comp = parseComponent({ component: 'magic-widget', foo: 'bar' })
      expect(comp.component).toBe('unknown')
      if (comp.component === 'unknown') {
        expect(comp.originalType).toBe('magic-widget')
      }
    })

    it('preserves originalType', () => {
      const comp = parseComponent({ component: 'custom-thing' })
      if (comp.component === 'unknown') {
        expect(comp.originalType).toBe('custom-thing')
      }
    })

    it('preserves rawJson', () => {
      const comp = parseComponent({ component: 'whatever', x: 1, y: 'two' })
      if (comp.component === 'unknown') {
        expect(comp.rawJson['x']).toBe(1)
        expect(comp.rawJson['y']).toBe('two')
      }
    })

    it('handles missing component type', () => {
      const comp = parseComponent({})
      expect(comp.component).toBe('unknown')
      if (comp.component === 'unknown') {
        expect(comp.originalType).toBe('unknown')
      }
    })
  })

  // -------------------------------------------------------------------------
  // Base fields: styleHint, visibleWhen, roles
  // -------------------------------------------------------------------------

  describe('base fields', () => {
    it('parses styleHint on text', () => {
      const comp = parseComponent({
        component: 'text',
        content: 'Hi',
        styleHint: { variant: 'headline' },
      })
      expect(comp.styleHint).toEqual({ variant: 'headline' })
    })

    it('defaults styleHint to empty object', () => {
      const comp = parseComponent({ component: 'text', content: 'Hi' })
      expect(comp.styleHint).toEqual({})
    })

    it('parses visibleWhen on list', () => {
      const comp = parseComponent({
        component: 'list',
        dataSource: 'ds',
        columns: [],
        visibleWhen: { field: 'status', equals: 'active' },
      })
      expect(comp.visibleWhen).toBeDefined()
    })

    it('parses roles on summary', () => {
      const comp = parseComponent({
        component: 'summary',
        label: 'Secret',
        value: '42',
        roles: ['admin', 'manager'],
      })
      expect(comp.roles).toEqual(['admin', 'manager'])
    })

    it('roles is undefined when missing', () => {
      const comp = parseComponent({ component: 'text', content: 'Public' })
      expect(comp.roles).toBeUndefined()
    })

    it('parses styleHint on form', () => {
      const comp = parseComponent({
        component: 'form',
        id: 'f1',
        fields: [],
        styleHint: { density: 'compact' },
      })
      expect(comp.styleHint).toEqual({ density: 'compact' })
    })

    it('parses roles on button', () => {
      const comp = parseComponent({
        component: 'button',
        label: 'Delete',
        onClick: [],
        roles: ['admin'],
      })
      expect(comp.roles).toEqual(['admin'])
    })

    it('parses roles on chart', () => {
      const comp = parseComponent({
        component: 'chart',
        dataSource: 'ds',
        labelField: 'x',
        valueField: 'y',
        roles: ['viewer'],
      })
      expect(comp.roles).toEqual(['viewer'])
    })

    it('parses roles on tabs', () => {
      const comp = parseComponent({
        component: 'tabs',
        tabs: [],
        roles: ['admin'],
      })
      expect(comp.roles).toEqual(['admin'])
    })

    it('parses roles on kanban', () => {
      const comp = parseComponent({
        component: 'kanban',
        dataSource: 'ds',
        statusField: 'status',
        cardFields: [],
        roles: ['manager'],
      })
      expect(comp.roles).toEqual(['manager'])
    })

    it('parses roles on detail', () => {
      const comp = parseComponent({
        component: 'detail',
        dataSource: 'ds',
        roles: ['admin'],
      })
      expect(comp.roles).toEqual(['admin'])
    })
  })
})

// ===========================================================================
// hideWhenMatches
// ===========================================================================

describe('hideWhenMatches', () => {
  it('returns true when equals matches', () => {
    const hw: OdsRowActionHideWhen = { field: 'status', equals: 'closed' }
    expect(hideWhenMatches(hw, { status: 'closed' })).toBe(true)
  })

  it('returns false when equals does not match', () => {
    const hw: OdsRowActionHideWhen = { field: 'status', equals: 'closed' }
    expect(hideWhenMatches(hw, { status: 'open' })).toBe(false)
  })

  it('returns true when notEquals does not match row value', () => {
    const hw: OdsRowActionHideWhen = { field: 'status', notEquals: 'active' }
    expect(hideWhenMatches(hw, { status: 'closed' })).toBe(true)
  })

  it('returns false when notEquals matches row value', () => {
    const hw: OdsRowActionHideWhen = { field: 'status', notEquals: 'active' }
    expect(hideWhenMatches(hw, { status: 'active' })).toBe(false)
  })

  it('returns false when no condition matches', () => {
    const hw: OdsRowActionHideWhen = { field: 'status' }
    expect(hideWhenMatches(hw, { status: 'anything' })).toBe(false)
  })

  it('treats missing field as empty string', () => {
    const hw: OdsRowActionHideWhen = { field: 'status', equals: '' }
    expect(hideWhenMatches(hw, {})).toBe(true)
  })

  it('treats missing field as not equal to a value', () => {
    const hw: OdsRowActionHideWhen = { field: 'status', equals: 'active' }
    expect(hideWhenMatches(hw, {})).toBe(false)
  })
})

import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { ListComponent } from '../../../src/renderer/components/ListComponent.tsx'
import type { OdsListComponent, OdsListColumn } from '../../../src/models/ods-component.ts'
import { useAppStore } from '../../../src/engine/app-store.ts'

function column(overrides?: Partial<OdsListColumn>): OdsListColumn {
  return {
    header: 'Name',
    field: 'name',
    sortable: false,
    filterable: false,
    currency: false,
    ...overrides,
  }
}

function listModel(overrides?: Partial<OdsListComponent>): OdsListComponent {
  return {
    component: 'list',
    dataSource: 'tasks',
    columns: [column()],
    rowActions: [],
    summary: [],
    searchable: false,
    displayAs: 'table',
    styleHint: {},
    ...overrides,
  }
}

const sampleRows = [
  { _id: '1', name: 'Task A', status: 'open' },
  { _id: '2', name: 'Task B', status: 'done' },
]

describe('ListComponent', () => {
  beforeEach(() => {
    useAppStore.setState({
      queryDataSource: vi.fn().mockResolvedValue(sampleRows),
      executeActions: vi.fn(),
      executeDeleteRowAction: vi.fn(),
      executeCopyRowsAction: vi.fn(),
      executeToggle: vi.fn(),
      populateFormAndNavigate: vi.fn(),
      navigateTo: vi.fn(),
      authService: null,
      isMultiUser: false,
      lastMessage: null,
      recordGeneration: 0,
      currentPageId: 'home',
      appSettings: {},
      app: null,
    } as never)
  })

  it('renders a loading indicator initially', () => {
    // queryDataSource returns a never-resolving promise to keep loading state
    useAppStore.setState({
      queryDataSource: vi.fn().mockReturnValue(new Promise(() => {})),
    } as never)
    render(<ListComponent model={listModel()} />)
    expect(screen.getByText('Loading...')).toBeTruthy()
  })

  it('renders rows after data loads', async () => {
    render(<ListComponent model={listModel()} />)
    await waitFor(() => {
      expect(screen.getByText('Task A')).toBeTruthy()
      expect(screen.getByText('Task B')).toBeTruthy()
    })
  })

  it('renders column headers', async () => {
    const model = listModel({
      columns: [
        column({ header: 'Name', field: 'name' }),
        column({ header: 'Status', field: 'status' }),
      ],
    })
    render(<ListComponent model={model} />)
    await waitFor(() => {
      expect(screen.getByText('Name')).toBeTruthy()
      expect(screen.getByText('Status')).toBeTruthy()
    })
  })

  it('shows empty state when no data', async () => {
    useAppStore.setState({
      queryDataSource: vi.fn().mockResolvedValue([]),
    } as never)
    render(<ListComponent model={listModel()} />)
    await waitFor(() => {
      expect(screen.getByText('No data yet')).toBeTruthy()
    })
  })

  it('renders row action buttons when rowActions are provided', async () => {
    const model = listModel({
      rowActions: [
        {
          label: 'Delete',
          action: 'delete',
          dataSource: 'tasks',
          matchField: '_id',
          values: {},
          resetValues: {},
        },
      ],
    })
    render(<ListComponent model={model} />)
    await waitFor(() => {
      const buttons = screen.getAllByText('Delete')
      expect(buttons.length).toBe(2) // one per row
    })
  })

  it('renders a search input when searchable is true', async () => {
    const model = listModel({ searchable: true })
    render(<ListComponent model={model} />)
    await waitFor(() => {
      expect(screen.getByPlaceholderText('Search...')).toBeTruthy()
    })
  })

  it('does not render a search input when searchable is false', async () => {
    render(<ListComponent model={listModel()} />)
    await waitFor(() => {
      expect(screen.getByText('Task A')).toBeTruthy()
    })
    expect(screen.queryByPlaceholderText('Search...')).toBeNull()
  })

  it('renders an Actions column header when row actions exist', async () => {
    const model = listModel({
      rowActions: [
        {
          label: 'Edit',
          action: 'update',
          dataSource: 'tasks',
          matchField: '_id',
          values: {},
          resetValues: {},
        },
      ],
    })
    render(<ListComponent model={model} />)
    await waitFor(() => {
      expect(screen.getByText('Actions')).toBeTruthy()
    })
  })
})

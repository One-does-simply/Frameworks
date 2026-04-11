import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { KanbanComponent } from '../../../src/renderer/components/KanbanComponent.tsx'
import type { OdsKanbanComponent } from '../../../src/models/ods-component.ts'
import { useAppStore } from '../../../src/engine/app-store.ts'

function kanbanModel(overrides?: Partial<OdsKanbanComponent>): OdsKanbanComponent {
  return {
    component: 'kanban',
    dataSource: 'tasks',
    statusField: 'status',
    cardFields: ['title', 'assignee'],
    rowActions: [],
    searchable: false,
    styleHint: {},
    ...overrides,
  }
}

/** Minimal app that provides status field options for the kanban board. */
const minimalApp = {
  appName: 'Test',
  startPage: 'home',
  startPageByRole: {},
  menu: [],
  pages: {
    home: { title: 'Home', content: [] },
  },
  dataSources: {
    tasks: {
      url: 'local://tasks',
      method: 'GET',
      fields: [
        { name: 'title', type: 'text', label: 'Title', required: false, options: [] },
        { name: 'assignee', type: 'text', label: 'Assignee', required: false, options: [] },
        { name: 'status', type: 'select', label: 'Status', required: false, options: ['todo', 'in-progress', 'done'] },
      ],
      ownership: { enabled: false, ownerField: '_owner', adminOverride: true },
    },
  },
  tour: [],
  settings: {},
  auth: { multiUser: false, selfRegistration: false, defaultRole: 'user', multiUserOnly: false },
  branding: { theme: 'indigo', mode: 'system', headerStyle: 'light' },
}

const sampleRows = [
  { _id: '1', title: 'Task A', assignee: 'Alice', status: 'todo' },
  { _id: '2', title: 'Task B', assignee: 'Bob', status: 'in-progress' },
  { _id: '3', title: 'Task C', assignee: 'Alice', status: 'done' },
]

describe('KanbanComponent', () => {
  beforeEach(() => {
    useAppStore.setState({
      app: minimalApp as any,
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
    } as never)
  })

  it('renders a loading indicator initially', () => {
    useAppStore.setState({
      queryDataSource: vi.fn().mockReturnValue(new Promise(() => {})),
    } as never)
    render(<KanbanComponent model={kanbanModel()} />)
    expect(screen.getByText('Loading...')).toBeTruthy()
  })

  it('renders kanban columns by status values', async () => {
    render(<KanbanComponent model={kanbanModel()} />)
    await waitFor(() => {
      expect(screen.getByText('todo')).toBeTruthy()
      expect(screen.getByText('in-progress')).toBeTruthy()
      expect(screen.getByText('done')).toBeTruthy()
    })
  })

  it('renders card content fields', async () => {
    render(<KanbanComponent model={kanbanModel()} />)
    await waitFor(() => {
      expect(screen.getByText('Task A')).toBeTruthy()
      expect(screen.getByText('Task B')).toBeTruthy()
      expect(screen.getByText('Task C')).toBeTruthy()
    })
  })

  it('shows empty columns when no data', async () => {
    useAppStore.setState({
      queryDataSource: vi.fn().mockResolvedValue([]),
    } as never)
    render(<KanbanComponent model={kanbanModel()} />)
    await waitFor(() => {
      // Columns should still render from options even with no data
      expect(screen.getByText('todo')).toBeTruthy()
      expect(screen.getByText('done')).toBeTruthy()
    })
  })

  it('renders a search input when searchable is true', async () => {
    const model = kanbanModel({ searchable: true })
    render(<KanbanComponent model={model} />)
    await waitFor(() => {
      expect(screen.getByPlaceholderText('Search cards...')).toBeTruthy()
    })
  })

  it('does not render a search input when searchable is false', async () => {
    render(<KanbanComponent model={kanbanModel()} />)
    await waitFor(() => {
      expect(screen.getByText('Task A')).toBeTruthy()
    })
    expect(screen.queryByPlaceholderText('Search cards...')).toBeNull()
  })

  it('shows error message when status field has no options', async () => {
    useAppStore.setState({
      app: {
        ...minimalApp,
        dataSources: {
          tasks: {
            ...minimalApp.dataSources.tasks,
            fields: [
              { name: 'status', type: 'text', label: 'Status', required: false, options: [] },
            ],
          },
        },
      } as any,
    } as never)
    render(<KanbanComponent model={kanbanModel()} />)
    await waitFor(() => {
      expect(screen.getByText(/no options found/i)).toBeTruthy()
    })
  })
})

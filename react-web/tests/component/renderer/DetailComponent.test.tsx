import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { DetailComponent } from '../../../src/renderer/components/DetailComponent.tsx'
import type { OdsDetailComponent } from '../../../src/models/ods-component.ts'
import { useAppStore } from '../../../src/engine/app-store.ts'

function detailModel(overrides?: Partial<OdsDetailComponent>): OdsDetailComponent {
  return {
    component: 'detail',
    dataSource: 'items',
    styleHint: {},
    ...overrides,
  }
}

const sampleRow = { _id: '1', title: 'My Item', status: 'active', _createdAt: '2026-01-01' }

describe('DetailComponent', () => {
  beforeEach(() => {
    useAppStore.setState({
      queryDataSource: vi.fn().mockResolvedValue([sampleRow]),
      getFormState: vi.fn().mockReturnValue({}),
      formStates: {},
      recordGeneration: 0,
    } as never)
  })

  it('shows a loading state initially', () => {
    useAppStore.setState({
      queryDataSource: vi.fn().mockReturnValue(new Promise(() => {})),
    } as never)
    render(<DetailComponent model={detailModel()} />)
    expect(screen.getByText('Loading...')).toBeTruthy()
  })

  it('renders field values from the data source', async () => {
    render(<DetailComponent model={detailModel()} />)
    await waitFor(() => {
      expect(screen.getByText('My Item')).toBeTruthy()
      expect(screen.getByText('active')).toBeTruthy()
    })
  })

  it('hides internal fields (prefixed with _) by default', async () => {
    render(<DetailComponent model={detailModel()} />)
    await waitFor(() => {
      expect(screen.getByText('My Item')).toBeTruthy()
    })
    // Internal fields should not appear
    expect(screen.queryByText('1')).toBeNull()
  })

  it('shows only specified fields when fields array is provided', async () => {
    const model = detailModel({ fields: ['title'] })
    render(<DetailComponent model={model} />)
    await waitFor(() => {
      expect(screen.getByText('My Item')).toBeTruthy()
    })
    // 'status' should not appear since it is not in the fields list
    expect(screen.queryByText('active')).toBeNull()
  })

  it('uses custom labels when provided', async () => {
    const model = detailModel({
      fields: ['title'],
      labels: { title: 'Item Name' },
    })
    render(<DetailComponent model={model} />)
    await waitFor(() => {
      expect(screen.getByText('Item Name')).toBeTruthy()
    })
  })

  it('shows "No data available" when data source returns empty', async () => {
    useAppStore.setState({
      queryDataSource: vi.fn().mockResolvedValue([]),
    } as never)
    render(<DetailComponent model={detailModel()} />)
    await waitFor(() => {
      expect(screen.getByText('No data available')).toBeTruthy()
    })
  })

  it('reads from form state when fromForm is specified', async () => {
    useAppStore.setState({
      getFormState: vi.fn().mockReturnValue({ name: 'Alice', role: 'Admin' }),
    } as never)
    const model = detailModel({ fromForm: 'userForm', fields: ['name', 'role'] })
    render(<DetailComponent model={model} />)
    await waitFor(() => {
      expect(screen.getByText('Alice')).toBeTruthy()
      expect(screen.getByText('Admin')).toBeTruthy()
    })
  })

  it('humanizes camelCase field names as labels', async () => {
    useAppStore.setState({
      queryDataSource: vi.fn().mockResolvedValue([{ firstName: 'Bob' }]),
    } as never)
    const model = detailModel({ fields: ['firstName'] })
    render(<DetailComponent model={model} />)
    await waitFor(() => {
      expect(screen.getByText('First Name')).toBeTruthy()
    })
  })
})

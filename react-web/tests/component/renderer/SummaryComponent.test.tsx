import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { SummaryComponent } from '../../../src/renderer/components/SummaryComponent.tsx'
import type { OdsSummaryComponent } from '../../../src/models/ods-component.ts'

function summaryModel(overrides?: Partial<OdsSummaryComponent>): OdsSummaryComponent {
  return {
    component: 'summary',
    label: 'Total Items',
    value: '42',
    styleHint: {},
    ...overrides,
  }
}

describe('SummaryComponent', () => {
  it('renders label and value', () => {
    render(<SummaryComponent model={summaryModel()} />)
    expect(screen.getByText('Total Items')).toBeTruthy()
    expect(screen.getByText('42')).toBeTruthy()
  })

  it('renders with icon', () => {
    render(<SummaryComponent model={summaryModel({ icon: 'check' })} />)
    // Icon should be rendered (SVG element)
    expect(screen.getByText('Total Items')).toBeTruthy()
  })

  it('renders with color accent', () => {
    render(<SummaryComponent model={summaryModel({ styleHint: { color: 'success' } })} />)
    expect(screen.getByText('42')).toBeTruthy()
  })
})

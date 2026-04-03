import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { TabsComponent } from '../../../src/renderer/components/TabsComponent.tsx'
import type { OdsTabsComponent, OdsComponent } from '../../../src/models/ods-component.ts'

function tabsModel(overrides?: Partial<OdsTabsComponent>): OdsTabsComponent {
  return {
    component: 'tabs',
    tabs: [
      {
        label: 'Tab One',
        content: [
          { component: 'text', content: 'Content of tab one', format: 'plain', styleHint: {} } as OdsComponent,
        ],
      },
      {
        label: 'Tab Two',
        content: [
          { component: 'text', content: 'Content of tab two', format: 'plain', styleHint: {} } as OdsComponent,
        ],
      },
    ],
    styleHint: {},
    ...overrides,
  }
}

const mockRenderComponent = vi.fn((component: OdsComponent, index: number) => {
  if (component.component === 'text') {
    return <p key={index}>{(component as { content: string }).content}</p>
  }
  return <div key={index}>unknown</div>
})

describe('TabsComponent', () => {
  it('renders tab labels', () => {
    render(<TabsComponent model={tabsModel()} renderComponent={mockRenderComponent} />)
    expect(screen.getByText('Tab One')).toBeTruthy()
    expect(screen.getByText('Tab Two')).toBeTruthy()
  })

  it('renders the first tab content by default', () => {
    render(<TabsComponent model={tabsModel()} renderComponent={mockRenderComponent} />)
    expect(screen.getByText('Content of tab one')).toBeTruthy()
  })

  it('switches tab content when a tab is clicked', async () => {
    const user = userEvent.setup()
    render(<TabsComponent model={tabsModel()} renderComponent={mockRenderComponent} />)

    await user.click(screen.getByText('Tab Two'))
    expect(screen.getByText('Content of tab two')).toBeTruthy()
  })

  it('returns null when tabs array is empty', () => {
    const model = tabsModel({ tabs: [] })
    const { container } = render(<TabsComponent model={model} renderComponent={mockRenderComponent} />)
    expect(container.innerHTML).toBe('')
  })

  it('calls renderComponent for each content item', () => {
    mockRenderComponent.mockClear()
    render(<TabsComponent model={tabsModel()} renderComponent={mockRenderComponent} />)
    // Both tabs' content arrays are rendered (2 tabs x 1 component each)
    expect(mockRenderComponent).toHaveBeenCalledTimes(2)
  })

  it('renders three or more tabs', () => {
    const model = tabsModel({
      tabs: [
        { label: 'A', content: [] },
        { label: 'B', content: [] },
        { label: 'C', content: [] },
      ],
    })
    render(<TabsComponent model={model} renderComponent={mockRenderComponent} />)
    expect(screen.getByText('A')).toBeTruthy()
    expect(screen.getByText('B')).toBeTruthy()
    expect(screen.getByText('C')).toBeTruthy()
  })
})

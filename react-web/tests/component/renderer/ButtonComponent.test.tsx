import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ButtonComponent } from '../../../src/renderer/components/ButtonComponent.tsx'
import type { OdsButtonComponent } from '../../../src/models/ods-component.ts'
import { useAppStore } from '../../../src/engine/app-store.ts'

function buttonModel(overrides?: Partial<OdsButtonComponent>): OdsButtonComponent {
  return {
    component: 'button',
    label: 'Click Me',
    onClick: [{ action: 'navigate', target: 'page2', computedFields: [], preserveFields: [] }],
    styleHint: {},
    ...overrides,
  }
}

describe('ButtonComponent', () => {
  it('renders the button label', () => {
    render(<ButtonComponent model={buttonModel()} />)
    expect(screen.getByText('Click Me')).toBeTruthy()
  })

  it('renders with primary emphasis as default variant', () => {
    render(<ButtonComponent model={buttonModel({ styleHint: { emphasis: 'primary' } })} />)
    const btn = screen.getByRole('button')
    expect(btn).toBeTruthy()
  })

  it('renders with danger emphasis', () => {
    render(<ButtonComponent model={buttonModel({ styleHint: { emphasis: 'danger' } })} />)
    const btn = screen.getByRole('button')
    expect(btn.className).toContain('destructive')
  })

  it('renders with secondary emphasis as outline', () => {
    render(<ButtonComponent model={buttonModel({ styleHint: { emphasis: 'secondary' } })} />)
    const btn = screen.getByRole('button')
    expect(btn.className).toContain('outline')
  })

  it('calls executeActions on click', async () => {
    const spy = vi.fn()
    useAppStore.setState({ executeActions: spy } as never)

    const user = userEvent.setup()
    render(<ButtonComponent model={buttonModel()} />)
    await user.click(screen.getByRole('button'))

    expect(spy).toHaveBeenCalledTimes(1)
  })
})

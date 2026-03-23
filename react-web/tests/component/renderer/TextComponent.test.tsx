import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { TextComponent } from '../../../src/renderer/components/TextComponent.tsx'
import type { OdsTextComponent } from '../../../src/models/ods-component.ts'

function textModel(overrides?: Partial<OdsTextComponent>): OdsTextComponent {
  return {
    component: 'text',
    content: 'Hello World',
    format: 'plain',
    styleHint: {},
    ...overrides,
  }
}

describe('TextComponent', () => {
  it('renders plain text content', () => {
    render(<TextComponent model={textModel()} />)
    expect(screen.getByText('Hello World')).toBeTruthy()
  })

  it('renders heading variant as h2', () => {
    render(<TextComponent model={textModel({ styleHint: { variant: 'heading' } })} />)
    const el = screen.getByText('Hello World')
    expect(el.tagName).toBe('H2')
  })

  it('renders subheading variant as h3', () => {
    render(<TextComponent model={textModel({ styleHint: { variant: 'subheading' } })} />)
    const el = screen.getByText('Hello World')
    expect(el.tagName).toBe('H3')
  })

  it('renders caption variant as small', () => {
    render(<TextComponent model={textModel({ styleHint: { variant: 'caption' } })} />)
    const el = screen.getByText('Hello World')
    expect(el.tagName).toBe('SMALL')
  })

  it('renders body variant as p (default)', () => {
    render(<TextComponent model={textModel()} />)
    const el = screen.getByText('Hello World')
    expect(el.tagName).toBe('P')
  })

  it('applies center alignment', () => {
    const { container } = render(<TextComponent model={textModel({ styleHint: { align: 'center' } })} />)
    // The alignment class may be on the element itself or a parent wrapper
    const hasCenter = container.innerHTML.includes('text-center')
    expect(hasCenter).toBe(true)
  })

  it('renders markdown when format is markdown', () => {
    render(<TextComponent model={textModel({ content: '**Bold text**', format: 'markdown' })} />)
    expect(screen.getByText('Bold text')).toBeTruthy()
  })
})

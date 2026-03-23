import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { PageRenderer } from '../../../src/renderer/PageRenderer.tsx'
import type { OdsPage } from '../../../src/models/ods-page.ts'

function page(content: unknown[]): OdsPage {
  return {
    title: 'Test Page',
    content: content.map(c => c as OdsPage['content'][0]),
  }
}

describe('PageRenderer', () => {
  it('renders text components', () => {
    render(
      <PageRenderer
        page={page([
          { component: 'text', content: 'Hello World', format: 'plain', styleHint: {} },
        ])}
      />
    )
    expect(screen.getByText('Hello World')).toBeTruthy()
  })

  it('renders multiple components', () => {
    render(
      <PageRenderer
        page={page([
          { component: 'text', content: 'First', format: 'plain', styleHint: {} },
          { component: 'text', content: 'Second', format: 'plain', styleHint: {} },
        ])}
      />
    )
    expect(screen.getByText('First')).toBeTruthy()
    expect(screen.getByText('Second')).toBeTruthy()
  })

  it('renders button components', () => {
    render(
      <PageRenderer
        page={page([
          {
            component: 'button',
            label: 'Click Me',
            onClick: [{ action: 'navigate', target: 'p', computedFields: [], preserveFields: [] }],
            styleHint: {},
          },
        ])}
      />
    )
    expect(screen.getByText('Click Me')).toBeTruthy()
  })

  it('renders summary components', () => {
    render(
      <PageRenderer
        page={page([
          { component: 'summary', label: 'Total', value: '99', styleHint: {} },
        ])}
      />
    )
    expect(screen.getByText('Total')).toBeTruthy()
    expect(screen.getByText('99')).toBeTruthy()
  })

  it('skips unknown components in normal mode', () => {
    render(
      <PageRenderer
        page={page([
          { component: 'unknown', originalType: 'magic', rawJson: {}, styleHint: {} },
          { component: 'text', content: 'Visible', format: 'plain', styleHint: {} },
        ])}
      />
    )
    expect(screen.getByText('Visible')).toBeTruthy()
    expect(screen.queryByText('magic')).toBeNull()
  })

  it('renders empty page without error', () => {
    const { container } = render(<PageRenderer page={page([])} />)
    expect(container).toBeTruthy()
  })
})

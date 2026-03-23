import { render, type RenderOptions } from '@testing-library/react'
import type { ReactElement } from 'react'

/**
 * Custom render wrapper for ODS component tests.
 * Can be extended to provide Zustand store context, router, etc.
 */
export function renderOds(ui: ReactElement, options?: RenderOptions) {
  return render(ui, { ...options })
}

/** Builds a minimal ODS app JSON string for testing. */
export function minimalAppJson(overrides?: Record<string, unknown>): string {
  return JSON.stringify({
    appName: 'Test',
    startPage: 'home',
    pages: {
      home: { component: 'page', title: 'Home', content: [] },
    },
    ...overrides,
  })
}

import { describe, it, expect } from 'vitest'
import { parseHelp, parseTourStep } from '../../../src/models/ods-help.ts'

// ===========================================================================
// OdsHelp model tests
// ===========================================================================

describe('parseHelp', () => {
  // -------------------------------------------------------------------------
  // Null / missing / invalid input
  // -------------------------------------------------------------------------

  it('returns undefined for null', () => {
    expect(parseHelp(null)).toBeUndefined()
  })

  it('returns undefined for undefined', () => {
    expect(parseHelp(undefined)).toBeUndefined()
  })

  it('returns undefined for non-object', () => {
    expect(parseHelp('not-an-object')).toBeUndefined()
  })

  // -------------------------------------------------------------------------
  // Valid help objects
  // -------------------------------------------------------------------------

  it('parses valid help with overview and pages', () => {
    const help = parseHelp({
      overview: 'Welcome to the app.',
      pages: { home: 'Home page help', settings: 'Settings help' },
    })
    expect(help).toBeDefined()
    expect(help!.overview).toBe('Welcome to the app.')
    expect(help!.pages).toEqual({ home: 'Home page help', settings: 'Settings help' })
  })

  it('defaults pages to empty object when missing', () => {
    const help = parseHelp({ overview: 'Some overview' })
    expect(help).toBeDefined()
    expect(help!.pages).toEqual({})
  })
})

// ===========================================================================
// OdsTourStep model tests
// ===========================================================================

describe('parseTourStep', () => {
  it('parses all fields', () => {
    const step = parseTourStep({
      title: 'Step 1',
      content: 'Click the button.',
      page: 'home',
    })
    expect(step.title).toBe('Step 1')
    expect(step.content).toBe('Click the button.')
    expect(step.page).toBe('home')
  })

  it('page is undefined when missing', () => {
    const step = parseTourStep({
      title: 'Step 2',
      content: 'Enter your name.',
    })
    expect(step.title).toBe('Step 2')
    expect(step.content).toBe('Enter your name.')
    expect(step.page).toBeUndefined()
  })
})

import { describe, it, expect } from 'vitest'
import { parseAppSetting } from '../../../src/models/ods-app-setting.ts'

// ===========================================================================
// OdsAppSetting model tests
// ===========================================================================

describe('parseAppSetting', () => {
  // -------------------------------------------------------------------------
  // Full valid setting
  // -------------------------------------------------------------------------

  it('parses a full valid setting', () => {
    const setting = parseAppSetting({
      label: 'Language',
      type: 'select',
      default: 'en',
      options: ['en', 'fr', 'de'],
    })
    expect(setting.label).toBe('Language')
    expect(setting.type).toBe('select')
    expect(setting.defaultValue).toBe('en')
    expect(setting.options).toEqual(['en', 'fr', 'de'])
  })

  // -------------------------------------------------------------------------
  // Default values
  // -------------------------------------------------------------------------

  it('default label is empty string', () => {
    const setting = parseAppSetting({})
    expect(setting.label).toBe('')
  })

  it('default type is text', () => {
    const setting = parseAppSetting({})
    expect(setting.type).toBe('text')
  })

  it('default defaultValue is empty string', () => {
    const setting = parseAppSetting({})
    expect(setting.defaultValue).toBe('')
  })

  // -------------------------------------------------------------------------
  // Options handling
  // -------------------------------------------------------------------------

  it('options as array', () => {
    const setting = parseAppSetting({ options: ['a', 'b', 'c'] })
    expect(setting.options).toEqual(['a', 'b', 'c'])
  })

  it('options as comma-separated string', () => {
    const setting = parseAppSetting({ options: 'red, green, blue' })
    expect(setting.options).toEqual(['red', 'green', 'blue'])
  })

  it('options missing returns undefined', () => {
    const setting = parseAppSetting({ label: 'Name' })
    expect(setting.options).toBeUndefined()
  })
})

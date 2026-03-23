import { describe, it, expect } from 'vitest'
import {
  validateField,
  type OdsValidation,
  type OdsFieldDefinition,
  parseFieldDefinition,
  isComputed,
} from '../../../src/models/ods-field.ts'

// ===========================================================================
// Main validation tests (ported from validation_test.dart)
// ===========================================================================

describe('OdsValidation', () => {
  describe('Email validation', () => {
    const v: OdsValidation = {}

    it('valid email passes', () => {
      expect(validateField(v, 'user@example.com', 'email')).toBeUndefined()
    })

    it('missing @ fails', () => {
      expect(validateField(v, 'userexample.com', 'email')).toBeDefined()
    })

    it('missing domain fails', () => {
      expect(validateField(v, 'user@', 'email')).toBeDefined()
    })

    it('empty string skipped (required handles that)', () => {
      expect(validateField(v, '', 'email')).toBeUndefined()
    })
  })

  describe('minLength validation', () => {
    const v: OdsValidation = { minLength: 5 }

    it('long enough passes', () => {
      expect(validateField(v, 'hello', 'text')).toBeUndefined()
    })

    it('too short fails', () => {
      expect(validateField(v, 'hi', 'text')).toBeDefined()
    })

    it('empty string skipped', () => {
      expect(validateField(v, '', 'text')).toBeUndefined()
    })
  })

  describe('Pattern validation', () => {
    const v: OdsValidation = { pattern: String.raw`^\d{3}-\d{4}$` }

    it('matching pattern passes', () => {
      expect(validateField(v, '123-4567', 'text')).toBeUndefined()
    })

    it('non-matching pattern fails', () => {
      expect(validateField(v, '1234567', 'text')).toBeDefined()
    })
  })

  describe('Number min/max validation', () => {
    const v: OdsValidation = { min: 1, max: 100 }

    it('in range passes', () => {
      expect(validateField(v, '50', 'number')).toBeUndefined()
    })

    it('at min passes', () => {
      expect(validateField(v, '1', 'number')).toBeUndefined()
    })

    it('at max passes', () => {
      expect(validateField(v, '100', 'number')).toBeUndefined()
    })

    it('below min fails', () => {
      expect(validateField(v, '0', 'number')).toBeDefined()
    })

    it('above max fails', () => {
      expect(validateField(v, '101', 'number')).toBeDefined()
    })

    it('non-number ignored', () => {
      expect(validateField(v, 'abc', 'number')).toBeUndefined()
    })

    it('min/max ignored for non-number fields', () => {
      expect(validateField(v, '0', 'text')).toBeUndefined()
    })
  })

  describe('Custom message', () => {
    it('uses custom message when provided', () => {
      const v: OdsValidation = { minLength: 10, message: 'Too short!' }
      expect(validateField(v, 'hi', 'text')).toBe('Too short!')
    })
  })
})

// ===========================================================================
// Edge case tests (ported from validation_edge_test.dart)
// ===========================================================================

describe('OdsValidation edge cases', () => {
  describe('Email edge cases', () => {
    const v: OdsValidation = {}

    it('email with subdomain passes', () => {
      expect(validateField(v, 'user@mail.example.com', 'email')).toBeUndefined()
    })

    it('email with + passes', () => {
      expect(validateField(v, 'user+tag@example.com', 'email')).toBeUndefined()
    })

    it('email with spaces fails', () => {
      expect(validateField(v, 'user @example.com', 'email')).toBeDefined()
    })

    it('email with no TLD fails', () => {
      expect(validateField(v, 'user@localhost', 'email')).toBeDefined()
    })

    it('email validation only applies to email type', () => {
      expect(validateField(v, 'not-an-email', 'text')).toBeUndefined()
    })
  })

  describe('Min/Max edge cases', () => {
    it('decimal min boundary', () => {
      const v: OdsValidation = { min: 0.5 }
      expect(validateField(v, '0.5', 'number')).toBeUndefined()
      expect(validateField(v, '0.4', 'number')).toBeDefined()
    })

    it('negative min', () => {
      const v: OdsValidation = { min: -10, max: 10 }
      expect(validateField(v, '-10', 'number')).toBeUndefined()
      expect(validateField(v, '-11', 'number')).toBeDefined()
      expect(validateField(v, '0', 'number')).toBeUndefined()
    })

    it('min only (no max)', () => {
      const v: OdsValidation = { min: 0 }
      expect(validateField(v, '0', 'number')).toBeUndefined()
      expect(validateField(v, '-1', 'number')).toBeDefined()
      expect(validateField(v, '999999', 'number')).toBeUndefined()
    })

    it('max only (no min)', () => {
      const v: OdsValidation = { max: 100 }
      expect(validateField(v, '100', 'number')).toBeUndefined()
      expect(validateField(v, '101', 'number')).toBeDefined()
      expect(validateField(v, '-999', 'number')).toBeUndefined()
    })
  })

  describe('MinLength edge cases', () => {
    it('exact minLength passes', () => {
      const v: OdsValidation = { minLength: 3 }
      expect(validateField(v, 'abc', 'text')).toBeUndefined()
    })

    it('one below minLength fails', () => {
      const v: OdsValidation = { minLength: 3 }
      expect(validateField(v, 'ab', 'text')).toBeDefined()
    })

    it('minLength 1', () => {
      const v: OdsValidation = { minLength: 1 }
      expect(validateField(v, 'x', 'text')).toBeUndefined()
    })
  })

  describe('Pattern edge cases', () => {
    it('phone number pattern', () => {
      const v: OdsValidation = { pattern: String.raw`^\d{3}-\d{3}-\d{4}$` }
      expect(validateField(v, '123-456-7890', 'text')).toBeUndefined()
      expect(validateField(v, '1234567890', 'text')).toBeDefined()
    })

    it('case-sensitive pattern', () => {
      const v: OdsValidation = { pattern: String.raw`^[A-Z]+$` }
      expect(validateField(v, 'HELLO', 'text')).toBeUndefined()
      expect(validateField(v, 'hello', 'text')).toBeDefined()
    })

    it('pattern with special characters', () => {
      const v: OdsValidation = { pattern: String.raw`^https?://` }
      expect(validateField(v, 'https://example.com', 'text')).toBeUndefined()
      expect(validateField(v, 'http://test.com', 'text')).toBeUndefined()
      expect(validateField(v, 'ftp://nope.com', 'text')).toBeDefined()
    })
  })

  describe('Multiple rules combined', () => {
    it('minLength + pattern both checked', () => {
      const v: OdsValidation = { minLength: 3, pattern: String.raw`^\d+$` }
      // Too short
      expect(validateField(v, '12', 'text')).toBeDefined()
      // Long enough but wrong pattern
      expect(validateField(v, 'abc', 'text')).toBeDefined()
      // Both pass
      expect(validateField(v, '123', 'text')).toBeUndefined()
    })

    it('min + max + pattern on number', () => {
      const v: OdsValidation = { min: 1, max: 100, pattern: String.raw`^\d+$` }
      expect(validateField(v, '50', 'number')).toBeUndefined()
      expect(validateField(v, '0', 'number')).toBeDefined()
    })
  })

  describe('Custom messages', () => {
    it('custom message on email validation', () => {
      const v: OdsValidation = { message: 'Bad email!' }
      expect(validateField(v, 'nope', 'email')).toBe('Bad email!')
    })

    it('custom message on min validation', () => {
      const v: OdsValidation = { min: 10, message: 'Too low!' }
      expect(validateField(v, '5', 'number')).toBe('Too low!')
    })

    it('custom message on pattern', () => {
      const v: OdsValidation = { pattern: String.raw`^[A-Z]`, message: 'Must start with uppercase' }
      expect(validateField(v, 'hello', 'text')).toBe('Must start with uppercase')
    })
  })
})

// ===========================================================================
// OdsFieldDefinition tests (ported from validation_edge_test.dart)
// ===========================================================================

describe('OdsFieldDefinition', () => {
  it('fromJson roundtrip', () => {
    const json = {
      name: 'email',
      type: 'email',
      label: 'Email Address',
      required: true,
      placeholder: 'you@example.com',
      validation: { pattern: String.raw`^[^@]+@[^@]+$`, message: 'Invalid' },
    }
    const field = parseFieldDefinition(json)
    expect(field.name).toBe('email')
    expect(field.type).toBe('email')
    expect(field.label).toBe('Email Address')
    expect(field.required).toBe(true)
    expect(field.validation).toBeDefined()
  })

  it('isComputed flag', () => {
    const field = parseFieldDefinition({
      name: 'total',
      type: 'number',
      formula: '{qty} * {price}',
    })
    expect(isComputed(field)).toBe(true)
  })

  it('non-computed field', () => {
    const field = parseFieldDefinition({ name: 'name', type: 'text' })
    expect(isComputed(field)).toBe(false)
  })
})

import { parseApp, type OdsApp } from '../models/ods-app.ts'
import { validate, ValidationResult } from './spec-validator.ts'

/** The result of parsing an ODS spec JSON string. */
export interface ParseResult {
  app: OdsApp | null
  validation: ValidationResult
  parseError: string | null
}

/** True when the spec parsed successfully with no validation errors. */
export function isOk(result: ParseResult): boolean {
  return result.app != null && !result.validation.hasErrors
}

/** Parses a raw JSON string into an OdsApp model with validation. */
export function parseSpec(jsonString: string): ParseResult {
  const validation = new ValidationResult()

  // Phase 1: Decode JSON and check required top-level fields.
  let json: Record<string, unknown>
  try {
    const parsed = JSON.parse(jsonString)
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
      return { app: null, validation, parseError: 'Invalid JSON: expected an object' }
    }
    json = parsed as Record<string, unknown>
  } catch (e) {
    return { app: null, validation, parseError: `Invalid JSON: ${e}` }
  }

  if (!('appName' in json)) {
    validation.error('Missing required field: appName')
  }
  if (!('startPage' in json)) {
    validation.error('Missing required field: startPage')
  }
  if (!('pages' in json)) {
    validation.error('Missing required field: pages')
  }

  // Bail early if required fields are missing.
  if (validation.hasErrors) {
    return { app: null, validation, parseError: null }
  }

  // Phase 2: Construct the model tree from JSON.
  let app: OdsApp
  try {
    app = parseApp(json)
  } catch (e) {
    return { app: null, validation, parseError: `Failed to parse spec: ${e}` }
  }

  // Phase 3: Semantic validation of cross-references.
  const fullValidation = validate(app)
  return { app, validation: fullValidation, parseError: null }
}

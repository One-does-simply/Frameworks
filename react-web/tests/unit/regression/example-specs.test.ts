import { describe, it, expect } from 'vitest'
import fs from 'fs'
import path from 'path'
import { parseSpec, isOk } from '../../../src/parser/spec-parser.ts'

/// Regression test: every example spec in the Specification repo must parse
/// successfully with no validation errors.
/// Ported from flutter-local/test/regression/example_specs_test.dart.

const examplesDir = path.resolve(__dirname, '../../../../../Specification/Examples')

// Files that are not app specs (e.g., catalog/index files).
const SKIP_FILES = new Set(['catalog.json'])

function getSpecFiles(): string[] {
  if (!fs.existsSync(examplesDir)) {
    return []
  }
  return fs
    .readdirSync(examplesDir)
    .filter((f) => f.endsWith('.json') && !SKIP_FILES.has(f))
    .sort()
}

const specFiles = getSpecFiles()

if (specFiles.length === 0) {
  describe('Example specs (SKIPPED)', () => {
    it('SKIP: Specification/Examples not found', () => {
      // Not a failure — the Specification repo may not be adjacent in CI.
    })
  })
} else {
  describe('Example specs parse without errors', () => {
    for (const fileName of specFiles) {
      it(fileName, () => {
        const filePath = path.join(examplesDir, fileName)
        const json = fs.readFileSync(filePath, 'utf-8')
        const result = parseSpec(json)

        // Must parse successfully.
        expect(result.parseError, `Parse error in ${fileName}: ${result.parseError}`).toBeNull()

        // Must have no validation errors (warnings are OK).
        expect(
          result.validation.hasErrors,
          `Validation errors in ${fileName}: ${result.validation.errors.map((e) => e.message).join(', ')}`,
        ).toBe(false)

        // Must produce a valid app model.
        expect(result.app, `${fileName} produced null app`).not.toBeNull()
        expect(result.app!.appName, `${fileName} has empty appName`).toBeTruthy()
        expect(Object.keys(result.app!.pages).length, `${fileName} has no pages`).toBeGreaterThan(0)
      })
    }
  })

  describe('Example spec structure checks', () => {
    for (const fileName of specFiles) {
      it(`${fileName}: startPage exists in pages`, () => {
        const filePath = path.join(examplesDir, fileName)
        const json = fs.readFileSync(filePath, 'utf-8')
        const result = parseSpec(json)
        if (result.app == null) return // Covered by parse test above.

        expect(
          result.app.startPage in result.app.pages,
          `${fileName}: startPage "${result.app.startPage}" not found in pages`,
        ).toBe(true)
      })
    }
  })
}

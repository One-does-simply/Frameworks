/**
 * Evaluates expressions for computed fields on submit/update actions.
 *
 * Extends the concept in formula-evaluator with additional capabilities:
 *   - Ternary comparison: `{a} == {b} ? 'yes' : 'no'`
 *   - Magic values: `NOW` (current ISO datetime)
 *   - Math expressions: delegated to evaluateFormula
 *   - String interpolation: `{firstName} {lastName}`
 */

import { evaluateFormula } from './formula-evaluator.ts';

const FIELD_PATTERN = /\{(\w+)\}/g;

/**
 * Pattern for ternary comparison expressions.
 * Matches: `<left> == <right> ? '<trueVal>' : '<falseVal>'`
 */
const TERNARY_PATTERN = /^(\S+)\s*==\s*(\S+)\s*\?\s*'([^']*)'\s*:\s*'([^']*)'\s*$/;

/**
 * Evaluates an expression given the current form field values.
 *
 * Resolves `{fieldName}` references from values, then attempts (in order):
 *   1. Magic value `NOW` -> current ISO datetime
 *   2. Ternary comparison -> `left == right ? 'a' : 'b'`
 *   3. Numeric math -> delegated to evaluateFormula
 *   4. String interpolation -> returns the substituted string as-is
 *
 * Returns the computed string value, or the raw substituted string on failure.
 */
export function evaluateExpression(
  expression: string,
  values: Record<string, string>,
): string {
  // Magic value: NOW -> current ISO datetime.
  if (expression.trim().toUpperCase() === 'NOW') {
    return new Date().toISOString();
  }

  // Substitute field references first.
  const substituted = expression.replace(
    new RegExp(FIELD_PATTERN.source, 'g'),
    (_, fieldName: string) => values[fieldName] ?? '',
  );

  // Check for ternary comparison pattern.
  const ternaryMatch = TERNARY_PATTERN.exec(substituted);
  if (ternaryMatch !== null) {
    const left = ternaryMatch[1].trim();
    const right = ternaryMatch[2].trim();
    const trueVal = ternaryMatch[3];
    const falseVal = ternaryMatch[4];
    return left === right ? trueVal : falseVal;
  }

  // Try math evaluation if it looks numeric. Pass the *substituted* string
  // so evaluateFormula sees concrete numbers, not `{field}` placeholders.
  if (looksNumeric(substituted)) {
    try {
      // evaluateFormula expects {field} refs + values map, but since we
      // already substituted, pass the substituted string with an empty
      // values map so it parses the literal numbers directly.
      return evaluateFormula(substituted, 'number', {});
    } catch {
      // Fall through to string interpolation.
    }
  }

  // Default: return the substituted string (string interpolation).
  return substituted;
}

/**
 * Evaluates an expression and returns a boolean result.
 *
 * Used for expression-based visibility (`visible` property on components).
 * Supports:
 *   - `{field} == 'value'` -> equality check
 *   - `{field} != 'value'` -> inequality check
 *   - `{field}` -> truthy check (non-empty, not "false", not "0")
 *   - `!{field}` -> negated truthy check
 */
export function evaluateBool(
  expression: string,
  values: Record<string, string>,
): boolean {
  const expr = expression.trim();
  if (expr === '') return true;

  // Substitute field references.
  const substituted = expr.replace(
    new RegExp(FIELD_PATTERN.source, 'g'),
    (_, fieldName: string) => values[fieldName] ?? '',
  );

  // Equality: left == 'value' or left == right
  const eqMatch = /^([^=!]+?)\s*==\s*'?([^']*)'?\s*$/.exec(substituted);
  if (eqMatch !== null) {
    return eqMatch[1].trim() === eqMatch[2].trim();
  }

  // Inequality: left != 'value' or left != right
  const neqMatch = /^([^=!]+?)\s*!=\s*'?([^']*)'?\s*$/.exec(substituted);
  if (neqMatch !== null) {
    return neqMatch[1].trim() !== neqMatch[2].trim();
  }

  // Negation: !value
  if (substituted.startsWith('!')) {
    return !isTruthy(substituted.substring(1).trim());
  }

  // Truthy check.
  return isTruthy(substituted);
}

/** Returns true if a value is truthy (non-empty, not "false", not "0"). */
function isTruthy(value: string): boolean {
  if (value === '') return false;
  if (value === 'false') return false;
  if (value === '0') return false;
  return true;
}

/** Quick heuristic: does the string look like a math expression? */
function looksNumeric(s: string): boolean {
  const trimmed = s.trim();
  if (trimmed === '') return false;
  // Contains at least one digit and only math-related characters.
  return /^[\d\s+\-*/().]+$/.test(trimmed);
}

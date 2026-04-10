/**
 * JSON-e subset engine for ODS templates.
 *
 * Implements the JSON-e operators needed for Quick Build templates:
 *   - `${expr}` string interpolation — replaces variable references in strings
 *   - `$if`/`then`/`else` — conditionally includes or omits values
 *   - `$map`/`each(v)` — iterates an array to produce a list of values
 *   - `$eval` — evaluates an expression and returns the raw value
 *   - `$flatten` — flattens nested arrays one level
 *
 * Templates are valid JSON-e. Frameworks with a full JSON-e library can skip
 * this engine entirely. This subset covers the operators used by ODS templates
 * while keeping the implementation small and dependency-free.
 */

// Sentinel value for removed elements (from failed $if with no else).
const REMOVED = Symbol('removed')

type Context = Record<string, unknown>

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/** Renders a JSON-e template with the given context. */
export function render(template: unknown, context: Context): unknown {
  if (typeof template === 'string') {
    return interpolateString(template, context)
  }
  if (Array.isArray(template)) {
    return template
      .map((item) => render(item, context))
      .filter((item) => item !== REMOVED)
  }
  if (template !== null && typeof template === 'object') {
    return renderObject(template as Record<string, unknown>, context)
  }
  // Primitives pass through.
  return template
}

// ---------------------------------------------------------------------------
// Object rendering — handles $if, $map, $eval, $flatten
// ---------------------------------------------------------------------------

function renderObject(obj: Record<string, unknown>, context: Context): unknown {
  // --- $if / then / else ---
  if ('$if' in obj) {
    const condition = obj['$if'] as string
    const result = evaluateCondition(condition, context)
    if (result) {
      const thenBranch = obj['then']
      return thenBranch == null ? REMOVED : render(thenBranch, context)
    } else {
      const elseBranch = obj['else']
      return elseBranch == null ? REMOVED : render(elseBranch, context)
    }
  }

  // --- $eval ---
  if ('$eval' in obj) {
    const expr = obj['$eval'] as string
    return evaluateExpression(expr, context)
  }

  // --- $flatten ---
  if ('$flatten' in obj) {
    const inner = render(obj['$flatten'], context)
    if (Array.isArray(inner)) {
      const result: unknown[] = []
      for (const item of inner) {
        if (Array.isArray(item)) {
          result.push(...item)
        } else if (item !== REMOVED) {
          result.push(item)
        }
      }
      return result
    }
    return inner
  }

  // --- $map / each(var) ---
  if ('$map' in obj) {
    return renderMap(obj, context)
  }

  // --- Plain object: render each value recursively ---
  const result: Record<string, unknown> = {}
  for (const [key, value] of Object.entries(obj)) {
    const rendered = render(value, context)
    if (rendered !== REMOVED) {
      result[key] = rendered
    }
  }
  return result
}

// ---------------------------------------------------------------------------
// $map handler
// ---------------------------------------------------------------------------

const EACH_PATTERN = /^each\((\w+)(?:,\s*(\w+))?\)$/

function renderMap(obj: Record<string, unknown>, context: Context): unknown[] {
  const sourceExpr = obj['$map'] as string
  const source = evaluateExpression(sourceExpr, context)
  if (!Array.isArray(source)) return []

  // Find the each(varName) or each(varName, indexName) key.
  let varName: string | undefined
  let indexName: string | undefined
  let itemTemplate: unknown
  for (const key of Object.keys(obj)) {
    const match = EACH_PATTERN.exec(key)
    if (match) {
      varName = match[1]
      indexName = match[2] // optional
      itemTemplate = obj[key]
      break
    }
  }
  if (!varName || itemTemplate === undefined) return []

  const results: unknown[] = []
  for (let i = 0; i < source.length; i++) {
    const itemContext: Context = { ...context }
    itemContext[varName] = source[i]
    // Expose index under both explicit name (if given) and legacy implicit name.
    itemContext[`${varName}Index`] = i
    if (indexName) {
      itemContext[indexName] = i
    }
    const rendered = render(itemTemplate, itemContext)
    if (rendered !== REMOVED) {
      results.push(rendered)
    }
  }
  return results
}

// ---------------------------------------------------------------------------
// String interpolation
// ---------------------------------------------------------------------------

const WHOLE_EXPR_PATTERN = /^\$\{([^}]+)\}$/
const EXPR_PATTERN = /\$\{(.+?)\}/g

/**
 * Interpolates `${expr}` references in a string.
 * If the entire string is a single `${expr}`, returns the raw value
 * (preserving type — e.g., a list stays a list).
 */
function interpolateString(template: string, context: Context): unknown {
  // Whole-string expression: return raw value to preserve type.
  const wholeMatch = WHOLE_EXPR_PATTERN.exec(template)
  if (wholeMatch) {
    return evaluateExpression(wholeMatch[1], context)
  }

  // Partial interpolation: replace each ${...} with its string value.
  return template.replace(EXPR_PATTERN, (_, expr: string) => {
    const value = evaluateExpression(expr, context)
    return value != null ? String(value) : ''
  })
}

// ---------------------------------------------------------------------------
// Expression evaluation
// ---------------------------------------------------------------------------

/**
 * Evaluates a simple expression against context.
 * Supports dotted paths (a.b.c), indexed access (a[0]), and literals.
 */
export function evaluateExpression(expr: string, context: Context): unknown {
  expr = expr.trim()

  // String literal: 'hello' or "hello"
  if (
    (expr.startsWith("'") && expr.endsWith("'")) ||
    (expr.startsWith('"') && expr.endsWith('"'))
  ) {
    return expr.substring(1, expr.length - 1)
  }

  // Numeric literal
  const asNum = Number(expr)
  if (!isNaN(asNum) && expr !== '') return asNum

  // Boolean literal
  if (expr === 'true') return true
  if (expr === 'false') return false

  // Navigate dotted/indexed path
  return resolvePath(expr, context)
}

// ---------------------------------------------------------------------------
// Path resolution
// ---------------------------------------------------------------------------

interface PathSegment {
  type: 'field' | 'index'
  name?: string
  index?: number
}

/** Resolves a dotted/indexed path like "field.options" or "fields[0].name". */
function resolvePath(path: string, context: Context): unknown {
  const segments: PathSegment[] = []
  let buffer = ''

  for (let i = 0; i < path.length; i++) {
    const ch = path[i]
    if (ch === '.') {
      if (buffer) {
        segments.push({ type: 'field', name: buffer })
        buffer = ''
      }
    } else if (ch === '[') {
      if (buffer) {
        segments.push({ type: 'field', name: buffer })
        buffer = ''
      }
      // Read until ]
      i++
      while (i < path.length && path[i] !== ']') {
        buffer += path[i]
        i++
      }
      const idx = parseInt(buffer, 10)
      if (!isNaN(idx)) {
        segments.push({ type: 'index', index: idx })
      } else {
        segments.push({ type: 'field', name: buffer })
      }
      buffer = ''
    } else {
      buffer += ch
    }
  }
  if (buffer) {
    segments.push({ type: 'field', name: buffer })
  }

  let current: unknown = context
  for (const segment of segments) {
    if (current == null) return null
    if (segment.type === 'index') {
      if (Array.isArray(current) && segment.index! < current.length) {
        current = current[segment.index!]
      } else {
        return null
      }
    } else {
      if (typeof current === 'object' && current !== null && !Array.isArray(current)) {
        current = (current as Record<string, unknown>)[segment.name!]
      } else {
        return null
      }
    }
  }
  return current
}

// ---------------------------------------------------------------------------
// Condition evaluation
// ---------------------------------------------------------------------------

/**
 * Evaluates a boolean condition string.
 * Supports: `varName`, `!varName`, `a == b`, `a != b`, `a == 'literal'`,
 * `a && b`, `a || b`.
 */
export function evaluateCondition(condition: string, context: Context): boolean {
  condition = condition.trim()

  // Logical AND: split on && (lower precedence than ||? Actually AND > OR).
  // We check || first (lowest precedence) then &&.
  const orIndex = findLogicalOp(condition, '||')
  if (orIndex >= 0) {
    const left = condition.substring(0, orIndex).trim()
    const right = condition.substring(orIndex + 2).trim()
    return evaluateCondition(left, context) || evaluateCondition(right, context)
  }

  const andIndex = findLogicalOp(condition, '&&')
  if (andIndex >= 0) {
    const left = condition.substring(0, andIndex).trim()
    const right = condition.substring(andIndex + 2).trim()
    return evaluateCondition(left, context) && evaluateCondition(right, context)
  }

  // Negation: !expr
  if (condition.startsWith('!')) {
    return !evaluateCondition(condition.substring(1), context)
  }

  // Equality: a == b
  if (condition.includes('==')) {
    const parts = condition.split('==').map((s) => s.trim())
    if (parts.length === 2) {
      const left = evaluateExpression(parts[0], context)
      const right = evaluateExpression(parts[1], context)
      return String(left) === String(right)
    }
  }

  // Inequality: a != b
  if (condition.includes('!=')) {
    const parts = condition.split('!=').map((s) => s.trim())
    if (parts.length === 2) {
      const left = evaluateExpression(parts[0], context)
      const right = evaluateExpression(parts[1], context)
      return String(left) !== String(right)
    }
  }

  // Truthy check: just a variable name
  const value = evaluateExpression(condition, context)
  if (value == null) return false
  if (typeof value === 'boolean') return value
  if (typeof value === 'string') return value.length > 0
  if (typeof value === 'number') return value !== 0
  if (Array.isArray(value)) return value.length > 0
  return true
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Finds the index of a logical operator (`&&` or `||`) outside of string
 * literals. Returns -1 if not found.
 */
function findLogicalOp(condition: string, op: string): number {
  let inSingle = false
  let inDouble = false
  for (let i = 0; i < condition.length - 1; i++) {
    const ch = condition[i]
    if (ch === "'" && !inDouble) {
      inSingle = !inSingle
    } else if (ch === '"' && !inSingle) {
      inDouble = !inDouble
    } else if (!inSingle && !inDouble) {
      if (condition.substring(i, i + 2) === op) {
        return i
      }
    }
  }
  return -1
}

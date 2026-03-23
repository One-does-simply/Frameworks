/**
 * Evaluates formula expressions for computed fields.
 *
 * ODS Spec: Computed fields use `{fieldName}` placeholders to reference
 * other fields. For number-type fields, the result is evaluated as a math
 * expression (supports +, -, *, /, parentheses). For text-type fields,
 * placeholders are simply replaced with their values (string interpolation).
 */

const FIELD_PATTERN = /\{(\w+)\}/g;

/** Returns the list of field names referenced in a formula. */
export function formulaDependencies(formula: string): string[] {
  const seen = new Set<string>();
  let match: RegExpExecArray | null;
  const re = new RegExp(FIELD_PATTERN.source, 'g');
  while ((match = re.exec(formula)) !== null) {
    seen.add(match[1]);
  }
  return Array.from(seen);
}

/**
 * Evaluates a formula given field values.
 *
 * For fieldType "number", substitutes values and evaluates the math
 * expression. For all other types, performs string interpolation.
 * Returns an empty string if any referenced field is missing or if
 * evaluation fails.
 */
export function evaluateFormula(
  formula: string,
  fieldType: string,
  values: Record<string, string | null | undefined>,
): string {
  // Check that all referenced fields have values.
  const re = new RegExp(FIELD_PATTERN.source, 'g');
  let match: RegExpExecArray | null;
  while ((match = re.exec(formula)) !== null) {
    const name = match[1];
    const val = values[name];
    if (val == null || val === '') return '';
  }

  // Substitute field references with their values.
  const substituted = formula.replace(
    new RegExp(FIELD_PATTERN.source, 'g'),
    (_, fieldName: string) => values[fieldName] ?? '',
  );

  if (fieldType === 'number') {
    try {
      const result = evaluateMath(substituted);
      if (!isFinite(result) || isNaN(result)) return '';
      if (result === Math.round(result)) {
        return Math.round(result).toString();
      }
      // Round to 2 decimal places for display.
      return result.toFixed(2);
    } catch {
      return '';
    }
  }

  // For text and other types, return the interpolated string.
  return substituted;
}

// ---------------------------------------------------------------------------
// Simple recursive-descent math evaluator for +, -, *, /, parentheses.
// ---------------------------------------------------------------------------

function evaluateMath(expression: string): number {
  const tokens = tokenize(expression);
  const parser = new MathParser(tokens);
  const result = parser.parseExpression();
  if (parser.pos < tokens.length) {
    throw new Error(`Unexpected token: ${tokens[parser.pos]}`);
  }
  return result;
}

/** Tokenizes a math expression string into numbers and operator characters. */
function tokenize(expr: string): string[] {
  const tokens: string[] = [];
  let buffer = '';

  for (let i = 0; i < expr.length; i++) {
    const ch = expr[i];
    if (ch === ' ') {
      if (buffer.length > 0) {
        tokens.push(buffer);
        buffer = '';
      }
      continue;
    }
    if ('+-*/()'.includes(ch)) {
      if (buffer.length > 0) {
        tokens.push(buffer);
        buffer = '';
      }
      // Handle unary minus: at start, after '(', or after an operator.
      if (
        ch === '-' &&
        (tokens.length === 0 ||
          tokens[tokens.length - 1] === '(' ||
          '+-*/'.includes(tokens[tokens.length - 1]))
      ) {
        buffer += '-';
      } else {
        tokens.push(ch);
      }
    } else {
      buffer += ch;
    }
  }
  if (buffer.length > 0) {
    tokens.push(buffer);
  }
  return tokens;
}

/**
 * Simple recursive-descent parser for math expressions.
 *
 * Grammar:
 *   expression = term (('+' | '-') term)*
 *   term       = factor (('*' | '/') factor)*
 *   factor     = NUMBER | '(' expression ')'
 */
class MathParser {
  private tokens: string[];
  pos: number = 0;

  constructor(tokens: string[]) {
    this.tokens = tokens;
  }

  private peek(): string | undefined {
    return this.pos < this.tokens.length ? this.tokens[this.pos] : undefined;
  }

  private consume(): string {
    if (this.pos >= this.tokens.length) {
      throw new Error('Unexpected end of expression');
    }
    return this.tokens[this.pos++];
  }

  parseExpression(): number {
    let result = this.parseTerm();
    while (this.peek() === '+' || this.peek() === '-') {
      const op = this.consume();
      const right = this.parseTerm();
      result = op === '+' ? result + right : result - right;
    }
    return result;
  }

  private parseTerm(): number {
    let result = this.parseFactor();
    while (this.peek() === '*' || this.peek() === '/') {
      const op = this.consume();
      const right = this.parseFactor();
      result = op === '*' ? result * right : result / right;
    }
    return result;
  }

  private parseFactor(): number {
    if (this.peek() === '(') {
      this.consume(); // '('
      const result = this.parseExpression();
      if (this.peek() !== ')') {
        throw new Error('Expected closing parenthesis');
      }
      this.consume(); // ')'
      return result;
    }
    const token = this.consume();
    const value = Number(token);
    if (isNaN(value)) {
      throw new Error(`Expected number, got: ${token}`);
    }
    return value;
  }
}

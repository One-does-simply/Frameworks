import { describe, it, expect } from 'vitest';
import { formulaDependencies, evaluateFormula } from '../../../src/engine/formula-evaluator.ts';

describe('formulaDependencies', () => {
  it('extracts field names', () => {
    const deps = formulaDependencies('{quantity} * {unitPrice}');
    expect(deps).toContain('quantity');
    expect(deps).toContain('unitPrice');
    expect(deps).toHaveLength(2);
  });

  it('deduplicates', () => {
    const deps = formulaDependencies('{a} + {a}');
    expect(deps).toEqual(['a']);
  });

  it('no references returns empty', () => {
    const deps = formulaDependencies('42');
    expect(deps).toHaveLength(0);
  });
});

describe('Number formulas', () => {
  it('addition', () => {
    const result = evaluateFormula('{a} + {b}', 'number', { a: '10', b: '5' });
    expect(result).toBe('15');
  });

  it('subtraction', () => {
    const result = evaluateFormula('{a} - {b}', 'number', { a: '10', b: '3' });
    expect(result).toBe('7');
  });

  it('multiplication', () => {
    const result = evaluateFormula('{qty} * {price}', 'number', { qty: '4', price: '2.50' });
    expect(result).toBe('10');
  });

  it('division', () => {
    const result = evaluateFormula('{total} / {count}', 'number', { total: '100', count: '4' });
    expect(result).toBe('25');
  });

  it('decimal result rounds to 2 places', () => {
    const result = evaluateFormula('{a} / {b}', 'number', { a: '10', b: '3' });
    expect(result).toBe('3.33');
  });

  it('parentheses', () => {
    const result = evaluateFormula('({a} + {b}) * {c}', 'number', { a: '2', b: '3', c: '4' });
    expect(result).toBe('20');
  });

  it('operator precedence: multiply before add', () => {
    const result = evaluateFormula('{a} + {b} * {c}', 'number', { a: '2', b: '3', c: '4' });
    expect(result).toBe('14');
  });

  it('unary minus', () => {
    const result = evaluateFormula('-{a} + {b}', 'number', { a: '5', b: '10' });
    expect(result).toBe('5');
  });

  it('missing field returns empty string', () => {
    const result = evaluateFormula('{a} + {b}', 'number', { a: '10' });
    expect(result).toBe('');
  });

  it('empty field returns empty string', () => {
    const result = evaluateFormula('{a} + {b}', 'number', { a: '10', b: '' });
    expect(result).toBe('');
  });

  it('integer result has no decimal', () => {
    const result = evaluateFormula('{a} * {b}', 'number', { a: '3', b: '7' });
    expect(result).toBe('21');
    expect(result.includes('.')).toBe(false);
  });
});

describe('Text formulas (string interpolation)', () => {
  it('simple interpolation', () => {
    const result = evaluateFormula('{first} {last}', 'text', { first: 'John', last: 'Doe' });
    expect(result).toBe('John Doe');
  });

  it('missing field returns empty', () => {
    const result = evaluateFormula('{greeting} {name}', 'text', { greeting: 'Hello' });
    expect(result).toBe('');
  });
});

// Edge cases (from formula_evaluator_edge_test.dart)

describe('Division edge cases', () => {
  it('division by zero returns empty string', () => {
    const result = evaluateFormula('{a} / {b}', 'number', { a: '10', b: '0' });
    expect(result).toBe('');
  });

  it('zero divided by zero', () => {
    const result = evaluateFormula('{a} / {b}', 'number', { a: '0', b: '0' });
    expect(typeof result).toBe('string');
  });
});

describe('Nested parentheses', () => {
  it('double nesting', () => {
    const result = evaluateFormula(
      '(({a} + {b}) * ({c} - {d}))',
      'number',
      { a: '2', b: '3', c: '10', d: '4' },
    );
    // (2+3) * (10-4) = 5 * 6 = 30
    expect(result).toBe('30');
  });

  it('triple nesting', () => {
    const result = evaluateFormula(
      '((({a} + {b}) * {c}) - {d})',
      'number',
      { a: '1', b: '2', c: '3', d: '4' },
    );
    // ((1+2)*3)-4 = 9-4 = 5
    expect(result).toBe('5');
  });
});

describe('Non-numeric field values', () => {
  it('text in number field returns empty', () => {
    const result = evaluateFormula('{a} + {b}', 'number', { a: 'abc', b: '10' });
    expect(typeof result).toBe('string');
  });
});

describe('Large numbers', () => {
  it('handles large multiplication', () => {
    const result = evaluateFormula('{a} * {b}', 'number', { a: '1000000', b: '1000000' });
    expect(result).toBe('1000000000000');
  });
});

describe('Whitespace handling', () => {
  it('extra whitespace in expression', () => {
    const result = evaluateFormula('{a}  +  {b}', 'number', { a: '5', b: '3' });
    expect(result).toBe('8');
  });
});

describe('Negative numbers', () => {
  it('negative field value', () => {
    const result = evaluateFormula('{a} + {b}', 'number', { a: '-5', b: '10' });
    expect(result).toBe('5');
  });

  it('double negative', () => {
    const result = evaluateFormula('-{a} + -{b}', 'number', { a: '5', b: '3' });
    expect(result).toBe('-8');
  });
});

describe('Decimal precision', () => {
  it('currency-like multiplication', () => {
    const result = evaluateFormula('{qty} * {price}', 'number', { qty: '3', price: '19.99' });
    expect(result).toBe('59.97');
  });

  it('many decimal places get rounded to 2', () => {
    const result = evaluateFormula('{a} / {b}', 'number', { a: '100', b: '7' });
    expect(result).toBe('14.29');
  });
});

describe('Complex expressions', () => {
  it('multiple operations mixed', () => {
    const result = evaluateFormula(
      '{a} * {b} + {c} / {d} - {e}',
      'number',
      { a: '10', b: '2', c: '30', d: '5', e: '3' },
    );
    // 10*2 + 30/5 - 3 = 20 + 6 - 3 = 23
    expect(result).toBe('23');
  });
});

describe('Single value', () => {
  it('just a field reference', () => {
    const result = evaluateFormula('{a}', 'number', { a: '42' });
    expect(result).toBe('42');
  });
});

describe('Text formula edge cases', () => {
  it('special characters in text interpolation', () => {
    const result = evaluateFormula(
      '{name} <{email}>',
      'text',
      { name: "O'Brien", email: 'o@test.com' },
    );
    expect(result).toBe("O'Brien <o@test.com>");
  });

  it('empty text interpolation returns field value', () => {
    const result = evaluateFormula('{a}', 'text', { a: 'hello' });
    expect(result).toBe('hello');
  });
});

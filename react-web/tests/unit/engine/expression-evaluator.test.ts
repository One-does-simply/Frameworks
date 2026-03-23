import { describe, it, expect } from 'vitest';
import { evaluateExpression, evaluateBool } from '../../../src/engine/expression-evaluator.ts';

// --- evaluateExpression tests (from expression_evaluator_test.dart) ---

describe('Ternary comparison', () => {
  it('equal values return true branch', () => {
    const result = evaluateExpression("{a} == {b} ? 'match' : 'nope'", { a: 'X', b: 'X' });
    expect(result).toBe('match');
  });

  it('unequal values return false branch', () => {
    const result = evaluateExpression("{a} == {b} ? 'match' : 'nope'", { a: 'X', b: 'Y' });
    expect(result).toBe('nope');
  });

  it('quiz scoring pattern: correct answer', () => {
    const result = evaluateExpression(
      "{userAnswer} == {correctOption} ? '1' : '0'",
      { userAnswer: 'B', correctOption: 'B' },
    );
    expect(result).toBe('1');
  });

  it('quiz scoring pattern: wrong answer', () => {
    const result = evaluateExpression(
      "{userAnswer} == {correctOption} ? '1' : '0'",
      { userAnswer: 'A', correctOption: 'B' },
    );
    expect(result).toBe('0');
  });
});

describe('Magic values', () => {
  it('NOW returns ISO datetime', () => {
    const result = evaluateExpression('NOW', {});
    expect(result.startsWith('20')).toBe(true); // Starts with year
    expect(result).toContain('T'); // ISO format has T separator
  });

  it('NOW is case-insensitive', () => {
    const result = evaluateExpression('now', {});
    expect(result.startsWith('20')).toBe(true);
  });
});

describe('Math delegation', () => {
  it('simple addition', () => {
    const result = evaluateExpression('{a} + {b}', { a: '10', b: '5' });
    expect(result).toBe('15');
  });

  it('multiplication', () => {
    const result = evaluateExpression('{qty} * {price}', { qty: '3', price: '9.99' });
    expect(result).toBe('29.97');
  });
});

describe('String interpolation', () => {
  it('simple field substitution', () => {
    const result = evaluateExpression('{first} {last}', { first: 'John', last: 'Doe' });
    expect(result).toBe('John Doe');
  });

  it('missing field resolves to empty', () => {
    const result = evaluateExpression('{first} {last}', { first: 'John' });
    expect(result).toBe('John ');
  });
});

// --- evaluateBool tests (from expression_evaluator_bool_test.dart) ---

describe('evaluateBool - equality', () => {
  it('field equals quoted value', () => {
    expect(evaluateBool("{status} == 'Done'", { status: 'Done' })).toBe(true);
  });

  it('field does not equal quoted value', () => {
    expect(evaluateBool("{status} == 'Done'", { status: 'Open' })).toBe(false);
  });

  it('field equals unquoted value', () => {
    expect(evaluateBool('{count} == 0', { count: '0' })).toBe(true);
  });

  it('field equals empty string', () => {
    expect(evaluateBool("{name} == ''", { name: '' })).toBe(true);
  });
});

describe('evaluateBool - inequality', () => {
  it('field not equal to value', () => {
    expect(evaluateBool("{status} != 'Done'", { status: 'Open' })).toBe(true);
  });

  it('field equals value returns false for !=', () => {
    expect(evaluateBool("{status} != 'Done'", { status: 'Done' })).toBe(false);
  });
});

describe('evaluateBool - truthy checks', () => {
  it('non-empty string is truthy', () => {
    expect(evaluateBool('{name}', { name: 'Alice' })).toBe(true);
  });

  it('empty string is falsy', () => {
    expect(evaluateBool('{name}', { name: '' })).toBe(false);
  });

  it('missing field is falsy', () => {
    expect(evaluateBool('{missing}', {})).toBe(false);
  });

  it('"false" string is falsy', () => {
    expect(evaluateBool('{flag}', { flag: 'false' })).toBe(false);
  });

  it('"0" string is falsy', () => {
    expect(evaluateBool('{count}', { count: '0' })).toBe(false);
  });

  it('"true" string is truthy', () => {
    expect(evaluateBool('{flag}', { flag: 'true' })).toBe(true);
  });

  it('"1" is truthy', () => {
    expect(evaluateBool('{count}', { count: '1' })).toBe(true);
  });
});

describe('evaluateBool - negation', () => {
  it('negated truthy value', () => {
    expect(evaluateBool('!{active}', { active: 'true' })).toBe(false);
  });

  it('negated falsy value', () => {
    expect(evaluateBool('!{active}', { active: '' })).toBe(true);
  });

  it('negated missing field', () => {
    expect(evaluateBool('!{missing}', {})).toBe(true);
  });
});

describe('evaluateBool - edge cases', () => {
  it('empty expression returns true', () => {
    expect(evaluateBool('', {})).toBe(true);
  });

  it('whitespace-only expression returns true', () => {
    expect(evaluateBool('   ', {})).toBe(true);
  });

  it('comparison with spaces around operator', () => {
    expect(evaluateBool("{x}   ==   'yes'", { x: 'yes' })).toBe(true);
  });
});

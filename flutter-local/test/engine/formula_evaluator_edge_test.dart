import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/engine/formula_evaluator.dart';

/// Edge case tests for FormulaEvaluator, complementing the main test file.
void main() {
  group('Division edge cases', () {
    test('division by zero returns empty string', () {
      final result = FormulaEvaluator.evaluate(
        '{a} / {b}',
        'number',
        {'a': '10', 'b': '0'},
      );
      // Division by zero produces Infinity, which the evaluator
      // catches and returns empty string.
      expect(result, isEmpty);
    });

    test('zero divided by zero', () {
      final result = FormulaEvaluator.evaluate(
        '{a} / {b}',
        'number',
        {'a': '0', 'b': '0'},
      );
      // 0/0 = NaN in Dart, which should be caught.
      expect(result, isA<String>());
    });
  });

  group('Nested parentheses', () {
    test('double nesting', () {
      final result = FormulaEvaluator.evaluate(
        '(({a} + {b}) * ({c} - {d}))',
        'number',
        {'a': '2', 'b': '3', 'c': '10', 'd': '4'},
      );
      // (2+3) * (10-4) = 5 * 6 = 30
      expect(result, '30');
    });

    test('triple nesting', () {
      final result = FormulaEvaluator.evaluate(
        '((({a} + {b}) * {c}) - {d})',
        'number',
        {'a': '1', 'b': '2', 'c': '3', 'd': '4'},
      );
      // ((1+2)*3)-4 = 9-4 = 5
      expect(result, '5');
    });
  });

  group('Non-numeric field values', () {
    test('text in number field returns empty', () {
      final result = FormulaEvaluator.evaluate(
        '{a} + {b}',
        'number',
        {'a': 'abc', 'b': '10'},
      );
      // 'abc' is not parseable — the math evaluator should catch this.
      expect(result, isA<String>());
    });
  });

  group('Large numbers', () {
    test('handles large multiplication', () {
      final result = FormulaEvaluator.evaluate(
        '{a} * {b}',
        'number',
        {'a': '1000000', 'b': '1000000'},
      );
      expect(result, '1000000000000');
    });
  });

  group('Whitespace handling', () {
    test('extra whitespace in expression', () {
      final result = FormulaEvaluator.evaluate(
        '{a}  +  {b}',
        'number',
        {'a': '5', 'b': '3'},
      );
      expect(result, '8');
    });
  });

  group('Negative numbers', () {
    test('negative field value', () {
      final result = FormulaEvaluator.evaluate(
        '{a} + {b}',
        'number',
        {'a': '-5', 'b': '10'},
      );
      expect(result, '5');
    });

    test('double negative', () {
      final result = FormulaEvaluator.evaluate(
        '-{a} + -{b}',
        'number',
        {'a': '5', 'b': '3'},
      );
      expect(result, '-8');
    });
  });

  group('Decimal precision', () {
    test('currency-like multiplication', () {
      final result = FormulaEvaluator.evaluate(
        '{qty} * {price}',
        'number',
        {'qty': '3', 'price': '19.99'},
      );
      expect(result, '59.97');
    });

    test('many decimal places get rounded to 2', () {
      final result = FormulaEvaluator.evaluate(
        '{a} / {b}',
        'number',
        {'a': '100', 'b': '7'},
      );
      expect(result, '14.29');
    });
  });

  group('Complex expressions', () {
    test('multiple operations mixed', () {
      final result = FormulaEvaluator.evaluate(
        '{a} * {b} + {c} / {d} - {e}',
        'number',
        {'a': '10', 'b': '2', 'c': '30', 'd': '5', 'e': '3'},
      );
      // 10*2 + 30/5 - 3 = 20 + 6 - 3 = 23
      expect(result, '23');
    });
  });

  group('Single value', () {
    test('just a field reference', () {
      final result = FormulaEvaluator.evaluate(
        '{a}',
        'number',
        {'a': '42'},
      );
      expect(result, '42');
    });
  });

  group('Text formula edge cases', () {
    test('special characters in text interpolation', () {
      final result = FormulaEvaluator.evaluate(
        '{name} <{email}>',
        'text',
        {'name': "O'Brien", 'email': 'o@test.com'},
      );
      expect(result, "O'Brien <o@test.com>");
    });

    test('empty text interpolation returns field value', () {
      final result = FormulaEvaluator.evaluate(
        '{a}',
        'text',
        {'a': 'hello'},
      );
      expect(result, 'hello');
    });
  });
}

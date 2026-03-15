import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/engine/formula_evaluator.dart';

void main() {
  group('dependencies', () {
    test('extracts field names', () {
      final deps = FormulaEvaluator.dependencies('{quantity} * {unitPrice}');
      expect(deps, containsAll(['quantity', 'unitPrice']));
      expect(deps.length, 2);
    });

    test('deduplicates', () {
      final deps = FormulaEvaluator.dependencies('{a} + {a}');
      expect(deps, ['a']);
    });

    test('no references returns empty', () {
      final deps = FormulaEvaluator.dependencies('42');
      expect(deps, isEmpty);
    });
  });

  group('Number formulas', () {
    test('addition', () {
      final result = FormulaEvaluator.evaluate(
        '{a} + {b}',
        'number',
        {'a': '10', 'b': '5'},
      );
      expect(result, '15');
    });

    test('subtraction', () {
      final result = FormulaEvaluator.evaluate(
        '{a} - {b}',
        'number',
        {'a': '10', 'b': '3'},
      );
      expect(result, '7');
    });

    test('multiplication', () {
      final result = FormulaEvaluator.evaluate(
        '{qty} * {price}',
        'number',
        {'qty': '4', 'price': '2.50'},
      );
      expect(result, '10');
    });

    test('division', () {
      final result = FormulaEvaluator.evaluate(
        '{total} / {count}',
        'number',
        {'total': '100', 'count': '4'},
      );
      expect(result, '25');
    });

    test('decimal result rounds to 2 places', () {
      final result = FormulaEvaluator.evaluate(
        '{a} / {b}',
        'number',
        {'a': '10', 'b': '3'},
      );
      expect(result, '3.33');
    });

    test('parentheses', () {
      final result = FormulaEvaluator.evaluate(
        '({a} + {b}) * {c}',
        'number',
        {'a': '2', 'b': '3', 'c': '4'},
      );
      expect(result, '20');
    });

    test('operator precedence: multiply before add', () {
      final result = FormulaEvaluator.evaluate(
        '{a} + {b} * {c}',
        'number',
        {'a': '2', 'b': '3', 'c': '4'},
      );
      expect(result, '14');
    });

    test('unary minus', () {
      final result = FormulaEvaluator.evaluate(
        '-{a} + {b}',
        'number',
        {'a': '5', 'b': '10'},
      );
      expect(result, '5');
    });

    test('missing field returns empty string', () {
      final result = FormulaEvaluator.evaluate(
        '{a} + {b}',
        'number',
        {'a': '10'},
      );
      expect(result, '');
    });

    test('empty field returns empty string', () {
      final result = FormulaEvaluator.evaluate(
        '{a} + {b}',
        'number',
        {'a': '10', 'b': ''},
      );
      expect(result, '');
    });

    test('integer result has no decimal', () {
      final result = FormulaEvaluator.evaluate(
        '{a} * {b}',
        'number',
        {'a': '3', 'b': '7'},
      );
      expect(result, '21');
      expect(result.contains('.'), false);
    });
  });

  group('Text formulas (string interpolation)', () {
    test('simple interpolation', () {
      final result = FormulaEvaluator.evaluate(
        '{first} {last}',
        'text',
        {'first': 'John', 'last': 'Doe'},
      );
      expect(result, 'John Doe');
    });

    test('missing field returns empty', () {
      final result = FormulaEvaluator.evaluate(
        '{greeting} {name}',
        'text',
        {'greeting': 'Hello'},
      );
      expect(result, '');
    });
  });
}

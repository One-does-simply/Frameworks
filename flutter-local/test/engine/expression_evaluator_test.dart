import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/engine/expression_evaluator.dart';

void main() {
  group('Ternary comparison', () {
    test('equal values return true branch', () {
      final result = ExpressionEvaluator.evaluate(
        "{a} == {b} ? 'match' : 'nope'",
        {'a': 'X', 'b': 'X'},
      );
      expect(result, 'match');
    });

    test('unequal values return false branch', () {
      final result = ExpressionEvaluator.evaluate(
        "{a} == {b} ? 'match' : 'nope'",
        {'a': 'X', 'b': 'Y'},
      );
      expect(result, 'nope');
    });

    test('quiz scoring pattern: correct answer', () {
      final result = ExpressionEvaluator.evaluate(
        "{userAnswer} == {correctOption} ? '1' : '0'",
        {'userAnswer': 'B', 'correctOption': 'B'},
      );
      expect(result, '1');
    });

    test('quiz scoring pattern: wrong answer', () {
      final result = ExpressionEvaluator.evaluate(
        "{userAnswer} == {correctOption} ? '1' : '0'",
        {'userAnswer': 'A', 'correctOption': 'B'},
      );
      expect(result, '0');
    });
  });

  group('Magic values', () {
    test('NOW returns ISO datetime', () {
      final result = ExpressionEvaluator.evaluate('NOW', {});
      expect(result, startsWith('20')); // Starts with year
      expect(result, contains('T'));    // ISO format has T separator
    });

    test('NOW is case-insensitive', () {
      final result = ExpressionEvaluator.evaluate('now', {});
      expect(result, startsWith('20'));
    });
  });

  group('Math delegation', () {
    test('simple addition', () {
      final result = ExpressionEvaluator.evaluate(
        '{a} + {b}',
        {'a': '10', 'b': '5'},
      );
      expect(result, '15');
    });

    test('multiplication', () {
      final result = ExpressionEvaluator.evaluate(
        '{qty} * {price}',
        {'qty': '3', 'price': '9.99'},
      );
      expect(result, '29.97');
    });
  });

  group('String interpolation', () {
    test('simple field substitution', () {
      final result = ExpressionEvaluator.evaluate(
        '{first} {last}',
        {'first': 'John', 'last': 'Doe'},
      );
      expect(result, 'John Doe');
    });

    test('missing field resolves to empty', () {
      final result = ExpressionEvaluator.evaluate(
        '{first} {last}',
        {'first': 'John'},
      );
      expect(result, 'John ');
    });
  });
}

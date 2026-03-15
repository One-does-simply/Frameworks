import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/engine/expression_evaluator.dart';

void main() {
  group('evaluateBool — equality', () {
    test('field equals quoted value', () {
      expect(
        ExpressionEvaluator.evaluateBool("{status} == 'Done'", {'status': 'Done'}),
        true,
      );
    });

    test('field does not equal quoted value', () {
      expect(
        ExpressionEvaluator.evaluateBool("{status} == 'Done'", {'status': 'Open'}),
        false,
      );
    });

    test('field equals unquoted value', () {
      expect(
        ExpressionEvaluator.evaluateBool("{count} == 0", {'count': '0'}),
        true,
      );
    });

    test('field equals empty string', () {
      expect(
        ExpressionEvaluator.evaluateBool("{name} == ''", {'name': ''}),
        true,
      );
    });
  });

  group('evaluateBool — inequality', () {
    test('field not equal to value', () {
      expect(
        ExpressionEvaluator.evaluateBool("{status} != 'Done'", {'status': 'Open'}),
        true,
      );
    });

    test('field equals value returns false for !=', () {
      expect(
        ExpressionEvaluator.evaluateBool("{status} != 'Done'", {'status': 'Done'}),
        false,
      );
    });
  });

  group('evaluateBool — truthy checks', () {
    test('non-empty string is truthy', () {
      expect(
        ExpressionEvaluator.evaluateBool('{name}', {'name': 'Alice'}),
        true,
      );
    });

    test('empty string is falsy', () {
      expect(
        ExpressionEvaluator.evaluateBool('{name}', {'name': ''}),
        false,
      );
    });

    test('missing field is falsy', () {
      expect(
        ExpressionEvaluator.evaluateBool('{missing}', {}),
        false,
      );
    });

    test('"false" string is falsy', () {
      expect(
        ExpressionEvaluator.evaluateBool('{flag}', {'flag': 'false'}),
        false,
      );
    });

    test('"0" string is falsy', () {
      expect(
        ExpressionEvaluator.evaluateBool('{count}', {'count': '0'}),
        false,
      );
    });

    test('"true" string is truthy', () {
      expect(
        ExpressionEvaluator.evaluateBool('{flag}', {'flag': 'true'}),
        true,
      );
    });

    test('"1" is truthy', () {
      expect(
        ExpressionEvaluator.evaluateBool('{count}', {'count': '1'}),
        true,
      );
    });
  });

  group('evaluateBool — negation', () {
    test('negated truthy value', () {
      expect(
        ExpressionEvaluator.evaluateBool('!{active}', {'active': 'true'}),
        false,
      );
    });

    test('negated falsy value', () {
      expect(
        ExpressionEvaluator.evaluateBool('!{active}', {'active': ''}),
        true,
      );
    });

    test('negated missing field', () {
      expect(
        ExpressionEvaluator.evaluateBool('!{missing}', {}),
        true,
      );
    });
  });

  group('evaluateBool — edge cases', () {
    test('empty expression returns true', () {
      expect(ExpressionEvaluator.evaluateBool('', {}), true);
    });

    test('whitespace-only expression returns true', () {
      expect(ExpressionEvaluator.evaluateBool('   ', {}), true);
    });

    test('comparison with spaces around operator', () {
      expect(
        ExpressionEvaluator.evaluateBool("{x}   ==   'yes'", {'x': 'yes'}),
        true,
      );
    });
  });
}

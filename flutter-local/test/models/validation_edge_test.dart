import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/models/ods_field_definition.dart';

/// Edge case tests for OdsValidation, complementing the main validation test file.
void main() {
  group('Email edge cases', () {
    const v = OdsValidation();

    test('email with subdomain passes', () {
      expect(v.validate('user@mail.example.com', 'email'), isNull);
    });

    test('email with + passes', () {
      expect(v.validate('user+tag@example.com', 'email'), isNull);
    });

    test('email with spaces fails', () {
      expect(v.validate('user @example.com', 'email'), isNotNull);
    });

    test('email with no TLD fails', () {
      expect(v.validate('user@localhost', 'email'), isNotNull);
    });

    test('email validation only applies to email type', () {
      expect(v.validate('not-an-email', 'text'), isNull);
    });
  });

  group('Min/Max edge cases', () {
    test('decimal min boundary', () {
      const v = OdsValidation(min: 0.5);
      expect(v.validate('0.5', 'number'), isNull);
      expect(v.validate('0.4', 'number'), isNotNull);
    });

    test('negative min', () {
      const v = OdsValidation(min: -10, max: 10);
      expect(v.validate('-10', 'number'), isNull);
      expect(v.validate('-11', 'number'), isNotNull);
      expect(v.validate('0', 'number'), isNull);
    });

    test('min only (no max)', () {
      const v = OdsValidation(min: 0);
      expect(v.validate('0', 'number'), isNull);
      expect(v.validate('-1', 'number'), isNotNull);
      expect(v.validate('999999', 'number'), isNull);
    });

    test('max only (no min)', () {
      const v = OdsValidation(max: 100);
      expect(v.validate('100', 'number'), isNull);
      expect(v.validate('101', 'number'), isNotNull);
      expect(v.validate('-999', 'number'), isNull);
    });
  });

  group('MinLength edge cases', () {
    test('exact minLength passes', () {
      const v = OdsValidation(minLength: 3);
      expect(v.validate('abc', 'text'), isNull);
    });

    test('one below minLength fails', () {
      const v = OdsValidation(minLength: 3);
      expect(v.validate('ab', 'text'), isNotNull);
    });

    test('minLength 1', () {
      const v = OdsValidation(minLength: 1);
      expect(v.validate('x', 'text'), isNull);
    });
  });

  group('Pattern edge cases', () {
    test('phone number pattern', () {
      const v = OdsValidation(pattern: r'^\d{3}-\d{3}-\d{4}$');
      expect(v.validate('123-456-7890', 'text'), isNull);
      expect(v.validate('1234567890', 'text'), isNotNull);
    });

    test('case-sensitive pattern', () {
      const v = OdsValidation(pattern: r'^[A-Z]+$');
      expect(v.validate('HELLO', 'text'), isNull);
      expect(v.validate('hello', 'text'), isNotNull);
    });

    test('pattern with special characters', () {
      const v = OdsValidation(pattern: r'^https?://');
      expect(v.validate('https://example.com', 'text'), isNull);
      expect(v.validate('http://test.com', 'text'), isNull);
      expect(v.validate('ftp://nope.com', 'text'), isNotNull);
    });
  });

  group('Multiple rules combined', () {
    test('minLength + pattern both checked', () {
      const v = OdsValidation(minLength: 3, pattern: r'^\d+$');
      // Too short
      expect(v.validate('12', 'text'), isNotNull);
      // Long enough but wrong pattern
      expect(v.validate('abc', 'text'), isNotNull);
      // Both pass
      expect(v.validate('123', 'text'), isNull);
    });

    test('min + max + pattern on number', () {
      const v = OdsValidation(min: 1, max: 100, pattern: r'^\d+$');
      // pattern checked first (for text type), but for number, min/max is main
      expect(v.validate('50', 'number'), isNull);
      expect(v.validate('0', 'number'), isNotNull);
    });
  });

  group('Custom messages', () {
    test('custom message on email validation', () {
      const v = OdsValidation(message: 'Bad email!');
      expect(v.validate('nope', 'email'), 'Bad email!');
    });

    test('custom message on min validation', () {
      const v = OdsValidation(min: 10, message: 'Too low!');
      expect(v.validate('5', 'number'), 'Too low!');
    });

    test('custom message on pattern', () {
      const v = OdsValidation(pattern: r'^[A-Z]', message: 'Must start with uppercase');
      expect(v.validate('hello', 'text'), 'Must start with uppercase');
    });
  });

  group('OdsFieldDefinition', () {
    test('fromJson roundtrip', () {
      final json = {
        'name': 'email',
        'type': 'email',
        'label': 'Email Address',
        'required': true,
        'placeholder': 'you@example.com',
        'validation': {'pattern': r'^[^@]+@[^@]+$', 'message': 'Invalid'},
      };
      final field = OdsFieldDefinition.fromJson(json);
      expect(field.name, 'email');
      expect(field.type, 'email');
      expect(field.label, 'Email Address');
      expect(field.required, true);
      expect(field.validation, isNotNull);
    });

    test('isComputed flag', () {
      final field = const OdsFieldDefinition(
        name: 'total',
        type: 'number',
        formula: '{qty} * {price}',
      );
      expect(field.isComputed, true);
    });

    test('non-computed field', () {
      final field = const OdsFieldDefinition(name: 'name', type: 'text');
      expect(field.isComputed, false);
    });
  });
}

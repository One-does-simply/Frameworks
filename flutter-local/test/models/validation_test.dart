import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/models/ods_field_definition.dart';

void main() {
  group('Email validation', () {
    const v = OdsValidation();

    test('valid email passes', () {
      expect(v.validate('user@example.com', 'email'), isNull);
    });

    test('missing @ fails', () {
      expect(v.validate('userexample.com', 'email'), isNotNull);
    });

    test('missing domain fails', () {
      expect(v.validate('user@', 'email'), isNotNull);
    });

    test('empty string skipped (required handles that)', () {
      expect(v.validate('', 'email'), isNull);
    });
  });

  group('minLength validation', () {
    const v = OdsValidation(minLength: 5);

    test('long enough passes', () {
      expect(v.validate('hello', 'text'), isNull);
    });

    test('too short fails', () {
      expect(v.validate('hi', 'text'), isNotNull);
    });

    test('empty string skipped', () {
      expect(v.validate('', 'text'), isNull);
    });
  });

  group('Pattern validation', () {
    const v = OdsValidation(pattern: r'^\d{3}-\d{4}$');

    test('matching pattern passes', () {
      expect(v.validate('123-4567', 'text'), isNull);
    });

    test('non-matching pattern fails', () {
      expect(v.validate('1234567', 'text'), isNotNull);
    });
  });

  group('Number min/max validation', () {
    const v = OdsValidation(min: 1, max: 100);

    test('in range passes', () {
      expect(v.validate('50', 'number'), isNull);
    });

    test('at min passes', () {
      expect(v.validate('1', 'number'), isNull);
    });

    test('at max passes', () {
      expect(v.validate('100', 'number'), isNull);
    });

    test('below min fails', () {
      expect(v.validate('0', 'number'), isNotNull);
    });

    test('above max fails', () {
      expect(v.validate('101', 'number'), isNotNull);
    });

    test('non-number ignored', () {
      expect(v.validate('abc', 'number'), isNull);
    });

    test('min/max ignored for non-number fields', () {
      expect(v.validate('0', 'text'), isNull);
    });
  });

  group('Custom message', () {
    test('uses custom message when provided', () {
      const v = OdsValidation(minLength: 10, message: 'Too short!');
      expect(v.validate('hi', 'text'), 'Too short!');
    });
  });
}

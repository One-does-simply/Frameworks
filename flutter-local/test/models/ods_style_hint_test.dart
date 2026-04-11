import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/models/ods_style_hint.dart';

void main() {
  // =========================================================================
  // fromJson
  // =========================================================================

  group('OdsStyleHint.fromJson', () {
    test('fromJson with null returns empty hints', () {
      final h = OdsStyleHint.fromJson(null);
      expect(h.hints, isEmpty);
    });

    test('fromJson with valid map passes through', () {
      final h = OdsStyleHint.fromJson({'variant': 'heading', 'color': 'red'});
      expect(h.hints['variant'], 'heading');
      expect(h.hints['color'], 'red');
    });
  });

  // =========================================================================
  // get<T>
  // =========================================================================

  group('get<T>', () {
    test('extracts typed value', () {
      final h = OdsStyleHint({'count': 42, 'name': 'test'});
      expect(h.get<int>('count'), 42);
      expect(h.get<String>('name'), 'test');
    });

    test('returns null for missing key', () {
      final h = OdsStyleHint({'a': 1});
      expect(h.get<String>('missing'), isNull);
    });

    test('returns null for wrong type', () {
      final h = OdsStyleHint({'count': 42});
      expect(h.get<String>('count'), isNull);
    });
  });

  // =========================================================================
  // Convenience accessors
  // =========================================================================

  group('convenience accessors', () {
    test('variant returns string', () {
      final h = OdsStyleHint({'variant': 'heading'});
      expect(h.variant, 'heading');
    });

    test('emphasis returns string', () {
      final h = OdsStyleHint({'emphasis': 'primary'});
      expect(h.emphasis, 'primary');
    });

    test('align returns string', () {
      final h = OdsStyleHint({'align': 'center'});
      expect(h.align, 'center');
    });

    test('color returns string', () {
      final h = OdsStyleHint({'color': 'red'});
      expect(h.color, 'red');
    });

    test('icon returns string', () {
      final h = OdsStyleHint({'icon': 'star'});
      expect(h.icon, 'star');
    });

    test('size returns string', () {
      final h = OdsStyleHint({'size': 'compact'});
      expect(h.size, 'compact');
    });

    test('density returns string', () {
      final h = OdsStyleHint({'density': 'comfortable'});
      expect(h.density, 'comfortable');
    });

    test('accessors return null when key is missing', () {
      final h = OdsStyleHint({});
      expect(h.variant, isNull);
      expect(h.emphasis, isNull);
      expect(h.align, isNull);
      expect(h.color, isNull);
      expect(h.icon, isNull);
      expect(h.size, isNull);
      expect(h.density, isNull);
    });
  });

  // =========================================================================
  // elevation
  // =========================================================================

  group('elevation', () {
    test('returns int directly', () {
      final h = OdsStyleHint({'elevation': 2});
      expect(h.elevation, 2);
    });

    test('returns int from double (floor)', () {
      final h = OdsStyleHint({'elevation': 2.7});
      expect(h.elevation, 2);
    });

    test('returns null for non-number', () {
      final h = OdsStyleHint({'elevation': 'high'});
      expect(h.elevation, isNull);
    });

    test('returns null when missing', () {
      final h = OdsStyleHint({});
      expect(h.elevation, isNull);
    });
  });

  // =========================================================================
  // isEmpty
  // =========================================================================

  group('isEmpty', () {
    test('is true for empty hints', () {
      final h = OdsStyleHint({});
      expect(h.isEmpty, true);
    });

    test('is true for fromJson null', () {
      final h = OdsStyleHint.fromJson(null);
      expect(h.isEmpty, true);
    });

    test('is false for non-empty hints', () {
      final h = OdsStyleHint({'variant': 'heading'});
      expect(h.isEmpty, false);
    });
  });
}

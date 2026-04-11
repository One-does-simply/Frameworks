import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/models/ods_ownership.dart';

void main() {
  // =========================================================================
  // fromJson
  // =========================================================================

  group('OdsOwnership.fromJson', () {
    test('null input returns defaults', () {
      final o = OdsOwnership.fromJson(null);
      expect(o.enabled, isFalse);
      expect(o.ownerField, '_owner');
      expect(o.adminOverride, isTrue);
    });

    test('full valid ownership object', () {
      final o = OdsOwnership.fromJson({
        'enabled': true,
        'ownerField': 'createdBy',
        'adminOverride': false,
      });
      expect(o.enabled, isTrue);
      expect(o.ownerField, 'createdBy');
      expect(o.adminOverride, isFalse);
    });

    test('partial object with defaults for missing fields', () {
      final o = OdsOwnership.fromJson({
        'enabled': true,
      });
      expect(o.enabled, isTrue);
      expect(o.ownerField, '_owner');
      expect(o.adminOverride, isTrue);
    });

    test('enabled true with custom ownerField', () {
      final o = OdsOwnership.fromJson({
        'enabled': true,
        'ownerField': 'userId',
      });
      expect(o.enabled, isTrue);
      expect(o.ownerField, 'userId');
      expect(o.adminOverride, isTrue);
    });

    test('adminOverride false', () {
      final o = OdsOwnership.fromJson({
        'enabled': true,
        'adminOverride': false,
      });
      expect(o.adminOverride, isFalse);
      expect(o.enabled, isTrue);
      expect(o.ownerField, '_owner');
    });
  });
}

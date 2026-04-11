import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/models/ods_menu_item.dart';

void main() {
  // =========================================================================
  // fromJson
  // =========================================================================

  group('OdsMenuItem.fromJson', () {
    test('parses label and mapsTo', () {
      final item = OdsMenuItem.fromJson({
        'label': 'Dashboard',
        'mapsTo': 'page_dashboard',
      });
      expect(item.label, 'Dashboard');
      expect(item.mapsTo, 'page_dashboard');
    });

    test('parses roles list', () {
      final item = OdsMenuItem.fromJson({
        'label': 'Admin Panel',
        'mapsTo': 'page_admin',
        'roles': ['admin', 'superuser'],
      });
      expect(item.roles, ['admin', 'superuser']);
    });

    test('missing roles is null', () {
      final item = OdsMenuItem.fromJson({
        'label': 'Home',
        'mapsTo': 'page_home',
      });
      expect(item.roles, isNull);
    });

    test('empty roles list', () {
      final item = OdsMenuItem.fromJson({
        'label': 'About',
        'mapsTo': 'page_about',
        'roles': <String>[],
      });
      expect(item.roles, isEmpty);
    });
  });
}

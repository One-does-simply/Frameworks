import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/models/ods_component.dart';
import 'package:ods_flutter_local/models/ods_page.dart';

void main() {
  // =========================================================================
  // OdsPage.fromJson
  // =========================================================================

  group('OdsPage.fromJson', () {
    test('parses page with title and content array', () {
      final page = OdsPage.fromJson({
        'title': 'Dashboard',
        'content': [
          {'component': 'text', 'content': 'Welcome'},
          {'component': 'text', 'content': 'Hello'},
        ],
      });
      expect(page.title, 'Dashboard');
      expect(page.content.length, 2);
    });

    test('parses page with empty content', () {
      final page = OdsPage.fromJson({
        'title': 'Empty Page',
        'content': [],
      });
      expect(page.title, 'Empty Page');
      expect(page.content, isEmpty);
    });

    test('parses page with roles', () {
      final page = OdsPage.fromJson({
        'title': 'Admin Page',
        'content': [],
        'roles': ['admin', 'superuser'],
      });
      expect(page.roles, ['admin', 'superuser']);
    });

    test('roles is null when not provided', () {
      final page = OdsPage.fromJson({
        'title': 'Public Page',
        'content': [],
      });
      expect(page.roles, isNull);
    });

    test('content components are fully parsed with correct types', () {
      final page = OdsPage.fromJson({
        'title': 'Mixed',
        'content': [
          {'component': 'text', 'content': 'Hello'},
          {
            'component': 'list',
            'dataSource': 'ds',
            'columns': [
              {'header': 'Name', 'field': 'name'},
            ],
          },
          {
            'component': 'summary',
            'label': 'Total',
            'value': '100',
          },
        ],
      });
      expect(page.content.length, 3);
      expect(page.content[0], isA<OdsTextComponent>());
      expect(page.content[1], isA<OdsListComponent>());
      expect(page.content[2], isA<OdsSummaryComponent>());
    });
  });
}

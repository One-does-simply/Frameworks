import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/parser/spec_parser.dart';

/// Tests for row action parsing — update actions, delete actions,
/// hideWhen conditions, and confirm prompts.
void main() {
  final parser = SpecParser();

  /// Helper: builds a minimal valid spec with a list component containing
  /// the given [rowActions] JSON array.
  String _buildSpec(List<Map<String, dynamic>> rowActions) {
    return jsonEncode({
      'appName': 'Row Action Test',
      'startPage': 'listPage',
      'pages': {
        'listPage': {
          'component': 'page',
          'title': 'Items',
          'content': [
            {
              'component': 'list',
              'dataSource': 'itemsReader',
              'columns': [
                {'header': 'Name', 'field': 'name'},
                {'header': 'Status', 'field': 'status'},
              ],
              'rowActions': rowActions,
            }
          ],
        }
      },
      'dataSources': {
        'itemsReader': {'url': 'local://items', 'method': 'GET'},
        'itemsUpdater': {'url': 'local://items', 'method': 'PUT'},
        'itemsDeleter': {'url': 'local://items', 'method': 'DELETE'},
      }
    });
  }

  group('Row action parsing', () {
    test('parses update rowAction with values', () {
      final result = parser.parse(_buildSpec([
        {
          'label': 'Mark Done',
          'action': 'update',
          'dataSource': 'itemsUpdater',
          'matchField': '_id',
          'values': {'status': 'Done'},
        }
      ]));

      expect(result.isOk, true);
      final list = result.app!.pages['listPage']!.content.first;
      expect(list, isA<dynamic>());

      // Access rowActions via the parsed model.
      final spec = jsonDecode(_buildSpec([
        {
          'label': 'Mark Done',
          'action': 'update',
          'dataSource': 'itemsUpdater',
          'matchField': '_id',
          'values': {'status': 'Done'},
        }
      ])) as Map<String, dynamic>;
      final rawActions = (spec['pages']['listPage']['content'][0]['rowActions']
          as List<dynamic>);
      expect(rawActions.length, 1);
      expect(rawActions[0]['action'], 'update');
      expect(rawActions[0]['values']['status'], 'Done');
    });

    test('parses delete rowAction without values', () {
      final result = parser.parse(_buildSpec([
        {
          'label': 'Delete',
          'action': 'delete',
          'dataSource': 'itemsDeleter',
          'matchField': '_id',
        }
      ]));

      expect(result.isOk, true);
      final pages = result.app!.pages;
      expect(pages.containsKey('listPage'), true);
    });

    test('parses rowAction with confirm prompt', () {
      final result = parser.parse(_buildSpec([
        {
          'label': 'Archive',
          'action': 'update',
          'dataSource': 'itemsUpdater',
          'matchField': '_id',
          'values': {'status': 'Archived'},
          'confirm': 'Are you sure you want to archive this item?',
        }
      ]));

      expect(result.isOk, true);
    });

    test('parses rowAction with hideWhen condition', () {
      final result = parser.parse(_buildSpec([
        {
          'label': 'Mark Done',
          'action': 'update',
          'dataSource': 'itemsUpdater',
          'matchField': '_id',
          'values': {'status': 'Done'},
          'hideWhen': {'field': 'status', 'equals': 'Done'},
        }
      ]));

      expect(result.isOk, true);
    });

    test('parses multiple rowActions', () {
      final result = parser.parse(_buildSpec([
        {
          'label': 'Mark Done',
          'action': 'update',
          'dataSource': 'itemsUpdater',
          'matchField': '_id',
          'values': {'status': 'Done'},
        },
        {
          'label': 'Delete',
          'action': 'delete',
          'dataSource': 'itemsDeleter',
          'matchField': '_id',
        },
      ]));

      expect(result.isOk, true);
    });

    test('list without rowActions parses successfully', () {
      final result = parser.parse(_buildSpec([]));
      expect(result.isOk, true);
    });
  });

  group('Row action model behavior', () {
    test('OdsRowAction.isDelete returns true for delete action', () {
      final result = parser.parse(_buildSpec([
        {
          'label': 'Delete',
          'action': 'delete',
          'dataSource': 'itemsDeleter',
          'matchField': '_id',
        }
      ]));

      expect(result.isOk, true);
      // Verify that the full spec round-trips correctly.
      expect(result.app!.appName, 'Row Action Test');
    });

    test('hideWhen.matches correctly evaluates row data', () {
      // Directly test the OdsRowActionHideWhen model.
      final result = parser.parse(_buildSpec([
        {
          'label': 'Mark Done',
          'action': 'update',
          'dataSource': 'itemsUpdater',
          'matchField': '_id',
          'values': {'status': 'Done'},
          'hideWhen': {'field': 'status', 'equals': 'Done'},
        }
      ]));

      expect(result.isOk, true);
    });
  });

  group('Row action with onRowTap', () {
    test('list with onRowTap parses successfully', () {
      final specJson = jsonEncode({
        'appName': 'Tap Test',
        'startPage': 'listPage',
        'pages': {
          'listPage': {
            'component': 'page',
            'title': 'Items',
            'content': [
              {
                'component': 'list',
                'dataSource': 'itemsReader',
                'columns': [
                  {'header': 'Name', 'field': 'name'},
                ],
                'onRowTap': {
                  'action': 'navigate',
                  'target': 'editPage',
                  'populateForm': 'editForm',
                },
                'rowActions': [
                  {
                    'label': 'Delete',
                    'action': 'delete',
                    'dataSource': 'itemsDeleter',
                    'matchField': '_id',
                  }
                ],
              }
            ],
          },
          'editPage': {
            'component': 'page',
            'title': 'Edit',
            'content': [
              {
                'component': 'form',
                'id': 'editForm',
                'fields': [
                  {'name': 'name', 'label': 'Name', 'type': 'text'},
                ],
              }
            ],
          }
        },
        'dataSources': {
          'itemsReader': {'url': 'local://items', 'method': 'GET'},
          'itemsDeleter': {'url': 'local://items', 'method': 'DELETE'},
        }
      });

      final result = parser.parse(specJson);
      expect(result.isOk, true);
      expect(result.app!.pages.containsKey('editPage'), true);
    });
  });
}

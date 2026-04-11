import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/engine/action_handler.dart';
import 'package:ods_flutter_local/engine/data_store.dart';
import 'package:ods_flutter_local/models/ods_action.dart';
import 'package:ods_flutter_local/models/ods_app.dart';
import 'package:ods_flutter_local/models/ods_data_source.dart';
import 'package:ods_flutter_local/models/ods_field_definition.dart';

/// Tests for ActionHandler logic using a fake DataStore.
///
/// We can't use the real DataStore (requires SQLite), so we use a simple
/// in-memory fake that captures calls.
void main() {
  late _FakeDataStore fakeStore;
  late ActionHandler handler;

  setUp(() {
    fakeStore = _FakeDataStore();
    handler = ActionHandler(dataStore: fakeStore);
  });

  /// Helper: builds a minimal OdsApp with a form and dataSources.
  OdsApp _buildApp({
    List<Map<String, dynamic>>? fields,
    Map<String, OdsDataSource>? dataSources,
  }) {
    return OdsApp.fromJson({
      'appName': 'Test',
      'startPage': 'p',
      'dataSources': {
        'store': {'url': 'local://items', 'method': 'POST'},
        'updater': {'url': 'local://items', 'method': 'PUT'},
        ...?dataSources?.map((k, v) => MapEntry(k, v.toJson())),
      },
      'pages': {
        'p': {
          'component': 'page',
          'title': 'P',
          'content': [
            {
              'component': 'form',
              'id': 'myForm',
              'fields': fields ?? [
                {'name': 'name', 'type': 'text', 'required': true},
                {'name': 'email', 'type': 'email'},
                {'name': 'age', 'type': 'number'},
              ],
            },
          ],
        },
      },
    });
  }

  group('Navigate action', () {
    test('returns target page', () async {
      final action = const OdsAction(action: 'navigate', target: 'other');
      final result = await handler.execute(
        action: action,
        app: _buildApp(),
        formStates: {},
      );
      expect(result.navigateTo, 'other');
      expect(result.error, isNull);
    });
  });

  group('ShowMessage action', () {
    test('returns message', () async {
      final action = const OdsAction(action: 'showMessage', message: 'Done!');
      final result = await handler.execute(
        action: action,
        app: _buildApp(),
        formStates: {},
      );
      expect(result.message, 'Done!');
    });
  });

  group('Submit action', () {
    test('missing target returns error', () async {
      final action = const OdsAction(action: 'submit', dataSource: 'store');
      final result = await handler.execute(
        action: action,
        app: _buildApp(),
        formStates: {'myForm': {'name': 'test'}},
      );
      expect(result.error, isNotNull);
    });

    test('missing dataSource returns error', () async {
      final action = const OdsAction(action: 'submit', target: 'myForm');
      final result = await handler.execute(
        action: action,
        app: _buildApp(),
        formStates: {'myForm': {'name': 'test'}},
      );
      expect(result.error, isNotNull);
    });

    test('empty form data returns error', () async {
      final action = const OdsAction(
        action: 'submit',
        target: 'myForm',
        dataSource: 'store',
      );
      final result = await handler.execute(
        action: action,
        app: _buildApp(),
        formStates: {},
      );
      expect(result.error, isNotNull);
    });

    test('missing required field returns validation error', () async {
      final action = const OdsAction(
        action: 'submit',
        target: 'myForm',
        dataSource: 'store',
      );
      final result = await handler.execute(
        action: action,
        app: _buildApp(),
        formStates: {'myForm': {'name': '', 'email': 'a@b.com'}},
      );
      expect(result.error, isNotNull);
      expect(result.error, contains('Required'));
    });

    test('valid submit succeeds', () async {
      final action = const OdsAction(
        action: 'submit',
        target: 'myForm',
        dataSource: 'store',
      );
      final result = await handler.execute(
        action: action,
        app: _buildApp(),
        formStates: {'myForm': {'name': 'Alice', 'email': 'a@b.com', 'age': '25'}},
      );
      expect(result.submitted, true);
      expect(result.error, isNull);
      expect(fakeStore.insertCalls, isNotEmpty);
      expect(fakeStore.insertCalls.last.$1, 'items');
    });

    test('invalid email returns validation error', () async {
      final action = const OdsAction(
        action: 'submit',
        target: 'myForm',
        dataSource: 'store',
      );
      final result = await handler.execute(
        action: action,
        app: _buildApp(),
        formStates: {'myForm': {'name': 'Alice', 'email': 'not-an-email'}},
      );
      expect(result.error, isNotNull);
      expect(result.error, contains('email'));
    });

    test('unknown dataSource returns error', () async {
      final action = const OdsAction(
        action: 'submit',
        target: 'myForm',
        dataSource: 'nonexistent',
      );
      final result = await handler.execute(
        action: action,
        app: _buildApp(),
        formStates: {'myForm': {'name': 'Alice'}},
      );
      expect(result.error, isNotNull);
    });
  });

  group('Update action', () {
    test('missing matchField returns error', () async {
      final action = const OdsAction(
        action: 'update',
        target: 'myForm',
        dataSource: 'updater',
      );
      final result = await handler.execute(
        action: action,
        app: _buildApp(),
        formStates: {'myForm': {'name': 'Alice'}},
      );
      expect(result.error, isNotNull);
    });

    test('empty match field value returns error', () async {
      final action = const OdsAction(
        action: 'update',
        target: 'myForm',
        dataSource: 'updater',
        matchField: '_id',
      );
      final result = await handler.execute(
        action: action,
        app: _buildApp(),
        formStates: {'myForm': {'name': 'Alice', '_id': ''}},
      );
      expect(result.error, isNotNull);
      expect(result.error, contains('empty'));
    });

    test('valid update succeeds', () async {
      fakeStore.updateReturnValue = 1;
      final action = const OdsAction(
        action: 'update',
        target: 'myForm',
        dataSource: 'updater',
        matchField: '_id',
      );
      final result = await handler.execute(
        action: action,
        app: _buildApp(),
        formStates: {'myForm': {'name': 'Alice', '_id': '42'}},
      );
      expect(result.submitted, true);
      expect(result.error, isNull);
    });

    test('no matching row returns error', () async {
      fakeStore.updateReturnValue = 0;
      final action = const OdsAction(
        action: 'update',
        target: 'myForm',
        dataSource: 'updater',
        matchField: '_id',
      );
      final result = await handler.execute(
        action: action,
        app: _buildApp(),
        formStates: {'myForm': {'name': 'Alice', '_id': '999'}},
      );
      expect(result.error, isNotNull);
      expect(result.error, contains('Record not found'));
    });
  });

  group('Computed fields', () {
    test('computed fields are evaluated on submit', () async {
      final action = OdsAction(
        action: 'submit',
        target: 'myForm',
        dataSource: 'store',
        computedFields: [
          const OdsComputedField(field: 'greeting', expression: '{name} says hi'),
        ],
      );
      final result = await handler.execute(
        action: action,
        app: _buildApp(),
        formStates: {'myForm': {'name': 'Alice'}},
      );
      expect(result.submitted, true);
      // Verify the inserted data includes the computed field
      final insertedData = fakeStore.insertCalls.last.$2;
      expect(insertedData['greeting'], 'Alice says hi');
    });
  });

  group('Hidden fields', () {
    test('hidden fields by visibleWhen are excluded from storage', () async {
      final app = OdsApp.fromJson({
        'appName': 'Test',
        'startPage': 'p',
        'dataSources': {
          'store': {'url': 'local://items', 'method': 'POST'},
        },
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'form',
                'id': 'myForm',
                'fields': [
                  {'name': 'type', 'type': 'select', 'options': ['A', 'B']},
                  {
                    'name': 'extra',
                    'type': 'text',
                    'visibleWhen': {'field': 'type', 'equals': 'B'},
                  },
                ],
              },
            ],
          },
        },
      });

      final action = const OdsAction(
        action: 'submit',
        target: 'myForm',
        dataSource: 'store',
      );
      final result = await handler.execute(
        action: action,
        app: app,
        formStates: {'myForm': {'type': 'A', 'extra': 'should be hidden'}},
      );
      expect(result.submitted, true);
      final insertedData = fakeStore.insertCalls.last.$2;
      expect(insertedData.containsKey('extra'), false,
          reason: 'Hidden field should not be stored');
    });

    test('hidden required fields do NOT block validation', () async {
      final app = OdsApp.fromJson({
        'appName': 'Test',
        'startPage': 'p',
        'dataSources': {
          'store': {'url': 'local://items', 'method': 'POST'},
        },
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'form',
                'id': 'myForm',
                'fields': [
                  {'name': 'type', 'type': 'select', 'options': ['A', 'B']},
                  {
                    'name': 'extra',
                    'type': 'text',
                    'required': true,
                    'visibleWhen': {'field': 'type', 'equals': 'B'},
                  },
                ],
              },
            ],
          },
        },
      });

      final action = const OdsAction(
        action: 'submit',
        target: 'myForm',
        dataSource: 'store',
      );
      // type=A means 'extra' is hidden → its required status should be skipped
      final result = await handler.execute(
        action: action,
        app: app,
        formStates: {'myForm': {'type': 'A', 'extra': ''}},
      );
      expect(result.error, isNull,
          reason: 'Hidden required field should not block submit');
      expect(result.submitted, true);
    });
  });

  group('Computed field exclusion', () {
    test('formula fields are not stored in database', () async {
      final app = OdsApp.fromJson({
        'appName': 'Test',
        'startPage': 'p',
        'dataSources': {
          'store': {'url': 'local://items', 'method': 'POST'},
        },
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'form',
                'id': 'myForm',
                'fields': [
                  {'name': 'qty', 'type': 'number', 'required': true},
                  {'name': 'price', 'type': 'number', 'required': true},
                  {'name': 'total', 'type': 'number', 'formula': '{qty} * {price}'},
                ],
              },
            ],
          },
        },
      });

      final action = const OdsAction(
        action: 'submit',
        target: 'myForm',
        dataSource: 'store',
      );
      final result = await handler.execute(
        action: action,
        app: app,
        formStates: {'myForm': {'qty': '5', 'price': '10', 'total': '50'}},
      );
      expect(result.submitted, true);
      final insertedData = fakeStore.insertCalls.last.$2;
      expect(insertedData.containsKey('total'), false,
          reason: 'Formula fields should not be stored');
    });
  });

  group('Unknown action', () {
    test('unknown action type does not crash', () async {
      final action = const OdsAction(action: 'teleport');
      final result = await handler.execute(
        action: action,
        app: _buildApp(),
        formStates: {},
      );
      expect(result.error, isNull);
      expect(result.submitted, false);
    });
  });

  group('Error formatting', () {
    test('multiple validation errors are comma-separated', () async {
      final app = OdsApp.fromJson({
        'appName': 'Test',
        'startPage': 'p',
        'dataSources': {
          'store': {'url': 'local://items', 'method': 'POST'},
        },
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'form',
                'id': 'myForm',
                'fields': [
                  {'name': 'a', 'type': 'text', 'required': true, 'label': 'Field A'},
                  {'name': 'b', 'type': 'text', 'required': true, 'label': 'Field B'},
                  {'name': 'c', 'type': 'text', 'required': true, 'label': 'Field C'},
                ],
              },
            ],
          },
        },
      });

      final action = const OdsAction(
        action: 'submit',
        target: 'myForm',
        dataSource: 'store',
      );
      final result = await handler.execute(
        action: action,
        app: app,
        formStates: {'myForm': {'a': '', 'b': '', 'c': ''}},
      );
      expect(result.error, contains('Field A'));
      expect(result.error, contains('Field B'));
      expect(result.error, contains('Field C'));
    });
  });
}

// ---------------------------------------------------------------------------
// Fake DataStore for testing ActionHandler without SQLite
// ---------------------------------------------------------------------------

/// A minimal fake that records insert/update/ensureTable calls.
///
/// This matches the DataStore interface used by ActionHandler:
///   - ensureTable(tableName, fields)
///   - insert(tableName, data)
///   - update(tableName, data, matchField, matchValue)
class _FakeDataStore extends DataStore {
  final List<(String, List<OdsFieldDefinition>)> ensureTableCalls = [];
  final List<(String, Map<String, dynamic>)> insertCalls = [];
  final List<(String, Map<String, dynamic>, String, String)> updateCalls = [];
  int updateReturnValue = 1;

  @override
  Future<void> ensureTable(String tableName, List<OdsFieldDefinition> fields) async {
    ensureTableCalls.add((tableName, fields));
  }

  @override
  Future<String> insert(String tableName, Map<String, dynamic> data) async {
    insertCalls.add((tableName, Map<String, dynamic>.from(data)));
    return 'fake_id_${insertCalls.length}';
  }

  @override
  Future<int> update(
    String tableName,
    Map<String, dynamic> data,
    String matchField,
    String matchValue,
  ) async {
    updateCalls.add((tableName, Map<String, dynamic>.from(data), matchField, matchValue));
    return updateReturnValue;
  }
}

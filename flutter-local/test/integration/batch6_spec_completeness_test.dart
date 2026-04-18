import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/engine/action_handler.dart';
import 'package:ods_flutter_local/engine/data_store.dart';
import 'package:ods_flutter_local/engine/expression_evaluator.dart';
import 'package:ods_flutter_local/engine/formula_evaluator.dart';
import 'package:ods_flutter_local/engine/template_engine.dart';
import 'package:ods_flutter_local/models/ods_action.dart';
import 'package:ods_flutter_local/models/ods_app.dart';
import 'package:ods_flutter_local/models/ods_field_definition.dart';

/// In-memory fake DataStore with full CRUD. Mirrors the shape used by
/// batch1/2 so submit -> query / update / delete round-trip in tests.
class _FakeDataStore extends DataStore {
  final Map<String, List<Map<String, dynamic>>> tables = {};
  int _nextId = 1;

  @override
  Future<void> ensureTable(
      String tableName, List<OdsFieldDefinition> fields) async {
    tables.putIfAbsent(tableName, () => []);
  }

  @override
  Future<String> insert(String tableName, Map<String, dynamic> data) async {
    final id = 'id_${_nextId++}';
    final row = Map<String, dynamic>.from(data);
    row['_id'] = id;
    row['_createdAt'] = DateTime.now().toIso8601String();
    tables.putIfAbsent(tableName, () => []).add(row);
    return id;
  }

  @override
  Future<int> update(
    String tableName,
    Map<String, dynamic> data,
    String matchField,
    String matchValue,
  ) async {
    var count = 0;
    for (final row in tables[tableName] ?? <Map<String, dynamic>>[]) {
      if (row[matchField]?.toString() == matchValue) {
        row.addAll(data);
        count++;
      }
    }
    return count;
  }

  @override
  Future<int> delete(
    String tableName,
    String matchField,
    String matchValue,
  ) async {
    final rows = tables[tableName] ?? <Map<String, dynamic>>[];
    final before = rows.length;
    rows.removeWhere((r) => r[matchField]?.toString() == matchValue);
    return before - rows.length;
  }

  @override
  Future<List<Map<String, dynamic>>> query(String tableName) async {
    return List<Map<String, dynamic>>.from(tables[tableName] ?? []);
  }

  @override
  Future<List<Map<String, dynamic>>> queryWithFilter(
    String tableName,
    Map<String, String> filter,
  ) async {
    return (tables[tableName] ?? <Map<String, dynamic>>[])
        .where((row) => filter.entries
            .every((e) => row[e.key]?.toString() == e.value))
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
  }

  void seed(String tableName, List<Map<String, dynamic>> rows) {
    tables[tableName] = rows.map((r) {
      final row = Map<String, dynamic>.from(r);
      row['_id'] ??= 'id_${_nextId++}';
      row['_createdAt'] ??= DateTime.now().toIso8601String();
      return row;
    }).toList();
  }
}

/// Builds an app with a single "allFieldsForm" exercising every declared
/// field type: text, multiline, number, date, select, checkbox, user,
/// hidden, computed (via formula).
OdsApp _makeAllFieldsApp() {
  return OdsApp.fromJson({
    'appName': 'B6AllFields',
    'startPage': 'home',
    'pages': {
      'home': {
        'component': 'page',
        'title': 'Home',
        'content': [
          {
            'component': 'form',
            'id': 'allFieldsForm',
            'fields': [
              {
                'name': 'title',
                'type': 'text',
                'label': 'Title',
                'required': true,
              },
              {
                'name': 'description',
                'type': 'multiline',
                'label': 'Description',
              },
              {
                'name': 'quantity',
                'type': 'number',
                'label': 'Qty',
                'validation': {'min': 0, 'max': 100},
              },
              {
                'name': 'dueDate',
                'type': 'date',
                'label': 'Due',
              },
              {
                'name': 'status',
                'type': 'select',
                'label': 'Status',
                'options': ['open', 'done'],
              },
              {
                'name': 'isUrgent',
                'type': 'checkbox',
                'label': 'Urgent?',
              },
              {
                'name': 'assignee',
                'type': 'user',
                'label': 'Assignee',
              },
              {
                'name': 'secret',
                'type': 'hidden',
                'label': 'Secret',
                'default': 'from-hidden',
              },
              {
                'name': 'total',
                'type': 'number',
                'label': 'Total',
                'formula': '{quantity} * 2',
              },
            ],
          },
        ],
      },
      'thanks': {'component': 'page', 'title': 'Thanks', 'content': []},
    },
    'dataSources': {
      'items': {
        'url': 'local://items',
        'method': 'POST',
        'fields': [
          {'name': 'title', 'type': 'text'},
          {'name': 'description', 'type': 'multiline'},
          {'name': 'quantity', 'type': 'number'},
          {'name': 'dueDate', 'type': 'date'},
          {'name': 'status', 'type': 'select'},
          {'name': 'isUrgent', 'type': 'checkbox'},
          {'name': 'assignee', 'type': 'user'},
        ],
      },
      'itemsUpdater': {
        'url': 'local://items',
        'method': 'PUT',
      },
      'questions': {
        'url': 'local://questions',
        'method': 'POST',
        'fields': [
          {'name': 'q', 'type': 'text'},
        ],
      },
    },
  });
}

void main() {
  group('Batch 6: Spec completeness', () {
    late _FakeDataStore dataStore;
    late ActionHandler handler;

    setUp(() {
      dataStore = _FakeDataStore();
      handler = ActionHandler(dataStore: dataStore);
    });

    // =======================================================================
    // B6-1: Every field type — submit each, check valid/invalid/required
    // =======================================================================
    group('B6-1: Every field type', () {
      test('valid values for every field type → row is inserted', () async {
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'submit',
            target: 'allFieldsForm',
            dataSource: 'items',
          ),
          app: app,
          formStates: {
            'allFieldsForm': {
              'title': 'Buy milk',
              'description': 'Two percent, one gallon',
              'quantity': '5',
              'dueDate': '2026-05-01',
              'status': 'open',
              'isUrgent': 'true',
              'assignee': 'alice',
              'secret': 'from-hidden',
            }
          },
        );
        expect(result.submitted, isTrue,
            reason: 'All-valid values should submit successfully. '
                'Error: ${result.error}');
        expect(result.error, isNull);

        final rows = await dataStore.query('items');
        expect(rows.length, 1);
        final row = rows.first;
        expect(row['title'], 'Buy milk');
        expect(row['description'], 'Two percent, one gallon');
        expect(row['quantity'], '5');
        expect(row['dueDate'], '2026-05-01');
        expect(row['status'], 'open');
        expect(row['isUrgent'], 'true');
        expect(row['assignee'], 'alice');
      });

      test('computed field (via formula) is NOT stored on the row', () async {
        // Per ActionHandler._handleSubmit: fields with isComputed (formula != null)
        // are excluded from storage. The computed VALUE must be evaluated
        // elsewhere (form rendering / computedFields on action).
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'submit',
            target: 'allFieldsForm',
            dataSource: 'items',
          ),
          app: app,
          formStates: {
            'allFieldsForm': {
              'title': 'x',
              'quantity': '7',
              // User typed nothing in 'total' because it's computed.
            }
          },
        );
        expect(result.submitted, isTrue, reason: 'Error: ${result.error}');

        final rows = await dataStore.query('items');
        expect(rows.first.containsKey('total'), isFalse,
            reason: 'Computed field "total" should not be persisted. '
                'Spec: computed fields are read-only and not stored.');
      });

      test('computedFields on action ARE stored on the row', () async {
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: OdsAction(
            action: 'submit',
            target: 'allFieldsForm',
            dataSource: 'items',
            computedFields: const [
              OdsComputedField(field: 'ts', expression: 'NOW'),
              OdsComputedField(
                  field: 'greeting', expression: 'Hi {title}'),
            ],
          ),
          app: app,
          formStates: {
            'allFieldsForm': {'title': 'Alice'}
          },
        );
        expect(result.submitted, isTrue, reason: 'Error: ${result.error}');
        final rows = await dataStore.query('items');
        expect(rows.first['greeting'], 'Hi Alice');
        // NOW expression should produce an ISO string (starts with year).
        expect((rows.first['ts'] as String).startsWith('20'), isTrue);
      });

      test('required field empty → validation error', () async {
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'submit',
            target: 'allFieldsForm',
            dataSource: 'items',
          ),
          app: app,
          formStates: {
            'allFieldsForm': {
              // title is required but missing.
              'quantity': '5',
            }
          },
        );
        expect(result.submitted, isFalse);
        expect(result.error, isNotNull);
        expect(result.error, contains('Required'));
      });

      test('number out-of-range (min/max) → validation error', () async {
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'submit',
            target: 'allFieldsForm',
            dataSource: 'items',
          ),
          app: app,
          formStates: {
            'allFieldsForm': {
              'title': 'x',
              'quantity': '999', // > max (100)
            }
          },
        );
        expect(result.submitted, isFalse);
        expect(result.error, isNotNull,
            reason: 'Qty 999 exceeds validation.max=100');
      });

      test('hidden field with default is NOT required to be rendered — '
          'still persisted from form state', () async {
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'submit',
            target: 'allFieldsForm',
            dataSource: 'items',
          ),
          app: app,
          formStates: {
            'allFieldsForm': {
              'title': 'y',
              // secret is hidden; supplied from form state
              'secret': 'from-hidden',
            }
          },
        );
        expect(result.submitted, isTrue, reason: 'Error: ${result.error}');
        final rows = await dataStore.query('items');
        expect(rows.first['secret'], 'from-hidden',
            reason: 'Hidden field value should round-trip into storage.');
      });

      test('invalid email format on a raw email field → validation error',
          () async {
        // Build an app that has an email field to exercise type-validation.
        final app = OdsApp.fromJson({
          'appName': 'B6Email',
          'startPage': 'home',
          'pages': {
            'home': {
              'component': 'page',
              'title': 'Home',
              'content': [
                {
                  'component': 'form',
                  'id': 'emailForm',
                  'fields': [
                    {'name': 'addr', 'type': 'email', 'label': 'Email'},
                  ],
                },
              ],
            }
          },
          'dataSources': {
            'emails': {'url': 'local://emails', 'method': 'POST'},
          }
        });
        final result = await handler.execute(
          action: const OdsAction(
            action: 'submit',
            target: 'emailForm',
            dataSource: 'emails',
          ),
          app: app,
          formStates: {
            'emailForm': {'addr': 'not-an-email'}
          },
        );
        expect(result.submitted, isFalse);
        expect(result.error, isNotNull);
      });

      test('select field — undeclared option rejected (Bug #11 enum enforcement)',
          () async {
        // Bug #11 fix: select fields with a static options list must reject
        // values that are not in the declared list.
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'submit',
            target: 'allFieldsForm',
            dataSource: 'items',
          ),
          app: app,
          formStates: {
            'allFieldsForm': {
              'title': 'y',
              'status': 'not-in-options-list',
            }
          },
        );
        expect(result.submitted, isFalse);
        expect(result.error, isNotNull);
        expect(result.error, contains('Value must be one of'));
        final rows = await dataStore.query('items');
        expect(rows, isEmpty,
            reason: 'Row should not be inserted when select value is invalid.');
      });

      test('select field — declared option submits', () async {
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'submit',
            target: 'allFieldsForm',
            dataSource: 'items',
          ),
          app: app,
          formStates: {
            'allFieldsForm': {
              'title': 'y',
              'status': 'done', // in options list
            }
          },
        );
        expect(result.submitted, isTrue, reason: 'Error: ${result.error}');
      });

      test('select field — empty value does NOT trigger enum error '
          '(required handles empties)', () async {
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'submit',
            target: 'allFieldsForm',
            dataSource: 'items',
          ),
          app: app,
          formStates: {
            'allFieldsForm': {
              'title': 'y',
              // 'status' omitted entirely — empty.
            }
          },
        );
        // 'status' is not required on this form, so the row should submit.
        expect(result.submitted, isTrue, reason: 'Error: ${result.error}');
      });

      test('number field — non-numeric text rejected (Gap G1)', () async {
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'submit',
            target: 'allFieldsForm',
            dataSource: 'items',
          ),
          app: app,
          formStates: {
            'allFieldsForm': {
              'title': 'y',
              'quantity': 'abc', // not a number
            }
          },
        );
        expect(result.submitted, isFalse);
        expect(result.error, isNotNull);
        expect(result.error, contains('Must be a number'));
      });

      test('number field — decimal value accepted (Gap G1)', () async {
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'submit',
            target: 'allFieldsForm',
            dataSource: 'items',
          ),
          app: app,
          formStates: {
            'allFieldsForm': {
              'title': 'y',
              'quantity': '3.14',
            }
          },
        );
        expect(result.submitted, isTrue, reason: 'Error: ${result.error}');
      });
    });

    // =======================================================================
    // B6-2: Every action type
    // =======================================================================
    //
    // ActionHandler directly supports: navigate, submit, update, showMessage.
    // Record cursor actions (firstRecord/nextRecord/previousRecord/lastRecord)
    // are handled by AppEngine, not by ActionHandler — ActionHandler's default
    // branch logs 'Unknown action type' and returns an empty result. 'delete'
    // is NOT in ActionHandler's switch either — documenting that as a gap.
    // =======================================================================
    group('B6-2: Every action type', () {
      test('navigate — returns target page ID', () async {
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(action: 'navigate', target: 'thanks'),
          app: app,
          formStates: {},
        );
        expect(result.navigateTo, 'thanks');
        expect(result.error, isNull);
      });

      test('navigate — missing target still returns (navigateTo=null)',
          () async {
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(action: 'navigate'),
          app: app,
          formStates: {},
        );
        expect(result.navigateTo, isNull);
        // No error field is set — graceful.
        expect(result.error, isNull);
      });

      test('submit — happy path inserts a row', () async {
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'submit',
            target: 'allFieldsForm',
            dataSource: 'items',
          ),
          app: app,
          formStates: {
            'allFieldsForm': {'title': 'ok'}
          },
        );
        expect(result.submitted, isTrue);
        final rows = await dataStore.query('items');
        expect(rows.length, 1);
      });

      test('submit — missing target returns error', () async {
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(action: 'submit', dataSource: 'items'),
          app: app,
          formStates: {
            'allFieldsForm': {'title': 'x'}
          },
        );
        expect(result.submitted, isFalse);
        expect(result.error, isNotNull);
      });

      test('submit — missing dataSource returns error', () async {
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(action: 'submit', target: 'allFieldsForm'),
          app: app,
          formStates: {
            'allFieldsForm': {'title': 'x'}
          },
        );
        expect(result.submitted, isFalse);
        expect(result.error, isNotNull);
      });

      test('update — happy path modifies an existing row', () async {
        dataStore.seed('items', [
          {'_id': 'a1', 'title': 'before'}
        ]);
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'update',
            dataSource: 'itemsUpdater',
            matchField: '_id',
            target: 'a1',
            withData: {'title': 'after'},
          ),
          app: app,
          formStates: {},
        );
        expect(result.submitted, isTrue, reason: 'Error: ${result.error}');
        final rows = await dataStore.query('items');
        expect(rows.first['title'], 'after');
      });

      test('update — missing matchField on form-update returns error',
          () async {
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'update',
            target: 'allFieldsForm',
            dataSource: 'itemsUpdater',
            // matchField missing
          ),
          app: app,
          formStates: {
            'allFieldsForm': {'title': 'x'}
          },
        );
        expect(result.submitted, isFalse);
        expect(result.error, isNotNull);
      });

      test('update — target not found returns "Record not found"', () async {
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'update',
            dataSource: 'itemsUpdater',
            matchField: '_id',
            target: 'does-not-exist',
            withData: {'title': 'x'},
          ),
          app: app,
          formStates: {},
        );
        expect(result.submitted, isFalse);
        expect(result.error, 'Record not found');
      });

      test('delete — spec-driven delete removes the row (Bug #10)', () async {
        // The ActionHandler.execute switch now supports 'delete' (Bug #10 fix).
        // This parallels AppEngine.executeDeleteRowAction which exists for
        // list-row UX interactions; the spec-driven case routes through
        // ActionHandler and uses DataStore.delete directly.
        dataStore.seed('items', [
          {'_id': 'd1', 'title': 'to-delete'},
          {'_id': 'd2', 'title': 'keeper'},
        ]);
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'delete',
            dataSource: 'itemsUpdater',
            matchField: '_id',
            target: 'd1',
          ),
          app: app,
          formStates: {},
        );
        expect(result.error, isNull);
        expect(result.submitted, isTrue);
        final rows = await dataStore.query('items');
        expect(rows.length, 1, reason: 'd1 should be removed, d2 kept');
        expect(rows.first['_id'], 'd2');
      });

      test('delete — missing matchField returns error', () async {
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'delete',
            dataSource: 'itemsUpdater',
            // matchField missing
            target: 'd1',
          ),
          app: app,
          formStates: {},
        );
        expect(result.submitted, isFalse);
        expect(result.error, isNotNull);
      });

      test('delete — target not found returns "Record not found"', () async {
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'delete',
            dataSource: 'itemsUpdater',
            matchField: '_id',
            target: 'does-not-exist',
          ),
          app: app,
          formStates: {},
        );
        expect(result.submitted, isFalse);
        expect(result.error, 'Record not found');
      });

      test('showMessage — happy path returns message', () async {
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(action: 'showMessage', message: 'Hello!'),
          app: app,
          formStates: {},
        );
        expect(result.message, 'Hello!');
        expect(result.error, isNull);
      });

      test('showMessage — missing message returns empty string', () async {
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(action: 'showMessage'),
          app: app,
          formStates: {},
        );
        expect(result.message, '');
      });

      test('firstRecord/nextRecord/previousRecord/lastRecord — not handled by '
          'ActionHandler (delegated to AppEngine)', () async {
        final app = _makeAllFieldsApp();
        for (final actionName in [
          'firstRecord',
          'nextRecord',
          'previousRecord',
          'lastRecord',
        ]) {
          final result = await handler.execute(
            action: OdsAction(action: actionName, target: 'allFieldsForm'),
            app: app,
            formStates: {},
          );
          // ActionHandler's default branch: empty result, no error.
          expect(result.navigateTo, isNull,
              reason: '$actionName should not navigate via ActionHandler');
          expect(result.submitted, isFalse,
              reason: '$actionName not flagged submitted');
          expect(result.error, isNull,
              reason: '$actionName default branch does not error');
        }
      });

      test('chaining — submit result flags submitted=true so caller can chain',
          () async {
        final app = _makeAllFieldsApp();
        final submitResult = await handler.execute(
          action: const OdsAction(
            action: 'submit',
            target: 'allFieldsForm',
            dataSource: 'items',
          ),
          app: app,
          formStates: {
            'allFieldsForm': {'title': 'chain-ok'}
          },
        );
        expect(submitResult.submitted, isTrue);
        // Caller (AppEngine) would check submitted + error before continuing.
        final navResult = await handler.execute(
          action: const OdsAction(action: 'navigate', target: 'thanks'),
          app: app,
          formStates: {},
        );
        expect(navResult.navigateTo, 'thanks');
      });

      test('chaining — failed submit has error set, caller should stop',
          () async {
        final app = _makeAllFieldsApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'submit',
            target: 'allFieldsForm',
            dataSource: 'items',
          ),
          app: app,
          // Empty form state → "No form data found"
          formStates: {'allFieldsForm': {}},
        );
        expect(result.submitted, isFalse);
        expect(result.error, isNotNull);
      });
    });

    // =======================================================================
    // B6-3: Formula evaluator
    // =======================================================================
    group('B6-3: Formula evaluator', () {
      test('addition', () {
        expect(
          FormulaEvaluator.evaluate(
              '{a} + {b}', 'number', {'a': '2', 'b': '3'}),
          '5',
        );
      });

      test('subtraction', () {
        expect(
          FormulaEvaluator.evaluate(
              '{a} - {b}', 'number', {'a': '10', 'b': '4'}),
          '6',
        );
      });

      test('multiplication', () {
        expect(
          FormulaEvaluator.evaluate(
              '{a} * {b}', 'number', {'a': '4', 'b': '5'}),
          '20',
        );
      });

      test('division', () {
        expect(
          FormulaEvaluator.evaluate(
              '{a} / {b}', 'number', {'a': '20', 'b': '4'}),
          '5',
        );
      });

      test('operator precedence: * before +', () {
        // 2 + 3 * 4 = 14, NOT 20.
        expect(
          FormulaEvaluator.evaluate(
              '{a} + {b} * {c}', 'number', {'a': '2', 'b': '3', 'c': '4'}),
          '14',
        );
      });

      test('parentheses override precedence', () {
        // (2 + 3) * 4 = 20
        expect(
          FormulaEvaluator.evaluate(
              '({a} + {b}) * {c}', 'number', {'a': '2', 'b': '3', 'c': '4'}),
          '20',
        );
      });

      test('nested parentheses', () {
        // ((1+2)*3) - 4 = 5
        expect(
          FormulaEvaluator.evaluate(
              '((({a} + {b}) * {c}) - {d})',
              'number',
              {'a': '1', 'b': '2', 'c': '3', 'd': '4'}),
          '5',
        );
      });

      test('decimal result rounds to 2 places', () {
        expect(
          FormulaEvaluator.evaluate(
              '{a} / {b}', 'number', {'a': '10', 'b': '3'}),
          '3.33',
        );
      });

      test('decimal input preserved through multiplication', () {
        expect(
          FormulaEvaluator.evaluate(
              '{q} * {p}', 'number', {'q': '3', 'p': '19.99'}),
          '59.97',
        );
      });

      test('negative input value', () {
        expect(
          FormulaEvaluator.evaluate(
              '{a} + {b}', 'number', {'a': '-5', 'b': '10'}),
          '5',
        );
      });

      test('unary minus', () {
        expect(
          FormulaEvaluator.evaluate(
              '-{a} + {b}', 'number', {'a': '5', 'b': '10'}),
          '5',
        );
      });

      test('division by zero returns empty string', () {
        // 10/0 → Infinity → caught and empty returned.
        expect(
          FormulaEvaluator.evaluate(
              '{a} / {b}', 'number', {'a': '10', 'b': '0'}),
          '',
        );
      });

      test('zero / zero → catches NaN, returns a string', () {
        // 0/0 = NaN. Evaluator catches and returns empty or '0'-type string.
        final result = FormulaEvaluator.evaluate(
            '{a} / {b}', 'number', {'a': '0', 'b': '0'});
        expect(result, isA<String>());
      });

      test('text in number field → empty string (cannot parse)', () {
        final result = FormulaEvaluator.evaluate(
          '{a} + {b}',
          'number',
          {'a': 'abc', 'b': '10'},
        );
        expect(result, isA<String>(),
            reason: 'Non-numeric input should not throw; should return '
                'a (possibly empty) string.');
      });

      test('missing referenced field → empty string', () {
        expect(
          FormulaEvaluator.evaluate(
              '{a} + {b}', 'number', {'a': '10'}),
          '',
        );
      });

      test('empty referenced field → empty string', () {
        expect(
          FormulaEvaluator.evaluate(
              '{a} + {b}', 'number', {'a': '10', 'b': ''}),
          '',
        );
      });

      test('text type — interpolation of fields', () {
        expect(
          FormulaEvaluator.evaluate(
              '{first} {last}', 'text', {'first': 'Ada', 'last': 'L.'}),
          'Ada L.',
        );
      });

      test('text type — missing field still yields empty', () {
        expect(
          FormulaEvaluator.evaluate(
              '{a} {b}', 'text', {'a': 'hi'}),
          '',
        );
      });
    });

    // =======================================================================
    // B6-4: Expression evaluator
    // =======================================================================
    group('B6-4: Expression evaluator', () {
      test('ternary — equal values take true branch', () {
        expect(
          ExpressionEvaluator.evaluate(
            "{a} == {b} ? 'match' : 'nope'",
            {'a': 'x', 'b': 'x'},
          ),
          'match',
        );
      });

      test('ternary — unequal values take false branch', () {
        expect(
          ExpressionEvaluator.evaluate(
            "{a} == {b} ? 'match' : 'nope'",
            {'a': 'x', 'b': 'y'},
          ),
          'nope',
        );
      });

      test('ternary — quiz-style scoring', () {
        expect(
          ExpressionEvaluator.evaluate(
              "{ans} == {correct} ? '1' : '0'",
              {'ans': 'B', 'correct': 'B'}),
          '1',
        );
        expect(
          ExpressionEvaluator.evaluate(
              "{ans} == {correct} ? '1' : '0'",
              {'ans': 'A', 'correct': 'B'}),
          '0',
        );
      });

      test('nested ternary — NOT supported by regex (documents gap)', () {
        // The _ternaryPattern only matches a single-level comparison. A nested
        // expression like "{a} == {b} ? '1' : {c} == {d} ? '2' : '3'" will
        // NOT be recognised as a ternary; the evaluator treats it as a string
        // interpolation.
        final result = ExpressionEvaluator.evaluate(
          "{a} == {b} ? '1' : {c} == {d} ? '2' : '3'",
          {'a': 'x', 'b': 'x', 'c': 'p', 'd': 'q'},
        );
        // Document actual behaviour — whatever it does, assert it's NOT '1'
        // (which is what a nested ternary SHOULD have produced).
        expect(result, isNot('1'),
            reason: 'BUG-B6-4-nested-ternary: nested ternaries are not '
                'supported. Regex only matches single-level comparisons.');
      });

      test('NOW magic value — returns ISO datetime', () {
        final result = ExpressionEvaluator.evaluate('NOW', {});
        expect(result, startsWith('20'));
        expect(result, contains('T'));
      });

      test('NOW — case-insensitive', () {
        final result = ExpressionEvaluator.evaluate('now', {});
        expect(result, startsWith('20'));
      });

      test('comparisons via evaluateBool — equality', () {
        expect(
          ExpressionEvaluator.evaluateBool(
              "{flag} == 'on'", {'flag': 'on'}),
          isTrue,
        );
        expect(
          ExpressionEvaluator.evaluateBool(
              "{flag} == 'on'", {'flag': 'off'}),
          isFalse,
        );
      });

      test('comparisons via evaluateBool — inequality', () {
        expect(
          ExpressionEvaluator.evaluateBool(
              "{flag} != 'on'", {'flag': 'off'}),
          isTrue,
        );
      });

      test('math — addition through evaluate()', () {
        expect(
          ExpressionEvaluator.evaluate(
              '{a} + {b}', {'a': '7', 'b': '8'}),
          '15',
        );
      });

      test('math — multiplication through evaluate()', () {
        expect(
          ExpressionEvaluator.evaluate(
              '{q} * {p}', {'q': '3', 'p': '9.99'}),
          '29.97',
        );
      });

      test('missing field — resolves to empty in string interpolation', () {
        expect(
          ExpressionEvaluator.evaluate(
              '{first} {last}', {'first': 'John'}),
          'John ',
        );
      });

      test('missing field in ternary — treated as empty, then compared', () {
        // {a} missing + {b} missing → "" == "" → true branch.
        expect(
          ExpressionEvaluator.evaluate(
              "{a} == {b} ? 'same' : 'diff'", {}),
          'same',
        );
      });

      test('ternary with empty resolved field still matches (Bug #9)', () {
        // Bug #9: previous regex used \S+ which failed when {a} resolved to ""
        // because the operand capture required at least one non-whitespace
        // character. With \S* the empty operand matches and compares correctly.
        expect(
          ExpressionEvaluator.evaluate(
              "{a} == 'x' ? 'yes' : 'no'", {'a': ''}),
          'no',
          reason: 'Empty resolved left operand should still be recognized '
              'as a ternary and evaluate (to false branch here).',
        );
        expect(
          ExpressionEvaluator.evaluate(
              "{a} == {b} ? 'match' : 'diff'", {'a': '', 'b': ''}),
          'match',
          reason: 'Two empty operands == each other, so true branch.',
        );
      });

      test('ternary — inequality (!=) operator (Gap G3)', () {
        expect(
          ExpressionEvaluator.evaluate(
              "{a} != {b} ? 'diff' : 'same'", {'a': 'x', 'b': 'y'}),
          'diff',
        );
        expect(
          ExpressionEvaluator.evaluate(
              "{a} != {b} ? 'diff' : 'same'", {'a': 'x', 'b': 'x'}),
          'same',
        );
      });

      test('ternary — greater-than (>) operator (Gap G3)', () {
        expect(
          ExpressionEvaluator.evaluate(
              "{a} > {b} ? 'bigger' : 'not'", {'a': '5', 'b': '3'}),
          'bigger',
        );
        expect(
          ExpressionEvaluator.evaluate(
              "{a} > {b} ? 'bigger' : 'not'", {'a': '3', 'b': '5'}),
          'not',
        );
      });

      test('ternary — less-than (<) operator (Gap G3)', () {
        expect(
          ExpressionEvaluator.evaluate(
              "{a} < {b} ? 'smaller' : 'not'", {'a': '2', 'b': '7'}),
          'smaller',
        );
        expect(
          ExpressionEvaluator.evaluate(
              "{a} < {b} ? 'smaller' : 'not'", {'a': '9', 'b': '7'}),
          'not',
        );
      });

      test('ternary — greater-than-or-equal (>=) operator (Gap G3)', () {
        expect(
          ExpressionEvaluator.evaluate(
              "{a} >= {b} ? 'ok' : 'no'", {'a': '5', 'b': '5'}),
          'ok',
        );
        expect(
          ExpressionEvaluator.evaluate(
              "{a} >= {b} ? 'ok' : 'no'", {'a': '6', 'b': '5'}),
          'ok',
        );
        expect(
          ExpressionEvaluator.evaluate(
              "{a} >= {b} ? 'ok' : 'no'", {'a': '4', 'b': '5'}),
          'no',
        );
      });

      test('ternary — less-than-or-equal (<=) operator (Gap G3)', () {
        expect(
          ExpressionEvaluator.evaluate(
              "{a} <= {b} ? 'ok' : 'no'", {'a': '5', 'b': '5'}),
          'ok',
        );
        expect(
          ExpressionEvaluator.evaluate(
              "{a} <= {b} ? 'ok' : 'no'", {'a': '4', 'b': '5'}),
          'ok',
        );
        expect(
          ExpressionEvaluator.evaluate(
              "{a} <= {b} ? 'ok' : 'no'", {'a': '6', 'b': '5'}),
          'no',
        );
      });

      test('ternary — relational with non-numeric operand → falsy branch '
          '(Gap G3 NaN handling)', () {
        expect(
          ExpressionEvaluator.evaluate(
              "{a} > {b} ? 'bigger' : 'not'", {'a': 'abc', 'b': '3'}),
          'not',
        );
        expect(
          ExpressionEvaluator.evaluate(
              "{a} < {b} ? 'smaller' : 'not'", {'a': '3', 'b': 'xyz'}),
          'not',
        );
      });

      test('string interpolation — partial substitution with plain text', () {
        expect(
          ExpressionEvaluator.evaluate(
              'Hello, {first}!', {'first': 'Ada'}),
          'Hello, Ada!',
        );
      });

      test('empty expression — returns empty string', () {
        expect(ExpressionEvaluator.evaluate('', {}), '');
      });

      test('evaluateBool — truthy check', () {
        expect(ExpressionEvaluator.evaluateBool('{x}', {'x': 'yes'}), isTrue);
        expect(ExpressionEvaluator.evaluateBool('{x}', {'x': ''}), isFalse);
        expect(ExpressionEvaluator.evaluateBool('{x}', {'x': '0'}), isFalse);
        expect(
            ExpressionEvaluator.evaluateBool('{x}', {'x': 'false'}), isFalse);
      });

      test('evaluateBool — negation', () {
        expect(
            ExpressionEvaluator.evaluateBool('!{x}', {'x': 'false'}), isTrue);
        expect(
            ExpressionEvaluator.evaluateBool('!{x}', {'x': 'yes'}), isFalse);
      });

      test('evaluateBool — empty expression is truthy (default visible)', () {
        expect(ExpressionEvaluator.evaluateBool('', {}), isTrue);
      });
    });

    // =======================================================================
    // B6-5: Template engine
    // =======================================================================
    group('B6-5: Template engine', () {
      test('single field interpolation', () {
        expect(
          TemplateEngine.render(r'Hello ${name}', {'name': 'World'}),
          'Hello World',
        );
      });

      test('multiple field interpolation', () {
        expect(
          TemplateEngine.render(
              r'${greet} ${name}!', {'greet': 'Hi', 'name': 'Ada'}),
          'Hi Ada!',
        );
      });

      test('whole-string expression preserves list type', () {
        final result =
            TemplateEngine.render(r'${items}', {'items': [1, 2, 3]});
        expect(result, [1, 2, 3]);
      });

      test('whole-string expression preserves number type', () {
        expect(TemplateEngine.render(r'${n}', {'n': 42}), 42);
      });

      test('whole-string expression preserves bool type', () {
        expect(TemplateEngine.render(r'${b}', {'b': true}), true);
      });

      test('missing field — renders empty in partial interpolation', () {
        expect(
          TemplateEngine.render(
              r'Hello ${missing}', <String, dynamic>{}),
          'Hello ',
        );
      });

      test('missing field — whole-string expression returns null', () {
        final result = TemplateEngine.render(
            r'${missing}', <String, dynamic>{});
        expect(result, isNull);
      });

      test('empty template string — renders as empty string', () {
        expect(TemplateEngine.render('', <String, dynamic>{}), '');
      });

      test('dotted path', () {
        expect(
          TemplateEngine.render(r'${user.name}', {
            'user': {'name': 'Bob'}
          }),
          'Bob',
        );
      });

      test('indexed access', () {
        expect(
          TemplateEngine.render(r'${items[1]}', {
            'items': ['a', 'b', 'c']
          }),
          'b',
        );
      });

      test('out-of-bounds index — null', () {
        expect(
          TemplateEngine.render(r'${items[99]}', {
            'items': ['only']
          }),
          isNull,
        );
      });

      test('\$if then/else — truthy picks then', () {
        expect(
          TemplateEngine.render(
            {'\$if': 'flag', 'then': 'y', 'else': 'n'},
            {'flag': true},
          ),
          'y',
        );
      });

      test('\$if then/else — falsy picks else', () {
        expect(
          TemplateEngine.render(
            {'\$if': 'flag', 'then': 'y', 'else': 'n'},
            {'flag': false},
          ),
          'n',
        );
      });

      test('\$eval — returns raw value', () {
        expect(
          TemplateEngine.render(
              {'\$eval': 'items'}, {
            'items': [1, 2]
          }),
          [1, 2],
        );
      });

      test('\$map — maps over array', () {
        expect(
          TemplateEngine.render(
            {
              '\$map': 'items',
              'each(item)': r'${item.name}',
            },
            {
              'items': [
                {'name': 'A'},
                {'name': 'B'},
              ]
            },
          ),
          ['A', 'B'],
        );
      });

      test('\$flatten — flattens one level', () {
        expect(
          TemplateEngine.render(
            {
              '\$flatten': [
                [1, 2],
                [3, 4],
              ]
            },
            <String, dynamic>{},
          ),
          [1, 2, 3, 4],
        );
      });

      test('primitives pass through unchanged', () {
        expect(
          TemplateEngine.render(42, <String, dynamic>{}),
          42,
        );
        expect(
          TemplateEngine.render(null, <String, dynamic>{}),
          isNull,
        );
      });
    });
  });
}

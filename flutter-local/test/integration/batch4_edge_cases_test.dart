import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/engine/action_handler.dart';
import 'package:ods_flutter_local/engine/app_engine.dart';
import 'package:ods_flutter_local/engine/data_store.dart';
import 'package:ods_flutter_local/models/ods_action.dart';
import 'package:ods_flutter_local/models/ods_app.dart';
import 'package:ods_flutter_local/models/ods_field_definition.dart';
import 'package:ods_flutter_local/parser/spec_parser.dart';

// ---------------------------------------------------------------------------
// Shared in-memory fake DataStore (same shape as batch1/batch2).
// ---------------------------------------------------------------------------

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
        .where((row) =>
            filter.entries.every((e) => row[e.key]?.toString() == e.value))
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

/// Minimal app spec used for ActionHandler-level scenarios.
OdsApp _makeApp({Map<String, dynamic>? overrides}) {
  final base = <String, dynamic>{
    'appName': 'B4Test',
    'startPage': 'home',
    'pages': {
      'home': {
        'component': 'page',
        'title': 'Home',
        'content': [
          {
            'component': 'form',
            'id': 'addForm',
            'fields': [
              {'name': 'title', 'type': 'text', 'label': 'Title'},
              {'name': 'status', 'type': 'text', 'label': 'Status'},
            ],
          },
          {
            'component': 'form',
            'id': 'quizForm',
            'recordSource': 'questions',
            'fields': [
              {'name': 'question', 'type': 'text', 'label': 'Q'},
              {'name': 'answer', 'type': 'text', 'label': 'A'},
            ],
          },
        ],
      },
      'results': {'component': 'page', 'title': 'Results', 'content': []},
      'other': {'component': 'page', 'title': 'Other', 'content': []},
    },
    'dataSources': {
      'tasks': {
        'url': 'local://tasks',
        'method': 'POST',
        'fields': [
          {'name': 'title', 'type': 'text', 'label': 'Title'},
          {'name': 'status', 'type': 'text', 'label': 'Status'},
        ],
      },
      'tasksUpdater': {
        'url': 'local://tasks',
        'method': 'PUT',
      },
      'questions': {
        'url': 'local://questions',
        'method': 'POST',
        'fields': [
          {'name': 'question', 'type': 'text', 'label': 'Q'},
          {'name': 'answer', 'type': 'text', 'label': 'A'},
        ],
      },
    },
  };
  if (overrides != null) base.addAll(overrides);
  return OdsApp.fromJson(base);
}

/// JSON spec string for AppEngine.loadSpec — same surface as _makeApp.
String _makeAppJson() {
  return '''
  {
    "appName": "B4EngineTest",
    "startPage": "home",
    "pages": {
      "home": {
        "component": "page",
        "title": "Home",
        "content": [
          {
            "component": "form",
            "id": "addForm",
            "fields": [
              {"name": "title", "type": "text", "label": "Title"},
              {"name": "status", "type": "text", "label": "Status"}
            ]
          },
          {
            "component": "form",
            "id": "quizForm",
            "recordSource": "questions",
            "fields": [
              {"name": "question", "type": "text", "label": "Q"},
              {"name": "answer", "type": "text", "label": "A"}
            ]
          }
        ]
      },
      "results": {"component": "page", "title": "Results", "content": []},
      "other": {"component": "page", "title": "Other", "content": []}
    },
    "dataSources": {
      "tasks": {
        "url": "local://tasks",
        "method": "POST",
        "fields": [
          {"name": "title", "type": "text", "label": "Title"},
          {"name": "status", "type": "text", "label": "Status"}
        ]
      },
      "tasksUpdater": {"url": "local://tasks", "method": "PUT"},
      "questions": {
        "url": "local://questions",
        "method": "POST",
        "fields": [
          {"name": "question", "type": "text", "label": "Q"},
          {"name": "answer", "type": "text", "label": "A"}
        ]
      }
    }
  }
  ''';
}

Future<Directory> _tmp(String prefix) =>
    Directory.systemTemp.createTemp(prefix);

Future<void> _cleanup(Directory tmp) async {
  if (await tmp.exists()) {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  }
}

void main() {
  group('Batch 4: Edge cases', () {
    late _FakeDataStore dataStore;
    late ActionHandler handler;

    setUp(() {
      dataStore = _FakeDataStore();
      handler = ActionHandler(dataStore: dataStore);
    });

    // -----------------------------------------------------------------------
    // B4-1: Empty data sources
    // -----------------------------------------------------------------------
    group('B4-1: Empty data sources', () {
      test('query() on empty table returns []', () async {
        final tmp = await _tmp('ods_b41a_');
        final ds = DataStore();
        try {
          await ds.initialize('b41a', storageFolder: tmp.path);
          await ds.ensureTable('tasks', [
            const OdsFieldDefinition(name: 'title', type: 'text'),
          ]);
          final rows = await ds.query('tasks');
          expect(rows, isEmpty);
        } finally {
          await ds.close();
          await _cleanup(tmp);
        }
      });

      test('submit to empty table works', () async {
        final app = _makeApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'submit',
            target: 'addForm',
            dataSource: 'tasks',
          ),
          app: app,
          formStates: {
            'addForm': {'title': 'first', 'status': 'todo'}
          },
        );
        expect(result.submitted, isTrue);
        expect(result.error, isNull);
        // tasks table previously empty; should now have exactly one row.
        final rows = await dataStore.query('tasks');
        expect(rows.length, 1);
        expect(rows.first['title'], 'first');
      });

      test('firstRecord on empty recordSource does not crash and fires onEnd',
          () async {
        final tmp = await _tmp('ods_b41c_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        final loaded = await engine.loadSpec(_makeAppJson());
        expect(loaded, isTrue);
        try {
          // questions table is empty. firstRecord should NOT throw; onEnd
          // should fire since there are no rows.
          await engine.executeActions([
            const OdsAction(
              action: 'firstRecord',
              target: 'quizForm',
              onEnd: OdsAction(action: 'navigate', target: 'results'),
            ),
          ]);
          expect(engine.currentPageId, 'results',
              reason: 'Empty recordSource must fire onEnd without crashing.');
          expect(engine.lastActionError, isNull);
        } finally {
          await engine.reset();
          engine.dispose();
          await _cleanup(tmp);
        }
      });
    });

    // -----------------------------------------------------------------------
    // B4-2: Large data sets (1000 rows)
    // -----------------------------------------------------------------------
    group('B4-2: Large data sets', () {
      test('seed 1000 rows, query returns all', () async {
        final tmp = await _tmp('ods_b42a_');
        final ds = DataStore();
        try {
          await ds.initialize('b42a', storageFolder: tmp.path);
          await ds.ensureTable('big', [
            const OdsFieldDefinition(name: 'title', type: 'text'),
          ]);
          for (var i = 0; i < 1000; i++) {
            await ds.insert('big', {'title': 't$i'});
          }
          final rows = await ds.query('big');
          expect(rows.length, 1000);
        } finally {
          await ds.close();
          await _cleanup(tmp);
        }
      }, timeout: const Timeout(Duration(seconds: 60)));

      test('insert into 1000-row table works', () async {
        final tmp = await _tmp('ods_b42b_');
        final ds = DataStore();
        try {
          await ds.initialize('b42b', storageFolder: tmp.path);
          await ds.ensureTable('big', [
            const OdsFieldDefinition(name: 'title', type: 'text'),
          ]);
          for (var i = 0; i < 1000; i++) {
            await ds.insert('big', {'title': 't$i'});
          }
          // Insert row 1001.
          final id = await ds.insert('big', {'title': 'newcomer'});
          expect(id, isNotEmpty);
          final rows = await ds.query('big');
          expect(rows.length, 1001);
          expect(rows.any((r) => r['title'] == 'newcomer'), isTrue);
        } finally {
          await ds.close();
          await _cleanup(tmp);
        }
      }, timeout: const Timeout(Duration(seconds: 60)));

      test('delete individual row from 1000-row table works', () async {
        final tmp = await _tmp('ods_b42c_');
        final ds = DataStore();
        try {
          await ds.initialize('b42c', storageFolder: tmp.path);
          await ds.ensureTable('big', [
            const OdsFieldDefinition(name: 'title', type: 'text'),
          ]);
          String? targetId;
          for (var i = 0; i < 1000; i++) {
            final id = await ds.insert('big', {'title': 't$i'});
            if (i == 500) targetId = id;
          }
          final affected = await ds.delete('big', '_id', targetId!);
          expect(affected, 1);
          final rows = await ds.query('big');
          expect(rows.length, 999);
          expect(rows.any((r) => r['_id'] == targetId), isFalse);
        } finally {
          await ds.close();
          await _cleanup(tmp);
        }
      }, timeout: const Timeout(Duration(seconds: 60)));
    });

    // -----------------------------------------------------------------------
    // B4-3: Missing optional spec fields
    // -----------------------------------------------------------------------
    group('B4-3: Missing optional spec fields', () {
      test('spec with no menu parses (defaults to empty list)', () {
        final app = OdsApp.fromJson({
          'appName': 'NoMenu',
          'startPage': 'home',
          'pages': {
            'home': {'component': 'page', 'title': 'Home', 'content': []},
          },
        });
        expect(app.menu, isEmpty);
      });

      test('spec with no branding uses defaults', () {
        final app = OdsApp.fromJson({
          'appName': 'NoBranding',
          'startPage': 'home',
          'pages': {
            'home': {'component': 'page', 'title': 'Home', 'content': []},
          },
        });
        // Branding model exists with default values; should not be null.
        expect(app.branding, isNotNull);
      });

      test('spec with no auth defaults to single-user (multiUser=false)', () {
        final app = OdsApp.fromJson({
          'appName': 'NoAuth',
          'startPage': 'home',
          'pages': {
            'home': {'component': 'page', 'title': 'Home', 'content': []},
          },
        });
        expect(app.auth.multiUser, isFalse);
      });

      test('spec with no help parses OK (help is null)', () {
        final app = OdsApp.fromJson({
          'appName': 'NoHelp',
          'startPage': 'home',
          'pages': {
            'home': {'component': 'page', 'title': 'Home', 'content': []},
          },
        });
        expect(app.help, isNull);
      });

      test('page with no roles is accessible (roles is null)', () {
        final app = OdsApp.fromJson({
          'appName': 'NoRoles',
          'startPage': 'home',
          'pages': {
            'home': {'component': 'page', 'title': 'Home', 'content': []},
          },
        });
        expect(app.pages['home']!.roles, isNull);
      });
    });

    // -----------------------------------------------------------------------
    // B4-4: Malformed JSON specs
    // -----------------------------------------------------------------------
    group('B4-4: Malformed JSON specs', () {
      test('syntax error returns parseError, does not crash', () {
        final parser = SpecParser();
        // Malformed JSON — missing closing brace.
        final result = parser.parse('{"appName": "Broken"');
        expect(result.parseError, isNotNull);
        expect(result.app, isNull);
        expect(result.isOk, isFalse);
      });

      test('empty spec "{}" yields validation errors', () {
        final parser = SpecParser();
        final result = parser.parse('{}');
        expect(result.validation.hasErrors, isTrue);
        expect(result.app, isNull);
        expect(result.isOk, isFalse);
        // Errors should mention the required fields.
        final messages =
            result.validation.errors.map((e) => e.message).join(' ');
        expect(messages, contains('appName'));
        expect(messages, contains('startPage'));
        expect(messages, contains('pages'));
      });

      test('spec with wrong types is handled gracefully', () {
        final parser = SpecParser();
        // startPage expected to be String or Map; give it a number.
        // Will fail inside fromJson and be captured as parseError.
        final result = parser.parse(
          '{"appName":"Wrong","startPage":42,"pages":{"home":{"component":"page","title":"H","content":[]}}}',
        );
        // Either parseError OR validation error — both are "graceful".
        expect(result.isOk, isFalse);
        expect(
          result.parseError != null || result.validation.hasErrors,
          isTrue,
          reason:
              'Malformed types should surface as parseError or validation '
              'error — never as an uncaught exception.',
        );
      });
    });

    // -----------------------------------------------------------------------
    // B4-5: Unicode in values
    // -----------------------------------------------------------------------
    group('B4-5: Unicode in values', () {
      test('submit with unicode/emoji round-trips via SQLite', () async {
        final tmp = await _tmp('ods_b45a_');
        final ds = DataStore();
        try {
          await ds.initialize('b45a', storageFolder: tmp.path);
          await ds.ensureTable('tasks', [
            const OdsFieldDefinition(name: 'title', type: 'text'),
          ]);
          const payload = 'Hello 🚀 café — 中文 — привет';
          await ds.insert('tasks', {'title': payload});
          final rows = await ds.query('tasks');
          expect(rows.length, 1);
          expect(rows.first['title'], payload);
        } finally {
          await ds.close();
          await _cleanup(tmp);
        }
      });

      test('filter query with unicode match works', () async {
        final tmp = await _tmp('ods_b45b_');
        final ds = DataStore();
        try {
          await ds.initialize('b45b', storageFolder: tmp.path);
          await ds.ensureTable('tasks', [
            const OdsFieldDefinition(name: 'title', type: 'text'),
            const OdsFieldDefinition(name: 'tag', type: 'text'),
          ]);
          await ds.insert('tasks', {'title': 'a', 'tag': '日本語'});
          await ds.insert('tasks', {'title': 'b', 'tag': 'english'});
          final rows =
              await ds.queryWithFilter('tasks', {'tag': '日本語'});
          expect(rows.length, 1);
          expect(rows.first['title'], 'a');
        } finally {
          await ds.close();
          await _cleanup(tmp);
        }
      });

      test('unicode match field name is rejected (field validation)',
          () async {
        // The Flutter equivalent of validateFieldName/table-name rejection.
        // Field names are validated against ^[a-zA-Z_][a-zA-Z0-9_]*$, so a
        // unicode field name used as a matchField must throw ArgumentError.
        final tmp = await _tmp('ods_b45c_');
        final ds = DataStore();
        try {
          await ds.initialize('b45c', storageFolder: tmp.path);
          await ds.ensureTable('tasks', [
            const OdsFieldDefinition(name: 'title', type: 'text'),
          ]);
          expect(
            () => ds.update('tasks', {'title': 'x'}, 'café', 'anything'),
            throwsArgumentError,
            reason: 'Unicode field name must be rejected by _validateFieldName.',
          );
          expect(
            () => ds.delete('tasks', '日本語', 'x'),
            throwsArgumentError,
          );
        } finally {
          await ds.close();
          await _cleanup(tmp);
        }
      });

      test('unicode table name is rejected on import', () async {
        // _isValidTableName uses the same regex — unicode table names are
        // skipped silently by importAllData, or throw in importTableRows.
        final tmp = await _tmp('ods_b45d_');
        final ds = DataStore();
        try {
          await ds.initialize('b45d', storageFolder: tmp.path);
          expect(
            () => ds.importTableRows('日本語', [
              {'title': 'x'}
            ]),
            throwsArgumentError,
            reason: 'Unicode table name must be rejected.',
          );
          // importAllData silently skips (doesn't throw) — verify the table
          // was NOT created.
          await ds.importAllData({
            '日本語': [
              {'title': 'x'}
            ]
          });
          final tables = await ds.listTables();
          expect(tables.contains('日本語'), isFalse);
        } finally {
          await ds.close();
          await _cleanup(tmp);
        }
      });
    });

    // -----------------------------------------------------------------------
    // B4-6: Concurrent actions
    // -----------------------------------------------------------------------
    group('B4-6: Concurrent actions', () {
      test('multiple executeActions run concurrently without crash',
          () async {
        final tmp = await _tmp('ods_b46a_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        final ok = await engine.loadSpec(_makeAppJson());
        expect(ok, isTrue);
        try {
          // Seed form state.
          engine.updateFormField('addForm', 'title', 'c1');
          engine.updateFormField('addForm', 'status', 's');

          // Kick off 5 concurrent executeActions chains. None should throw.
          final futures = List.generate(5, (_) {
            return engine.executeActions([
              const OdsAction(
                action: 'submit',
                target: 'addForm',
                dataSource: 'tasks',
              ),
            ]);
          });
          // Future.wait resolves only if none of the futures throw.
          await Future.wait(futures);
          // At least one submit should have succeeded (form snapshot is
          // cleared after each). Exact count of rows is non-deterministic
          // due to interleaving — only assert NO crash and at least 1 row.
          final rows = await engine.dataStore.query('tasks');
          expect(rows.length, greaterThanOrEqualTo(1),
              reason: 'At least one concurrent submit must land.');
        } finally {
          await engine.reset();
          engine.dispose();
          await _cleanup(tmp);
        }
      });

      test('multiple direct inserts via Future.wait all succeed', () async {
        final tmp = await _tmp('ods_b46b_');
        final ds = DataStore();
        try {
          await ds.initialize('b46b', storageFolder: tmp.path);
          await ds.ensureTable('tasks', [
            const OdsFieldDefinition(name: 'title', type: 'text'),
          ]);
          final futures = List.generate(
            20,
            (i) => ds.insert('tasks', {'title': 't$i'}),
          );
          final ids = await Future.wait(futures);
          // All inserts returned non-empty ids.
          expect(ids.length, 20);
          expect(ids.every((id) => id.isNotEmpty), isTrue);
          // Total row count matches.
          final rows = await ds.query('tasks');
          expect(rows.length, 20);
        } finally {
          await ds.close();
          await _cleanup(tmp);
        }
      });
    });

    // -----------------------------------------------------------------------
    // B4-7: Stale state after navigation
    // -----------------------------------------------------------------------
    group('B4-7: Stale state after navigation', () {
      test('form state preserved across navigation', () async {
        final tmp = await _tmp('ods_b47a_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        final ok = await engine.loadSpec(_makeAppJson());
        expect(ok, isTrue);
        try {
          engine.updateFormField('addForm', 'title', 'carry-me');
          engine.updateFormField('addForm', 'status', 'todo');
          // Navigate away.
          engine.navigateTo('results');
          expect(engine.currentPageId, 'results');
          // And back.
          engine.navigateTo('home');
          expect(engine.currentPageId, 'home');
          final state = engine.getFormState('addForm');
          expect(state['title'], 'carry-me',
              reason: 'Form state must survive navigate-away-and-back.');
          expect(state['status'], 'todo');
        } finally {
          await engine.reset();
          engine.dispose();
          await _cleanup(tmp);
        }
      });

      test('cursor state intact after navigate-away-and-back', () async {
        final tmp = await _tmp('ods_b47b_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        final ok = await engine.loadSpec(_makeAppJson());
        expect(ok, isTrue);
        try {
          final ds = engine.dataStore;
          await ds.ensureTable('questions', [
            const OdsFieldDefinition(name: 'question', type: 'text'),
            const OdsFieldDefinition(name: 'answer', type: 'text'),
          ]);
          await ds.insert('questions', {'question': 'Q1', 'answer': 'A1'});
          await ds.insert('questions', {'question': 'Q2', 'answer': 'A2'});
          await ds.insert('questions', {'question': 'Q3', 'answer': 'A3'});

          // Load cursor on quizForm at first record.
          await engine.executeActions([
            const OdsAction(action: 'firstRecord', target: 'quizForm'),
          ]);
          final firstSeen = engine.getFormState('quizForm')['question'];
          expect(firstSeen, isNotNull);

          // Navigate away.
          engine.navigateTo('other');
          expect(engine.currentPageId, 'other');
          // And back.
          engine.navigateTo('home');
          expect(engine.currentPageId, 'home');

          // nextRecord should advance to a NEW row — meaning the cursor
          // still remembers it was at index 0.
          await engine.executeActions([
            const OdsAction(action: 'nextRecord', target: 'quizForm'),
          ]);
          final secondSeen = engine.getFormState('quizForm')['question'];
          expect(secondSeen, isNotNull);
          expect(secondSeen, isNot(firstSeen),
              reason: 'Cursor should have advanced past its first position — '
                  'state survived navigation.');
        } finally {
          await engine.reset();
          engine.dispose();
          await _cleanup(tmp);
        }
      });
    });

    // -----------------------------------------------------------------------
    // B4-8: Field name boundaries
    // -----------------------------------------------------------------------
    //
    // Exercised via public DataStore.update() which runs every name through
    // _validateFieldName. Regex: ^[a-zA-Z_][a-zA-Z0-9_]*$
    //   - dash               → invalid (reject)
    //   - digit-start        → invalid (reject)
    //   - underscore-start   → VALID (intentional, matches React; Bug #13/14)
    //   - 1-char [a-z]       → valid
    //   - 256-char           → valid (no length cap, matches React; Bug #13/14)
    //
    // These cases document intentional framework behavior. The underscore
    // and length cases were reviewed in Bug #13/14 and confirmed intentional.
    // -----------------------------------------------------------------------
    group('B4-8: Field name boundaries', () {
      test('dash in field name is rejected', () async {
        final tmp = await _tmp('ods_b48a_');
        final ds = DataStore();
        try {
          await ds.initialize('b48a', storageFolder: tmp.path);
          await ds.ensureTable('tasks', [
            const OdsFieldDefinition(name: 'title', type: 'text'),
          ]);
          expect(
            () => ds.update('tasks', {'title': 'x'}, 'bad-name', 'v'),
            throwsArgumentError,
          );
        } finally {
          await ds.close();
          await _cleanup(tmp);
        }
      });

      test('digit-start field name is rejected', () async {
        final tmp = await _tmp('ods_b48b_');
        final ds = DataStore();
        try {
          await ds.initialize('b48b', storageFolder: tmp.path);
          await ds.ensureTable('tasks', [
            const OdsFieldDefinition(name: 'title', type: 'text'),
          ]);
          expect(
            () => ds.update('tasks', {'title': 'x'}, '1name', 'v'),
            throwsArgumentError,
          );
        } finally {
          await ds.close();
          await _cleanup(tmp);
        }
      });

      test(
          'underscore-start field name is ACCEPTED by validation '
          '(intentional — consistent with React framework)', () async {
        // Regex ^[a-zA-Z_][a-zA-Z0-9_]* allows leading underscore. Framework
        // fields (_id, _createdAt) use this convention, and user-defined
        // fields starting with _ are also permitted. This behavior is
        // intentional and matches the React framework (Bug #13/14 decision).
        final tmp = await _tmp('ods_b48c_');
        final ds = DataStore();
        try {
          await ds.initialize('b48c', storageFolder: tmp.path);
          // Create the column too so SQLite has something to match against —
          // we're isolating "does _validateFieldName accept it?" from the
          // separate "does the column exist?" failure mode.
          await ds.ensureTable('tasks', [
            const OdsFieldDefinition(name: '_userField', type: 'text'),
            const OdsFieldDefinition(name: 'title', type: 'text'),
          ]);
          // Validation passes both in ensureTable (column added) and in
          // update (matchField accepted). 0 rows match; no throw.
          final n = await ds.update('tasks', {'title': 'x'}, '_userField', 'v');
          expect(n, 0,
              reason:
                  'Underscore-prefixed user field names are intentionally '
                  'allowed and are NOT reserved for framework use.');
        } finally {
          await ds.close();
          await _cleanup(tmp);
        }
      });

      test('1-character field name is accepted', () async {
        final tmp = await _tmp('ods_b48d_');
        final ds = DataStore();
        try {
          await ds.initialize('b48d', storageFolder: tmp.path);
          await ds.ensureTable('tasks', [
            const OdsFieldDefinition(name: 'a', type: 'text'),
            const OdsFieldDefinition(name: 'title', type: 'text'),
          ]);
          final n =
              await ds.update('tasks', {'title': 'x'}, 'a', 'anything');
          expect(n, 0, reason: 'No match, but validation must have passed.');
        } finally {
          await ds.close();
          await _cleanup(tmp);
        }
      });

      test('256-character field name is accepted by validation '
          '(intentional — consistent with React framework)', () async {
        // Regex imposes no length cap — this is intentional behavior that
        // matches the React framework (Bug #13/14 decision). SQLite accepts
        // arbitrarily long column names.
        final tmp = await _tmp('ods_b48e_');
        final ds = DataStore();
        try {
          await ds.initialize('b48e', storageFolder: tmp.path);
          final longName = 'a' + 'b' * 255; // 256 chars, all [a-z].
          expect(longName.length, 256);
          await ds.ensureTable('tasks', [
            OdsFieldDefinition(name: longName, type: 'text'),
            const OdsFieldDefinition(name: 'title', type: 'text'),
          ]);
          final n = await ds.update('tasks', {'title': 'x'}, longName, 'v');
          expect(n, 0,
              reason: 'Long field names are intentionally allowed, with no '
                  'length cap. This is consistent with the React framework.');
        } finally {
          await ds.close();
          await _cleanup(tmp);
        }
      });
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/engine/action_handler.dart';
import 'package:ods_flutter_local/engine/auth_service.dart';
import 'package:ods_flutter_local/engine/data_store.dart';
import 'package:ods_flutter_local/models/ods_action.dart';
import 'package:ods_flutter_local/models/ods_app.dart';
import 'package:ods_flutter_local/models/ods_field_definition.dart';

/// In-memory fake DataStore with full CRUD for integration tests.
///
/// Unlike the lightweight fake in test/engine/action_handler_test.dart, this
/// one supports query and delete and keeps rows in a map so we can exercise
/// end-to-end submit -> query flows.
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

  /// Seeds rows directly, bypassing insert (assigns _id if missing).
  void seed(String tableName, List<Map<String, dynamic>> rows) {
    tables[tableName] = rows.map((r) {
      final row = Map<String, dynamic>.from(r);
      row['_id'] ??= 'id_${_nextId++}';
      row['_createdAt'] ??= DateTime.now().toIso8601String();
      return row;
    }).toList();
  }
}

/// Builds a minimal OdsApp with a `tasks` local dataSource and an `addForm`.
OdsApp _makeApp({Map<String, dynamic>? overrides}) {
  final base = <String, dynamic>{
    'appName': 'Test',
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
        ],
      },
      'thanks': {'component': 'page', 'title': 'Thanks', 'content': []},
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
    },
  };
  if (overrides != null) base.addAll(overrides);
  return OdsApp.fromJson(base);
}

void main() {
  group('Batch 1: Regression tests', () {
    late _FakeDataStore dataStore;
    late ActionHandler handler;

    setUp(() {
      dataStore = _FakeDataStore();
      handler = ActionHandler(dataStore: dataStore);
    });

    // -----------------------------------------------------------------------
    // B1: Submit -> Query
    // -----------------------------------------------------------------------
    group('B1: Submit then query', () {
      test('single submit results in one queryable row', () async {
        final app = _makeApp();
        final action = const OdsAction(
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
        );
        final result = await handler.execute(
          action: action,
          app: app,
          formStates: {
            'addForm': {'title': 'Buy milk', 'status': ''}
          },
        );
        expect(result.submitted, isTrue);
        expect(result.error, isNull);

        final rows = await dataStore.query('tasks');
        expect(rows.length, 1);
        expect(rows.first['title'], 'Buy milk');
      });

      test('unicode title round-trips through submit/query', () async {
        final app = _makeApp();
        final action = const OdsAction(
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
        );
        final result = await handler.execute(
          action: action,
          app: app,
          formStates: {
            'addForm': {'title': 'Hello 🚀 café', 'status': ''}
          },
        );
        expect(result.submitted, isTrue);

        final rows = await dataStore.query('tasks');
        expect(rows.length, 1);
        expect(rows.first['title'], 'Hello 🚀 café');
      });

      test('two successive submits produce a count of 2', () async {
        final app = _makeApp();
        final action = const OdsAction(
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
        );
        await handler.execute(
          action: action,
          app: app,
          formStates: {
            'addForm': {'title': 'One', 'status': ''}
          },
        );
        await handler.execute(
          action: action,
          app: app,
          formStates: {
            'addForm': {'title': 'Two', 'status': ''}
          },
        );

        final rows = await dataStore.query('tasks');
        expect(rows.length, 2);
        final titles = rows.map((r) => r['title']).toSet();
        expect(titles, {'One', 'Two'});
      });

      test('submit with empty form state sets result.error', () async {
        final app = _makeApp();
        final action = const OdsAction(
          action: 'submit',
          target: 'addForm',
          dataSource: 'tasks',
        );
        // Empty map — ActionHandler returns 'No form data found'.
        final result = await handler.execute(
          action: action,
          app: app,
          formStates: {'addForm': {}},
        );
        expect(result.submitted, isFalse);
        expect(result.error, isNotNull);
      });
    });

    // -----------------------------------------------------------------------
    // B2: Update via withData (Gap #2 fix)
    // -----------------------------------------------------------------------
    group('B2: Update via withData', () {
      test('seeded row is updated by matching _id', () async {
        dataStore.seed('tasks', [
          {'_id': 'abc123', 'title': 'Write tests', 'status': 'todo'},
        ]);

        final app = _makeApp();
        final action = const OdsAction(
          action: 'update',
          dataSource: 'tasksUpdater',
          matchField: '_id',
          target: 'abc123',
          withData: {'status': 'done'},
        );
        final result = await handler.execute(
          action: action,
          app: app,
          formStates: {},
        );

        expect(result.submitted, isTrue);
        expect(result.error, isNull);

        final rows = await dataStore.query('tasks');
        expect(rows.length, 1);
        expect(rows.first['status'], 'done');
        expect(rows.first['title'], 'Write tests');
      });

      test('non-existent target sets submitted false and error Record not found',
          () async {
        final app = _makeApp();
        final action = const OdsAction(
          action: 'update',
          dataSource: 'tasksUpdater',
          matchField: '_id',
          target: 'does-not-exist',
          withData: {'status': 'done'},
        );
        final result = await handler.execute(
          action: action,
          app: app,
          formStates: {},
        );

        expect(result.submitted, isFalse);
        expect(result.error, 'Record not found');
      });
    });

    // -----------------------------------------------------------------------
    // B3: Delete
    // -----------------------------------------------------------------------
    group('B3: Delete', () {
      test('deleting one of two seeded rows leaves one remaining', () async {
        dataStore.seed('tasks', [
          {'_id': 'r1', 'title': 'A'},
          {'_id': 'r2', 'title': 'B'},
        ]);

        final affected = await dataStore.delete('tasks', '_id', 'r1');
        expect(affected, 1);

        final rows = await dataStore.query('tasks');
        expect(rows.length, 1);
        expect(rows.first['title'], 'B');
      });

      test('deleting non-existent row affects 0 rows without crashing',
          () async {
        dataStore.seed('tasks', [
          {'_id': 'r1', 'title': 'A'},
        ]);

        final affected = await dataStore.delete('tasks', '_id', 'nope');
        expect(affected, 0);

        final rows = await dataStore.query('tasks');
        expect(rows.length, 1);
      });
    });

    // -----------------------------------------------------------------------
    // B4: Admin role detection
    // -----------------------------------------------------------------------
    //
    // Flutter doesn't have `setSuperAdmin`; the equivalent is
    // AuthService.injectFrameworkAuth(roles: [...]). That lets us set roles
    // without needing SQLite for this test.
    group('B4: Admin role detection', () {
      test('admin user: isAdmin true, hasAccess([admin]) true', () {
        final ds = _FakeDataStore();
        final auth = AuthService(ds);
        auth.injectFrameworkAuth(
          username: 'alice',
          displayName: 'Alice',
          roles: ['admin', 'user'],
        );
        expect(auth.isAdmin, isTrue);
        expect(auth.hasAccess(['admin']), isTrue);
        expect(auth.hasAccess(['user']), isTrue);
        expect(auth.currentRoles, contains('admin'));
      });

      test('guest user: isAdmin false, hasAccess([admin]) false', () {
        final ds = _FakeDataStore();
        final auth = AuthService(ds);
        // No injectFrameworkAuth / login -> guest by default.
        expect(auth.isAdmin, isFalse);
        expect(auth.isGuest, isTrue);
        expect(auth.hasAccess(['admin']), isFalse);
        // No role restriction means everyone has access.
        expect(auth.hasAccess(null), isTrue);
        expect(auth.hasAccess([]), isTrue);
      });
    });

    // -----------------------------------------------------------------------
    // B5: Role-based start page
    // -----------------------------------------------------------------------
    group('B5: Role-based start page', () {
      test('object startPage exposes default + per-role map', () {
        final app = OdsApp.fromJson({
          'appName': 'Test',
          'startPage': {'default': 'home', 'admin': 'dashboard'},
          'pages': {
            'home': {'component': 'page', 'title': 'Home', 'content': []},
            'dashboard': {
              'component': 'page',
              'title': 'Dashboard',
              'content': []
            },
          },
        });

        expect(app.startPage, 'home');
        expect(app.startPageByRole, {'admin': 'dashboard'});
      });

      test('startPageForRoles: admin -> dashboard', () {
        final app = OdsApp.fromJson({
          'appName': 'Test',
          'startPage': {'default': 'home', 'admin': 'dashboard'},
          'pages': {
            'home': {'component': 'page', 'title': 'Home', 'content': []},
            'dashboard': {
              'component': 'page',
              'title': 'Dashboard',
              'content': []
            },
          },
        });

        expect(app.startPageForRoles(['admin']), 'dashboard');
      });

      test('startPageForRoles: non-matching role falls back to default', () {
        final app = OdsApp.fromJson({
          'appName': 'Test',
          'startPage': {'default': 'home', 'admin': 'dashboard'},
          'pages': {
            'home': {'component': 'page', 'title': 'Home', 'content': []},
            'dashboard': {
              'component': 'page',
              'title': 'Dashboard',
              'content': []
            },
          },
        });

        expect(app.startPageForRoles(['user']), 'home');
      });

      test('startPageForRoles: empty roles falls back to default', () {
        final app = OdsApp.fromJson({
          'appName': 'Test',
          'startPage': {'default': 'home', 'admin': 'dashboard'},
          'pages': {
            'home': {'component': 'page', 'title': 'Home', 'content': []},
            'dashboard': {
              'component': 'page',
              'title': 'Dashboard',
              'content': []
            },
          },
        });

        expect(app.startPageForRoles([]), 'home');
      });

      test('plain string startPage: startPageByRole is empty, lookup returns default',
          () {
        final app = OdsApp.fromJson({
          'appName': 'Test',
          'startPage': 'home',
          'pages': {
            'home': {'component': 'page', 'title': 'Home', 'content': []},
          },
        });

        expect(app.startPage, 'home');
        expect(app.startPageByRole, isEmpty);
        expect(app.startPageForRoles(['admin']), 'home');
        expect(app.startPageForRoles([]), 'home');
      });
    });

    // -----------------------------------------------------------------------
    // B6: Field name validation (Gap #1)
    // -----------------------------------------------------------------------
    //
    // _validateFieldName is private. We test it through the public update()
    // and delete() methods — both call it on matchField before touching _db.
    //
    // For the positive "valid names pass" case we need a real DB, so we
    // initialize one against a temp folder using sqflite_common_ffi (already
    // pulled in by DataStore).
    group('B6: Field name validation', () {
      test('update() with __proto__ matchField throws ArgumentError', () async {
        final real = DataStore();
        expect(
          () => real.update('tasks', {'a': 'b'}, '__proto__', 'x'),
          throwsArgumentError,
        );
      });

      test('update() with SQL-injection-style matchField throws', () async {
        final real = DataStore();
        expect(
          () => real.update('tasks', {'a': 'b'}, '; DROP TABLE tasks;--', 'x'),
          throwsArgumentError,
        );
      });

      test('delete() with invalid matchField throws ArgumentError', () async {
        final real = DataStore();
        expect(
          () => real.delete('tasks', '__proto__', 'x'),
          throwsArgumentError,
        );
        expect(
          () => real.delete('tasks', '; DROP TABLE tasks;--', 'x'),
          throwsArgumentError,
        );
      });

      test('_id and _createdAt are allowed as matchField (framework fields)',
          () async {
        // Use a temp storage folder so we can fully exercise update() without
        // touching the user's actual ODS data dir.
        final tmp = await Directory.systemTemp.createTemp('ods_b6_');
        final real = DataStore();
        try {
          await real.initialize('b6_app', storageFolder: tmp.path);
          await real.ensureTable('tasks', [
            const OdsFieldDefinition(name: 'title', type: 'text'),
          ]);
          // Insert a row so we can match against it.
          final id = await real.insert('tasks', {'title': 'hello'});
          // These should NOT throw — framework fields bypass validation.
          final n1 = await real.update('tasks', {'title': 'x'}, '_id', id);
          expect(n1, 1);
          // _createdAt is also framework-allowed; match may be 0 but no throw.
          final n2 =
              await real.update('tasks', {'title': 'y'}, '_createdAt', 'z');
          expect(n2, 0);
        } finally {
          await real.close();
          if (await tmp.exists()) {
            await tmp.delete(recursive: true);
          }
        }
      });

      test('valid names like user_email pass validation', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b6v_');
        final real = DataStore();
        try {
          await real.initialize('b6v_app', storageFolder: tmp.path);
          await real.ensureTable('users', [
            const OdsFieldDefinition(name: 'user_email', type: 'text'),
            const OdsFieldDefinition(name: 'display_name', type: 'text'),
          ]);
          // Use a data map that still has content after matchField is removed.
          // (DataStore.update strips the matchField from the update set.)
          // Should NOT throw — validation must pass for snake_case names.
          final n = await real.update(
            'users',
            {'display_name': 'New Name'},
            'user_email',
            'old@x',
          );
          expect(n, 0); // no match, but validation passed.
        } finally {
          await real.close();
          if (await tmp.exists()) {
            await tmp.delete(recursive: true);
          }
        }
      });
    });

    // -----------------------------------------------------------------------
    // B7: Backup round-trip
    // -----------------------------------------------------------------------
    //
    // The import/export validation logic lives on DataStore itself
    // (importAllData / exportAllData / _sanitizeRow). BackupManager only wraps
    // these with file IO and HMAC signing. So B7 exercises DataStore directly.
    group('B7: Backup round-trip', () {
      test('importAllData skips dangerous table names (__proto__)', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b7a_');
        final real = DataStore();
        try {
          await real.initialize('b7a_app', storageFolder: tmp.path);
          // Attempt to import a table with a reserved/dangerous name.
          await real.importAllData({
            '__proto__': [
              {'title': 'should not be imported'}
            ],
          });
          // The dangerous table should have been skipped silently.
          final tables = await real.listTables();
          expect(tables.contains('__proto__'), isFalse);
        } finally {
          await real.close();
          if (await tmp.exists()) {
            await tmp.delete(recursive: true);
          }
        }
      });

      test('importAllData with >100_000 rows throws ArgumentError', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b7b_');
        final real = DataStore();
        try {
          await real.initialize('b7b_app', storageFolder: tmp.path);
          // Build a huge list (101_000 rows) for a single table to trip the cap.
          final rows = List.generate(
            101000,
            (i) => <String, dynamic>{'title': 't$i'},
          );
          expect(
            () => real.importAllData({'big': rows}),
            throwsArgumentError,
          );
        } finally {
          await real.close();
          if (await tmp.exists()) {
            await tmp.delete(recursive: true);
          }
        }
      });

      test('imported rows drop dangerous field names (sanitizeRow)', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b7c_');
        final real = DataStore();
        try {
          await real.initialize('b7c_app', storageFolder: tmp.path);
          await real.importAllData({
            'tasks': [
              {
                'title': 'ok',
                '__proto__': 'bad',
                'constructor': 'also bad',
                'valid_field': 'keep me',
              }
            ],
          });

          final rows = await real.query('tasks');
          expect(rows.length, 1);
          expect(rows.first['title'], 'ok');
          expect(rows.first['valid_field'], 'keep me');
          // Dangerous keys must not appear as columns.
          expect(rows.first.containsKey('__proto__'), isFalse);
          expect(rows.first.containsKey('constructor'), isFalse);
        } finally {
          await real.close();
          if (await tmp.exists()) {
            await tmp.delete(recursive: true);
          }
        }
      });

      test('round-trip: insert, export, clear, import, verify', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b7d_');
        final real = DataStore();
        try {
          await real.initialize('b7d_app', storageFolder: tmp.path);
          await real.ensureTable('tasks', [
            const OdsFieldDefinition(name: 'title', type: 'text'),
            const OdsFieldDefinition(name: 'status', type: 'text'),
          ]);
          await real.insert('tasks', {'title': 'one', 'status': 'todo'});
          await real.insert('tasks', {'title': 'two', 'status': 'done'});

          final exported = await real.exportAllData();
          expect(exported.keys, contains('tasks'));
          expect(exported['tasks']!.length, 2);

          // Clear then re-import.
          // (importAllData wipes each target table before inserting.)
          await real.importAllData(exported);

          final rows = await real.query('tasks');
          expect(rows.length, 2);
          final titles = rows.map((r) => r['title']).toSet();
          expect(titles, {'one', 'two'});
          final statuses = rows.map((r) => r['status']).toSet();
          expect(statuses, {'todo', 'done'});
        } finally {
          await real.close();
          // Extra guard: close the DB file before removing the temp folder.
          // On Windows the file handle is otherwise held.
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {
              // Best-effort cleanup — temp dir will be reaped by the OS.
            }
          }
        }
      });
    });

    // -----------------------------------------------------------------------
    // B8: Action chain
    // -----------------------------------------------------------------------
    //
    // ActionHandler.execute processes exactly ONE action per call; the chain
    // logic lives in AppEngine.executeActions(), which pulls in the full
    // engine (notifiers, DataStore, auth, etc.) and is more than we want to
    // stand up in an integration smoke test.
    //
    // For B8 we assert the two properties the chain relies on at the
    // ActionHandler level:
    //   (a) a successful submit yields submitted=true so AppEngine will
    //       continue to the next action (navigate/showMessage),
    //   (b) a failed submit yields error set so AppEngine will STOP the chain
    //       (meaning a following showMessage wouldn't run).
    //
    // A fuller chain test that exercises AppEngine.executeActions is
    // deferred — see note below.
    group('B8: Action chain (ActionHandler-level)', () {
      test('successful submit -> submitted=true (chain would continue)',
          () async {
        final app = _makeApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'submit',
            target: 'addForm',
            dataSource: 'tasks',
          ),
          app: app,
          formStates: {
            'addForm': {'title': 'chain-ok', 'status': ''}
          },
        );
        expect(result.submitted, isTrue);
        expect(result.error, isNull);
      });

      test('failed submit -> error set (chain would stop)', () async {
        final app = _makeApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'submit',
            target: 'addForm',
            dataSource: 'tasks',
          ),
          app: app,
          // Empty form -> 'No form data found'.
          formStates: {'addForm': {}},
        );
        expect(result.submitted, isFalse);
        expect(result.error, isNotNull);
      });

      test('showMessage action returns its message', () async {
        final app = _makeApp();
        final result = await handler.execute(
          action: const OdsAction(action: 'showMessage', message: 'hi'),
          app: app,
          formStates: {},
        );
        expect(result.message, 'hi');
        expect(result.error, isNull);
      });

      test('navigate action returns target page', () async {
        final app = _makeApp();
        final result = await handler.execute(
          action: const OdsAction(action: 'navigate', target: 'thanks'),
          app: app,
          formStates: {},
        );
        expect(result.navigateTo, 'thanks');
      });

      // NOTE: "Empty list -> no-op" and full multi-action sequencing
      // (submit + showMessage + navigate) require AppEngine.executeActions,
      // which wires up the full engine (DataStore.initialize + auth +
      // notifiers). That integration is deferred for this batch.
      //
      // B8: requires AppEngine integration - deferred
    });
  });
}


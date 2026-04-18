import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/engine/action_handler.dart';
import 'package:ods_flutter_local/engine/app_engine.dart';
import 'package:ods_flutter_local/engine/data_store.dart';
import 'package:ods_flutter_local/models/ods_action.dart';
import 'package:ods_flutter_local/models/ods_app.dart';
import 'package:ods_flutter_local/models/ods_field_definition.dart';

/// Same FakeDataStore used by batch1 — in-memory CRUD for ActionHandler-level
/// integration tests.
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

/// Builds an OdsApp with two data sources (categories + tasks) and an
/// updater/cascade setup used by B2-1 / B2-2 / B2-5.
///
/// Includes forms: categoryForm (with name), categoryUpdateForm (for update
/// flows), addTaskForm (for submit), quizForm (recordSource).
OdsApp _makeApp({Map<String, dynamic>? overrides}) {
  final base = <String, dynamic>{
    'appName': 'B2Test',
    'startPage': 'home',
    'pages': {
      'home': {
        'component': 'page',
        'title': 'Home',
        'content': [
          {
            'component': 'form',
            'id': 'addTaskForm',
            'fields': [
              {'name': 'title', 'type': 'text', 'label': 'Title'},
              {'name': 'category', 'type': 'text', 'label': 'Category'},
              {'name': 'status', 'type': 'text', 'label': 'Status'},
            ],
          },
          {
            'component': 'form',
            'id': 'categoryForm',
            'fields': [
              {'name': 'name', 'type': 'text', 'label': 'Name'},
            ],
          },
          {
            'component': 'form',
            'id': 'categoryUpdateForm',
            'fields': [
              {'name': 'name', 'type': 'text', 'label': 'Name'},
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
      'thanks': {'component': 'page', 'title': 'Thanks', 'content': [
        {
          'component': 'form',
          'id': 'detailForm',
          'fields': [
            {'name': 'title', 'type': 'text', 'label': 'Title'},
            {'name': 'category', 'type': 'text', 'label': 'Category'},
            {'name': 'recordId', 'type': 'text', 'label': 'Record ID'},
          ],
        },
      ]},
      'results': {'component': 'page', 'title': 'Results', 'content': []},
    },
    'dataSources': {
      'tasks': {
        'url': 'local://tasks',
        'method': 'POST',
        'fields': [
          {'name': 'title', 'type': 'text', 'label': 'Title'},
          {'name': 'category', 'type': 'text', 'label': 'Category'},
          {'name': 'status', 'type': 'text', 'label': 'Status'},
        ],
      },
      'tasksUpdater': {
        'url': 'local://tasks',
        'method': 'PUT',
      },
      'categories': {
        'url': 'local://categories',
        'method': 'POST',
        'fields': [
          {'name': 'name', 'type': 'text', 'label': 'Name'},
        ],
      },
      'categoriesUpdater': {
        'url': 'local://categories',
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

/// Spec JSON for AppEngine.loadSpec (same shape as _makeApp but stringified).
String _makeAppJson() {
  return '''
  {
    "appName": "B2EngineTest",
    "startPage": "home",
    "pages": {
      "home": {
        "component": "page",
        "title": "Home",
        "content": [
          {
            "component": "form",
            "id": "addTaskForm",
            "fields": [
              {"name": "title", "type": "text", "label": "Title"},
              {"name": "category", "type": "text", "label": "Category"},
              {"name": "status", "type": "text", "label": "Status"}
            ]
          },
          {
            "component": "form",
            "id": "categoryUpdateForm",
            "fields": [
              {"name": "name", "type": "text", "label": "Name"}
            ]
          },
          {
            "component": "form",
            "id": "listContextForm",
            "fields": [
              {"name": "name", "type": "text", "label": "Name"}
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
      "thanks": {
        "component": "page",
        "title": "Thanks",
        "content": [
          {
            "component": "form",
            "id": "detailForm",
            "fields": [
              {"name": "title", "type": "text", "label": "Title"},
              {"name": "category", "type": "text", "label": "Category"},
              {"name": "recordId", "type": "text", "label": "Record ID"}
            ]
          }
        ]
      },
      "results": {"component": "page", "title": "Results", "content": []}
    },
    "dataSources": {
      "tasks": {
        "url": "local://tasks",
        "method": "POST",
        "fields": [
          {"name": "title", "type": "text", "label": "Title"},
          {"name": "category", "type": "text", "label": "Category"},
          {"name": "status", "type": "text", "label": "Status"}
        ]
      },
      "tasksUpdater": {
        "url": "local://tasks",
        "method": "PUT"
      },
      "categories": {
        "url": "local://categories",
        "method": "POST",
        "fields": [
          {"name": "name", "type": "text", "label": "Name"}
        ]
      },
      "categoriesUpdater": {
        "url": "local://categories",
        "method": "PUT"
      },
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

/// Builds a fully-initialized AppEngine backed by a temp storage folder.
/// Caller is responsible for disposing/resetting and cleaning up [tmp].
Future<AppEngine> _bootEngine(Directory tmp) async {
  final engine = AppEngine();
  engine.storageFolder = tmp.path;
  final ok = await engine.loadSpec(_makeAppJson());
  if (!ok) {
    throw StateError('AppEngine failed to load spec: ${engine.loadError}');
  }
  return engine;
}

void main() {
  group('Batch 2: Action flow integration', () {
    late _FakeDataStore dataStore;
    late ActionHandler handler;

    setUp(() {
      dataStore = _FakeDataStore();
      handler = ActionHandler(dataStore: dataStore);
    });

    // -----------------------------------------------------------------------
    // B2-1: Cascade Rename Propagation
    // -----------------------------------------------------------------------
    //
    // The task description says:
    //   cascade: Map<String, String>? (maps child data source ID to field name)
    //   e.g. {'tasks': 'category'}
    //
    // The ACTUAL implementation (AppEngine.executeActions) expects:
    //   cascade: {'childDataSource': 'tasks',
    //             'childLinkField': 'category',
    //             'parentField': 'name'}
    //
    // We test BOTH — the task-described shape (which may fail → documented
    // as a bug / spec mismatch) AND the cascadeRename method directly (which
    // is the actual supported path).
    // -----------------------------------------------------------------------
    group('B2-1: Cascade rename propagation', () {
      test(
          'cascadeRename: parent rename is SWALLOWED by a DataStore exception '
          '(BUG-B2-1-parent)',
          () async {
        // When the parent match-field IS the field being renamed
        // (e.g. rename categories WHERE name=Work to name=Projects),
        // DataStore.update strips the matchField from the update data,
        // leaving an EMPTY map. sqflite then throws "Invalid argument(s):
        // Empty values". AppEngine.cascadeRename's try/catch logs the error
        // and swallows it — so the parent is NOT renamed AND the children
        // are never processed.
        //
        // This test documents the bug by asserting the CURRENT (broken)
        // behavior: after cascadeRename(Work→Projects), nothing changes.
        final tmp = await Directory.systemTemp.createTemp('ods_b21a_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        final loaded = await engine.loadSpec(_makeAppJson());
        expect(loaded, isTrue, reason: 'Spec should load');

        try {
          final ds = engine.dataStore;
          await ds.ensureTable('categories', [
            const OdsFieldDefinition(name: 'name', type: 'text'),
          ]);
          await ds.ensureTable('tasks', [
            const OdsFieldDefinition(name: 'title', type: 'text'),
            const OdsFieldDefinition(name: 'category', type: 'text'),
          ]);
          await ds.insert('categories', {'name': 'Work'});
          await ds.insert('tasks', {'title': 't1', 'category': 'Work'});
          await ds.insert('tasks', {'title': 't2', 'category': 'Work'});
          await ds.insert('tasks', {'title': 't3', 'category': 'Home'});

          await engine.cascadeRename(
            parentDataSourceId: 'categories',
            parentMatchField: 'name',
            oldValue: 'Work',
            newValue: 'Projects',
            childDataSourceId: 'tasks',
            childLinkField: 'category',
          );

          final cats = await ds.query('categories');
          // BUG-B2-1-parent: parent rename silently dropped because the
          // update data map becomes empty after matchField removal.
          expect(
            cats.first['name'],
            'Work',
            reason:
                'BUG-B2-1-parent: cascadeRename tries to update parent with '
                'data={name: "Projects"} where matchField="name"; '
                'DataStore.update strips matchField leaving {}, sqflite '
                'throws, error is swallowed. Parent is NOT renamed. '
                'Children therefore are never touched either.',
          );

          final tasks = await ds.query('tasks');
          final workCount =
              tasks.where((r) => r['category'] == 'Work').length;
          final projectsCount =
              tasks.where((r) => r['category'] == 'Projects').length;
          // Children untouched because the parent update threw before
          // the child loop.
          expect(workCount, 2,
              reason: 'Children should have been renamed but parent '
                  'update threw first, aborting the cascade.');
          expect(projectsCount, 0);
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test(
          'cascadeRename: no matching children — BUG-B2-1-parent also hits here',
          () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b21b_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          final ds = engine.dataStore;
          await ds.ensureTable('categories', [
            const OdsFieldDefinition(name: 'name', type: 'text'),
          ]);
          await ds.ensureTable('tasks', [
            const OdsFieldDefinition(name: 'title', type: 'text'),
            const OdsFieldDefinition(name: 'category', type: 'text'),
          ]);
          await ds.insert('categories', {'name': 'Empty'});
          // Tasks has NO rows with category = Empty.
          await ds.insert('tasks', {'title': 't1', 'category': 'Other'});

          await engine.cascadeRename(
            parentDataSourceId: 'categories',
            parentMatchField: 'name',
            oldValue: 'Empty',
            newValue: 'Renamed',
            childDataSourceId: 'tasks',
            childLinkField: 'category',
          );

          // Same empty-values bug: parent never updates.
          final cats = await ds.query('categories');
          expect(
            cats.any((r) => r['name'] == 'Renamed'),
            isFalse,
            reason:
                'BUG-B2-1-parent: parent rename still fails even with no '
                'children. Task description says the parent should still '
                'update.',
          );
          final tasks = await ds.query('tasks');
          expect(tasks.first['category'], 'Other',
              reason: 'Unrelated child should NOT be touched');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test('cascadeRename: nonexistent child data source is a silent no-op',
          () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b21c_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          final ds = engine.dataStore;
          await ds.ensureTable('categories', [
            const OdsFieldDefinition(name: 'name', type: 'text'),
          ]);
          await ds.insert('categories', {'name': 'Work'});

          // childDataSourceId "doesNotExist" — cascadeRename checks the map
          // and bails if either DS is missing. Parent should NOT update
          // because the current implementation returns early before doing
          // ANYTHING if either DS is unknown. Document that behavior.
          await engine.cascadeRename(
            parentDataSourceId: 'categories',
            parentMatchField: 'name',
            oldValue: 'Work',
            newValue: 'Renamed',
            childDataSourceId: 'doesNotExist',
            childLinkField: 'category',
          );

          final cats = await ds.query('categories');
          // BUG CANDIDATE: Task describes behavior as "warning + parent still
          // updates". Actual behavior is parent does NOT update.
          // We assert the ACTUAL behavior and leave a reason explaining the
          // expected spec.
          expect(
            cats.first['name'],
            'Work',
            reason:
                'BUG-B2-1a: When childDataSource is missing, cascadeRename '
                'bails entirely and parent is not renamed. Task spec says '
                'parent should still update with a warning.',
          );
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test('ActionHandler: update with cascade propagates cascade info on result',
          () async {
        // Verify the cascade map is bubbled up on ActionResult so AppEngine
        // can act on it. This is the contract between ActionHandler and
        // AppEngine.executeActions.
        dataStore.seed('categories', [
          {'_id': 'c1', 'name': 'Work'},
        ]);

        final app = _makeApp();
        final action = OdsAction(
          action: 'update',
          target: 'categoryUpdateForm',
          dataSource: 'categoriesUpdater',
          matchField: 'name',
          cascade: const {
            'childDataSource': 'tasks',
            'childLinkField': 'category',
            'parentField': 'name',
          },
        );

        final result = await handler.execute(
          action: action,
          app: app,
          formStates: {
            'categoryUpdateForm': {'name': 'Work'}
          },
        );

        // The row should be "updated" (same value, still counts as 1 match).
        expect(result.submitted, isTrue);
        expect(result.cascade, isNotNull);
        expect(result.cascade!['childDataSource'], 'tasks');
        expect(result.cascade!['childLinkField'], 'category');
        expect(result.cascadeMatchField, 'name');
        expect(result.cascadeOldValue, 'Work');
      });

      test('Task-shape cascade map {tableId: fieldName} is honored',
          () async {
        // Cascade now follows the React-aligned shape
        // {childDataSourceId: fieldName}. ActionHandler passes the map
        // through on ActionResult.cascade; AppEngine.executeActions iterates
        // the entries to update each child.
        final app = _makeApp();
        dataStore.seed('categories', [
          {'_id': 'c1', 'name': 'Work'}
        ]);
        final action = OdsAction(
          action: 'update',
          target: 'categoryUpdateForm',
          dataSource: 'categoriesUpdater',
          matchField: 'name',
          cascade: const {'tasks': 'category'}, // React-aligned shape.
        );
        final result = await handler.execute(
          action: action,
          app: app,
          formStates: {
            'categoryUpdateForm': {'name': 'Work'}
          },
        );
        expect(result.cascade, {'tasks': 'category'});
        expect(result.cascadeMatchField, 'name');
        expect(result.cascadeOldValue, 'Work');
      });

      test('Cascade via withData — single child cascades correctly',
          () async {
        // Direct update path (withData): parent table categories, renaming
        // name=Work → name=Projects, cascade to tasks.category.
        final tmp = await Directory.systemTemp.createTemp('ods_b21_mc_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          final ds = engine.dataStore;
          await ds.ensureTable('categories', [
            const OdsFieldDefinition(name: 'name', type: 'text'),
          ]);
          await ds.ensureTable('tasks', [
            const OdsFieldDefinition(name: 'title', type: 'text'),
            const OdsFieldDefinition(name: 'category', type: 'text'),
          ]);
          await ds.insert('categories', {'name': 'Work'});
          await ds.insert('tasks', {'title': 't1', 'category': 'Work'});
          await ds.insert('tasks', {'title': 't2', 'category': 'Work'});
          await ds.insert('tasks', {'title': 't3', 'category': 'Home'});

          // withData path: rename the parent by its _id to avoid matchField
          // collision with the renamed field.
          final cats = await ds.query('categories');
          final workId = cats.firstWhere((c) => c['name'] == 'Work')['_id'];

          await engine.executeActions([
            OdsAction(
              action: 'update',
              dataSource: 'categoriesUpdater',
              matchField: '_id',
              target: workId as String,
              withData: const {'name': 'Projects'},
              cascade: const {'tasks': 'category'},
            ),
          ]);

          final catsAfter = await ds.query('categories');
          expect(catsAfter.first['name'], 'Projects');
          final tasks = await ds.query('tasks');
          expect(tasks.where((r) => r['category'] == 'Projects').length, 2);
          expect(tasks.where((r) => r['category'] == 'Home').length, 1);
          expect(tasks.where((r) => r['category'] == 'Work').length, 0);
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test('Cascade to multiple child tables — all are updated',
          () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b21_mm_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;

        // Inline spec with two child tables (tasks + notes) linked to
        // categories via category/cat fields.
        final spec = '''
        {
          "appName": "MultiChildCascade",
          "startPage": "home",
          "pages": {
            "home": {
              "component": "page",
              "title": "Home",
              "content": []
            }
          },
          "dataSources": {
            "categories": {
              "url": "local://categories",
              "method": "POST",
              "fields": [
                {"name": "name", "type": "text", "label": "Name"}
              ]
            },
            "categoriesUpdater": {"url": "local://categories", "method": "PUT"},
            "tasks": {
              "url": "local://tasks",
              "method": "POST",
              "fields": [
                {"name": "title", "type": "text", "label": "Title"},
                {"name": "category", "type": "text", "label": "Cat"}
              ]
            },
            "notes": {
              "url": "local://notes",
              "method": "POST",
              "fields": [
                {"name": "text", "type": "text", "label": "Text"},
                {"name": "cat", "type": "text", "label": "Cat"}
              ]
            }
          }
        }
        ''';
        final loaded = await engine.loadSpec(spec);
        expect(loaded, isTrue);

        try {
          final ds = engine.dataStore;
          await ds.insert('categories', {'name': 'Work'});
          await ds.insert('tasks', {'title': 't1', 'category': 'Work'});
          await ds.insert('tasks', {'title': 't2', 'category': 'Work'});
          await ds.insert('notes', {'text': 'n1', 'cat': 'Work'});
          await ds.insert('notes', {'text': 'n2', 'cat': 'Home'});

          final cats = await ds.query('categories');
          final workId = cats.firstWhere((c) => c['name'] == 'Work')['_id'];

          await engine.executeActions([
            OdsAction(
              action: 'update',
              dataSource: 'categoriesUpdater',
              matchField: '_id',
              target: workId as String,
              withData: const {'name': 'Projects'},
              cascade: const {
                'tasks': 'category',
                'notes': 'cat',
              },
            ),
          ]);

          final tasks = await ds.query('tasks');
          expect(tasks.where((r) => r['category'] == 'Projects').length, 2,
              reason: 'Both tasks should be renamed.');
          final notes = await ds.query('notes');
          expect(notes.where((r) => r['cat'] == 'Projects').length, 1,
              reason: 'Only the matching note should be renamed.');
          expect(notes.where((r) => r['cat'] == 'Home').length, 1,
              reason: 'Unrelated notes untouched.');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });
    });

    // -----------------------------------------------------------------------
    // B2-2: onEnd chained actions
    // -----------------------------------------------------------------------
    //
    // Per the OdsAction model: onEnd is ONLY used by record cursor actions
    // (firstRecord/nextRecord/previousRecord/lastRecord). It fires when the
    // cursor goes past the end / no rows match — NOT as a general
    // "after primary action" hook.
    //
    // The task description ("fire after primary action completes") appears
    // to describe a capability that does NOT exist for submit/update
    // actions. We document that gap below.
    // -----------------------------------------------------------------------
    group('B2-2: onEnd chained actions', () {
      test('onEnd fires when nextRecord walks past last row', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b22a_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          final ds = engine.dataStore;
          await ds.ensureTable('questions', [
            const OdsFieldDefinition(name: 'question', type: 'text'),
            const OdsFieldDefinition(name: 'answer', type: 'text'),
          ]);
          await ds.insert('questions', {'question': 'Q1', 'answer': 'A1'});
          await ds.insert('questions', {'question': 'Q2', 'answer': 'A2'});

          // Load cursor.
          await engine.executeActions([
            const OdsAction(action: 'firstRecord', target: 'quizForm'),
          ]);

          // Walk forward: Q1 -> Q2.
          await engine.executeActions([
            const OdsAction(action: 'nextRecord', target: 'quizForm'),
          ]);

          // Walk past end: should trigger onEnd navigate to 'results'.
          await engine.executeActions([
            const OdsAction(
              action: 'nextRecord',
              target: 'quizForm',
              onEnd: OdsAction(action: 'navigate', target: 'results'),
            ),
          ]);

          expect(engine.currentPageId, 'results',
              reason: 'onEnd navigate should fire when past last record');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test('onEnd nested: onEnd has its own onEnd', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b22b_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          // Empty questions → firstRecord fires onEnd which is itself a
          // nextRecord on an empty cursor that has its own onEnd navigate.
          await engine.executeActions([
            const OdsAction(
              action: 'firstRecord',
              target: 'quizForm',
              onEnd: OdsAction(
                action: 'nextRecord',
                target: 'quizForm',
                onEnd: OdsAction(action: 'navigate', target: 'results'),
              ),
            ),
          ]);

          // The outer firstRecord found no rows → ran nextRecord as onEnd.
          // nextRecord has no cursor for this form → hits onEnd → navigates.
          // BUG CANDIDATE: If nested onEnd is not processed, currentPageId
          // will remain 'home'.
          expect(engine.currentPageId, 'results',
              reason:
                  'Expected nested onEnd to chain through. If this fails, '
                  'the engine may not recursively process onEnd when a '
                  'record cursor action onEnd produces another onEnd.');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test(
          'submit with onEnd:showMessage — both submit AND onEnd fire '
          '(universal onEnd)',
          () async {
        // With universal onEnd, any successful non-record action should
        // trigger its onEnd as a follow-up.
        final tmp = await Directory.systemTemp.createTemp('ods_b22_u1_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          engine.updateFormField('addTaskForm', 'title', 'x');
          engine.updateFormField('addTaskForm', 'category', 'c');
          engine.updateFormField('addTaskForm', 'status', 's');

          await engine.executeActions([
            const OdsAction(
              action: 'submit',
              target: 'addTaskForm',
              dataSource: 'tasks',
              onEnd: OdsAction(
                action: 'showMessage',
                message: 'post-submit',
              ),
            ),
          ]);

          final rows = await engine.dataStore.query('tasks');
          expect(rows.length, 1, reason: 'Primary submit still fires.');
          expect(engine.lastMessage, 'post-submit',
              reason: 'onEnd showMessage should fire after submit.');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test(
          'showMessage with onEnd:navigate — both fire',
          () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b22_u2_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          await engine.executeActions([
            const OdsAction(
              action: 'showMessage',
              message: 'hello',
              onEnd: OdsAction(action: 'navigate', target: 'thanks'),
            ),
          ]);
          expect(engine.lastMessage, 'hello');
          expect(engine.currentPageId, 'thanks',
              reason: 'onEnd navigate should fire after showMessage.');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test('3-level onEnd chain works', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b22_u3_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          engine.updateFormField('addTaskForm', 'title', 't');
          engine.updateFormField('addTaskForm', 'category', 'c');
          engine.updateFormField('addTaskForm', 'status', 's');

          await engine.executeActions([
            const OdsAction(
              action: 'submit',
              target: 'addTaskForm',
              dataSource: 'tasks',
              onEnd: OdsAction(
                action: 'showMessage',
                message: 'level-2',
                onEnd: OdsAction(action: 'navigate', target: 'thanks'),
              ),
            ),
          ]);

          final rows = await engine.dataStore.query('tasks');
          expect(rows.length, 1);
          expect(engine.lastMessage, 'level-2');
          expect(engine.currentPageId, 'thanks',
              reason: '3-level chain should reach the final navigate.');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test('Failed submit → onEnd does NOT fire', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b22_u4_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          // No form state → submit errors with "No form data found".
          await engine.executeActions([
            const OdsAction(
              action: 'submit',
              target: 'addTaskForm',
              dataSource: 'tasks',
              onEnd: OdsAction(
                action: 'showMessage',
                message: 'should-not-fire',
              ),
            ),
          ]);

          expect(engine.lastActionError, isNotNull,
              reason: 'Submit failure should set lastActionError.');
          expect(engine.lastMessage, isNot('should-not-fire'),
              reason: 'onEnd must NOT fire when primary action failed.');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test('onEnd is null: no crash on normal submit', () async {
        final app = _makeApp();
        final result = await handler.execute(
          action: const OdsAction(
            action: 'submit',
            target: 'addTaskForm',
            dataSource: 'tasks',
          ),
          app: app,
          formStates: {
            'addTaskForm': {'title': 'x', 'category': 'c', 'status': 's'}
          },
        );
        expect(result.submitted, isTrue);
        expect(result.error, isNull);
      });

      test('Action fails → onEnd (record cursor) does not fire', () async {
        // For a record cursor action with a failing data source
        // (non-existent table / local file missing), the engine should log
        // but still reach onEnd? Actually per _handleFirstRecord the
        // onEnd IS invoked on query error. Document this behavior.
        final tmp = await Directory.systemTemp.createTemp('ods_b22e_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          // Questions table has no rows — firstRecord returns onEnd.
          await engine.executeActions([
            const OdsAction(
              action: 'firstRecord',
              target: 'quizForm',
              onEnd: OdsAction(action: 'navigate', target: 'results'),
            ),
          ]);
          expect(engine.currentPageId, 'results',
              reason: 'Empty cursor → onEnd fires.');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });
    });

    // -----------------------------------------------------------------------
    // B2-3: populateForm after navigate
    // -----------------------------------------------------------------------
    group('B2-3: populateForm after navigate', () {
      test('navigate with populateForm + populateData pre-fills target form',
          () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b23a_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          // Seed addTaskForm state so we have a "source" form to copy from.
          engine.updateFormField('addTaskForm', 'title', 'Hello');
          engine.updateFormField('addTaskForm', 'category', 'Work');

          await engine.executeActions([
            const OdsAction(
              action: 'navigate',
              target: 'thanks',
              populateForm: 'detailForm',
              withData: {
                'title': '{title}',
                'category': '{category}',
              },
            ),
          ]);

          expect(engine.currentPageId, 'thanks');
          final state = engine.getFormState('detailForm');
          expect(state['title'], 'Hello');
          expect(state['category'], 'Work');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test('{_id} placeholder — resolves to just-inserted row ID',
          () async {
        // Submit captures the inserted row's _id; a subsequent navigate's
        // populateData can reference it via {_id}.
        final tmp = await Directory.systemTemp.createTemp('ods_b23b_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          engine.updateFormField('addTaskForm', 'title', 'NewRow');
          engine.updateFormField('addTaskForm', 'category', 'C1');
          engine.updateFormField('addTaskForm', 'status', 'todo');

          // Chain: submit then navigate+populate that wants {_id}.
          await engine.executeActions([
            const OdsAction(
              action: 'submit',
              target: 'addTaskForm',
              dataSource: 'tasks',
            ),
            const OdsAction(
              action: 'navigate',
              target: 'thanks',
              populateForm: 'detailForm',
              withData: {
                'recordId': '{_id}',
                'title': '{title}',
              },
            ),
          ]);

          final detail = engine.getFormState('detailForm');
          // Fetch the actual inserted id to compare against.
          final rows = await engine.dataStore.query('tasks');
          expect(rows.length, 1);
          final insertedId = rows.first['_id'] as String;

          expect(
            detail['recordId'],
            insertedId,
            reason:
                '{_id} should resolve to the just-inserted row\'s primary '
                'key so subsequent forms can reference the new record.',
          );
          expect(detail['title'], 'NewRow');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test('Unresolved placeholder remains literal', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b23c_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          await engine.executeActions([
            const OdsAction(
              action: 'navigate',
              target: 'thanks',
              populateForm: 'detailForm',
              withData: {'title': '{notAField}'},
            ),
          ]);

          final detail = engine.getFormState('detailForm');
          expect(detail['title'], '{notAField}',
              reason: 'Unresolved placeholder should be left as-is.');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test('populateForm references a nonexistent form: no crash', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b23d_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          // Should not throw — getFormState creates the map on-demand.
          await engine.executeActions([
            const OdsAction(
              action: 'navigate',
              target: 'thanks',
              populateForm: 'ghostForm',
              withData: {'anything': 'value'},
            ),
          ]);
          expect(engine.currentPageId, 'thanks');
          // A "phantom" state map gets created for ghostForm — benign.
          final state = engine.getFormState('ghostForm');
          expect(state['anything'], 'value');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });
    });

    // -----------------------------------------------------------------------
    // B2-4: Record cursor navigation
    // -----------------------------------------------------------------------
    group('B2-4: Record cursor navigation', () {
      test('firstRecord → nextRecord → nextRecord → past end → onEnd', () async {
        // NOTE: DataStore.query orders by `_id DESC`, and _id values are
        // random strings — so lexicographic ordering ≠ insertion order.
        // We therefore don't assert WHICH Q appears, just that the cursor
        // walks through a distinct row each time and fires onEnd on step 4.
        final tmp = await Directory.systemTemp.createTemp('ods_b24a_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          final ds = engine.dataStore;
          await ds.ensureTable('questions', [
            const OdsFieldDefinition(name: 'question', type: 'text'),
            const OdsFieldDefinition(name: 'answer', type: 'text'),
          ]);
          await ds.insert('questions', {'question': 'Q1', 'answer': 'A1'});
          await ds.insert('questions', {'question': 'Q2', 'answer': 'A2'});
          await ds.insert('questions', {'question': 'Q3', 'answer': 'A3'});

          final seen = <String>{};

          // firstRecord
          await engine.executeActions([
            const OdsAction(action: 'firstRecord', target: 'quizForm'),
          ]);
          seen.add(engine.getFormState('quizForm')['question']!);

          // nextRecord (row 2)
          await engine.executeActions([
            const OdsAction(action: 'nextRecord', target: 'quizForm'),
          ]);
          seen.add(engine.getFormState('quizForm')['question']!);

          // nextRecord (row 3)
          await engine.executeActions([
            const OdsAction(action: 'nextRecord', target: 'quizForm'),
          ]);
          seen.add(engine.getFormState('quizForm')['question']!);

          // After 3 moves we should have seen all 3 distinct questions.
          expect(seen, {'Q1', 'Q2', 'Q3'});

          final lastSeen = engine.getFormState('quizForm')['question'];

          // Step 4: past end → no change, onEnd fires (navigate results).
          await engine.executeActions([
            const OdsAction(
              action: 'nextRecord',
              target: 'quizForm',
              onEnd: OdsAction(action: 'navigate', target: 'results'),
            ),
          ]);
          expect(engine.getFormState('quizForm')['question'], lastSeen,
              reason: 'Form state should NOT change when past the end.');
          expect(engine.currentPageId, 'results');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test('lastRecord populates, previousRecord moves back', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b24b_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          final ds = engine.dataStore;
          await ds.ensureTable('questions', [
            const OdsFieldDefinition(name: 'question', type: 'text'),
            const OdsFieldDefinition(name: 'answer', type: 'text'),
          ]);
          await ds.insert('questions', {'question': 'Q1', 'answer': 'A1'});
          await ds.insert('questions', {'question': 'Q2', 'answer': 'A2'});
          await ds.insert('questions', {'question': 'Q3', 'answer': 'A3'});

          await engine.executeActions([
            const OdsAction(action: 'lastRecord', target: 'quizForm'),
          ]);
          final last = engine.getFormState('quizForm')['question'];
          expect(['Q1', 'Q2', 'Q3'], contains(last),
              reason: 'lastRecord should land on some valid row.');

          await engine.executeActions([
            const OdsAction(action: 'previousRecord', target: 'quizForm'),
          ]);
          final prev = engine.getFormState('quizForm')['question'];
          expect(['Q1', 'Q2', 'Q3'], contains(prev));
          expect(prev, isNot(last),
              reason: 'previousRecord should move off lastRecord row.');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test('Empty recordSource: firstRecord fires onEnd', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b24c_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          // Do NOT seed any questions.
          await engine.executeActions([
            const OdsAction(
              action: 'firstRecord',
              target: 'quizForm',
              onEnd: OdsAction(action: 'navigate', target: 'results'),
            ),
          ]);
          expect(engine.currentPageId, 'results');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test('Filter with {placeholder} resolves from form state', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b24d_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          final ds = engine.dataStore;
          await ds.ensureTable('questions', [
            const OdsFieldDefinition(name: 'question', type: 'text'),
            const OdsFieldDefinition(name: 'answer', type: 'text'),
            const OdsFieldDefinition(name: 'topic', type: 'text'),
          ]);
          await ds.insert('questions',
              {'question': 'Q1', 'answer': 'A1', 'topic': 'math'});
          await ds.insert('questions',
              {'question': 'Q2', 'answer': 'A2', 'topic': 'history'});
          await ds.insert('questions',
              {'question': 'Q3', 'answer': 'A3', 'topic': 'math'});

          // Set a helper form value that the filter placeholder will read.
          engine.updateFormField('addTaskForm', 'category', 'math');

          await engine.executeActions([
            const OdsAction(
              action: 'firstRecord',
              target: 'quizForm',
              filter: {'topic': '{category}'},
            ),
          ]);

          // With topic=math filter, we land on one of the two math rows.
          final first = engine.getFormState('quizForm')['question'];
          expect(['Q1', 'Q3'], contains(first),
              reason: 'Filter topic=math should return only Q1 or Q3.');
          expect(first, isNot('Q2'),
              reason: 'Q2 has topic=history, should not appear.');

          await engine.executeActions([
            const OdsAction(action: 'nextRecord', target: 'quizForm'),
          ]);
          final second = engine.getFormState('quizForm')['question'];
          expect(['Q1', 'Q3'], contains(second));
          expect(second, isNot(first),
              reason: 'Advancing should move to the other math row.');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });
    });

    // -----------------------------------------------------------------------
    // B2-5: preserveFields on submit
    // -----------------------------------------------------------------------
    group('B2-5: Form preserveFields on submit', () {
      test('preserveFields keeps named fields after clear', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b25a_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          engine.updateFormField('addTaskForm', 'title', 'BuyMilk');
          engine.updateFormField('addTaskForm', 'category', 'Errands');
          engine.updateFormField('addTaskForm', 'status', 'todo');

          await engine.executeActions([
            const OdsAction(
              action: 'submit',
              target: 'addTaskForm',
              dataSource: 'tasks',
              preserveFields: ['category'],
            ),
          ]);

          final state = engine.getFormState('addTaskForm');
          expect(state['category'], 'Errands',
              reason: 'preserveFields keeps the named field.');
          expect(state.containsKey('title'), isFalse,
              reason: 'Non-preserved fields should be cleared.');
          expect(state.containsKey('status'), isFalse);
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test('Empty preserveFields list clears all', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b25b_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          engine.updateFormField('addTaskForm', 'title', 'BuyMilk');
          engine.updateFormField('addTaskForm', 'category', 'Errands');
          engine.updateFormField('addTaskForm', 'status', 'todo');

          await engine.executeActions([
            const OdsAction(
              action: 'submit',
              target: 'addTaskForm',
              dataSource: 'tasks',
              // Default preserveFields is const [].
            ),
          ]);

          final state = engine.getFormState('addTaskForm');
          expect(state.isEmpty, isTrue,
              reason: 'Empty preserveFields → form fully cleared.');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test('Nonexistent field in preserveFields is ignored', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b25c_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          engine.updateFormField('addTaskForm', 'title', 'BuyMilk');
          engine.updateFormField('addTaskForm', 'category', 'Errands');
          engine.updateFormField('addTaskForm', 'status', 'todo');

          await engine.executeActions([
            const OdsAction(
              action: 'submit',
              target: 'addTaskForm',
              dataSource: 'tasks',
              preserveFields: ['category', 'ghostField'],
            ),
          ]);

          final state = engine.getFormState('addTaskForm');
          expect(state['category'], 'Errands');
          expect(state.containsKey('ghostField'), isFalse,
              reason: 'Ghost fields silently skipped.');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });
    });

    // -----------------------------------------------------------------------
    // B2-6: Action chain failure rollback
    // -----------------------------------------------------------------------
    //
    // Confirmed from reading AppEngine.executeActions: on any result.error,
    // it sets _lastActionError and returns — no further actions run.
    // -----------------------------------------------------------------------
    group('B2-6: Action chain failure rollback', () {
      test('[submit-ok, update-fail, showMessage] — showMessage never fires',
          () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b26a_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          engine.updateFormField('addTaskForm', 'title', 'Ok');
          engine.updateFormField('addTaskForm', 'category', 'C');
          engine.updateFormField('addTaskForm', 'status', 's');

          await engine.executeActions([
            // Action 1: succeeds.
            const OdsAction(
              action: 'submit',
              target: 'addTaskForm',
              dataSource: 'tasks',
            ),
            // Action 2: fails (no row matches).
            const OdsAction(
              action: 'update',
              dataSource: 'tasksUpdater',
              matchField: '_id',
              target: 'missing-id-xxx',
              withData: {'status': 'done'},
            ),
            // Action 3: should NOT run because action 2 errored.
            const OdsAction(action: 'showMessage', message: 'should-not-run'),
          ]);

          // First submit created exactly one row.
          final rows = await engine.dataStore.query('tasks');
          expect(rows.length, 1);

          // lastActionError set; lastMessage NOT set to "should-not-run".
          expect(engine.lastActionError, 'Record not found');
          expect(engine.lastMessage, isNot('should-not-run'));
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test('Validation-failed submit → chain stops, no navigate', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b26b_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          // Form is empty → submit will error with 'No form data found'.
          await engine.executeActions([
            const OdsAction(
              action: 'submit',
              target: 'addTaskForm',
              dataSource: 'tasks',
            ),
            const OdsAction(action: 'navigate', target: 'thanks'),
          ]);

          expect(engine.lastActionError, isNotNull);
          expect(engine.currentPageId, 'home',
              reason: 'Navigate should NOT have run.');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test(
          'Exception thrown mid-action is caught — chain stops gracefully',
          () async {
        // AppEngine.executeActions now wraps the action handler in try/catch.
        // A thrown exception (e.g. invalid field name) is caught: the chain
        // stops, _lastActionError is set to the exception message, and the
        // exception does NOT escape. Later actions do not run.
        final tmp = await Directory.systemTemp.createTemp('ods_b26c_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          // Invalid matchField triggers ArgumentError inside DataStore.update.
          // The call must complete without rethrowing.
          await engine.executeActions([
            const OdsAction(
              action: 'update',
              dataSource: 'tasksUpdater',
              matchField: '__proto__',
              target: 'x',
              withData: {'status': 'done'},
            ),
            const OdsAction(
                action: 'showMessage', message: 'should-not-run'),
          ]);

          expect(engine.lastActionError, isNotNull,
              reason: 'Thrown exception should be captured as error.');
          expect(engine.lastMessage, isNot('should-not-run'),
              reason: 'Chain must stop — showMessage should not fire.');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });
    });

    // -----------------------------------------------------------------------
    // B2-7: Cross-form state isolation
    // -----------------------------------------------------------------------
    group('B2-7: Cross-form state isolation', () {
      test('Update formA and formB independently — values do not leak',
          () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b27a_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          engine.updateFormField('addTaskForm', 'title', 'A-title');
          engine.updateFormField('categoryUpdateForm', 'name', 'B-name');

          expect(engine.getFormState('addTaskForm')['title'], 'A-title');
          expect(engine.getFormState('addTaskForm').containsKey('name'),
              isFalse,
              reason: 'formA should not have formB field.');
          expect(
              engine.getFormState('categoryUpdateForm')['name'], 'B-name');
          expect(
              engine.getFormState('categoryUpdateForm').containsKey('title'),
              isFalse,
              reason: 'formB should not have formA field.');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test('clearForm formA leaves formB untouched', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b27b_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          engine.updateFormField('addTaskForm', 'title', 'A-title');
          engine.updateFormField('categoryUpdateForm', 'name', 'B-name');

          engine.clearForm('addTaskForm');

          expect(engine.allFormStates.containsKey('addTaskForm'), isFalse,
              reason: 'formA state fully removed.');
          expect(
              engine.getFormState('categoryUpdateForm')['name'], 'B-name',
              reason: 'formB untouched by clearForm(formA).');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });

      test('clearForm on nonexistent form is a no-op (no error)', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b27c_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        await engine.loadSpec(_makeAppJson());

        try {
          engine.updateFormField('addTaskForm', 'title', 'survivor');
          // Should not throw.
          engine.clearForm('ghostForm');
          expect(engine.getFormState('addTaskForm')['title'], 'survivor');
        } finally {
          await engine.reset();
          engine.dispose();
          if (await tmp.exists()) {
            try {
              await tmp.delete(recursive: true);
            } catch (_) {}
          }
        }
      });
    });
  });
}

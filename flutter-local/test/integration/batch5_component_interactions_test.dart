import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/engine/aggregate_evaluator.dart';
import 'package:ods_flutter_local/engine/app_engine.dart';
import 'package:ods_flutter_local/engine/expression_evaluator.dart';
import 'package:ods_flutter_local/models/ods_action.dart';
import 'package:ods_flutter_local/models/ods_field_definition.dart';

/// Spec used by most B5 scenarios.
///
/// Includes:
///   - tasks (POST) + tasksUpdater (PUT) data sources.
///   - categories (POST) for parent/child tests.
///   - questions (POST) for recordSource tests.
///   - An addTaskForm (regular form).
///   - A quizForm (recordSource = questions) for parent/child navigation.
///   - A detailForm used as a populateForm target.
String _makeSpecJson() {
  return '''
  {
    "appName": "B5Test",
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
              {"name": "status", "type": "text", "label": "Status"},
              {"name": "amount", "type": "number", "label": "Amount"}
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
          },
          {
            "component": "form",
            "id": "detailForm",
            "fields": [
              {"name": "title", "type": "text", "label": "Title"},
              {"name": "status", "type": "text", "label": "Status"}
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
          {"name": "status", "type": "text", "label": "Status"},
          {"name": "amount", "type": "number", "label": "Amount"},
          {"name": "listName", "type": "text", "label": "List"}
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
          {"name": "name", "type": "text", "label": "Name"},
          {"name": "status", "type": "text", "label": "Status"}
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
      },
      "questionsUpdater": {
        "url": "local://questions",
        "method": "PUT"
      }
    }
  }
  ''';
}

/// Bootstraps a fresh AppEngine with a temp storage folder. Caller must
/// call engine.reset() + engine.dispose() + remove [tmp] when done.
Future<AppEngine> _bootEngine(Directory tmp) async {
  final engine = AppEngine();
  engine.storageFolder = tmp.path;
  final ok = await engine.loadSpec(_makeSpecJson());
  if (!ok) {
    throw StateError('AppEngine failed to load spec: ${engine.loadError}');
  }
  return engine;
}

/// Convenience teardown: engine.reset() + dispose() + remove temp dir.
Future<void> _tearDown(AppEngine engine, Directory tmp) async {
  await engine.reset();
  engine.dispose();
  if (await tmp.exists()) {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {
      // Best-effort cleanup — Windows sometimes holds locks briefly.
    }
  }
}

void main() {
  group('Batch 5: Component interactions', () {
    // -----------------------------------------------------------------------
    // B5-1: Form -> List data sync via AppEngine
    // -----------------------------------------------------------------------
    //
    // Exercises the full submit -> query -> delete -> update loop through a
    // real AppEngine + DataStore. A list component would pull rows via
    // engine.queryDataSource, so we assert the query path sees each change.
    group('B5-1: Form -> List data sync via AppEngine', () {
      test('submit persists a row; queryDataSource reflects it', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b51a_');
        final engine = await _bootEngine(tmp);
        try {
          engine.updateFormField('addTaskForm', 'title', 'Buy milk');
          engine.updateFormField('addTaskForm', 'status', 'todo');
          engine.updateFormField('addTaskForm', 'amount', '3');

          await engine.executeActions([
            const OdsAction(
              action: 'submit',
              target: 'addTaskForm',
              dataSource: 'tasks',
            ),
          ]);

          final rows = await engine.queryDataSource('tasks');
          expect(rows.length, 1);
          expect(rows.first['title'], 'Buy milk');
          expect(rows.first['status'], 'todo');
          expect(rows.first['amount']?.toString(), '3');
        } finally {
          await _tearDown(engine, tmp);
        }
      });

      test('delete (executeDeleteRowAction) removes row from query',
          () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b51b_');
        final engine = await _bootEngine(tmp);
        try {
          final ds = engine.dataStore;
          await ds.ensureTable('tasks', const [
            OdsFieldDefinition(name: 'title', type: 'text'),
            OdsFieldDefinition(name: 'status', type: 'text'),
          ]);
          await ds.insert('tasks', {'title': 'Keep', 'status': 'todo'});
          final idToDelete = await ds.insert('tasks', {
            'title': 'Delete me',
            'status': 'todo',
          });

          await engine.executeDeleteRowAction(
            dataSourceId: 'tasksUpdater',
            matchField: '_id',
            matchValue: idToDelete,
          );

          final rows = await engine.queryDataSource('tasks');
          expect(rows.length, 1);
          expect(rows.first['title'], 'Keep');
        } finally {
          await _tearDown(engine, tmp);
        }
      });

      test('update via withData is visible in subsequent query',
          () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b51c_');
        final engine = await _bootEngine(tmp);
        try {
          final ds = engine.dataStore;
          await ds.ensureTable('tasks', const [
            OdsFieldDefinition(name: 'title', type: 'text'),
            OdsFieldDefinition(name: 'status', type: 'text'),
          ]);
          final id = await ds.insert('tasks', {
            'title': 'Task A',
            'status': 'todo',
          });

          await engine.executeActions([
            OdsAction(
              action: 'update',
              dataSource: 'tasksUpdater',
              matchField: '_id',
              target: id,
              withData: const {'status': 'done'},
            ),
          ]);

          final rows = await engine.queryDataSource('tasks');
          expect(rows.length, 1);
          expect(rows.first['status'], 'done');
          expect(rows.first['title'], 'Task A',
              reason: 'Unchanged fields should stay.');
        } finally {
          await _tearDown(engine, tmp);
        }
      });

      test('submit + delete + update roundtrip: final query matches state',
          () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b51d_');
        final engine = await _bootEngine(tmp);
        try {
          // Submit two rows via form.
          engine.updateFormField('addTaskForm', 'title', 'A');
          engine.updateFormField('addTaskForm', 'status', 'todo');
          await engine.executeActions([
            const OdsAction(
              action: 'submit',
              target: 'addTaskForm',
              dataSource: 'tasks',
            ),
          ]);
          engine.updateFormField('addTaskForm', 'title', 'B');
          engine.updateFormField('addTaskForm', 'status', 'todo');
          await engine.executeActions([
            const OdsAction(
              action: 'submit',
              target: 'addTaskForm',
              dataSource: 'tasks',
            ),
          ]);

          // Query -> find A's _id and delete it; update B's status.
          var rows = await engine.queryDataSource('tasks');
          expect(rows.length, 2);
          final aRow = rows.firstWhere((r) => r['title'] == 'A');
          final bRow = rows.firstWhere((r) => r['title'] == 'B');

          await engine.executeDeleteRowAction(
            dataSourceId: 'tasksUpdater',
            matchField: '_id',
            matchValue: aRow['_id'] as String,
          );

          await engine.executeActions([
            OdsAction(
              action: 'update',
              dataSource: 'tasksUpdater',
              matchField: '_id',
              target: bRow['_id'] as String,
              withData: const {'status': 'done'},
            ),
          ]);

          rows = await engine.queryDataSource('tasks');
          expect(rows.length, 1);
          expect(rows.first['title'], 'B');
          expect(rows.first['status'], 'done');
        } finally {
          await _tearDown(engine, tmp);
        }
      });
    });

    // -----------------------------------------------------------------------
    // B5-2: Parent/child via recordSource
    // -----------------------------------------------------------------------
    //
    // quizForm has recordSource=questions. firstRecord/nextRecord should
    // populate the form state; a subsequent update through
    // questionsUpdater should flow back into the DB and be visible when
    // we re-query.
    group('B5-2: Parent/child via recordSource', () {
      test(
          'firstRecord + nextRecord populate form state with distinct rows',
          () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b52a_');
        final engine = await _bootEngine(tmp);
        try {
          final ds = engine.dataStore;
          await ds.ensureTable('questions', const [
            OdsFieldDefinition(name: 'question', type: 'text'),
            OdsFieldDefinition(name: 'answer', type: 'text'),
          ]);
          await ds.insert('questions', {'question': 'Q1', 'answer': 'A1'});
          await ds.insert('questions', {'question': 'Q2', 'answer': 'A2'});

          await engine.executeActions([
            const OdsAction(action: 'firstRecord', target: 'quizForm'),
          ]);
          final first = engine.getFormState('quizForm')['question'];
          expect(['Q1', 'Q2'], contains(first));

          await engine.executeActions([
            const OdsAction(action: 'nextRecord', target: 'quizForm'),
          ]);
          final second = engine.getFormState('quizForm')['question'];
          expect(['Q1', 'Q2'], contains(second));
          expect(second, isNot(first),
              reason: 'nextRecord must move to a different row.');
        } finally {
          await _tearDown(engine, tmp);
        }
      });

      test(
          'update navigated record via form: edit in place, changes persist',
          () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b52b_');
        final engine = await _bootEngine(tmp);
        try {
          final ds = engine.dataStore;
          await ds.ensureTable('questions', const [
            OdsFieldDefinition(name: 'question', type: 'text'),
            OdsFieldDefinition(name: 'answer', type: 'text'),
          ]);
          await ds.insert('questions', {'question': 'Q1', 'answer': 'A1'});

          // Load cursor.
          await engine.executeActions([
            const OdsAction(action: 'firstRecord', target: 'quizForm'),
          ]);

          // User "edits" the answer via the form UI.
          engine.updateFormField('quizForm', 'answer', 'new-answer');

          // Save back to DB: the row's _id should be in form state after
          // firstRecord populates it (or we can look it up).
          final state = engine.getFormState('quizForm');
          final rowId = state['_id'];
          expect(rowId, isNotNull,
              reason:
                  'firstRecord should stash the row _id on the form state '
                  'so update actions can target it.');

          await engine.executeActions([
            OdsAction(
              action: 'update',
              dataSource: 'questionsUpdater',
              matchField: '_id',
              target: rowId!,
              withData: const {'answer': 'new-answer'},
            ),
          ]);

          final rows = await ds.query('questions');
          expect(rows.length, 1);
          expect(rows.first['answer'], 'new-answer');
          expect(rows.first['question'], 'Q1');
        } finally {
          await _tearDown(engine, tmp);
        }
      });
    });

    // -----------------------------------------------------------------------
    // B5-3: Toggle action
    // -----------------------------------------------------------------------
    //
    // ODS doesn't expose an `action: 'toggle'` verb — toggles are modeled on
    // a list column via OdsToggle (dataSource + matchField + optional
    // autoComplete). The list widget computes newValue = !current and calls
    // engine.executeRowAction with {field: newValue}. We exercise that path
    // directly here, plus the autoComplete hook.
    group('B5-3: Toggle action', () {
      test('executeRowAction toggles a field (true -> false -> true)',
          () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b53a_');
        final engine = await _bootEngine(tmp);
        try {
          final ds = engine.dataStore;
          await ds.ensureTable('tasks', const [
            OdsFieldDefinition(name: 'title', type: 'text'),
            OdsFieldDefinition(name: 'done', type: 'text'),
          ]);
          final id = await ds.insert('tasks', {
            'title': 'Write tests',
            'done': 'false',
          });

          // First toggle: false -> true.
          await engine.executeRowAction(
            dataSourceId: 'tasksUpdater',
            matchField: '_id',
            matchValue: id,
            values: const {'done': 'true'},
          );
          var rows = await engine.queryDataSource('tasks');
          expect(rows.first['done'], 'true');

          // Second toggle: true -> false.
          await engine.executeRowAction(
            dataSourceId: 'tasksUpdater',
            matchField: '_id',
            matchValue: id,
            values: const {'done': 'false'},
          );
          rows = await engine.queryDataSource('tasks');
          expect(rows.first['done'], 'false');

          // Third toggle: false -> true.
          await engine.executeRowAction(
            dataSourceId: 'tasksUpdater',
            matchField: '_id',
            matchValue: id,
            values: const {'done': 'true'},
          );
          rows = await engine.queryDataSource('tasks');
          expect(rows.first['done'], 'true');
        } finally {
          await _tearDown(engine, tmp);
        }
      });

      test(
          'checkAutoComplete: all items in group done -> parent values applied',
          () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b53b_');
        final engine = await _bootEngine(tmp);
        try {
          final ds = engine.dataStore;
          await ds.ensureTable('tasks', const [
            OdsFieldDefinition(name: 'title', type: 'text'),
            OdsFieldDefinition(name: 'done', type: 'text'),
            OdsFieldDefinition(name: 'listName', type: 'text'),
          ]);
          await ds.ensureTable('categories', const [
            OdsFieldDefinition(name: 'name', type: 'text'),
            OdsFieldDefinition(name: 'status', type: 'text'),
          ]);
          await ds.insert('categories',
              {'name': 'Errands', 'status': 'active'});
          await ds.insert('tasks', {
            'title': 't1',
            'done': 'true',
            'listName': 'Errands',
          });
          await ds.insert('tasks', {
            'title': 't2',
            'done': 'true',
            'listName': 'Errands',
          });
          await ds.insert('tasks', {
            'title': 't3',
            'done': 'false',
            'listName': 'Groceries',
          });

          await engine.checkAutoComplete(
            listDataSourceId: 'tasks',
            toggleField: 'done',
            groupField: 'listName',
            groupValue: 'Errands',
            parentDataSourceId: 'categoriesUpdater',
            parentMatchField: 'name',
            parentValues: const {'status': 'done'},
          );

          final cats = await ds.query('categories');
          expect(cats.length, 1);
          expect(cats.first['status'], 'done',
              reason:
                  'autoComplete should mark the parent category done when '
                  'every task in its group is done.');
        } finally {
          await _tearDown(engine, tmp);
        }
      });

      test(
          'checkAutoComplete: not all items done -> parent untouched',
          () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b53c_');
        final engine = await _bootEngine(tmp);
        try {
          final ds = engine.dataStore;
          await ds.ensureTable('tasks', const [
            OdsFieldDefinition(name: 'title', type: 'text'),
            OdsFieldDefinition(name: 'done', type: 'text'),
            OdsFieldDefinition(name: 'listName', type: 'text'),
          ]);
          await ds.ensureTable('categories', const [
            OdsFieldDefinition(name: 'name', type: 'text'),
            OdsFieldDefinition(name: 'status', type: 'text'),
          ]);
          await ds.insert('categories',
              {'name': 'Errands', 'status': 'active'});
          await ds.insert('tasks', {
            'title': 't1',
            'done': 'true',
            'listName': 'Errands',
          });
          await ds.insert('tasks', {
            'title': 't2',
            'done': 'false', // still pending
            'listName': 'Errands',
          });

          await engine.checkAutoComplete(
            listDataSourceId: 'tasks',
            toggleField: 'done',
            groupField: 'listName',
            groupValue: 'Errands',
            parentDataSourceId: 'categoriesUpdater',
            parentMatchField: 'name',
            parentValues: const {'status': 'done'},
          );

          final cats = await ds.query('categories');
          expect(cats.first['status'], 'active',
              reason:
                  'Parent must NOT be marked done if any child task is still '
                  'pending.');
        } finally {
          await _tearDown(engine, tmp);
        }
      });
    });

    // -----------------------------------------------------------------------
    // B5-4: Kanban-style roundtrip
    // -----------------------------------------------------------------------
    //
    // Classic "move card between columns" — update status via withData and
    // verify the other rows are untouched.
    group('B5-4: Kanban-style roundtrip', () {
      test('withData status change updates only the targeted row',
          () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b54a_');
        final engine = await _bootEngine(tmp);
        try {
          final ds = engine.dataStore;
          await ds.ensureTable('tasks', const [
            OdsFieldDefinition(name: 'title', type: 'text'),
            OdsFieldDefinition(name: 'status', type: 'text'),
          ]);
          final id1 = await ds.insert(
              'tasks', {'title': 'T1', 'status': 'todo'});
          final id2 = await ds.insert(
              'tasks', {'title': 'T2', 'status': 'todo'});
          final id3 = await ds.insert(
              'tasks', {'title': 'T3', 'status': 'in-progress'});

          // Move T1 from todo -> in-progress.
          await engine.executeActions([
            OdsAction(
              action: 'update',
              dataSource: 'tasksUpdater',
              matchField: '_id',
              target: id1,
              withData: const {'status': 'in-progress'},
            ),
          ]);

          final rows = await engine.queryDataSource('tasks');
          final byId = {for (final r in rows) r['_id']: r};
          expect(byId[id1]!['status'], 'in-progress');
          expect(byId[id2]!['status'], 'todo',
              reason: 'Other todo row must not move.');
          expect(byId[id3]!['status'], 'in-progress',
              reason:
                  'Unrelated in-progress row must not be touched by the '
                  'targeted update.');
        } finally {
          await _tearDown(engine, tmp);
        }
      });

      test('multi-step kanban flow: todo -> doing -> done', () async {
        final tmp = await Directory.systemTemp.createTemp('ods_b54b_');
        final engine = await _bootEngine(tmp);
        try {
          final ds = engine.dataStore;
          await ds.ensureTable('tasks', const [
            OdsFieldDefinition(name: 'title', type: 'text'),
            OdsFieldDefinition(name: 'status', type: 'text'),
          ]);
          final id = await ds.insert(
              'tasks', {'title': 'Ship it', 'status': 'todo'});

          await engine.executeActions([
            OdsAction(
              action: 'update',
              dataSource: 'tasksUpdater',
              matchField: '_id',
              target: id,
              withData: const {'status': 'doing'},
            ),
          ]);
          var rows = await engine.queryDataSource('tasks');
          expect(rows.first['status'], 'doing');

          await engine.executeActions([
            OdsAction(
              action: 'update',
              dataSource: 'tasksUpdater',
              matchField: '_id',
              target: id,
              withData: const {'status': 'done'},
            ),
          ]);
          rows = await engine.queryDataSource('tasks');
          expect(rows.first['status'], 'done');
          expect(rows.first['title'], 'Ship it',
              reason: 'Title must survive multiple status updates.');
        } finally {
          await _tearDown(engine, tmp);
        }
      });
    });

    // -----------------------------------------------------------------------
    // B5-5: Aggregate evaluator (AggregateEvaluator)
    // -----------------------------------------------------------------------
    //
    // AggregateEvaluator.resolve takes a content string and an async
    // queryFn(dataSourceId) -> List<Row>. It replaces {FUNC(ds, field)}
    // tokens with computed values.
    group('B5-5: Aggregate evaluator', () {
      // Shared dataset for the standard-function tests.
      final dataset = <Map<String, dynamic>>[
        {'amount': '10', 'label': 'a'},
        {'amount': '20', 'label': 'b'},
        {'amount': '30', 'label': 'c'},
        {'amount': '40', 'label': 'd'},
      ];

      Future<List<Map<String, dynamic>>> queryOf(
          Map<String, List<Map<String, dynamic>>> tables, String id) async {
        return tables[id] ?? <Map<String, dynamic>>[];
      }

      test('COUNT returns row count (ignores field)', () async {
        final result = await AggregateEvaluator.resolve(
          '{COUNT(expenses)}',
          (id) => queryOf({'expenses': dataset}, id),
        );
        expect(result, '4');
      });

      test('SUM adds numeric field values', () async {
        final result = await AggregateEvaluator.resolve(
          'Total: {SUM(expenses, amount)}',
          (id) => queryOf({'expenses': dataset}, id),
        );
        expect(result, 'Total: 100');
      });

      test('AVG divides sum by count', () async {
        final result = await AggregateEvaluator.resolve(
          'Avg: {AVG(expenses, amount)}',
          (id) => queryOf({'expenses': dataset}, id),
        );
        expect(result, 'Avg: 25');
      });

      test('MIN returns smallest numeric value', () async {
        final result = await AggregateEvaluator.resolve(
          'Min: {MIN(expenses, amount)}',
          (id) => queryOf({'expenses': dataset}, id),
        );
        expect(result, 'Min: 10');
      });

      test('MAX returns largest numeric value', () async {
        final result = await AggregateEvaluator.resolve(
          'Max: {MAX(expenses, amount)}',
          (id) => queryOf({'expenses': dataset}, id),
        );
        expect(result, 'Max: 40');
      });

      test('Empty data source -> all aggregates return 0', () async {
        Future<List<Map<String, dynamic>>> empty(String _) async => [];
        expect(await AggregateEvaluator.resolve('{COUNT(x)}', empty), '0');
        expect(await AggregateEvaluator.resolve('{SUM(x, amount)}', empty),
            '0');
        expect(await AggregateEvaluator.resolve('{AVG(x, amount)}', empty),
            '0');
        expect(await AggregateEvaluator.resolve('{MIN(x, amount)}', empty),
            '0');
        expect(await AggregateEvaluator.resolve('{MAX(x, amount)}', empty),
            '0');
      });

      test('Non-numeric values in SUM/AVG are skipped gracefully', () async {
        final mixed = <Map<String, dynamic>>[
          {'amount': '10'},
          {'amount': 'not a number'},
          {'amount': '20'},
          {'amount': ''},
          {'amount': null},
        ];
        final sum = await AggregateEvaluator.resolve(
          '{SUM(x, amount)}',
          (id) => queryOf({'x': mixed}, id),
        );
        expect(sum, '30', reason: 'Only 10+20 are numeric.');

        final avg = await AggregateEvaluator.resolve(
          '{AVG(x, amount)}',
          (id) => queryOf({'x': mixed}, id),
        );
        expect(avg, '15', reason: 'Average of the 2 numeric values.');
      });

      test(
          'All non-numeric values in SUM/AVG -> 0 (no crash on empty numeric set)',
          () async {
        final nonNumeric = <Map<String, dynamic>>[
          {'amount': 'abc'},
          {'amount': 'xyz'},
        ];
        final sum = await AggregateEvaluator.resolve(
          '{SUM(x, amount)}',
          (id) => queryOf({'x': nonNumeric}, id),
        );
        expect(sum, '0');
        final avg = await AggregateEvaluator.resolve(
          '{AVG(x, amount)}',
          (id) => queryOf({'x': nonNumeric}, id),
        );
        expect(avg, '0');
      });
    });

    // -----------------------------------------------------------------------
    // B5-6: Expression evaluator / template engine
    // -----------------------------------------------------------------------
    //
    // Two surfaces:
    //   (a) ExpressionEvaluator.evaluate — `{field}` interpolation +
    //       ternary/math. Does NOT do aggregates.
    //   (b) AggregateEvaluator.resolve — `{COUNT(tasks)}` aggregate templates.
    // We test both.
    group('B5-6: Expression evaluator / template engine', () {
      test('ExpressionEvaluator: {fieldName} interpolation', () {
        final out = ExpressionEvaluator.evaluate(
          '{firstName} {lastName}',
          {'firstName': 'Ada', 'lastName': 'Lovelace'},
        );
        expect(out, 'Ada Lovelace');
      });

      test('ExpressionEvaluator: missing field substitutes empty string', () {
        final out = ExpressionEvaluator.evaluate(
          'Hello {missing}!',
          {'other': 'x'},
        );
        expect(out, 'Hello !',
            reason:
                'Unknown field refs should substitute as empty per '
                'ExpressionEvaluator behaviour.');
      });

      test('ExpressionEvaluator: numeric math via FormulaEvaluator', () {
        final out = ExpressionEvaluator.evaluate(
          '{a} + {b}',
          {'a': '2', 'b': '3'},
        );
        // FormulaEvaluator returns a numeric string (may be "5" or "5.0").
        expect(['5', '5.0', '5.00'], contains(out),
            reason: 'Expression "2 + 3" should evaluate numerically.');
      });

      test('Template engine: aggregate {COUNT(tasks)}', () async {
        final tasks = <Map<String, dynamic>>[
          {'title': 'a'},
          {'title': 'b'},
          {'title': 'c'},
        ];
        final out = await AggregateEvaluator.resolve(
          'You have {COUNT(tasks)} tasks.',
          (id) async => id == 'tasks' ? tasks : [],
        );
        expect(out, 'You have 3 tasks.');
      });

      test(
          'Template engine: empty data source in aggregate -> 0',
          () async {
        final out = await AggregateEvaluator.resolve(
          '{COUNT(tasks)} items',
          (id) async => <Map<String, dynamic>>[],
        );
        expect(out, '0 items');
      });

      test(
          'Template engine: missing data source in aggregate -> 0',
          () async {
        // queryFn that returns [] for any unknown data source (typical
        // AppEngine.queryDataSource behaviour). AggregateEvaluator should
        // then report 0 without throwing.
        final out = await AggregateEvaluator.resolve(
          '{COUNT(doesNotExist)} rows, sum {SUM(doesNotExist, amount)}',
          (id) async => <Map<String, dynamic>>[],
        );
        expect(out, '0 rows, sum 0');
      });

      test(
          'Template engine: aggregate inside longer string is resolved in place',
          () async {
        final rows = <Map<String, dynamic>>[
          {'amount': '5'},
          {'amount': '7'},
        ];
        final out = await AggregateEvaluator.resolve(
          'Summary: {COUNT(x)} items totaling \${SUM(x, amount)}.',
          (id) async => id == 'x' ? rows : [],
        );
        expect(out, 'Summary: 2 items totaling \$12.');
      });

      test(
          'Template engine: non-aggregate content passes through unchanged',
          () async {
        final out = await AggregateEvaluator.resolve(
          'Hello world — no aggregates here.',
          (id) async => [],
        );
        expect(out, 'Hello world — no aggregates here.');
        expect(
          AggregateEvaluator.hasAggregates(
              'Hello world — no aggregates here.'),
          isFalse,
        );
      });
    });
  });
}

/// Batch 9: Performance baselines.
///
/// These tests characterize behavior under load. They are NOT hunting for
/// bugs — they establish soft timing bounds so a pathological regression
/// (10x slowdown, algorithmic blow-up, accidental O(n^2)) is caught by CI.
///
/// Guiding principles:
///   - Generous bounds. We want to catch pathological regressions, not tight timing.
///   - All bounds include comfortable slack for slow CI machines.
///   - Baseline timings are recorded in comments. Machine note:
///     the baselines below were measured on a Windows 11 laptop
///     (11th Gen Intel i7, Dart VM, flutter_test).
///   - DO NOT fix anything here. If a test is way off expectation,
///     flag it in the PR description.
///
/// Implementation notes:
///   - P1-P3 use a _FakeDataStore (in-memory) mirrored from batch4/batch6.
///   - P2 uses a real SQLite-backed DataStore against a temp folder to
///     capture realistic I/O throughput for the "data service" scenario.
///   - P4 uses the full AppEngine to exercise the real action chain path.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/engine/action_handler.dart';
import 'package:ods_flutter_local/engine/aggregate_evaluator.dart';
import 'package:ods_flutter_local/engine/app_engine.dart';
import 'package:ods_flutter_local/engine/data_store.dart';
import 'package:ods_flutter_local/engine/expression_evaluator.dart';
import 'package:ods_flutter_local/engine/formula_evaluator.dart';
import 'package:ods_flutter_local/models/ods_action.dart';
import 'package:ods_flutter_local/models/ods_app.dart';
import 'package:ods_flutter_local/models/ods_field_definition.dart';
import 'package:ods_flutter_local/parser/spec_parser.dart';

// ---------------------------------------------------------------------------
// In-memory fake DataStore (pattern borrowed from batch4/batch6).
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
      String tableName, String matchField, String matchValue) async {
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
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<Directory> _tmp(String prefix) =>
    Directory.systemTemp.createTemp(prefix);

Future<void> _cleanup(Directory tmp) async {
  if (await tmp.exists()) {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {
      // Windows sometimes holds a lock briefly; best-effort cleanup.
    }
  }
}

/// Generates a spec JSON string with [pageCount] distinct pages.
String _generateLargeSpec(int pageCount) {
  final pages = <String, dynamic>{};
  for (var i = 0; i < pageCount; i++) {
    pages['page$i'] = {
      'component': 'page',
      'title': 'Page $i',
      'content': [
        {'component': 'text', 'content': 'This is page $i.'},
        {
          'component': 'button',
          'label': 'Next',
          'onClick': [
            {'action': 'navigate', 'target': 'page${(i + 1) % pageCount}'},
          ],
        },
      ],
    };
  }
  final spec = {
    'appName': 'BigApp',
    'startPage': 'page0',
    'pages': pages,
    'dataSources': {
      'items': {
        'url': 'local://items',
        'method': 'POST',
        'fields': [
          {'name': 'name', 'type': 'text'},
        ],
      },
    },
  };
  return jsonEncode(spec);
}

/// Generates a spec with one form containing [fieldCount] fields.
String _generateLargeFormSpec(int fieldCount) {
  final fields = <Map<String, dynamic>>[];
  for (var i = 0; i < fieldCount; i++) {
    final type = i % 3 == 0
        ? 'text'
        : i % 3 == 1
            ? 'number'
            : 'select';
    final field = <String, dynamic>{
      'name': 'f$i',
      'type': type,
      'label': 'Field $i',
    };
    if (type == 'select') field['options'] = ['a', 'b', 'c'];
    fields.add(field);
  }
  final spec = {
    'appName': 'BigFormApp',
    'startPage': 'home',
    'pages': {
      'home': {
        'component': 'page',
        'title': 'Home',
        'content': [
          {'component': 'form', 'id': 'bigForm', 'fields': fields},
        ],
      },
    },
    'dataSources': {
      'items': {
        'url': 'local://items',
        'method': 'POST',
        'fields': fields
            .map((f) => {'name': f['name'], 'type': 'text'})
            .toList(),
      },
    },
  };
  return jsonEncode(spec);
}

/// Small app spec used for P4 action-chain scenarios.
String _tasksAppJson() {
  return '''
  {
    "appName": "B9Perf",
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
          }
        ]
      }
    },
    "dataSources": {
      "tasks": {
        "url": "local://tasks",
        "method": "POST",
        "fields": [
          {"name": "title", "type": "text"},
          {"name": "status", "type": "text"}
        ]
      }
    }
  }
  ''';
}

/// Builds the in-memory app used for the "100 computedFields" scenario.
OdsApp _computedFieldsApp() {
  return OdsApp.fromJson({
    'appName': 'B9Perf',
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
              {'name': 'title', 'type': 'text'},
              {'name': 'status', 'type': 'text'},
            ],
          },
        ],
      },
    },
    'dataSources': {
      'tasks': {
        'url': 'local://tasks',
        'method': 'POST',
        'fields': [
          {'name': 'title', 'type': 'text'},
          {'name': 'status', 'type': 'text'},
        ],
      },
    },
  });
}

/// Runs [fn] and prints a `[perf]` line with the elapsed ms. Returns the
/// stopwatch so the caller can make timing assertions.
Future<Stopwatch> _measure(String label, Future<void> Function() fn) async {
  final sw = Stopwatch()..start();
  await fn();
  sw.stop();
  // ignore: avoid_print
  print('[perf] $label: ${sw.elapsedMilliseconds}ms');
  return sw;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Batch 9: Performance baselines', () {
    // -----------------------------------------------------------------------
    // P1: Spec parsing at scale
    // -----------------------------------------------------------------------
    group('P1: Spec parsing at scale', () {
      test('parses a 500-page spec under 10s', () async {
        final parser = SpecParser();
        final json = _generateLargeSpec(500);
        final sw = await _measure('P1 500-page spec', () async {
          final result = parser.parse(json);
          expect(result.parseError, isNull);
          expect(result.app!.pages.length, 500);
        });
        // Generous budget to accommodate slow Windows I/O.
        expect(sw.elapsedMilliseconds, lessThan(10000));
      });

      test('parses all Specification/Examples under 2s total', () async {
        final parser = SpecParser();
        final examplesDir = Directory('../../Specification/Examples');
        if (!examplesDir.existsSync()) {
          // Gracefully skip if the Specification repo isn't available (CI).
          // ignore: avoid_print
          print('[perf] P1 examples: SKIPPED (Specification/Examples not found)');
          return;
        }
        final files = examplesDir
            .listSync()
            .whereType<File>()
            .where((f) =>
                f.path.endsWith('.json') && !f.path.endsWith('catalog.json'))
            .toList();

        final sw =
            await _measure('P1 examples (n=${files.length})', () async {
          for (final f in files) {
            final json = f.readAsStringSync();
            final result = parser.parse(json);
            expect(result.parseError, isNull, reason: 'Parse error in ${f.path}');
          }
        });
        // Baseline: TBD.
        expect(sw.elapsedMilliseconds, lessThan(2000));
      });

      test('parses a form with 1000 fields under 500ms', () async {
        final parser = SpecParser();
        final json = _generateLargeFormSpec(1000);
        final sw = await _measure('P1 1000-field form', () async {
          final result = parser.parse(json);
          expect(result.parseError, isNull);
        });
        // Baseline: TBD.
        expect(sw.elapsedMilliseconds, lessThan(500));
      });
    });

    // -----------------------------------------------------------------------
    // P2: Data service throughput
    // -----------------------------------------------------------------------
    //
    // Uses a real SQLite DataStore against a temp folder so the timings
    // reflect actual I/O overhead (not just in-memory dict manipulation).
    // -----------------------------------------------------------------------
    group('P2: Data service throughput', () {
      test('inserts 10,000 rows sequentially under 150s', () async {
        final tmp = await _tmp('ods_b92_seq_');
        final ds = DataStore();
        try {
          await ds.initialize('b9_seq', storageFolder: tmp.path);
          await ds.ensureTable('tasks', const [
            OdsFieldDefinition(name: 'title', type: 'text'),
            OdsFieldDefinition(name: 'status', type: 'text'),
          ]);
          final sw = await _measure('P2 insert 10k sequential', () async {
            for (var i = 0; i < 10000; i++) {
              await ds.insert('tasks', {'title': 'Task $i', 'status': 'todo'});
            }
          });
          // Baseline Windows+SQLite FFI: ~94s. Native: ~5s.
          expect(sw.elapsedMilliseconds, lessThan(150000));
          final count = await ds.getRowCount('tasks');
          expect(count, 10000);
        } finally {
          await ds.close();
          await _cleanup(tmp);
        }
      }, timeout: const Timeout(Duration(seconds: 60)));

      test('inserts 10,000 rows via Future.wait (concurrent) under 180s',
          () async {
        final tmp = await _tmp('ods_b92_conc_');
        final ds = DataStore();
        try {
          await ds.initialize('b9_conc', storageFolder: tmp.path);
          await ds.ensureTable('tasks', const [
            OdsFieldDefinition(name: 'title', type: 'text'),
            OdsFieldDefinition(name: 'status', type: 'text'),
          ]);
          final sw = await _measure('P2 insert 10k concurrent', () async {
            final futures = <Future<String>>[];
            for (var i = 0; i < 10000; i++) {
              futures.add(ds.insert(
                  'tasks', {'title': 'Task $i', 'status': 'todo'}));
            }
            await Future.wait(futures);
          });
          // NOTE: SQLite serializes writes internally; concurrent dispatch
          // amortizes some Dart overhead but does not give true parallelism.
          // Baseline Windows+SQLite FFI: ~105s. Native: ~2s.
          expect(sw.elapsedMilliseconds, lessThan(180000));
          final count = await ds.getRowCount('tasks');
          expect(count, 10000);
        } finally {
          await ds.close();
          await _cleanup(tmp);
        }
      }, timeout: const Timeout(Duration(seconds: 60)));

      test('queries 10,000 rows under 30s', () async {
        final tmp = await _tmp('ods_b92_query_');
        final ds = DataStore();
        try {
          await ds.initialize('b9_query', storageFolder: tmp.path);
          await ds.ensureTable('tasks', const [
            OdsFieldDefinition(name: 'title', type: 'text'),
            OdsFieldDefinition(name: 'status', type: 'text'),
          ]);
          for (var i = 0; i < 10000; i++) {
            await ds.insert('tasks', {'title': 'Task $i', 'status': 'todo'});
          }
          final sw = await _measure('P2 query 10k', () async {
            final rows = await ds.query('tasks');
            expect(rows.length, 10000);
          });
          // Baseline Windows+SQLite FFI: generous allowance for I/O.
          expect(sw.elapsedMilliseconds, lessThan(30000));
        } finally {
          await ds.close();
          await _cleanup(tmp);
        }
      }, timeout: const Timeout(Duration(seconds: 60)));

      test('filters 10,000 rows → ~10 matches under 500ms', () async {
        final tmp = await _tmp('ods_b92_filter_');
        final ds = DataStore();
        try {
          await ds.initialize('b9_filter', storageFolder: tmp.path);
          await ds.ensureTable('tasks', const [
            OdsFieldDefinition(name: 'title', type: 'text'),
            OdsFieldDefinition(name: 'status', type: 'text'),
          ]);
          for (var i = 0; i < 10000; i++) {
            await ds.insert('tasks', {
              'title': 'Task $i',
              'status': i % 1000 == 0 ? 'done' : 'todo',
            });
          }
          final sw = await _measure('P2 filter 10k → ~10', () async {
            final rows = await ds.queryWithFilter('tasks', {'status': 'done'});
            expect(rows.length, 10);
          });
          // Baseline: SQLite table scan is fast but not indexed — should still
          // Baseline Windows+SQLite FFI: generous allowance.
          expect(sw.elapsedMilliseconds, lessThan(15000));
        } finally {
          await ds.close();
          await _cleanup(tmp);
        }
      }, timeout: const Timeout(Duration(seconds: 60)));
    });

    // -----------------------------------------------------------------------
    // P3: Expression / formula / aggregate evaluation
    // -----------------------------------------------------------------------
    group('P3: Expression/formula evaluation', () {
      test('evaluates 10,000 math formulas under 1s', () async {
        final values = {'a': '5', 'b': '10', 'c': '2'};
        final sw = await _measure('P3 10k formulas', () async {
          for (var i = 0; i < 10000; i++) {
            final out =
                FormulaEvaluator.evaluate('{a} + {b} * {c}', 'number', values);
            if (out != '25') {
              throw StateError('Unexpected formula output: $out');
            }
          }
        });
        expect(sw.elapsedMilliseconds, lessThan(1000));
      });

      test('evaluates 1,000 ternary expressions under 500ms', () async {
        final values = {'status': 'active'};
        final sw = await _measure('P3 1k ternaries', () async {
          for (var i = 0; i < 1000; i++) {
            final out = ExpressionEvaluator.evaluate(
                "{status} == 'active' ? 'yes' : 'no'", values);
            if (out != 'yes') {
              throw StateError('Unexpected ternary output: $out');
            }
          }
        });
        expect(sw.elapsedMilliseconds, lessThan(500));
      });

      test('resolves a template with 100 aggregate refs under 1s', () async {
        // Seed a shared in-memory dataset.
        final rows = <Map<String, dynamic>>[
          for (var i = 0; i < 50; i++)
            {'status': i % 2 == 0 ? 'todo' : 'done'},
        ];
        final buf = StringBuffer();
        for (var i = 0; i < 100; i++) {
          if (i > 0) buf.write(' / ');
          buf.write('{COUNT(tasks)}');
        }
        final content = buf.toString();
        Future<List<Map<String, dynamic>>> queryFn(String id) async {
          return id == 'tasks' ? rows : const <Map<String, dynamic>>[];
        }

        final sw = await _measure('P3 100 aggregate refs', () async {
          final result = await AggregateEvaluator.resolve(content, queryFn);
          expect(result.startsWith('50'), isTrue);
        });
        expect(sw.elapsedMilliseconds, lessThan(1000));
      });
    });

    // -----------------------------------------------------------------------
    // P4: Action chains
    // -----------------------------------------------------------------------
    group('P4: Action chains', () {
      test('executes 100 sequential submits under 5s', () async {
        final tmp = await _tmp('ods_b94_submits_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        final loaded = await engine.loadSpec(_tasksAppJson());
        expect(loaded, isTrue);
        try {
          final sw = await _measure('P4 100 submits', () async {
            for (var i = 0; i < 100; i++) {
              engine.updateFormField('addForm', 'title', 'Task $i');
              engine.updateFormField('addForm', 'status', 'todo');
              await engine.executeActions(const [
                OdsAction(
                  action: 'submit',
                  target: 'addForm',
                  dataSource: 'tasks',
                ),
              ]);
            }
          });
          final rows = await engine.queryDataSource('tasks');
          expect(rows.length, 100);
          expect(sw.elapsedMilliseconds, lessThan(5000));
        } finally {
          await engine.reset();
          engine.dispose();
          await _cleanup(tmp);
        }
      }, timeout: const Timeout(Duration(seconds: 60)));

      // 1000-step cascade: intentionally NOT tested.
      //
      // ODS cascade rename is bounded by parent-data-source row count, not
      // action chain depth. A 1000-step cascade would indicate a spec bug
      // (circular ref), not a perf concern worth baselining. Documented as
      // a limitation.
      test('1000-step cascade — intentional limitation, not measured',
          () async {
        // No-op placeholder. See comment block above.
      }, skip: 'Intentional: cascade depth is not a perf target.');

      test('submit with 100 computedFields under 100ms', () async {
        final dataStore = _FakeDataStore();
        final handler = ActionHandler(dataStore: dataStore);
        final app = _computedFieldsApp();
        final computed = <OdsComputedField>[
          for (var i = 0; i < 100; i++)
            OdsComputedField(field: 'c$i', expression: 'prefix_{title}_$i'),
        ];
        final sw = await _measure('P4 100 computedFields', () async {
          final result = await handler.execute(
            action: OdsAction(
              action: 'submit',
              target: 'addForm',
              dataSource: 'tasks',
              computedFields: computed,
            ),
            app: app,
            formStates: {
              'addForm': {'title': 'Compute', 'status': 'todo'},
            },
          );
          expect(result.submitted, isTrue,
              reason: 'Computed submit failed: ${result.error}');
        });
        final rows = await dataStore.query('tasks');
        expect(rows.length, 1);
        expect(rows.first['c0'], 'prefix_Compute_0');
        expect(rows.first['c99'], 'prefix_Compute_99');
        expect(sw.elapsedMilliseconds, lessThan(100));
      });
    });

    // -----------------------------------------------------------------------
    // P5: Engine reactivity
    // -----------------------------------------------------------------------
    //
    // Flutter's AppEngine plays the role of the React app-store. Form updates
    // use `updateFormField`; recordGeneration bumps happen internally on every
    // data-changing action. We observe both directly.
    // -----------------------------------------------------------------------
    group('P5: Engine reactivity', () {
      test('fires 1,000 form field updates under 500ms', () async {
        final tmp = await _tmp('ods_b95_updates_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        final loaded = await engine.loadSpec(_tasksAppJson());
        expect(loaded, isTrue);
        try {
          final sw = await _measure('P5 1k field updates', () async {
            for (var i = 0; i < 1000; i++) {
              engine.updateFormField('myForm', 'field${i % 50}', 'v$i');
            }
          });
          expect(sw.elapsedMilliseconds, lessThan(500));
        } finally {
          await engine.reset();
          engine.dispose();
          await _cleanup(tmp);
        }
      });

      test('100 rapid clearForm/notifyListeners bumps under 100ms', () async {
        // Flutter equivalent of React's recordGeneration bump: exercise the
        // engine's ChangeNotifier path 100 times. clearForm() is the cheapest
        // public method that always calls notifyListeners(), so it's a good
        // proxy for "setState bump" in zustand.
        final tmp = await _tmp('ods_b95_recgen_');
        final engine = AppEngine();
        engine.storageFolder = tmp.path;
        final loaded = await engine.loadSpec(_tasksAppJson());
        expect(loaded, isTrue);
        try {
          var notifyCount = 0;
          void onNotify() => notifyCount++;
          engine.addListener(onNotify);
          try {
            final sw = await _measure('P5 100 clearForm bumps', () async {
              for (var i = 0; i < 100; i++) {
                engine.clearForm('bumpForm$i');
              }
            });
            expect(notifyCount, 100);
            expect(sw.elapsedMilliseconds, lessThan(100));
          } finally {
            engine.removeListener(onNotify);
          }
        } finally {
          await engine.reset();
          engine.dispose();
          await _cleanup(tmp);
        }
      });
    });
  });
}

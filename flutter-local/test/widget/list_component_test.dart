import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ods_flutter_local/models/ods_component.dart';
import 'package:ods_flutter_local/models/ods_field_definition.dart';
import 'package:ods_flutter_local/models/ods_style_hint.dart';
import 'package:ods_flutter_local/renderer/components/list_component.dart';

import '_test_harness.dart';

const String _kSpec = '''
{
  "appName": "ListTest",
  "startPage": "home",
  "pages": {"home": {"component": "page", "title": "Home", "content": []}},
  "dataSources": {
    "tasks": {
      "url": "local://tasks",
      "method": "POST",
      "fields": [
        {"name": "title", "type": "text", "label": "Title"},
        {"name": "status", "type": "text", "label": "Status"}
      ]
    }
  }
}
''';

/// Skip on Windows: Flutter's test runner hits a `flutter_tools` temp-dir
/// race (AV/file-system interference) that hangs the first widget test
/// indefinitely. Tests pass cleanly on Linux/macOS. Revisit if Flutter
/// ever ships a fix.
final String? _skipReason = Platform.isWindows
    ? 'Flutter-on-Windows widget-test harness hang (see REGRESSION_LOG.md)'
    : null;

void main() {
  group('OdsListWidget', () {
    testWidgets('Renders column headers', (tester) async {
      final booted = await bootEngine(_kSpec);
      try {
        const model = OdsListComponent(
          dataSource: 'tasks',
          columns: [
            OdsListColumn(header: 'Task Name', field: 'title'),
            OdsListColumn(header: 'Status', field: 'status'),
          ],
          rowActions: [],
          summary: [],
          searchable: false,
          displayAs: 'table',
          styleHint: OdsStyleHint({}),
        );
        await pumpAndSettle(
          tester,
          harness(engine: booted.engine, child: const OdsListWidget(model: model)),
        );
        expect(find.text('Task Name'), findsOneWidget);
        expect(find.text('Status'), findsOneWidget);
      } finally {
        await booted.disposeAll();
      }
    });

    testWidgets('Renders rows from data source', (tester) async {
      final booted = await bootEngine(_kSpec);
      try {
        final ds = booted.engine.dataStore;
        await ds.ensureTable('tasks', [
          const OdsFieldDefinition(name: 'title', type: 'text'),
          const OdsFieldDefinition(name: 'status', type: 'text'),
        ]);
        await ds.insert('tasks', {'title': 'Task A', 'status': 'open'});
        await ds.insert('tasks', {'title': 'Task B', 'status': 'done'});

        const model = OdsListComponent(
          dataSource: 'tasks',
          columns: [
            OdsListColumn(header: 'Title', field: 'title'),
            OdsListColumn(header: 'Status', field: 'status'),
          ],
          rowActions: [],
          summary: [],
          searchable: false,
          displayAs: 'table',
          styleHint: OdsStyleHint({}),
        );
        await pumpAndSettle(
          tester,
          harness(engine: booted.engine, child: const OdsListWidget(model: model)),
        );
        expect(find.text('Task A'), findsOneWidget);
        expect(find.text('Task B'), findsOneWidget);
      } finally {
        await booted.disposeAll();
      }
    });

    testWidgets('Empty state when no rows', (tester) async {
      final booted = await bootEngine(_kSpec);
      try {
        const model = OdsListComponent(
          dataSource: 'tasks',
          columns: [OdsListColumn(header: 'Title', field: 'title')],
          rowActions: [],
          summary: [],
          searchable: false,
          displayAs: 'table',
          styleHint: OdsStyleHint({}),
        );
        await pumpAndSettle(
          tester,
          harness(engine: booted.engine, child: const OdsListWidget(model: model)),
        );
        // No row data should appear; header still renders.
        expect(find.text('Title'), findsOneWidget);
      } finally {
        await booted.disposeAll();
      }
    });

    testWidgets('Search input renders when searchable is true', (tester) async {
      final booted = await bootEngine(_kSpec);
      try {
        const model = OdsListComponent(
          dataSource: 'tasks',
          columns: [OdsListColumn(header: 'Title', field: 'title')],
          rowActions: [],
          summary: [],
          searchable: true,
          displayAs: 'table',
          styleHint: OdsStyleHint({}),
        );
        await pumpAndSettle(
          tester,
          harness(engine: booted.engine, child: const OdsListWidget(model: model)),
        );
        // Search bar should render a TextField for input.
        expect(find.byType(TextField), findsAtLeastNWidgets(1));
      } finally {
        await booted.disposeAll();
      }
    });
  }, skip: _skipReason);
}

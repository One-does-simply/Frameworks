import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ods_flutter_local/models/ods_component.dart';
import 'package:ods_flutter_local/models/ods_field_definition.dart';
import 'package:ods_flutter_local/models/ods_style_hint.dart';
import 'package:ods_flutter_local/renderer/components/kanban_widget.dart';

import '_test_harness.dart';

const String _kSpec = '''
{
  "appName": "KanbanTest",
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
            {"name": "status", "type": "select", "label": "Status", "options": ["todo", "doing", "done"]}
          ]
        }
      ]
    }
  },
  "dataSources": {
    "cards": {
      "url": "local://cards",
      "method": "POST",
      "fields": [
        {"name": "title", "type": "text", "label": "Title"},
        {"name": "status", "type": "select", "label": "Status", "options": ["todo", "doing", "done"]}
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
  group('OdsKanbanWidget', () {
    testWidgets('Renders columns from status field options', (tester) async {
      final booted = await bootEngine(_kSpec);
      try {
        const model = OdsKanbanComponent(
          dataSource: 'cards',
          statusField: 'status',
          cardFields: ['title'],
          rowActions: [],
          searchable: false,
          styleHint: OdsStyleHint({}),
        );
        await pumpAndSettle(
          tester,
          harness(engine: booted.engine, child: const OdsKanbanWidget(model: model)),
        );
        expect(find.text('todo'), findsOneWidget);
        expect(find.text('doing'), findsOneWidget);
        expect(find.text('done'), findsOneWidget);
      } finally {
        await booted.disposeAll();
      }
    });

    testWidgets('Cards appear in their status column', (tester) async {
      final booted = await bootEngine(_kSpec);
      try {
        final ds = booted.engine.dataStore;
        await ds.ensureTable('cards', [
          const OdsFieldDefinition(name: 'title', type: 'text'),
          const OdsFieldDefinition(name: 'status', type: 'select', options: ['todo', 'doing', 'done']),
        ]);
        await ds.insert('cards', {'title': 'Card A', 'status': 'todo'});
        await ds.insert('cards', {'title': 'Card B', 'status': 'done'});

        const model = OdsKanbanComponent(
          dataSource: 'cards',
          statusField: 'status',
          cardFields: ['title'],
          rowActions: [],
          searchable: false,
          styleHint: OdsStyleHint({}),
        );
        await pumpAndSettle(
          tester,
          harness(engine: booted.engine, child: const OdsKanbanWidget(model: model)),
        );
        expect(find.text('Card A'), findsOneWidget);
        expect(find.text('Card B'), findsOneWidget);
      } finally {
        await booted.disposeAll();
      }
    });

    testWidgets('Empty data source still renders columns', (tester) async {
      final booted = await bootEngine(_kSpec);
      try {
        const model = OdsKanbanComponent(
          dataSource: 'cards',
          statusField: 'status',
          cardFields: ['title'],
          rowActions: [],
          searchable: false,
          styleHint: OdsStyleHint({}),
        );
        await pumpAndSettle(
          tester,
          harness(engine: booted.engine, child: const OdsKanbanWidget(model: model)),
        );
        expect(find.text('todo'), findsOneWidget);
      } finally {
        await booted.disposeAll();
      }
    });
  }, skip: _skipReason);
}

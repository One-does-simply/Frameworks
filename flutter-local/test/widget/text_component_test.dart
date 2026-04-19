import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ods_flutter_local/models/ods_component.dart';
import 'package:ods_flutter_local/models/ods_field_definition.dart';
import 'package:ods_flutter_local/models/ods_style_hint.dart';
import 'package:ods_flutter_local/renderer/components/text_component.dart';

import '_test_harness.dart';

const String _kBlankSpec = '''
{
  "appName": "TextTest",
  "startPage": "home",
  "pages": {"home": {"component": "page", "title": "Home", "content": []}}
}
''';

/// Spec with a tasks data source — used by the aggregate/COUNT test.
const String _kTasksSpec = '''
{
  "appName": "TextAggTest",
  "startPage": "home",
  "pages": {"home": {"component": "page", "title": "Home", "content": []}},
  "dataSources": {
    "tasks": {
      "url": "local://tasks",
      "method": "POST",
      "fields": [
        {"name": "title", "type": "text", "label": "Title"}
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
  group('OdsTextWidget', () {
    testWidgets('Plain text renders', (WidgetTester tester) async {
      final booted = await bootEngine(_kBlankSpec);
      try {
        const model = OdsTextComponent(
          content: 'Hello World',
          styleHint: OdsStyleHint({}),
        );
        await pumpAndSettle(
          tester,
          harness(
            engine: booted.engine,
            child: const OdsTextWidget(model: model),
          ),
        );
        expect(find.text('Hello World'), findsOneWidget);
      } finally {
        await booted.disposeAll();
      }
    });

    testWidgets('Aggregate reference {COUNT(tasks)} resolves to count',
        (WidgetTester tester) async {
      final booted = await bootEngine(_kTasksSpec);
      try {
        // Seed three rows directly through the real data store.
        final ds = booted.engine.dataStore;
        await ds.ensureTable('tasks',
            [const OdsFieldDefinition(name: 'title', type: 'text')]);
        await ds.insert('tasks', {'title': 't1'});
        await ds.insert('tasks', {'title': 't2'});
        await ds.insert('tasks', {'title': 't3'});

        const model = OdsTextComponent(
          content: 'Total: {COUNT(tasks)}',
          styleHint: OdsStyleHint({}),
        );
        await pumpAndSettle(
          tester,
          harness(
            engine: booted.engine,
            child: const OdsTextWidget(model: model),
          ),
        );
        expect(find.text('Total: 3'), findsOneWidget);
      } finally {
        await booted.disposeAll();
      }
    });

    testWidgets('Heading variant applies larger/bold style',
        (WidgetTester tester) async {
      final booted = await bootEngine(_kBlankSpec);
      try {
        const model = OdsTextComponent(
          content: 'Big Heading',
          styleHint: OdsStyleHint({'variant': 'heading'}),
        );
        await pumpAndSettle(
          tester,
          harness(
            engine: booted.engine,
            child: const OdsTextWidget(model: model),
          ),
        );
        final textWidget = tester.widget<Text>(find.text('Big Heading'));
        // Heading should have a heavy font weight.
        expect(textWidget.style?.fontWeight, isNotNull,
            reason: 'Heading variant should set an explicit font weight.');
      } finally {
        await booted.disposeAll();
      }
    });

    testWidgets('Alignment applies when styleHint.align is center',
        (WidgetTester tester) async {
      final booted = await bootEngine(_kBlankSpec);
      try {
        const model = OdsTextComponent(
          content: 'Centered',
          styleHint: OdsStyleHint({'align': 'center'}),
        );
        await pumpAndSettle(
          tester,
          harness(
            engine: booted.engine,
            child: const OdsTextWidget(model: model),
          ),
        );
        final textWidget = tester.widget<Text>(find.text('Centered'));
        expect(textWidget.textAlign, TextAlign.center);
      } finally {
        await booted.disposeAll();
      }
    });

    testWidgets('Empty content still renders an empty Text widget',
        (WidgetTester tester) async {
      final booted = await bootEngine(_kBlankSpec);
      try {
        const model = OdsTextComponent(
          content: '',
          styleHint: OdsStyleHint({}),
        );
        await pumpAndSettle(
          tester,
          harness(
            engine: booted.engine,
            child: const OdsTextWidget(model: model),
          ),
        );
        // The Text widget exists but has empty data.
        final text = tester.widget<Text>(find.byType(Text));
        expect(text.data, '');
      } finally {
        await booted.disposeAll();
      }
    });
  }, skip: _skipReason);
}

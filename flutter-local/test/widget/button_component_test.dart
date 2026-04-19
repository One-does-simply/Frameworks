import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ods_flutter_local/models/ods_action.dart';
import 'package:ods_flutter_local/models/ods_component.dart';
import 'package:ods_flutter_local/models/ods_style_hint.dart';
import 'package:ods_flutter_local/models/ods_visible_when.dart';
import 'package:ods_flutter_local/renderer/components/button_component.dart';

import '_test_harness.dart';

/// Minimal spec used by button tests — one page, no data sources required
/// for rendering a plain button.
const String _kSimpleSpec = '''
{
  "appName": "ButtonTest",
  "startPage": "home",
  "pages": {
    "home": {"component": "page", "title": "Home", "content": []},
    "next": {"component": "page", "title": "Next", "content": []}
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
  group('OdsButtonWidget', () {
    testWidgets('Renders label text', (WidgetTester tester) async {
      final booted = await bootEngine(_kSimpleSpec);
      try {
        const model = OdsButtonComponent(
          label: 'Click Me',
          onClick: [],
          styleHint: OdsStyleHint({}),
        );
        await pumpAndSettle(
          tester,
          harness(
            engine: booted.engine,
            child: const OdsButtonWidget(model: model),
          ),
        );
        expect(find.text('Click Me'), findsOneWidget);
      } finally {
        await booted.disposeAll();
      }
    });

    testWidgets('Tap triggers navigate action — engine state updates',
        (WidgetTester tester) async {
      final booted = await bootEngine(_kSimpleSpec);
      try {
        const model = OdsButtonComponent(
          label: 'Go',
          onClick: [OdsAction(action: 'navigate', target: 'next')],
          styleHint: OdsStyleHint({}),
        );
        await pumpAndSettle(
          tester,
          harness(
            engine: booted.engine,
            child: const OdsButtonWidget(model: model),
          ),
        );
        expect(booted.engine.currentPageId, 'home');
        await tester.tap(find.text('Go'));
        await tester.pumpAndSettle();
        expect(booted.engine.currentPageId, 'next',
            reason: 'Tap should execute navigate action and change page.');
      } finally {
        await booted.disposeAll();
      }
    });

    testWidgets('Primary emphasis renders ElevatedButton',
        (WidgetTester tester) async {
      final booted = await bootEngine(_kSimpleSpec);
      try {
        const model = OdsButtonComponent(
          label: 'Primary',
          onClick: [],
          styleHint: OdsStyleHint({'emphasis': 'primary'}),
        );
        await pumpAndSettle(
          tester,
          harness(
            engine: booted.engine,
            child: const OdsButtonWidget(model: model),
          ),
        );
        // Default variant (filled) + primary emphasis → ElevatedButton.
        expect(find.byType(ElevatedButton), findsOneWidget);
      } finally {
        await booted.disposeAll();
      }
    });

    testWidgets('Outlined variant renders OutlinedButton',
        (WidgetTester tester) async {
      final booted = await bootEngine(_kSimpleSpec);
      try {
        const model = OdsButtonComponent(
          label: 'Secondary',
          onClick: [],
          styleHint: OdsStyleHint({
            'emphasis': 'secondary',
            'variant': 'outlined',
          }),
        );
        await pumpAndSettle(
          tester,
          harness(
            engine: booted.engine,
            child: const OdsButtonWidget(model: model),
          ),
        );
        expect(find.byType(OutlinedButton), findsOneWidget);
      } finally {
        await booted.disposeAll();
      }
    });

    testWidgets('Icon renders when styleHint.icon is set',
        (WidgetTester tester) async {
      final booted = await bootEngine(_kSimpleSpec);
      try {
        const model = OdsButtonComponent(
          label: 'Add',
          onClick: [],
          styleHint: OdsStyleHint({'icon': 'add'}),
        );
        await pumpAndSettle(
          tester,
          harness(
            engine: booted.engine,
            child: const OdsButtonWidget(model: model),
          ),
        );
        expect(find.byIcon(Icons.add), findsOneWidget);
        expect(find.text('Add'), findsOneWidget);
      } finally {
        await booted.disposeAll();
      }
    });

    testWidgets('visibleWhen=false does NOT affect the widget itself — '
        'button always renders (visibility is enforced by PageRenderer)',
        (WidgetTester tester) async {
      // Document: the OdsButtonWidget itself does not consult visibleWhen.
      // That wrapper lives in PageRenderer. So a button with visibleWhen
      // rendered directly will still paint its label.
      final booted = await bootEngine(_kSimpleSpec);
      try {
        const model = OdsButtonComponent(
          label: 'ShouldShow',
          onClick: [],
          styleHint: OdsStyleHint({}),
          visibleWhen: OdsComponentVisibleWhen(
            form: 'none',
            field: 'nope',
            equals: 'impossible',
          ),
        );
        await pumpAndSettle(
          tester,
          harness(
            engine: booted.engine,
            child: const OdsButtonWidget(model: model),
          ),
        );
        expect(find.text('ShouldShow'), findsOneWidget);
      } finally {
        await booted.disposeAll();
      }
    });
  }, skip: _skipReason);
}

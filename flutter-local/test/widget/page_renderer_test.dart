import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ods_flutter_local/models/ods_component.dart';
import 'package:ods_flutter_local/models/ods_page.dart';
import 'package:ods_flutter_local/models/ods_style_hint.dart';
import 'package:ods_flutter_local/renderer/page_renderer.dart';

import '_test_harness.dart';

const String _kSpec = '''
{
  "appName": "PageRendererTest",
  "startPage": "home",
  "pages": {"home": {"component": "page", "title": "Home", "content": []}}
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
  group('PageRenderer', () {
    testWidgets('Dispatches to text component', (tester) async {
      final booted = await bootEngine(_kSpec);
      try {
        const page = OdsPage(
          title: 'Home',
          content: [
            OdsTextComponent(content: 'Hello from page renderer', styleHint: OdsStyleHint({})),
          ],
        );
        await pumpAndSettle(
          tester,
          harness(
            engine: booted.engine,
            child: const SingleChildScrollView(
              child: PageRenderer(page: page),
            ),
          ),
        );
        expect(find.text('Hello from page renderer'), findsOneWidget);
      } finally {
        await booted.disposeAll();
      }
    });

    testWidgets('Renders multiple components in order', (tester) async {
      final booted = await bootEngine(_kSpec);
      try {
        const page = OdsPage(
          title: 'Home',
          content: [
            OdsTextComponent(content: 'First', styleHint: OdsStyleHint({})),
            OdsTextComponent(content: 'Second', styleHint: OdsStyleHint({})),
            OdsTextComponent(content: 'Third', styleHint: OdsStyleHint({})),
          ],
        );
        await pumpAndSettle(
          tester,
          harness(
            engine: booted.engine,
            child: const SingleChildScrollView(
              child: PageRenderer(page: page),
            ),
          ),
        );
        expect(find.text('First'), findsOneWidget);
        expect(find.text('Second'), findsOneWidget);
        expect(find.text('Third'), findsOneWidget);
      } finally {
        await booted.disposeAll();
      }
    });

    testWidgets('Empty content renders nothing but no crash', (tester) async {
      final booted = await bootEngine(_kSpec);
      try {
        await pumpAndSettle(
          tester,
          harness(
            engine: booted.engine,
            child: const PageRenderer(page: OdsPage(title: 'Home', content: [])),
          ),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await booted.disposeAll();
      }
    });
  }, skip: _skipReason);
}

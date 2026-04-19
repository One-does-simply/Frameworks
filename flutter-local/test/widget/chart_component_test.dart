import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ods_flutter_local/models/ods_component.dart';
import 'package:ods_flutter_local/models/ods_field_definition.dart';
import 'package:ods_flutter_local/models/ods_style_hint.dart';
import 'package:ods_flutter_local/renderer/components/chart_component.dart';

import '_test_harness.dart';

const String _kSpec = '''
{
  "appName": "ChartTest",
  "startPage": "home",
  "pages": {"home": {"component": "page", "title": "Home", "content": []}},
  "dataSources": {
    "sales": {
      "url": "local://sales",
      "method": "POST",
      "fields": [
        {"name": "month", "type": "text", "label": "Month"},
        {"name": "revenue", "type": "number", "label": "Revenue"}
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
  group('OdsChartWidget', () {
    testWidgets('Renders without crash on empty data', (tester) async {
      final booted = await bootEngine(_kSpec);
      try {
        const model = OdsChartComponent(
          dataSource: 'sales',
          chartType: 'bar',
          labelField: 'month',
          valueField: 'revenue',
          aggregate: 'sum',
          styleHint: OdsStyleHint({}),
        );
        await pumpAndSettle(
          tester,
          harness(engine: booted.engine, child: const OdsChartWidget(model: model)),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await booted.disposeAll();
      }
    });

    testWidgets('Renders bar chart with data', (tester) async {
      final booted = await bootEngine(_kSpec);
      try {
        final ds = booted.engine.dataStore;
        await ds.ensureTable('sales', [
          const OdsFieldDefinition(name: 'month', type: 'text'),
          const OdsFieldDefinition(name: 'revenue', type: 'number'),
        ]);
        await ds.insert('sales', {'month': 'Jan', 'revenue': '100'});
        await ds.insert('sales', {'month': 'Feb', 'revenue': '200'});

        const model = OdsChartComponent(
          dataSource: 'sales',
          chartType: 'bar',
          labelField: 'month',
          valueField: 'revenue',
          aggregate: 'sum',
          styleHint: OdsStyleHint({}),
        );
        await pumpAndSettle(
          tester,
          harness(engine: booted.engine, child: const OdsChartWidget(model: model)),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await booted.disposeAll();
      }
    });

    testWidgets('Renders title when provided', (tester) async {
      final booted = await bootEngine(_kSpec);
      try {
        const model = OdsChartComponent(
          dataSource: 'sales',
          chartType: 'bar',
          labelField: 'month',
          valueField: 'revenue',
          aggregate: 'sum',
          title: 'Monthly Revenue',
          styleHint: OdsStyleHint({}),
        );
        await pumpAndSettle(
          tester,
          harness(engine: booted.engine, child: const OdsChartWidget(model: model)),
        );
        expect(find.text('Monthly Revenue'), findsOneWidget);
      } finally {
        await booted.disposeAll();
      }
    });
  }, skip: _skipReason);
}

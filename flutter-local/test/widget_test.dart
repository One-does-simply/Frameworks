import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ods_flutter_local/engine/app_engine.dart';
import 'package:ods_flutter_local/main.dart';
import 'package:ods_flutter_local/engine/settings_store.dart';

void main() {
  testWidgets('App builds and shows loading state', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppEngine()),
          ChangeNotifierProvider(create: (_) => SettingsStore()),
        ],
        child: const OdsFrameworkApp(),
      ),
    );

    // Before settings initialize, the app shows a loading indicator.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

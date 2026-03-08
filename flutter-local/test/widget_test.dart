import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ods_flutter_local/engine/app_engine.dart';
import 'package:ods_flutter_local/main.dart';

void main() {
  testWidgets('Welcome screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppEngine(),
        child: const OdsFrameworkApp(),
      ),
    );

    expect(find.text('ODS Framework'), findsOneWidget);
    expect(find.text('One Does Simply'), findsOneWidget);
    expect(find.text('Open Spec File'), findsOneWidget);
  });
}

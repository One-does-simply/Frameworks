import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ods_flutter_local/engine/app_engine.dart';

/// Wraps [child] in a MaterialApp + Scaffold with the given [engine] exposed
/// via Provider, so components that call `context.watch<AppEngine>()` /
/// `context.read<AppEngine>()` can locate it.
Widget harness({required AppEngine engine, required Widget child}) {
  return MaterialApp(
    home: ChangeNotifierProvider<AppEngine>.value(
      value: engine,
      child: Scaffold(body: child),
    ),
  );
}

/// Creates a fully-initialized [AppEngine] against a throwaway temp folder
/// so widget tests get real data-store behavior without polluting shared dirs.
///
/// [specJson] should be the full app-spec JSON string.
Future<_BootedEngine> bootEngine(String specJson) async {
  final tmp = await Directory.systemTemp.createTemp('ods_widget_');
  final engine = AppEngine();
  engine.storageFolder = tmp.path;
  final ok = await engine.loadSpec(specJson);
  if (!ok) {
    throw StateError('loadSpec failed: ${engine.loadError}');
  }
  return _BootedEngine(engine: engine, tmp: tmp);
}

class _BootedEngine {
  final AppEngine engine;
  final Directory tmp;
  _BootedEngine({required this.engine, required this.tmp});

  Future<void> disposeAll() async {
    await engine.reset();
    engine.dispose();
    if (await tmp.exists()) {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    }
  }
}

/// Pumps [widget] into [tester] and waits for pending futures (e.g.
/// FutureBuilder data sources) to settle.
Future<void> pumpAndSettle(
  WidgetTester tester,
  Widget widget, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle(timeout);
}

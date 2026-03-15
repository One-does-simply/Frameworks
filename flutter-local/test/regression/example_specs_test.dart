import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/parser/spec_parser.dart';

/// Regression test: every example spec in the Specification repo must parse
/// successfully with no validation errors.
void main() {
  final parser = SpecParser();
  final examplesDir = Directory('../../Specification/Examples');

  // Skip gracefully if running in CI without the Specification repo.
  if (!examplesDir.existsSync()) {
    test('SKIP: Specification/Examples not found', () {
      // Not a failure — the Specification repo may not be adjacent in CI.
    });
    return;
  }

  final specFiles = examplesDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json') && !f.path.endsWith('catalog.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  group('Example specs parse without errors', () {
    for (final file in specFiles) {
      final name = file.uri.pathSegments.last;
      test(name, () {
        final json = file.readAsStringSync();
        final result = parser.parse(json);

        // Must parse successfully.
        expect(result.parseError, isNull,
            reason: 'Parse error in $name: ${result.parseError}');

        // Must have no validation errors (warnings are OK).
        expect(result.validation.hasErrors, false,
            reason: 'Validation errors in $name: ${result.validation.errors}');

        // Must produce a valid app model.
        expect(result.app, isNotNull, reason: '$name produced null app');
        expect(result.app!.appName, isNotEmpty,
            reason: '$name has empty appName');
        expect(result.app!.pages, isNotEmpty,
            reason: '$name has no pages');
      });
    }
  });

  group('Example spec structure checks', () {
    for (final file in specFiles) {
      final name = file.uri.pathSegments.last;
      test('$name: startPage exists in pages', () {
        final json = file.readAsStringSync();
        final result = parser.parse(json);
        if (result.app == null) return; // Covered by parse test above.

        expect(result.app!.pages.containsKey(result.app!.startPage), true,
            reason:
                '$name: startPage "${result.app!.startPage}" not found in pages');
      });
    }
  });
}

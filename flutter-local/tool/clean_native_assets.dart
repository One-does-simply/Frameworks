import 'dart:io';

/// Windows-only workaround: on stable Flutter 3.41 the native_assets copy
/// step can fail with
///   "PathExistsException: Cannot copy file to .../build/native_assets/
///    windows/sqlite3.dll"
/// on the second `flutter test` run because the DLL is still mapped by a
/// child process. Running this script between test runs renames/copies
/// the file into a state that lets the next `flutter test` succeed.
///
/// Usage: `flutter pub run tool/clean_native_assets.dart`
void main() {
  final srcPath =
      '.dart_tool/hooks_runner/shared/sqlite3/build/download-1121710b/sqlite3.dll';
  final src = File(srcPath);

  // If the canonical source dll is gone but there's a .bak copy in build/,
  // restore it so the next test can copy it forward.
  if (!src.existsSync()) {
    final nativeDir = Directory('build/native_assets/windows');
    if (nativeDir.existsSync()) {
      final bak = nativeDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('sqlite3.dll.bak-'))
          .toList();
      if (bak.isNotEmpty) {
        src.parent.createSync(recursive: true);
        bak.first.copySync(src.path);
        print('Restored $srcPath from ${bak.first.path}');
        try {
          bak.first.deleteSync();
        } catch (_) {}
      }
    }
  }

  // Remove the stale build copy so flutter test can re-copy fresh.
  final buildCopy = File('build/native_assets/windows/sqlite3.dll');
  if (buildCopy.existsSync()) {
    try {
      buildCopy.deleteSync();
      print('Deleted stale build copy.');
    } catch (e) {
      // Still locked — rename it out of the way so the next copy succeeds.
      try {
        final renamed =
            '${buildCopy.path}.bak-${DateTime.now().millisecondsSinceEpoch}';
        buildCopy.renameSync(renamed);
        print('Renamed locked build copy to $renamed');
      } catch (e2) {
        print('Could not clean build copy: $e2');
      }
    }
  }
}

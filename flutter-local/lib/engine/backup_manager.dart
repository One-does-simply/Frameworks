import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_engine.dart';
import 'settings_store.dart';

/// Manages automatic backups: creates backups on app launch and prunes old ones.
class BackupManager {
  BackupManager._();

  static const _backupDir = 'ods_backups';

  /// Returns the backup directory for the given app, creating it if needed.
  /// If [customFolder] is provided, uses that as the root instead of the ODS
  /// data directory.
  static Future<Directory> _getBackupDir(String appName, {String? customFolder}) async {
    final odsDir = await getOdsDirectory(customPath: customFolder);
    final sanitized = appName.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
    final dir = Directory(p.join(odsDir.path, _backupDir, sanitized));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Runs an auto-backup for the given engine. Saves a timestamped JSON file
  /// and prunes backups beyond [retention].
  static Future<void> runAutoBackup(
    AppEngine engine, {
    int retention = 5,
    String? backupFolder,
  }) async {
    final appName = engine.app?.appName;
    if (appName == null) return;

    try {
      final data = await engine.backupData();
      final dir = await _getBackupDir(appName, customFolder: backupFolder);
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final file = File(p.join(dir.path, 'backup_$timestamp.json'));
      await file.writeAsString(jsonEncode(data));

      // Prune old backups beyond the retention count.
      await pruneBackups(appName, retention: retention, backupFolder: backupFolder);
    } catch (_) {
      // Auto-backup is best-effort; don't crash the app.
    }
  }

  /// Deletes the oldest backups beyond [retention] for the given app.
  static Future<void> pruneBackups(String appName, {int retention = 5, String? backupFolder}) async {
    try {
      final dir = await _getBackupDir(appName, customFolder: backupFolder);
      final files = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.json'))
          .cast<File>()
          .toList();

      if (files.length <= retention) return;

      // Sort by modification time, newest first.
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      // Delete everything beyond the retention limit.
      for (final old in files.skip(retention)) {
        await old.delete();
      }
    } catch (_) {
      // Best-effort cleanup.
    }
  }
}

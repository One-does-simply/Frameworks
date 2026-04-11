import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'app_engine.dart';
import 'password_hasher.dart';
import 'settings_store.dart';

/// Manages automatic backups: creates backups on app launch and prunes old ones.
class BackupManager {
  BackupManager._();

  static const _backupDir = 'ods_backups';

  /// App-specific signing key for backup HMAC integrity checks.
  /// In production, this should be sourced from a device keystore.
  static const _signingKey = 'ods-backup-integrity-v1';

  /// Computes an HMAC-SHA256 signature over the given data string.
  static String _computeSignature(String data) {
    final keyBytes = utf8.encode(_signingKey);
    final dataBytes = utf8.encode(data);
    final hmac = PasswordHasher.hmacSha256(keyBytes, dataBytes);
    return base64Url.encode(hmac);
  }

  /// Signs a backup map by computing an HMAC of its JSON content.
  /// Adds a `signature` field to the returned map.
  static Map<String, dynamic> signBackup(Map<String, dynamic> backup) {
    final copy = Map<String, dynamic>.from(backup);
    copy.remove('signature'); // Remove any existing signature before signing.
    final jsonData = jsonEncode(copy);
    copy['signature'] = _computeSignature(jsonData);
    return copy;
  }

  /// Verifies the HMAC signature of a backup map.
  /// Returns true if the signature is valid, false otherwise.
  /// Backups without a signature field are treated as unsigned (returns false).
  static bool verifyBackup(Map<String, dynamic> backup) {
    final signature = backup['signature'] as String?;
    if (signature == null) return false;
    final copy = Map<String, dynamic>.from(backup);
    copy.remove('signature');
    final jsonData = jsonEncode(copy);
    final expected = _computeSignature(jsonData);
    return expected == signature;
  }

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
      final signedData = signBackup(data);
      final dir = await _getBackupDir(appName, customFolder: backupFolder);
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final file = File(p.join(dir.path, 'backup_$timestamp.json'));
      await file.writeAsString(jsonEncode(signedData));

      // Prune old backups beyond the retention count.
      await pruneBackups(appName, retention: retention, backupFolder: backupFolder);
    } catch (e) {
      // Auto-backup is best-effort; don't crash the app.
      debugPrint('BackupManager: auto-backup failed: $e');
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
    } catch (e) {
      // Best-effort cleanup.
      debugPrint('BackupManager: prune failed: $e');
    }
  }
}

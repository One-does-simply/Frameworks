import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'settings_store.dart';

/// Logging service for ODS Flutter.
///
/// Provides structured, level-filtered logging with file persistence,
/// automatic retention pruning, and export/download for end-user support.
///
/// ODS Ethos: Novice users need a way to share what went wrong without
/// understanding developer tools. This service captures runtime events and
/// makes them exportable as a plain-text file they can email.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

enum LogLevel { debug, info, warn, error }

class LogEntry {
  final String timestamp;
  final LogLevel level;
  final String category;
  final String message;
  final String? data;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.data,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'level': level.name,
        'category': category,
        'message': message,
        if (data != null) 'data': data,
      };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
        timestamp: json['timestamp'] as String,
        level: LogLevel.values.firstWhere(
          (l) => l.name == json['level'],
          orElse: () => LogLevel.info,
        ),
        category: json['category'] as String,
        message: json['message'] as String,
        data: json['data'] as String?,
      );
}

class LogSettings {
  LogLevel level;
  int retentionDays;

  LogSettings({this.level = LogLevel.debug, this.retentionDays = 7});

  Map<String, dynamic> toJson() => {
        'level': level.name,
        'retentionDays': retentionDays,
      };

  factory LogSettings.fromJson(Map<String, dynamic> json) => LogSettings(
        level: LogLevel.values.firstWhere(
          (l) => l.name == json['level'],
          orElse: () => LogLevel.debug,
        ),
        retentionDays: json['retentionDays'] as int? ?? 7,
      );
}

// ---------------------------------------------------------------------------
// Singleton LogService
// ---------------------------------------------------------------------------

class LogService {
  LogService._();
  static final LogService instance = LogService._();

  static const int _maxEntries = 20000;
  static const Duration _flushDelay = Duration(seconds: 1);

  LogSettings _settings = LogSettings();
  final List<LogEntry> _buffer = [];
  List<LogEntry> _stored = [];
  bool _initialized = false;
  bool _flushScheduled = false;
  File? _logFile;
  File? _settingsFile;

  LogSettings get settings => _settings;

  /// Initialize the log service. Call once at app startup, after
  /// [SettingsStore.initialize] so the bootstrap-chosen folder is honored.
  Future<void> initialize() async {
    if (_initialized) return;
    final odsDir = await getOdsDirectory();
    _logFile = File(p.join(odsDir.path, 'ods_logs.json'));
    _settingsFile = File(p.join(odsDir.path, 'ods_log_settings.json'));

    // Load settings
    if (await _settingsFile!.exists()) {
      try {
        final data = jsonDecode(await _settingsFile!.readAsString());
        _settings = LogSettings.fromJson(data as Map<String, dynamic>);
      } catch (e) {
        debugPrint('LogService: failed to load settings: $e');
      }
    }

    // Load stored logs
    if (await _logFile!.exists()) {
      try {
        final data = jsonDecode(await _logFile!.readAsString()) as List;
        _stored = data
            .cast<Map<String, dynamic>>()
            .map(LogEntry.fromJson)
            .toList();
      } catch (e) {
        debugPrint('LogService: failed to load stored logs: $e');
        _stored = [];
      }
    }

    _pruneOldEntries();
    _initialized = true;
    info('LogService', 'Initialized — ${_stored.length} stored entries, level=${_settings.level.name}');
  }

  // -------------------------------------------------------------------------
  // Settings
  // -------------------------------------------------------------------------

  Future<void> updateSettings(LogSettings newSettings) async {
    _settings = newSettings;
    if (_settingsFile != null) {
      await _settingsFile!.writeAsString(jsonEncode(_settings.toJson()));
    }
  }

  // -------------------------------------------------------------------------
  // Core logging
  // -------------------------------------------------------------------------

  bool _shouldLog(LogLevel level) => level.index >= _settings.level.index;

  void log(LogLevel level, String category, String message, [dynamic data]) {
    // Always forward to debugPrint
    final tag = level.name.toUpperCase();
    if (data != null) {
      debugPrint('[ODS] [$tag] [$category] $message | $data');
    } else {
      debugPrint('[ODS] [$tag] [$category] $message');
    }

    if (!_shouldLog(level)) return;

    final entry = LogEntry(
      timestamp: DateTime.now().toUtc().toIso8601String(),
      level: level,
      category: category,
      message: message,
      data: data != null ? _serializeData(data) : null,
    );
    _buffer.add(entry);
    _scheduleFlush();
  }

  String _serializeData(dynamic data) {
    if (data is Error || data is Exception) return data.toString();
    try {
      return jsonEncode(data);
    } catch (_) {
      return data.toString();
    }
  }

  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    Future.delayed(_flushDelay, () {
      _flushScheduled = false;
      _flushToStorage();
    });
  }

  Future<void> _flushToStorage() async {
    if (_buffer.isEmpty || _logFile == null) return;
    _stored.addAll(_buffer);
    _buffer.clear();
    _pruneOldEntries();
    try {
      await _logFile!.writeAsString(
        jsonEncode(_stored.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('LogService: failed to flush logs to storage: $e');
    }
  }

  void _pruneOldEntries() {
    final cutoff = DateTime.now()
        .subtract(Duration(days: _settings.retentionDays))
        .toUtc();
    _stored.removeWhere((e) {
      final ts = DateTime.tryParse(e.timestamp);
      return ts != null && ts.isBefore(cutoff);
    });
    if (_stored.length > _maxEntries) {
      _stored = _stored.sublist(_stored.length - _maxEntries);
    }
  }

  // -------------------------------------------------------------------------
  // Convenience methods
  // -------------------------------------------------------------------------

  void debug(String category, String message, [dynamic data]) =>
      log(LogLevel.debug, category, message, data);

  void info(String category, String message, [dynamic data]) =>
      log(LogLevel.info, category, message, data);

  void warn(String category, String message, [dynamic data]) =>
      log(LogLevel.warn, category, message, data);

  void error(String category, String message, [dynamic data]) =>
      log(LogLevel.error, category, message, data);

  // -------------------------------------------------------------------------
  // Reading & export
  // -------------------------------------------------------------------------

  /// Get all stored logs plus any unflushed buffer entries.
  List<LogEntry> getLogs() {
    // Flush buffer first
    if (_buffer.isNotEmpty) {
      _stored.addAll(_buffer);
      _buffer.clear();
    }
    return List.unmodifiable(_stored);
  }

  /// Get logs filtered to at or above the given level.
  List<LogEntry> getLogsByLevel(LogLevel minLevel) {
    return getLogs().where((e) => e.level.index >= minLevel.index).toList();
  }

  /// Total count of stored entries.
  int get logCount => _stored.length + _buffer.length;

  /// Clear all stored logs and the buffer.
  Future<void> clearLogs() async {
    _buffer.clear();
    _stored.clear();
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.delete();
    }
  }

  /// Format all logs as plain text suitable for email/support.
  String exportLogsAsText() {
    final logs = getLogs();
    final buf = StringBuffer();
    buf.writeln('=== ODS Flutter — Log Export ===');
    buf.writeln('Exported: ${DateTime.now().toUtc().toIso8601String()}');
    buf.writeln('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buf.writeln('Log Level: ${_settings.level.name}');
    buf.writeln('Entries: ${logs.length}');
    buf.writeln('===================================');
    buf.writeln();

    for (final e in logs) {
      final level = e.level.name.toUpperCase().padRight(5);
      final cat = e.category.padRight(16);
      buf.writeln('[${e.timestamp}] [$level] [$cat] ${e.message}');
      if (e.data != null && e.data!.length < 500) {
        buf.writeln('    ${e.data}');
      }
    }
    return buf.toString();
  }

  /// Save the log export to a file and return the file path.
  Future<String> downloadLogs() async {
    final text = exportLogsAsText();
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final odsDir = await getOdsDirectory();
    final file = File(p.join(odsDir.path, 'ods_logs_$date.txt'));
    await file.writeAsString(text);
    return file.path;
  }

}

// ---------------------------------------------------------------------------
// Top-level convenience functions (match React API)
// ---------------------------------------------------------------------------

final _log = LogService.instance;

void logDebug(String category, String message, [dynamic data]) =>
    _log.debug(category, message, data);

void logInfo(String category, String message, [dynamic data]) =>
    _log.info(category, message, data);

void logWarn(String category, String message, [dynamic data]) =>
    _log.warn(category, message, data);

void logError(String category, String message, [dynamic data]) =>
    _log.error(category, message, data);

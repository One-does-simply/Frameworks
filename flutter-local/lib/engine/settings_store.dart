import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Persists framework-level settings: theme mode, toured apps, etc.
///
/// Separate from LoadedAppsStore because settings are framework concerns,
/// not app concerns. Notifies listeners so the MaterialApp rebuilds when
/// the theme changes.
class SettingsStore extends ChangeNotifier {
  static const _fileName = 'ods_settings.json';

  ThemeMode _themeMode = ThemeMode.system;
  final Set<String> _touredAppIds = {};
  bool _initialized = false;
  bool _autoBackup = false;
  int _backupRetention = 5;
  String? _backupFolder;
  bool _isMultiUserEnabled = false;
  String? _defaultAppId;
  String _defaultTheme = 'indigo';

  /// Per-app branding overrides: appName -> {primaryColor, cornerStyle}
  final Map<String, Map<String, String>> _brandingOverrides = {};

  ThemeMode get themeMode => _themeMode;
  bool get isInitialized => _initialized;
  bool get autoBackup => _autoBackup;
  int get backupRetention => _backupRetention;
  String? get backupFolder => _backupFolder;
  bool get isMultiUserEnabled => _isMultiUserEnabled;
  String? get defaultAppId => _defaultAppId;
  String get defaultTheme => _defaultTheme;

  /// Returns true if the tour has already been shown for this app ID.
  bool hasSeenTour(String appId) => _touredAppIds.contains(appId);

  /// Marks the tour as shown for an app so it won't auto-launch again.
  Future<void> markTourSeen(String appId) async {
    if (_touredAppIds.add(appId)) {
      await _save();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _save();
  }

  Future<void> setAutoBackup(bool enabled) async {
    if (_autoBackup == enabled) return;
    _autoBackup = enabled;
    notifyListeners();
    await _save();
  }

  Future<void> setBackupRetention(int count) async {
    if (_backupRetention == count) return;
    _backupRetention = count.clamp(1, 100);
    notifyListeners();
    await _save();
  }

  Future<void> setBackupFolder(String? path) async {
    if (_backupFolder == path) return;
    _backupFolder = path;
    notifyListeners();
    await _save();
  }

  /// Get branding overrides for a specific app.
  Map<String, String> getBrandingOverrides(String appName) {
    final key = appName.replaceAll(RegExp(r'[^\w]'), '_').toLowerCase();
    return _brandingOverrides[key] ?? {};
  }

  /// Set branding overrides for a specific app.
  Future<void> setBrandingOverrides(String appName, Map<String, String> overrides) async {
    final key = appName.replaceAll(RegExp(r'[^\w]'), '_').toLowerCase();
    if (overrides.isEmpty) {
      _brandingOverrides.remove(key);
    } else {
      _brandingOverrides[key] = overrides;
    }
    notifyListeners();
    await _save();
  }

  /// Enable multi-user mode. Cannot be undone once users exist.
  Future<void> setMultiUserEnabled(bool enabled) async {
    if (_isMultiUserEnabled == enabled) return;
    _isMultiUserEnabled = enabled;
    notifyListeners();
    await _save();
  }

  /// Set the default app for regular users in multi-user mode.
  Future<void> setDefaultAppId(String? appId) async {
    if (_defaultAppId == appId) return;
    _defaultAppId = appId;
    notifyListeners();
    await _save();
  }

  /// Ensure a default app is set. If none configured, sets the given ID.
  Future<void> ensureDefaultApp(String appId) async {
    if (_defaultAppId == null) {
      await setDefaultAppId(appId);
    }
  }

  Future<void> setDefaultTheme(String theme) async {
    if (_defaultTheme == theme) return;
    _defaultTheme = theme;
    notifyListeners();
    await _save();
  }

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  Future<void> initialize() async {
    if (_initialized) return;
    final file = await _getFile();
    if (await file.exists()) {
      try {
        final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final themeName = data['themeMode'] as String?;
        _themeMode = switch (themeName) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };
        final toured = data['touredAppIds'] as List<dynamic>?;
        if (toured != null) {
          _touredAppIds.addAll(toured.cast<String>());
        }
        _autoBackup = data['autoBackup'] as bool? ?? false;
        _backupRetention = data['backupRetention'] as int? ?? 5;
        _backupFolder = data['backupFolder'] as String?;
        _isMultiUserEnabled = data['isMultiUserEnabled'] as bool? ?? false;
        _defaultAppId = data['defaultAppId'] as String?;
        var loadedTheme = data['defaultTheme'] as String? ?? 'indigo';
        // Migrate legacy theme names
        if (loadedTheme == 'light') loadedTheme = 'indigo';
        if (loadedTheme == 'dark') loadedTheme = 'slate';
        _defaultTheme = loadedTheme;
        final brandOverrides = data['brandingOverrides'] as Map<String, dynamic>?;
        if (brandOverrides != null) {
          for (final entry in brandOverrides.entries) {
            _brandingOverrides[entry.key] = Map<String, String>.from(entry.value as Map);
          }
        }
      } catch (_) {}
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final file = await _getFile();
    await file.writeAsString(jsonEncode({
      'themeMode': switch (_themeMode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        _ => 'system',
      },
      'touredAppIds': _touredAppIds.toList(),
      'autoBackup': _autoBackup,
      'backupRetention': _backupRetention,
      if (_backupFolder != null) 'backupFolder': _backupFolder,
      'isMultiUserEnabled': _isMultiUserEnabled,
      if (_defaultAppId != null) 'defaultAppId': _defaultAppId,
      'defaultTheme': _defaultTheme,
      if (_brandingOverrides.isNotEmpty) 'brandingOverrides': _brandingOverrides,
    }));
  }
}

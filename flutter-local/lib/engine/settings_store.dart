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

  ThemeMode get themeMode => _themeMode;
  bool get isInitialized => _initialized;

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
    }));
  }
}

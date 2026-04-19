import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Default sub-folder inside the user's Documents directory where all ODS
/// files (databases, settings, backups, etc.) are stored.
const odsDefaultFolderName = 'One Does Simply';

/// Bootstrap file at the platform's ApplicationSupport directory, which
/// on Windows is under AppData — NOT OneDrive-redirected. This tiny file
/// holds just the user's chosen storage-folder path so the framework can
/// read it before any other state is loaded.
const _bootstrapFileName = 'ods_bootstrap.json';

Future<File> _bootstrapFile() async {
  final support = await getApplicationSupportDirectory();
  return File(p.join(support.path, _bootstrapFileName));
}

/// Reads the storage-folder path from the bootstrap file, or null if
/// no bootstrap file exists yet (first run).
Future<String?> readBootstrapStorageFolder() async {
  try {
    final file = await _bootstrapFile();
    if (!await file.exists()) return null;
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final path = data['storageFolder'] as String?;
    return (path != null && path.isNotEmpty) ? path : null;
  } catch (e) {
    debugPrint('readBootstrapStorageFolder: $e');
    return null;
  }
}

/// Writes the storage-folder path to the bootstrap file. Pass null to
/// remove the bootstrap entirely (reverts to default behaviour).
Future<void> writeBootstrapStorageFolder(String? path) async {
  final file = await _bootstrapFile();
  if (path == null || path.isEmpty) {
    if (await file.exists()) await file.delete();
    return;
  }
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode({'storageFolder': path}));
}

/// Returns the ODS data directory.
///
/// Resolution order:
/// 1. Explicit [customPath] argument, if given.
/// 2. Bootstrap file (`ods_bootstrap.json` in ApplicationSupport).
/// 3. Default `<Documents>/One Does Simply`.
///
/// The directory is created if it doesn't exist.
Future<Directory> getOdsDirectory({String? customPath}) async {
  String? root;
  if (customPath != null && customPath.isNotEmpty) {
    root = customPath;
  } else {
    final bootstrap = await readBootstrapStorageFolder();
    if (bootstrap != null && bootstrap.isNotEmpty) {
      root = bootstrap;
    } else {
      final docs = await getApplicationDocumentsDirectory();
      root = p.join(docs.path, odsDefaultFolderName);
    }
  }
  final dir = Directory(root);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// Legacy default location — `<Documents>/One Does Simply`. Used to detect
/// upgrades from earlier versions that always stored data there.
Future<Directory> getLegacyOdsDirectory() async {
  final docs = await getApplicationDocumentsDirectory();
  return Directory(p.join(docs.path, odsDefaultFolderName));
}

/// Copies every file and subdirectory from [src] to [dest]. Creates
/// [dest] if it doesn't exist. Preserves relative structure.
Future<void> copyOdsDirectoryContents(Directory src, Directory dest) async {
  if (!await dest.exists()) {
    await dest.create(recursive: true);
  }
  await for (final entity in src.list(recursive: false)) {
    final name = p.basename(entity.path);
    if (entity is File) {
      await entity.copy(p.join(dest.path, name));
    } else if (entity is Directory) {
      final sub = Directory(p.join(dest.path, name));
      await copyOdsDirectoryContents(entity, sub);
    }
  }
}

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
  String? _storageFolder;
  bool _hasPickedStorageFolder = false;

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

  /// Custom storage folder for all ODS data. When null, defaults to
  /// `Documents/One Does Simply/`.
  String? get storageFolder => _storageFolder;

  /// True once the user has seen (and dismissed) the first-run storage-folder
  /// prompt, or accepted its default. Prevents re-prompting on every launch.
  bool get hasPickedStorageFolder => _hasPickedStorageFolder;

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

  /// Set a custom storage folder for all ODS data (admin-only).
  /// Pass null to reset to the default `Documents/One Does Simply/`.
  ///
  /// Writes the bootstrap file so the choice survives restarts; does NOT
  /// move existing data. Use [moveStorageFolder] when you want to relocate
  /// files as well.
  Future<void> setStorageFolder(String? path) async {
    if (_storageFolder == path) return;
    _storageFolder = path;
    await writeBootstrapStorageFolder(path);
    notifyListeners();
    await _save();
  }

  /// Marks the first-run storage-folder prompt as shown so it won't
  /// re-appear on future launches.
  Future<void> markStoragePromptShown() async {
    if (_hasPickedStorageFolder) return;
    _hasPickedStorageFolder = true;
    notifyListeners();
    await _save();
  }

  /// Copies all ODS data from the current folder to [newPath], updates the
  /// bootstrap, then deletes the source folder. Throws on error (the caller
  /// should surface this to the user).
  ///
  /// Caller is responsible for ensuring no app has an open handle on the
  /// current folder (e.g. unload the current app first).
  Future<void> moveStorageFolder(String newPath) async {
    if (newPath.isEmpty) {
      throw ArgumentError('New storage folder path must not be empty');
    }
    final currentDir = await odsDirectory;
    final newDir = Directory(newPath);
    if (p.equals(currentDir.path, newDir.path)) {
      return;
    }

    if (!await newDir.exists()) {
      await newDir.create(recursive: true);
    }

    await copyOdsDirectoryContents(currentDir, newDir);

    // Update bootstrap BEFORE deleting the source so a crash leaves data
    // in the new location (discoverable) rather than lost.
    await writeBootstrapStorageFolder(newPath);
    _storageFolder = newPath;
    _hasPickedStorageFolder = true;

    try {
      await currentDir.delete(recursive: true);
    } catch (e) {
      debugPrint('moveStorageFolder: failed to delete old dir: $e');
    }

    notifyListeners();
    await _save();
  }

  /// Moves all ODS data back to the legacy default
  /// (`<Documents>/One Does Simply`) and clears the bootstrap so future
  /// launches fall through to the platform default.
  Future<void> resetStorageFolder() async {
    final legacyDir = await getLegacyOdsDirectory();
    final currentDir = await odsDirectory;
    final samePath = p.equals(currentDir.path, legacyDir.path);

    if (!samePath) {
      if (!await legacyDir.exists()) {
        await legacyDir.create(recursive: true);
      }
      await copyOdsDirectoryContents(currentDir, legacyDir);
    }

    await writeBootstrapStorageFolder(null);
    _storageFolder = null;

    if (!samePath) {
      try {
        await currentDir.delete(recursive: true);
      } catch (e) {
        debugPrint('resetStorageFolder: failed to delete old dir: $e');
      }
    }

    notifyListeners();
    await _save();
  }

  /// Convenience: returns the current ODS data directory, respecting the
  /// custom storage folder setting.
  Future<Directory> get odsDirectory => getOdsDirectory(customPath: _storageFolder);

  /// Settings file lives in the current ODS folder (which is resolved via
  /// the bootstrap — see [getOdsDirectory]). The bootstrap file itself
  /// lives in ApplicationSupport (not OneDrive-redirected), so the
  /// settings file can safely live alongside the rest of the data.
  Future<File> _getFile() async {
    final dir = await odsDirectory;
    return File(p.join(dir.path, _fileName));
  }

  Future<void> initialize() async {
    if (_initialized) return;
    // Hydrate the storage folder from the bootstrap file first so
    // subsequent reads/writes go to the right place.
    _storageFolder = await readBootstrapStorageFolder();

    final file = await _getFile();
    final settingsFileExisted = await file.exists();
    if (settingsFileExisted) {
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
        // storageFolder is source-of-truth in the bootstrap file; keep the
        // legacy settings.json value as a migration hint only.
        final legacyStorageFolder = data['storageFolder'] as String?;
        if (_storageFolder == null && legacyStorageFolder != null && legacyStorageFolder.isNotEmpty) {
          _storageFolder = legacyStorageFolder;
          await writeBootstrapStorageFolder(legacyStorageFolder);
        }
        _hasPickedStorageFolder = data['hasPickedStorageFolder'] as bool? ?? false;
        final brandOverrides = data['brandingOverrides'] as Map<String, dynamic>?;
        if (brandOverrides != null) {
          for (final entry in brandOverrides.entries) {
            _brandingOverrides[entry.key] = Map<String, String>.from(entry.value as Map);
          }
        }
      } catch (e) {
        debugPrint('SettingsStore: failed to load settings: $e');
      }
    }
    // Upgrade path: if we loaded an existing settings file from a version
    // that didn't track the first-run flag, treat the user as having already
    // picked a folder so they aren't prompted.
    if (settingsFileExisted && !_hasPickedStorageFolder) {
      _hasPickedStorageFolder = true;
      await _save();
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
      if (_storageFolder != null) 'storageFolder': _storageFolder,
      'hasPickedStorageFolder': _hasPickedStorageFolder,
      if (_brandingOverrides.isNotEmpty) 'brandingOverrides': _brandingOverrides,
    }));
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'log_service.dart';
import 'settings_store.dart';

/// Base URL for the ODS example catalog on GitHub Pages.
const _catalogBaseUrl =
    'https://one-does-simply.github.io/Specification/Examples';

/// A saved app entry in the user's "My Apps" list on the welcome screen.
///
/// Stores the full spec JSON alongside display metadata so apps can be
/// launched instantly without re-parsing or re-fetching.
class LoadedAppEntry {
  final String id;
  final String name;
  final String description;

  /// The complete ODS spec JSON, stored so the app can be launched offline.
  final String specJson;

  /// Whether this entry came from the remote example catalog (not user-added).
  /// Example apps cannot be removed from the list.
  final bool isBundled;

  /// Whether this entry has been archived (hidden from the main list).
  final bool isArchived;

  const LoadedAppEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.specJson,
    this.isBundled = false,
    this.isArchived = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'specJson': specJson,
        'isBundled': isBundled,
        'isArchived': isArchived,
      };

  factory LoadedAppEntry.fromJson(Map<String, dynamic> json) => LoadedAppEntry(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        specJson: json['specJson'] as String,
        isBundled: json['isBundled'] as bool? ?? false,
        isArchived: json['isArchived'] as bool? ?? false,
      );
}

/// An entry from the remote example catalog (metadata only, no spec loaded).
class CatalogEntry {
  final String id;
  final String name;
  final String description;
  final String file;

  const CatalogEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.file,
  });

  factory CatalogEntry.fromJson(Map<String, dynamic> json) => CatalogEntry(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        file: json['file'] as String,
      );
}

/// Persists the user's collection of saved ODS app specs to disk.
///
/// ODS Ethos: "My Apps" is the user's personal app library. On first run
/// the user is guided through an onboarding flow to pick example apps from
/// the remote catalog. On subsequent runs, new or updated examples are
/// synced silently in the background.
class LoadedAppsStore {
  static const _indexFileName = 'ods_loaded_apps.json';

  List<LoadedAppEntry> _apps = [];
  bool _initialized = false;
  bool _isFirstRun = false;

  /// Immutable view of the current app list.
  List<LoadedAppEntry> get apps => List.unmodifiable(_apps);

  /// Only non-archived apps (the main "My Apps" view).
  List<LoadedAppEntry> get activeApps =>
      List.unmodifiable(_apps.where((a) => !a.isArchived));

  /// Only archived apps (shown in an "Archived" section).
  List<LoadedAppEntry> get archivedApps =>
      List.unmodifiable(_apps.where((a) => a.isArchived));

  bool get isInitialized => _initialized;

  /// True when no saved app index exists — the user has never used the app.
  /// The UI layer checks this to show the onboarding flow.
  bool get isFirstRun => _isFirstRun;

  /// Custom storage folder override. Set by the framework before initialize().
  String? storageFolder;

  Future<File> _getIndexFile() async {
    final dir = await getOdsDirectory(customPath: storageFolder);
    return File(p.join(dir.path, _indexFileName));
  }

  /// Loads the saved app list from disk. On first run, sets [isFirstRun]
  /// so the UI can show onboarding instead of auto-seeding all examples.
  ///
  /// When [syncCatalog] is false, the remote catalog sync is skipped. Use
  /// this for read-only access (e.g., auto-launching a default app for a
  /// regular user) to avoid adding new examples behind the admin's back.
  Future<void> initialize({bool syncCatalog = true}) async {
    if (_initialized) return;

    final file = await _getIndexFile();
    if (await file.exists()) {
      try {
        final contents = await file.readAsString();
        final list = jsonDecode(contents) as List;
        _apps = list
            .map((e) => LoadedAppEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _apps = [];
      }

      // Returning user — sync catalog in the background (unless read-only).
      if (syncCatalog) _syncExamplesFromCatalog();
    } else {
      // First run — let the UI handle onboarding.
      _isFirstRun = true;
    }

    _initialized = true;
  }

  /// Fetches the remote catalog. Returns the list of available examples,
  /// or null if the fetch failed. Used by the onboarding UI.
  Future<List<CatalogEntry>?> fetchCatalog() async {
    try {
      final response = await http
          .get(Uri.parse('$_catalogBaseUrl/catalog.json'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final examples = data['examples'] as List;
      return examples
          .map((e) => CatalogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      logError('LoadedAppsStore', 'Failed to fetch example catalog', e);
      return null;
    }
  }

  /// Downloads and adds selected examples from the catalog.
  /// Called by the onboarding flow after the user picks examples.
  Future<void> addSelectedExamples(List<CatalogEntry> selected) async {
    for (final entry in selected) {
      final specJson = await _fetchSpec(entry.file);
      if (specJson != null) {
        _apps.add(LoadedAppEntry(
          id: 'example_${entry.id}',
          name: entry.name,
          description: entry.description,
          specJson: specJson,
          isBundled: true,
        ));
      }
    }

    _isFirstRun = false;
    await _save();
  }

  /// Marks first run as complete without adding any examples.
  /// Called when the user skips onboarding.
  Future<void> completeFirstRun() async {
    _isFirstRun = false;
    await _save();
  }

  /// Syncs example apps with the remote catalog: adds new ones and refreshes
  /// existing ones whose spec content has changed.
  Future<void> _syncExamplesFromCatalog() async {
    final catalog = await fetchCatalog();
    if (catalog == null) return;

    final existingById = {for (final a in _apps) a.id: a};
    var changed = false;

    for (final entry in catalog) {
      final entryId = 'example_${entry.id}';
      final specJson = await _fetchSpec(entry.file);
      if (specJson == null) continue;

      final existing = existingById[entryId];

      // Only update existing bundled examples — never add new ones silently.
      // New examples are added explicitly during onboarding.
      if (existing != null && existing.isBundled && existing.specJson != specJson) {
        final index = _apps.indexOf(existing);
        _apps[index] = LoadedAppEntry(
          id: entryId,
          name: entry.name,
          description: entry.description,
          specJson: specJson,
          isBundled: true,
          isArchived: existing.isArchived,
        );
        changed = true;
      }
    }

    if (changed) await _save();
  }

  /// Fetches a single spec JSON file from the remote examples directory.
  Future<String?> _fetchSpec(String fileName) async {
    try {
      final response = await http
          .get(Uri.parse('$_catalogBaseUrl/$fileName'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      return response.body;
    } catch (e) {
      logError('LoadedAppsStore', 'Failed to fetch example spec $fileName', e);
      return null;
    }
  }

  /// Adds a user-imported app to the top of the list and persists to disk.
  Future<void> addApp({
    required String name,
    required String description,
    required String specJson,
  }) async {
    final id = 'user_${DateTime.now().millisecondsSinceEpoch}';
    _apps.insert(
      0,
      LoadedAppEntry(
        id: id,
        name: name,
        description: description,
        specJson: specJson,
      ),
    );
    await _save();
  }

  /// Updates an existing app entry's metadata and spec JSON.
  Future<void> updateApp({
    required String id,
    required String name,
    required String description,
    required String specJson,
  }) async {
    final index = _apps.indexWhere((a) => a.id == id);
    if (index == -1) return;
    _apps[index] = LoadedAppEntry(
      id: id,
      name: name,
      description: description,
      specJson: specJson,
      isBundled: _apps[index].isBundled,
    );
    await _save();
  }

  /// Removes a user-added app from the list.
  Future<void> removeApp(String id) async {
    _apps.removeWhere((app) => app.id == id);
    await _save();
  }

  /// Archives an app (hides it without deleting).
  Future<void> archiveApp(String id) async {
    final index = _apps.indexWhere((a) => a.id == id);
    if (index == -1) return;
    final app = _apps[index];
    _apps[index] = LoadedAppEntry(
      id: app.id,
      name: app.name,
      description: app.description,
      specJson: app.specJson,
      isBundled: app.isBundled,
      isArchived: true,
    );
    await _save();
  }

  /// Restores an archived app back to the active list.
  Future<void> unarchiveApp(String id) async {
    final index = _apps.indexWhere((a) => a.id == id);
    if (index == -1) return;
    final app = _apps[index];
    _apps[index] = LoadedAppEntry(
      id: app.id,
      name: app.name,
      description: app.description,
      specJson: app.specJson,
      isBundled: app.isBundled,
      isArchived: false,
    );
    await _save();
  }

  /// Persists the current app list to the JSON index file.
  Future<void> _save() async {
    final file = await _getIndexFile();
    final json = jsonEncode(_apps.map((a) => a.toJson()).toList());
    await file.writeAsString(json);
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  /// Whether this entry was bundled with the framework (not user-added).
  /// Bundled apps cannot be removed from the list.
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

/// Persists the user's collection of saved ODS app specs to disk.
///
/// ODS Ethos: "My Apps" is the user's personal app library. Bundled examples
/// are seeded on first run to demonstrate ODS capabilities immediately.
/// User-added apps are saved so they survive app restarts — no re-importing
/// needed. Everything is a flat JSON file in the documents directory.
class LoadedAppsStore {
  static const _indexFileName = 'ods_loaded_apps.json';

  List<LoadedAppEntry> _apps = [];
  bool _initialized = false;

  /// Immutable view of the current app list.
  List<LoadedAppEntry> get apps => List.unmodifiable(_apps);

  /// Only non-archived apps (the main "My Apps" view).
  List<LoadedAppEntry> get activeApps =>
      List.unmodifiable(_apps.where((a) => !a.isArchived));

  /// Only archived apps (shown in an "Archived" section).
  List<LoadedAppEntry> get archivedApps =>
      List.unmodifiable(_apps.where((a) => a.isArchived));

  bool get isInitialized => _initialized;

  Future<File> _getIndexFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _indexFileName));
  }

  /// Loads the saved app list from disk, seeding bundled examples on first run.
  Future<void> initialize() async {
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
        // Corrupted index file — start fresh.
        _apps = [];
      }
    }

    // First run: seed all bundled examples.
    // Subsequent runs: add any new bundled examples that weren't there before.
    if (_apps.isEmpty) {
      await _seedBundledExamples();
    } else {
      await _addMissingBundledExamples();
    }

    _initialized = true;
  }

  /// Loads all bundled example spec assets and adds them to the app list.
  Future<void> _seedBundledExamples() async {
    for (final example in _bundledExamples) {
      try {
        final json = await rootBundle.loadString(example.assetPath);
        _apps.add(LoadedAppEntry(
          id: example.id,
          name: example.name,
          description: example.description,
          specJson: json,
          isBundled: true,
        ));
      } catch (_) {
        // Skip examples that fail to load — graceful degradation.
      }
    }

    await _save();
  }

  /// Syncs bundled examples with the saved list: adds new ones and refreshes
  /// existing ones whose asset content has changed. This ensures that when
  /// bundled specs are updated in a new version, users see the latest version
  /// without losing their own user-added apps.
  Future<void> _addMissingBundledExamples() async {
    final existingById = {for (final a in _apps) a.id: a};
    var changed = false;

    for (final example in _bundledExamples) {
      try {
        final json = await rootBundle.loadString(example.assetPath);
        final existing = existingById[example.id];

        if (existing == null) {
          // New bundled example — add it.
          _apps.add(LoadedAppEntry(
            id: example.id,
            name: example.name,
            description: example.description,
            specJson: json,
            isBundled: true,
          ));
          changed = true;
        } else if (existing.isBundled && existing.specJson != json) {
          // Existing bundled example with updated asset — refresh it.
          final index = _apps.indexOf(existing);
          _apps[index] = LoadedAppEntry(
            id: example.id,
            name: example.name,
            description: example.description,
            specJson: json,
            isBundled: true,
          );
          changed = true;
        }
      } catch (_) {
        // Skip examples that fail to load.
      }
    }

    if (changed) await _save();
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

  /// Removes a user-added app from the list. Bundled apps are protected
  /// from removal at the UI layer (remove button is not shown).
  Future<void> removeApp(String id) async {
    _apps.removeWhere((app) => app.id == id);
    await _save();
  }

  /// Archives an app (hides it without deleting). Works for both bundled
  /// and user-added apps.
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

  /// All bundled example apps shipped with the framework.
  static const _bundledExamples = [
    _BundledExample(
      id: 'bundled_customer_feedback',
      name: 'Customer Feedback',
      description: 'Collect and view customer feedback with a simple form.',
      assetPath: 'assets/customer-feedback-app.json',
    ),
    _BundledExample(
      id: 'bundled_habit_tracker',
      name: 'Habit Tracker',
      description: 'Track daily habits and review your consistency over time.',
      assetPath: 'assets/habit-tracker-app.json',
    ),
    _BundledExample(
      id: 'bundled_personal_journal',
      name: 'Personal Journal',
      description: 'A private diary to capture your thoughts and moods.',
      assetPath: 'assets/personal-journal-app.json',
    ),
    _BundledExample(
      id: 'bundled_recipe_book',
      name: 'Recipe Book',
      description: 'Save and browse your favorite recipes.',
      assetPath: 'assets/recipe-book-app.json',
    ),
    _BundledExample(
      id: 'bundled_expense_tracker',
      name: 'Expense Tracker',
      description: 'Log your spending and keep track of where your money goes.',
      assetPath: 'assets/expense-tracker-app.json',
    ),
    _BundledExample(
      id: 'bundled_reading_list',
      name: 'Reading List',
      description:
          'Track books you want to read, are reading, or have finished.',
      assetPath: 'assets/reading-list-app.json',
    ),
    _BundledExample(
      id: 'bundled_todo_list',
      name: 'To-Do List',
      description:
          'Track tasks, set priorities, and mark them complete.',
      assetPath: 'assets/todo-list-app.json',
    ),
  ];
}

/// Internal metadata for a bundled example app asset.
class _BundledExample {
  final String id;
  final String name;
  final String description;
  final String assetPath;

  const _BundledExample({
    required this.id,
    required this.name,
    required this.description,
    required this.assetPath,
  });
}

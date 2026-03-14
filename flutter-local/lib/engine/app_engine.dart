import 'package:flutter/material.dart';

import '../models/ods_app.dart';
import '../models/ods_action.dart';
import '../models/ods_component.dart';
import '../parser/spec_parser.dart';
import '../parser/spec_validator.dart';
import 'action_handler.dart';
import 'data_store.dart';

/// Holds a filtered dataset and a cursor position for record-source forms.
///
/// Used by forms with `recordSource` to step through rows one at a time
/// (e.g., quiz questions). The cursor loads all matching rows upfront and
/// navigates by index, keeping the flow snappy without repeated DB queries.
class RecordCursor {
  final List<Map<String, dynamic>> rows;
  int currentIndex;

  RecordCursor({required this.rows, this.currentIndex = 0});

  Map<String, dynamic>? get currentRecord =>
      (currentIndex >= 0 && currentIndex < rows.length)
          ? rows[currentIndex]
          : null;

  bool get hasNext => currentIndex < rows.length - 1;
  bool get hasPrevious => currentIndex > 0;
  bool get isEmpty => rows.isEmpty;
  int get count => rows.length;
}

/// The central state manager for a running ODS application.
///
/// ODS Spec alignment: This is where the spec comes alive. The engine takes
/// a parsed [OdsApp] model and provides the runtime state that the UI layer
/// observes: current page, navigation stack, form values, and data access.
///
/// ODS Ethos: The engine is the "do simply" layer. It hides all complexity
/// (SQLite, navigation history, form state) behind a clean interface so the
/// renderer can focus purely on displaying components.
///
/// Architecture note: Uses [ChangeNotifier] (via Provider) for state
/// management — chosen for simplicity over more powerful alternatives like
/// Bloc or Riverpod. This matches the ODS philosophy: use the simplest tool
/// that works.
class AppEngine extends ChangeNotifier {
  OdsApp? _app;
  String? _currentPageId;
  final List<String> _navigationStack = [];
  final Map<String, Map<String, String>> _formStates = {};
  final DataStore _dataStore = DataStore();
  late final ActionHandler _actionHandler;
  ValidationResult? _validation;

  /// Record cursors for forms with `recordSource`. Keyed by form ID.
  final Map<String, RecordCursor> _recordCursors = {};

  /// Incremented when any record cursor moves. Used by form widgets as a key
  /// suffix to force dropdown recreation on record change.
  int _recordGeneration = 0;
  String? _loadError;
  bool _debugMode = false;
  bool _isLoading = false;

  /// The most recent action error (e.g., required field validation failure).
  /// Cleared on the next successful action. The UI layer reads this to show
  /// SnackBar feedback to the user.
  String? _lastActionError;

  AppEngine() {
    _actionHandler = ActionHandler(dataStore: _dataStore);
  }

  // ---------------------------------------------------------------------------
  // Public getters — the UI layer reads these via context.watch<AppEngine>().
  // ---------------------------------------------------------------------------

  /// The currently loaded app model, or null if no spec is loaded.
  OdsApp? get app => _app;

  /// The ID of the currently displayed page.
  String? get currentPageId => _currentPageId;

  /// The navigation history stack (immutable view for debug panel).
  List<String> get navigationStack => List.unmodifiable(_navigationStack);

  /// Validation results from the most recent spec load.
  ValidationResult? get validation => _validation;

  /// Human-readable error message if the most recent load failed.
  String? get loadError => _loadError;

  /// Whether debug mode (validation + navigation + data panels) is active.
  bool get debugMode => _debugMode;

  /// Whether a spec is currently being loaded (shows progress indicator).
  bool get isLoading => _isLoading;

  /// Direct access to the data store for the debug panel's data explorer.
  DataStore get dataStore => _dataStore;

  /// The most recent action error, if any. Used by the UI to show feedback
  /// (e.g., SnackBar) when required fields are missing on submit.
  String? get lastActionError => _lastActionError;

  /// The record cursor generation counter. Incremented whenever a cursor
  /// moves, so form widgets can use it as a key to force full rebuild.
  int get recordGeneration => _recordGeneration;

  /// Returns the record cursor for a form, if one has been loaded.
  RecordCursor? getRecordCursor(String formId) => _recordCursors[formId];

  /// Returns the current field values for a form, creating the map if needed.
  /// Called by form widgets to initialize their text controllers.
  Map<String, String> getFormState(String formId) {
    return _formStates.putIfAbsent(formId, () => {});
  }

  // ---------------------------------------------------------------------------
  // Spec loading — the entry point for bringing an ODS app to life.
  // ---------------------------------------------------------------------------

  /// Parses, validates, and activates an ODS spec from raw JSON.
  ///
  /// Returns true on success, false on failure (check [loadError] for details).
  /// On success, initializes the local database and navigates to [startPage].
  Future<bool> loadSpec(String jsonString) async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();

    // Parse the JSON into an OdsApp model with validation.
    final parser = SpecParser();
    final result = parser.parse(jsonString);

    _validation = result.validation;

    if (result.parseError != null) {
      _loadError = result.parseError;
      _isLoading = false;
      notifyListeners();
      return false;
    }

    if (!result.isOk) {
      _loadError = result.validation.errors.map((e) => e.message).join('\n');
      _isLoading = false;
      notifyListeners();
      return false;
    }

    _app = result.app!;

    // Initialize local storage: create tables, run seed data.
    try {
      await _dataStore.initialize(_app!.appName);
      await _dataStore.setupDataSources(_app!.dataSources);
    } catch (e) {
      _loadError = 'Database initialization failed: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    // Load app settings from the database, falling back to spec defaults.
    _appSettings.clear();
    for (final entry in _app!.settings.entries) {
      _appSettings[entry.key] = entry.value.defaultValue;
    }
    final savedSettings = await _dataStore.getAllAppSettings();
    _appSettings.addAll(savedSettings);

    // Ready — navigate to the start page.
    _currentPageId = _app!.startPage;
    _navigationStack.clear();
    _formStates.clear();
    _recordCursors.clear();
    _isLoading = false;
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Navigation — simple stack-based page management.
  // ---------------------------------------------------------------------------

  /// Navigates to a page, pushing the current page onto the back stack.
  /// Silently ignores requests to navigate to unknown page IDs.
  void navigateTo(String pageId) {
    if (_app == null || !_app!.pages.containsKey(pageId)) return;
    if (_currentPageId != null) {
      _navigationStack.add(_currentPageId!);
    }
    _currentPageId = pageId;
    notifyListeners();
  }

  /// Populates a form with data from a map (e.g., a tapped list row) and
  /// navigates to the target page. Internal fields (_id, _createdAt) are
  /// stored so update actions can match on them.
  void populateFormAndNavigate({
    required String formId,
    required String pageId,
    required Map<String, dynamic> rowData,
  }) {
    final state = _formStates.putIfAbsent(formId, () => {});
    state.clear();
    for (final entry in rowData.entries) {
      state[entry.key] = entry.value?.toString() ?? '';
    }
    navigateTo(pageId);
  }

  bool canGoBack() => _navigationStack.isNotEmpty;

  /// Pops the navigation stack and returns to the previous page.
  void goBack() {
    if (_navigationStack.isEmpty) return;
    _currentPageId = _navigationStack.removeLast();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Form state — tracks field values for all active forms.
  // ---------------------------------------------------------------------------

  /// Updates a single field value in a form's state map.
  /// Called by form field widgets on every keystroke.
  void updateFormField(String formId, String fieldName, String value) {
    final state = _formStates.putIfAbsent(formId, () => {});
    state[fieldName] = value;
    // No notifyListeners() here — form fields manage their own controllers.
    // Only clearForm() triggers a rebuild so text fields can reset.
  }

  /// Removes all field values for a form, triggering a UI rebuild so
  /// text controllers reset to empty.
  void clearForm(String formId) {
    _formStates.remove(formId);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Action execution — processes button onClick action arrays.
  // ---------------------------------------------------------------------------

  /// Executes a list of actions sequentially (e.g., submit then navigate).
  ///
  /// ODS Spec: Actions in an onClick array run in order. A submit followed
  /// by a navigate gives the natural "save and go" flow. If any action
  /// errors, it is logged and the remaining actions continue.
  ///
  /// Form state is snapshotted before the chain starts so that later actions
  /// (e.g., nextRecord after submit) can still resolve field values even
  /// after the form has been cleared.
  Future<void> executeActions(List<OdsAction> actions) async {
    _lastActionError = null;

    // Snapshot form state so later actions in the chain can still read values
    // after submit clears the original form.
    final formSnapshot = _formStates.map(
      (k, v) => MapEntry(k, Map<String, String>.from(v)),
    );

    for (final action in actions) {
      // Record cursor actions are handled directly by the engine.
      if (action.isRecordAction) {
        final onEndAction = await _handleRecordAction(action, formSnapshot);
        if (onEndAction != null) {
          // The cursor hit the end — execute the onEnd action and stop this chain.
          await executeActions([onEndAction]);
          return;
        }
        continue;
      }

      final result = await _actionHandler.execute(
        action: action,
        app: _app!,
        formStates: formSnapshot,
      );

      if (result.error != null) {
        debugPrint('ODS Action Error: ${result.error}');
        _lastActionError = result.error;
        notifyListeners();
        return; // Stop executing further actions in the chain.
      }

      // Clear the form after a successful submit so fields reset.
      if (result.submitted && action.target != null) {
        clearForm(action.target!);
      }

      if (result.navigateTo != null) {
        navigateTo(result.navigateTo!);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Record cursor — step-through navigation for forms with recordSource.
  // ---------------------------------------------------------------------------

  /// Handles a record cursor action (firstRecord, nextRecord, etc.).
  ///
  /// Returns the `onEnd` action if the cursor went past the end/start,
  /// or null if the cursor moved successfully.
  Future<OdsAction?> _handleRecordAction(
    OdsAction action,
    Map<String, Map<String, String>> formSnapshot,
  ) async {
    final formId = action.target;
    if (formId == null || _app == null) return null;

    switch (action.action) {
      case 'firstRecord':
        return await _handleFirstRecord(formId, action, formSnapshot);
      case 'nextRecord':
        return _handleNextRecord(formId, action);
      case 'previousRecord':
        return _handlePreviousRecord(formId, action);
      case 'lastRecord':
        return await _handleLastRecord(formId, action, formSnapshot);
      default:
        return null;
    }
  }

  /// Loads all matching records for a form and moves to the first one.
  Future<OdsAction?> _handleFirstRecord(
    String formId,
    OdsAction action,
    Map<String, Map<String, String>> formSnapshot,
  ) async {
    // Find the form component to get its recordSource.
    final form = _findFormComponent(formId);
    if (form == null || form.recordSource == null) {
      debugPrint('ODS: firstRecord — form "$formId" has no recordSource');
      return null;
    }

    final ds = _app!.dataSources[form.recordSource!];
    if (ds == null || !ds.isLocal) return null;

    // Resolve {field} references in the filter from current form state.
    final resolvedFilter = _resolveFilter(action.filter, formSnapshot);

    // Query all matching rows.
    List<Map<String, dynamic>> rows;
    try {
      if (resolvedFilter != null && resolvedFilter.isNotEmpty) {
        rows = await _dataStore.queryWithFilter(ds.tableName, resolvedFilter);
      } else {
        rows = await _dataStore.query(ds.tableName);
      }
    } catch (e) {
      debugPrint('ODS: firstRecord query failed: $e');
      return action.onEnd;
    }

    if (rows.isEmpty) {
      return action.onEnd;
    }

    // Create cursor and populate form.
    _recordCursors[formId] = RecordCursor(rows: rows, currentIndex: 0);
    _populateFormFromCursor(formId);
    return null;
  }

  /// Moves the cursor to the next record. Returns onEnd if past the last row.
  OdsAction? _handleNextRecord(String formId, OdsAction action) {
    final cursor = _recordCursors[formId];
    if (cursor == null || !cursor.hasNext) {
      return action.onEnd;
    }

    cursor.currentIndex++;
    _populateFormFromCursor(formId);
    return null;
  }

  /// Moves the cursor to the previous record. Returns onEnd if before first.
  OdsAction? _handlePreviousRecord(String formId, OdsAction action) {
    final cursor = _recordCursors[formId];
    if (cursor == null || !cursor.hasPrevious) {
      return action.onEnd;
    }

    cursor.currentIndex--;
    _populateFormFromCursor(formId);
    return null;
  }

  /// Loads all matching records and moves to the last one.
  Future<OdsAction?> _handleLastRecord(
    String formId,
    OdsAction action,
    Map<String, Map<String, String>> formSnapshot,
  ) async {
    // Reuse firstRecord logic to load data, then jump to end.
    final result = await _handleFirstRecord(formId, action, formSnapshot);
    if (result != null) return result; // onEnd (empty)

    final cursor = _recordCursors[formId];
    if (cursor != null && cursor.rows.isNotEmpty) {
      cursor.currentIndex = cursor.rows.length - 1;
      _populateFormFromCursor(formId);
    }
    return null;
  }

  /// Populates a form's state map from the current record in its cursor.
  void _populateFormFromCursor(String formId) {
    final cursor = _recordCursors[formId];
    final record = cursor?.currentRecord;
    if (record == null) return;

    final state = _formStates.putIfAbsent(formId, () => {});
    state.clear();
    for (final entry in record.entries) {
      state[entry.key] = entry.value?.toString() ?? '';
    }

    _recordGeneration++;
    notifyListeners();
  }

  /// Resolves `{fieldName}` references in a filter map using all form states.
  Map<String, String>? _resolveFilter(
    Map<String, String>? filter,
    Map<String, Map<String, String>> formSnapshot,
  ) {
    if (filter == null || filter.isEmpty) return null;

    // Build a flat map of all form values for reference resolution.
    final allValues = <String, String>{};
    for (final formState in formSnapshot.values) {
      allValues.addAll(formState);
    }
    // Also include current (non-snapshot) form state for recently populated forms.
    for (final formState in _formStates.values) {
      allValues.addAll(formState);
    }

    final fieldPattern = RegExp(r'\{(\w+)\}');
    return filter.map((key, value) {
      final resolved = value.replaceAllMapped(fieldPattern, (match) {
        return allValues[match.group(1)!] ?? '';
      });
      return MapEntry(key, resolved);
    });
  }

  /// Finds a form component by ID across all pages.
  OdsFormComponent? _findFormComponent(String formId) {
    for (final page in _app!.pages.values) {
      for (final component in page.content) {
        if (component is OdsFormComponent && component.id == formId) {
          return component;
        }
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Row actions — inline per-row operations triggered from list components.
  // ---------------------------------------------------------------------------

  /// Executes a row action (e.g., "Mark Done") using the row's own data to
  /// identify the record and the action's `values` map to set new values.
  /// Bypasses form state entirely — the list component drives this directly.
  Future<void> executeRowAction({
    required String dataSourceId,
    required String matchField,
    required String matchValue,
    required Map<String, String> values,
  }) async {
    final ds = _app?.dataSources[dataSourceId];
    if (ds == null || !ds.isLocal) return;

    try {
      await _dataStore.update(ds.tableName, values, matchField, matchValue);
      notifyListeners(); // Trigger list rebuild to reflect the change.
    } catch (e) {
      debugPrint('ODS Row Action Error: $e');
    }
  }

  /// Executes a delete row action, removing the matched record from storage.
  Future<void> executeDeleteRowAction({
    required String dataSourceId,
    required String matchField,
    required String matchValue,
  }) async {
    final ds = _app?.dataSources[dataSourceId];
    if (ds == null || !ds.isLocal) return;

    try {
      await _dataStore.delete(ds.tableName, matchField, matchValue);
      notifyListeners(); // Trigger list rebuild to reflect the deletion.
    } catch (e) {
      debugPrint('ODS Delete Row Action Error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // App settings — user-configurable settings defined in the spec.
  // ---------------------------------------------------------------------------

  /// In-memory cache of app settings, loaded from the database on spec load.
  final Map<String, String> _appSettings = {};

  /// Gets the current value for an app setting, falling back to the spec default.
  String? getAppSetting(String key) => _appSettings[key];

  /// Updates an app setting value and persists it to the database.
  Future<void> setAppSetting(String key, String value) async {
    _appSettings[key] = value;
    await _dataStore.setAppSetting(key, value);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Data export — off-ramp: export all app data as portable JSON.
  // ---------------------------------------------------------------------------

  /// Exports all user data as a JSON-serializable map.
  /// Includes metadata (app name, export timestamp) and all table data.
  Future<Map<String, dynamic>> exportData() async {
    final tables = await _dataStore.exportAllData();
    return {
      'odsExport': {
        'appName': _app?.appName ?? 'unknown',
        'exportedAt': DateTime.now().toIso8601String(),
        'version': '1.0',
      },
      'tables': tables,
    };
  }

  // ---------------------------------------------------------------------------
  // Backup & restore — save and reload all app data.
  // ---------------------------------------------------------------------------

  /// Creates a backup of all app data as a JSON-serializable map.
  Future<Map<String, dynamic>> backupData() async {
    final tables = await _dataStore.exportAllData();
    final settings = await _dataStore.getAllAppSettings();
    return {
      'odsBackup': {
        'appName': _app?.appName ?? 'unknown',
        'createdAt': DateTime.now().toIso8601String(),
        'version': '1.0',
      },
      'tables': tables,
      'appSettings': settings,
    };
  }

  /// Restores app data from a backup map, replacing all existing data.
  /// Triggers a UI rebuild so lists refresh with the restored data.
  Future<void> restoreData(Map<String, dynamic> backup) async {
    final tablesRaw = backup['tables'] as Map<String, dynamic>?;
    if (tablesRaw != null) {
      final tables = tablesRaw.map<String, List<Map<String, dynamic>>>(
        (key, value) => MapEntry(
          key,
          (value as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        ),
      );
      await _dataStore.importAllData(tables);
    }

    // Restore app settings.
    final settingsRaw = backup['appSettings'] as Map<String, dynamic>?;
    if (settingsRaw != null) {
      for (final entry in settingsRaw.entries) {
        final value = entry.value.toString();
        _appSettings[entry.key] = value;
        await _dataStore.setAppSetting(entry.key, value);
      }
    }

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Table import — append rows to a specific table from CSV/JSON.
  // ---------------------------------------------------------------------------

  /// Returns the list of local table names defined in the app's data sources.
  List<String> get localTableNames {
    if (_app == null) return [];
    return _app!.dataSources.values
        .where((ds) => ds.isLocal)
        .map((ds) => ds.tableName)
        .toSet()
        .toList()
      ..sort();
  }

  /// Imports rows into a specific table and triggers a UI rebuild.
  /// Returns the number of rows imported.
  Future<int> importTableRows(
      String tableName, List<Map<String, dynamic>> rows) async {
    final count = await _dataStore.importTableRows(tableName, rows);
    notifyListeners();
    return count;
  }

  // ---------------------------------------------------------------------------
  // Debug mode — toggle-able inspection tools for spec authors.
  // ---------------------------------------------------------------------------

  void toggleDebugMode() {
    _debugMode = !_debugMode;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Data access — used by list components to fetch rows from local storage.
  // ---------------------------------------------------------------------------

  /// Queries a data source by ID and returns all rows.
  /// Returns an empty list for unknown, non-local, or errored sources.
  Future<List<Map<String, dynamic>>> queryDataSource(String dataSourceId) async {
    final ds = _app?.dataSources[dataSourceId];
    if (ds == null || !ds.isLocal) return [];
    try {
      return await _dataStore.query(ds.tableName);
    } catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Cleanup — release resources when returning to the welcome screen.
  // ---------------------------------------------------------------------------

  /// Resets all state and closes the database, returning the framework
  /// to the welcome screen ready to load a new spec.
  Future<void> reset() async {
    await _dataStore.close();
    _app = null;
    _currentPageId = null;
    _navigationStack.clear();
    _formStates.clear();
    _recordCursors.clear();
    _appSettings.clear();
    _validation = null;
    _loadError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _dataStore.close();
    super.dispose();
  }
}

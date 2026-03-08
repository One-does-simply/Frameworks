import 'package:flutter/material.dart';

import '../models/ods_app.dart';
import '../models/ods_action.dart';
import '../parser/spec_parser.dart';
import '../parser/spec_validator.dart';
import 'action_handler.dart';
import 'data_store.dart';

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

    // Ready — navigate to the start page.
    _currentPageId = _app!.startPage;
    _navigationStack.clear();
    _formStates.clear();
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
  Future<void> executeActions(List<OdsAction> actions) async {
    _lastActionError = null;

    for (final action in actions) {
      final result = await _actionHandler.execute(
        action: action,
        app: _app!,
        formStates: _formStates,
      );

      if (result.error != null) {
        debugPrint('ODS Action Error: ${result.error}');
        // Surface the error to the UI so the user sees feedback
        // (e.g., "Required fields missing: Amount, Description").
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

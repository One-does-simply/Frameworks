import 'package:flutter/material.dart';

import '../models/ods_app.dart';
import '../models/ods_action.dart';
import '../models/ods_component.dart';
import '../parser/spec_parser.dart';
import '../parser/spec_validator.dart';
import 'action_handler.dart';
import 'auth_service.dart';
import 'data_store.dart';
import 'log_service.dart';

/// Holds a filtered dataset and a cursor position for record-source forms.
///
/// Used by forms with `recordSource` to step through rows one at a time
/// (e.g., quiz questions). The cursor loads all matching rows upfront and
/// navigates by index, keeping the flow snappy without repeated DB queries.
class RecordCursor {
  final List<Map<String, dynamic>> rows;
  int _currentIndex;

  RecordCursor({required this.rows, int currentIndex = 0})
      : _currentIndex = currentIndex;

  /// The current position in the row list. Clamped to valid bounds on set.
  int get currentIndex => _currentIndex;
  set currentIndex(int value) {
    _currentIndex = value.clamp(0, rows.isEmpty ? 0 : rows.length - 1);
  }

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
  late final AuthService _authService;
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

  /// The most recent informational message from a `showMessage` action.
  ///
  /// Lifecycle: Cleared at the start of every [executeActions] call. Set when
  /// a `showMessage` result is returned by the [ActionHandler]. The UI layer
  /// reads this after `executeActions` completes to show a SnackBar.
  String? _lastMessage;

  /// Custom storage folder override. Set by the framework before loading.
  String? storageFolder;

  /// When true, per-app auth is bypassed because the framework already handles
  /// authentication. The framework's roles are used for role-based features.
  bool skipAppAuth = false;

  /// Framework-level user info injected when [skipAppAuth] is true.
  List<String> frameworkRoles = const [];
  String frameworkUsername = '';
  String frameworkEmail = '';
  String frameworkDisplayName = '';

  AppEngine() {
    _authService = AuthService(_dataStore);
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

  /// The auth service for login, user management, and role checks.
  AuthService get authService => _authService;

  /// Whether the loaded app uses multi-user mode.
  bool get isMultiUser => _app?.auth.multiUser ?? false;

  /// Whether the admin setup wizard needs to be shown.
  /// True when multi-user is enabled but no admin account exists yet.
  /// Always false when [skipAppAuth] is true (framework handles auth).
  bool get needsAdminSetup => !skipAppAuth && isMultiUser && !_authService.isAdminSetUp;

  /// Whether the login screen needs to be shown.
  /// True when multi-user is enabled, admin is set up, but no user is logged in.
  /// Always false when [skipAppAuth] is true (framework handles auth).
  bool get needsLogin => !skipAppAuth && isMultiUser && _authService.isAdminSetUp && !_authService.isLoggedIn;

  /// Whether the app requires multi-user and cannot run without it.
  bool get isMultiUserOnly => _app?.auth.multiUserOnly ?? false;

  /// The effective roles for the current user — framework roles when
  /// framework auth is active, per-app roles otherwise.
  List<String> get effectiveRoles =>
      skipAppAuth ? frameworkRoles : _authService.currentRoles;

  /// Re-resolves the start page for the current user's roles.
  /// Called after login/admin-setup when the user's roles have changed.
  void resolveStartPage() {
    if (_app == null) return;
    _currentPageId = _app!.startPageForRoles(effectiveRoles);
    notifyListeners();
  }

  /// The most recent action error, if any. Used by the UI to show feedback
  /// (e.g., SnackBar) when required fields are missing on submit.
  String? get lastActionError => _lastActionError;

  /// The most recent informational message from a showMessage action.
  String? get lastMessage => _lastMessage;

  /// The record cursor generation counter. Incremented whenever a cursor
  /// moves, so form widgets can use it as a key to force full rebuild.
  int get recordGeneration => _recordGeneration;

  /// Returns the record cursor for a form, if one has been loaded.
  RecordCursor? getRecordCursor(String formId) => _recordCursors[formId];

  /// Returns all form states. Used by expression-based visibility to
  /// collect all field values into a flat map for evaluation.
  Map<String, Map<String, String>> get allFormStates => _formStates;

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

    // Initialize local storage: create tables, run seed data, load settings.
    try {
      await _dataStore.initialize(_app!.appName, storageFolder: storageFolder);
      await _dataStore.setupDataSources(_app!.dataSources);

      // Load app settings from the database, falling back to spec defaults.
      _appSettings.clear();
      for (final entry in _app!.settings.entries) {
        _appSettings[entry.key] = entry.value.defaultValue;
      }
      final savedSettings = await _dataStore.getAllAppSettings();
      _appSettings.addAll(savedSettings);

      // Initialize auth if multi-user mode is enabled.
      if (_app!.auth.multiUser) {
        if (skipAppAuth && frameworkRoles.isNotEmpty) {
          // Framework already authenticated — inject its state into per-app
          // auth so hasAccess, isAdmin, etc. work without a second login.
          _authService.injectFrameworkAuth(
            username: frameworkUsername,
            email: frameworkEmail,
            displayName: frameworkDisplayName,
            roles: frameworkRoles,
          );
        } else {
          await _authService.initialize();
        }
      }
    } catch (e) {
      _loadError = 'Database initialization failed: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    // Ready — navigate to the start page (role-aware).
    _currentPageId = _app!.startPageForRoles(effectiveRoles);
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
  /// Logs a warning and ignores requests to navigate to unknown page IDs.
  /// Blocks navigation to role-restricted pages the user can't access.
  void navigateTo(String pageId) {
    if (_app == null || !_app!.pages.containsKey(pageId)) {
      if (_app != null) {
        logWarn('AppEngine', 'Navigate to unknown page "$pageId"');
      }
      return;
    }

    // Role-based navigation guard.
    final targetPage = _app!.pages[pageId]!;
    if (isMultiUser && !_authService.hasAccess(targetPage.roles)) {
      logWarn('AppEngine', 'Navigation blocked — user lacks role for page "$pageId"');
      return;
    }

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

  /// Clears all form states and record cursors. Used when switching users
  /// to prevent stale data from leaking between sessions.
  void clearFormStates() {
    _formStates.clear();
    _recordCursors.clear();
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
  ///
  /// The optional [confirmFn] callback is invoked when an action has a
  /// `confirm` property. It should show a dialog and return true to proceed
  /// or false to abort the chain. This keeps the engine UI-free while
  /// supporting per-action confirmation.
  Future<void> executeActions(
    List<OdsAction> actions, {
    Future<bool> Function(String message)? confirmFn,
  }) async {
    _lastActionError = null;
    _lastMessage = null;

    // Snapshot form state so later actions in the chain can still read values
    // after submit clears the original form.
    final formSnapshot = _formStates.map(
      (k, v) => MapEntry(k, Map<String, String>.from(v)),
    );

    // Tracks the _id of the most recently inserted row (from a submit) so
    // later actions in the same chain can reference it via {_id} placeholders.
    String? lastInsertedId;

    for (final action in actions) {
      // Per-action confirmation: show a dialog before executing.
      if (action.confirm != null && confirmFn != null) {
        final proceed = await confirmFn(action.confirm!);
        if (!proceed) return;
      }

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

      // Wrap the action handler in try/catch so thrown exceptions do not
      // escape executeActions. Graceful degradation: log, set the error,
      // and break the chain.
      ActionResult result;
      try {
        result = await _actionHandler.execute(
          action: action,
          app: _app!,
          formStates: formSnapshot,
          ownerId: isMultiUser ? _authService.currentUserId?.toString() : null,
        );
      } catch (e, st) {
        logError('AppEngine', 'Action threw exception', e);
        logDebug('AppEngine', st.toString());
        _lastActionError = e.toString();
        notifyListeners();
        return; // Stop executing further actions in the chain.
      }

      if (result.error != null) {
        logError('AppEngine', 'Action error', result.error);
        _lastActionError = result.error;
        notifyListeners();
        return; // Stop executing further actions in the chain.
      }

      if (result.message != null) {
        _lastMessage = result.message;
        notifyListeners();
      }

      // Capture the inserted row's _id on successful submit so later actions
      // in the chain can use {_id} placeholders to reference it.
      if (result.submitted && result.insertedId != null) {
        lastInsertedId = result.insertedId;
      }

      // Clear the form after a successful submit so fields reset.
      // If preserveFields is set, restore those values after clearing
      // (enables "Add & Add Another" flows where context is kept).
      if (result.submitted && action.target != null) {
        Map<String, String>? preserved;
        if (action.preserveFields.isNotEmpty) {
          final oldState = _formStates[action.target!];
          if (oldState != null) {
            preserved = {
              for (final field in action.preserveFields)
                if (oldState.containsKey(field)) field: oldState[field]!,
            };
          }
        }
        clearForm(action.target!);
        if (preserved != null && preserved.isNotEmpty) {
          final state = getFormState(action.target!);
          state.addAll(preserved);
          notifyListeners();
        }
      }

      // Handle cascade rename: update linked children when a parent field changes.
      // New map shape (React-aligned): cascade = {childDsId: fieldName, ...}
      if (result.cascade != null && result.cascade!.isNotEmpty) {
        final parentField = result.cascadeMatchField;
        final oldValue = result.cascadeOldValue;
        // The new value is what the update wrote — read it from either the
        // action's withData (direct update path) or the form state (form path).
        String? newValue;
        if (action.withData != null && parentField != null &&
            action.withData!.containsKey(parentField)) {
          newValue = action.withData![parentField]?.toString();
        }
        newValue ??= formSnapshot[action.target]?[parentField];

        if (parentField != null && oldValue != null && newValue != null &&
            oldValue != newValue) {
          for (final entry in result.cascade!.entries) {
            final childDsId = entry.key;
            final childField = entry.value;
            await _cascadeChildOnly(
              childDataSourceId: childDsId,
              childLinkField: childField,
              oldValue: oldValue,
              newValue: newValue,
            );
          }
        }
      }

      if (result.navigateTo != null) {
        navigateTo(result.navigateTo!);
      }

      // Pre-fill a form with data after navigation.
      if (result.populateForm != null && result.populateData != null) {
        final state = getFormState(result.populateForm!);
        for (final entry in result.populateData!.entries) {
          var value = entry.value?.toString() ?? '';
          // Resolve {fieldName} references from form state snapshot.
          // Also resolve {_id} to the most recently inserted row's id.
          value = value.replaceAllMapped(
            RegExp(r'\{(\w+)\}'),
            (m) {
              final ref = m.group(1)!;
              if (ref == '_id' && lastInsertedId != null) {
                return lastInsertedId!;
              }
              for (final fs in formSnapshot.values) {
                if (fs.containsKey(ref)) return fs[ref]!;
              }
              return m.group(0)!; // Leave unreplaced if not found.
            },
          );
          state[entry.key] = value;
        }
      }

      // Universal onEnd: after any successful NON-record action completes,
      // fire onEnd as a follow-up action. Record actions chain onEnd via
      // their own helper (above) — keep that working by skipping here.
      if (action.onEnd != null && !action.isRecordAction) {
        // Preserve the current message so the nested executeActions reset
        // doesn't erase the primary action's message if the nested chain
        // doesn't produce its own.
        final preservedMessage = _lastMessage;
        await executeActions([action.onEnd!], confirmFn: confirmFn);
        // If the nested chain produced its own message/error, keep that.
        // Otherwise, restore the primary action's message.
        if (_lastMessage == null && preservedMessage != null) {
          _lastMessage = preservedMessage;
        }
        // If the nested chain errored, stop the outer chain too.
        if (_lastActionError != null) return;
      }
    }
  }

  /// Updates child rows whose link field equals [oldValue] to [newValue].
  /// Used by cascade rename to sweep a single child table; the parent row is
  /// assumed to have already been updated by the primary update action.
  Future<void> _cascadeChildOnly({
    required String childDataSourceId,
    required String childLinkField,
    required String oldValue,
    required String newValue,
  }) async {
    final childDs = _app?.dataSources[childDataSourceId];
    if (childDs == null) {
      logWarn('AppEngine',
          'Cascade: unknown child data source "$childDataSourceId"');
      return;
    }
    if (oldValue == newValue) return;
    try {
      final children = await _dataStore.query(childDs.tableName);
      for (final child in children) {
        if (child[childLinkField]?.toString() == oldValue) {
          final id = child['_id']?.toString() ?? '';
          await _dataStore.update(
            childDs.tableName,
            {childLinkField: newValue},
            '_id',
            id,
          );
        }
      }
      notifyListeners();
    } catch (e) {
      logError('AppEngine', 'Cascade child update error', e);
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
      logWarn('AppEngine', 'firstRecord — form "$formId" has no recordSource');
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
      logError('AppEngine', 'firstRecord query failed', e);
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
  ///
  /// When ownership is enabled on the data source and the user is not an admin,
  /// the row's owner field must match the current user ID.
  Future<void> executeRowAction({
    required String dataSourceId,
    required String matchField,
    required String matchValue,
    required Map<String, String> values,
    Map<String, dynamic>? rowData,
  }) async {
    final ds = _app?.dataSources[dataSourceId];
    if (ds == null || !ds.isLocal) return;

    // Ownership check: verify current user owns this row before allowing update.
    if (isMultiUser && ds.ownership.enabled && !_authService.isAdmin) {
      final currentUserId = _authService.currentUserId?.toString();
      final rowOwner = rowData?[ds.ownership.ownerField]?.toString();
      if (currentUserId == null || rowOwner != currentUserId) {
        logWarn('AppEngine', '[SECURITY] permission_denied: '
            'user ${_authService.currentUsername} attempted row update on "$dataSourceId" '
            'owned by $rowOwner');
        _lastActionError = 'You do not have permission to modify this record.';
        notifyListeners();
        return;
      }
    }

    try {
      await _dataStore.update(ds.tableName, values, matchField, matchValue);
      notifyListeners(); // Trigger list rebuild to reflect the change.
    } catch (e) {
      logError('AppEngine', 'Row action error', e);
    }
  }

  /// Executes a delete row action, removing the matched record from storage.
  ///
  /// When ownership is enabled on the data source and the user is not an admin,
  /// the row's owner field must match the current user ID.
  Future<void> executeDeleteRowAction({
    required String dataSourceId,
    required String matchField,
    required String matchValue,
    Map<String, dynamic>? rowData,
  }) async {
    final ds = _app?.dataSources[dataSourceId];
    if (ds == null || !ds.isLocal) return;

    // Ownership check: verify current user owns this row before allowing delete.
    if (isMultiUser && ds.ownership.enabled && !_authService.isAdmin) {
      final currentUserId = _authService.currentUserId?.toString();
      final rowOwner = rowData?[ds.ownership.ownerField]?.toString();
      if (currentUserId == null || rowOwner != currentUserId) {
        logWarn('AppEngine', '[SECURITY] permission_denied: '
            'user ${_authService.currentUsername} attempted row delete on "$dataSourceId" '
            'owned by $rowOwner');
        _lastActionError = 'You do not have permission to delete this record.';
        notifyListeners();
        return;
      }
    }

    try {
      await _dataStore.delete(ds.tableName, matchField, matchValue);
      notifyListeners(); // Trigger list rebuild to reflect the deletion.
    } catch (e) {
      logError('AppEngine', 'Delete row action error', e);
    }
  }

  /// Renames a value across a parent record and all linked child records.
  /// Used when a parent's name field is used as a foreign key in children.
  Future<void> cascadeRename({
    required String parentDataSourceId,
    required String parentMatchField,
    required String oldValue,
    required String newValue,
    required String childDataSourceId,
    required String childLinkField,
  }) async {
    final parentDs = _app?.dataSources[parentDataSourceId];
    final childDs = _app?.dataSources[childDataSourceId];
    if (parentDs == null || childDs == null) return;
    if (oldValue == newValue) return;

    // NOTE: Ideally this entire cascade rename should run inside a single
    // database transaction to ensure atomicity. The DataStore currently does
    // not expose a transaction API, so a failure mid-rename could leave data
    // in an inconsistent state. TODO: Add transaction support to DataStore.
    try {
      // Update parent.
      await _dataStore.update(
        parentDs.tableName,
        {parentMatchField: newValue},
        parentMatchField,
        oldValue,
      );
      // Update all children.
      final children = await _dataStore.query(childDs.tableName);
      for (final child in children) {
        if (child[childLinkField]?.toString() == oldValue) {
          final id = child['_id']?.toString() ?? '';
          await _dataStore.update(
            childDs.tableName,
            {childLinkField: newValue},
            '_id',
            id,
          );
        }
      }
      notifyListeners();
    } catch (e) {
      logError('AppEngine', 'Cascade rename error', e);
    }
  }

  /// Checks if all items in a group are complete, and if so, updates the parent.
  Future<void> checkAutoComplete({
    required String listDataSourceId,
    required String toggleField,
    required String groupField,
    required String groupValue,
    required String parentDataSourceId,
    required String parentMatchField,
    required Map<String, String> parentValues,
  }) async {
    final listDs = _app?.dataSources[listDataSourceId];
    final parentDs = _app?.dataSources[parentDataSourceId];
    if (listDs == null || parentDs == null) return;

    try {
      final allRows = await _dataStore.query(listDs.tableName);
      final groupRows = allRows
          .where((r) => r[groupField]?.toString() == groupValue)
          .toList();

      if (groupRows.isEmpty) return;

      final allDone = groupRows.every((r) => r[toggleField]?.toString() == 'true');
      if (allDone) {
        await _dataStore.update(
          parentDs.tableName,
          parentValues,
          parentMatchField,
          groupValue,
        );
        _lastMessage = 'All items complete — list marked as done!';
        notifyListeners();
      }
    } catch (e) {
      logError('AppEngine', 'AutoComplete error', e);
    }
  }

  /// Executes a copyRows row action: copies the parent row and all linked
  /// child rows, resetting specified fields on the copies.
  Future<void> executeCopyRowsAction({
    required Map<String, dynamic> row,
    required String sourceDataSourceId,
    required String targetDataSourceId,
    required String parentDataSourceId,
    required String linkField,
    required String nameField,
    required Map<String, String> resetValues,
  }) async {
    final sourceDsConfig = _app?.dataSources[sourceDataSourceId];
    final targetDsConfig = _app?.dataSources[targetDataSourceId];
    final parentDsConfig = _app?.dataSources[parentDataSourceId];
    if (sourceDsConfig == null || targetDsConfig == null || parentDsConfig == null) return;

    try {
      // 1. Generate a copy name from the parent row.
      final originalName = row[nameField]?.toString() ?? 'Untitled';
      final copyName = '$originalName (copy)';

      // 2. Create the parent copy: duplicate key fields, override values.
      final parentRow = Map<String, dynamic>.from(row);
      parentRow.remove('_id'); // Don't copy the primary key.
      parentRow[nameField] = copyName;
      // Apply any reset values to the parent (e.g., status → Active).
      for (final entry in resetValues.entries) {
        if (parentRow.containsKey(entry.key)) {
          parentRow[entry.key] = entry.value;
        }
      }
      // Auto-set date fields to now.
      for (final key in parentRow.keys.toList()) {
        if (key.toLowerCase().contains('date') && parentRow[key] != null) {
          parentRow[key] = DateTime.now().toIso8601String().split('T').first;
        }
      }
      await _dataStore.insert(parentDsConfig.tableName, parentRow);

      // 3. Query children linked to the original parent.
      final originalLinkValue = row[nameField]?.toString() ?? '';
      final children = await _dataStore.query(sourceDsConfig.tableName);
      final matchingChildren = children
          .where((child) => child[linkField]?.toString() == originalLinkValue)
          .toList();

      // 4. Copy each child with the new link value and reset fields.
      for (final child in matchingChildren) {
        final childCopy = Map<String, dynamic>.from(child);
        childCopy.remove('_id');
        childCopy[linkField] = copyName;
        for (final entry in resetValues.entries) {
          childCopy[entry.key] = entry.value;
        }
        await _dataStore.insert(targetDsConfig.tableName, childCopy);
      }

      _lastMessage = 'Copied "$originalName" → "$copyName" with ${matchingChildren.length} items';
      notifyListeners();
    } catch (e) {
      logError('AppEngine', 'CopyRows error', e);
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
    logInfo('AppEngine', '[SECURITY] backup_restore: initiated by ${_authService.currentUsername}');
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
      // Apply ownership filtering when enabled.
      if (isMultiUser && ds.ownership.enabled) {
        return await _dataStore.queryWithOwnership(
          ds.tableName,
          ownerField: ds.ownership.ownerField,
          ownerId: _authService.currentUserId?.toString(),
          isAdmin: _authService.isAdmin,
          adminOverride: ds.ownership.adminOverride,
        );
      }
      return await _dataStore.query(ds.tableName);
    } catch (e) {
      logError('AppEngine', 'queryDataSource failed for "$dataSourceId": $e');
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
    _authService.reset();
    _app = null;
    _currentPageId = null;
    _navigationStack.clear();
    _formStates.clear();
    _recordCursors.clear();
    _appSettings.clear();
    _validation = null;
    _loadError = null;
    skipAppAuth = false;
    frameworkRoles = const [];
    frameworkUsername = '';
    frameworkEmail = '';
    frameworkDisplayName = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _dataStore.close();
    super.dispose();
  }
}

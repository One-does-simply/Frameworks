import '../models/ods_action.dart';
import '../models/ods_app.dart';
import '../models/ods_component.dart';
import '../models/ods_field_definition.dart';
import 'data_store.dart';
import 'expression_evaluator.dart';
import 'log_service.dart';

/// Executes ODS actions (navigate, submit, update) on behalf of the [AppEngine].
///
/// ODS Spec alignment: Implements the action types defined in the spec:
///   - "navigate" → returns a page ID for the engine to navigate to.
///   - "submit" → collects form data, ensures the table exists, inserts a row.
///   - "update" → collects form data, finds a matching row by key field, updates it.
///
/// Record cursor actions (firstRecord, nextRecord, etc.) are handled directly
/// by the [AppEngine] since they manage UI state (form cursors).
///
/// ODS Ethos: This is where "the form is the schema" comes to life. On submit,
/// the handler looks up the form's field definitions and uses them to
/// auto-create the database table if it doesn't exist yet. The citizen
/// developer never needs to think about database design.
class ActionHandler {
  final DataStore dataStore;

  ActionHandler({required this.dataStore});

  /// Executes a single action and returns the result.
  ///
  /// [ownerId] is the current user's ID string (null in single-user mode).
  /// When non-null and the target dataSource has ownership enabled, the owner
  /// field is auto-injected on submit.
  Future<ActionResult> execute({
    required OdsAction action,
    required OdsApp app,
    required Map<String, Map<String, String>> formStates,
    String? ownerId,
  }) async {
    switch (action.action) {
      case 'navigate':
        return ActionResult(
          navigateTo: action.target,
          populateForm: action.populateForm,
          populateData: action.withData,
        );

      case 'submit':
        return await _handleSubmit(action, app, formStates, ownerId: ownerId);

      case 'update':
        return await _handleUpdate(action, app, formStates);

      case 'delete':
        return await _handleDelete(action, app);

      case 'showMessage':
        return ActionResult(message: action.message ?? '');

      default:
        // Graceful degradation: unknown action types are logged, not crashed.
        logWarn('ActionHandler', 'Unknown action type "${action.action}"');
        return const ActionResult();
    }
  }

  /// Handles the "submit" action: validates required fields, ensures the
  /// table exists, and inserts the form data as a new row.
  Future<ActionResult> _handleSubmit(
    OdsAction action,
    OdsApp app,
    Map<String, Map<String, String>> formStates, {
    String? ownerId,
  }) async {
    final formId = action.target;
    final dataSourceId = action.dataSource;

    if (formId == null || dataSourceId == null) {
      return const ActionResult(error: 'Submit action missing target or dataSource');
    }

    final formData = formStates[formId];
    if (formData == null || formData.isEmpty) {
      return const ActionResult(error: 'No form data found');
    }

    // Validate required fields and validation rules before persisting.
    final formFields = _findFormFields(formId, app);
    final errors = _validateFields(formFields, formData);
    if (errors.isNotEmpty) {
      return ActionResult(error: _formatErrors(errors));
    }

    final ds = app.dataSources[dataSourceId];
    if (ds == null) {
      return const ActionResult(error: 'Unknown dataSource');
    }

    if (!ds.isLocal) {
      return const ActionResult(error: 'External dataSources not supported in local mode');
    }

    // Strip computed, hidden, and framework-injected fields — they are not stored.
    final excludeNames = _fieldsToExclude(formFields, formData);
    final storedFields = formFields
        .where((f) => !f.isComputed && !excludeNames.contains(f.name))
        .toList();
    final declaredNames = formFields.map((f) => f.name).toSet();
    final storedData = Map<String, dynamic>.from(formData)
      ..removeWhere((key, _) =>
          excludeNames.contains(key) || !declaredNames.contains(key));

    // Evaluate computed fields and merge into stored data.
    _applyComputedFields(action.computedFields, storedData, storedFields);

    // "Form is the schema": use the field definitions to create or update the table.
    if (storedFields.isNotEmpty) {
      await dataStore.ensureTable(ds.tableName, storedFields);
    }

    // Auto-inject ownership field when row-level security is enabled.
    if (ds.ownership.enabled && ownerId != null) {
      storedData[ds.ownership.ownerField] = ownerId;
    }

    final insertedId = await dataStore.insert(ds.tableName, storedData);
    return ActionResult(submitted: true, insertedId: insertedId);
  }

  /// Handles the "update" action: validates required fields, finds the
  /// matching row by [matchField], and updates it with the form data.
  Future<ActionResult> _handleUpdate(
    OdsAction action,
    OdsApp app,
    Map<String, Map<String, String>> formStates,
  ) async {
    // Direct update via withData (e.g., kanban drag-drop) — no form needed.
    if (action.withData != null &&
        action.dataSource != null &&
        action.matchField != null &&
        action.target != null) {
      final ds = app.dataSources[action.dataSource];
      if (ds == null) {
        return const ActionResult(error: 'Unknown dataSource');
      }
      if (!ds.isLocal) {
        return const ActionResult(error: 'External dataSources not supported in local mode');
      }
      // Strip framework-managed and match fields so a crafted spec can't rewrite them.
      final safeData = Map<String, dynamic>.from(action.withData!);
      safeData.remove(action.matchField);
      safeData.remove('_id');
      safeData.remove('_createdAt');

      // For cascade: read the current (old) value of the parent field BEFORE
      // applying the update. The parent field is the sole key of withData
      // (after stripping match/framework keys). If there are multiple keys,
      // fall back to the matchField.
      String? cascadeParentField;
      String? cascadeOldValue;
      if (action.cascade != null && action.cascade!.isNotEmpty) {
        cascadeParentField = safeData.length == 1
            ? safeData.keys.first
            : action.matchField;
        if (cascadeParentField != null) {
          try {
            final existingRows = await dataStore.queryWithFilter(
              ds.tableName,
              {action.matchField!: action.target!},
            );
            if (existingRows.isNotEmpty) {
              cascadeOldValue =
                  existingRows.first[cascadeParentField]?.toString();
            }
          } catch (e) {
            logDebug('ActionHandler',
                'Cascade old-value lookup failed: $e');
          }
        }
      }

      final rowsAffected = await dataStore.update(
        ds.tableName,
        safeData,
        action.matchField!,
        action.target!,
      );
      if (rowsAffected == 0) {
        logDebug('ActionHandler', 'withData update found no match: ${action.matchField} = "${action.target}"');
        return const ActionResult(error: 'Record not found');
      }
      return ActionResult(
        submitted: true,
        cascade: action.cascade,
        cascadeMatchField: cascadeParentField,
        cascadeOldValue: cascadeOldValue,
      );
    }

    final formId = action.target;
    final dataSourceId = action.dataSource;
    final matchField = action.matchField;

    if (formId == null || dataSourceId == null || matchField == null) {
      return const ActionResult(error: 'Update action missing target, dataSource, or matchField');
    }

    final formData = formStates[formId];
    if (formData == null || formData.isEmpty) {
      return const ActionResult(error: 'No form data found');
    }

    final matchValue = formData[matchField]?.trim() ?? '';
    if (matchValue.isEmpty) {
      return ActionResult(error: 'Match field "$matchField" is empty');
    }

    // Validate required fields and validation rules before persisting.
    final formFields = _findFormFields(formId, app);
    final errors = _validateFields(formFields, formData);
    if (errors.isNotEmpty) {
      return ActionResult(error: _formatErrors(errors));
    }

    final ds = app.dataSources[dataSourceId];
    if (ds == null) {
      return const ActionResult(error: 'Unknown dataSource');
    }

    if (!ds.isLocal) {
      return const ActionResult(error: 'External dataSources not supported in local mode');
    }

    // Strip computed, hidden, and framework-injected fields — they are not stored.
    final excludeNames = _fieldsToExclude(formFields, formData);
    final storedFields = formFields
        .where((f) => !f.isComputed && !excludeNames.contains(f.name))
        .toList();
    final declaredNames = formFields.map((f) => f.name).toSet();
    final storedData = Map<String, dynamic>.from(formData)
      ..removeWhere((key, _) =>
          excludeNames.contains(key) || !declaredNames.contains(key));

    // Evaluate computed fields and merge into stored data.
    _applyComputedFields(action.computedFields, storedData, storedFields);

    // Ensure table schema is up to date.
    if (storedFields.isNotEmpty) {
      await dataStore.ensureTable(ds.tableName, storedFields);
    }

    // For cascade: capture the current (old) parent field value from the row
    // BEFORE applying the update, so cascade can find/rewrite children even
    // when the rename is form-driven (e.g., form state holds the new value).
    String? cascadeOldValueFromRow;
    if (action.cascade != null && action.cascade!.isNotEmpty) {
      try {
        final existingRows = await dataStore.queryWithFilter(
          ds.tableName,
          {matchField: matchValue},
        );
        if (existingRows.isNotEmpty) {
          cascadeOldValueFromRow =
              existingRows.first[matchField]?.toString();
        }
      } catch (e) {
        logDebug('ActionHandler',
            'Cascade old-value lookup failed: $e');
      }
    }

    final rowsAffected = await dataStore.update(
      ds.tableName,
      storedData,
      matchField,
      matchValue,
    );

    if (rowsAffected == 0) {
      logDebug('ActionHandler', 'Update found no match: $matchField = "$matchValue"');
      return const ActionResult(error: 'Record not found');
    }

    return ActionResult(
      submitted: true,
      cascade: action.cascade,
      cascadeMatchField: matchField,
      cascadeOldValue: cascadeOldValueFromRow ?? matchValue,
    );
  }

  /// Handles the "delete" action: removes a row matched by [matchField].
  ///
  /// Spec-driven delete (distinct from [AppEngine.executeDeleteRowAction],
  /// which is the list-row UX helper). Requires [action.dataSource],
  /// [action.matchField], and [action.target]. Follows the same error
  /// handling pattern as `_handleUpdate`'s withData branch.
  Future<ActionResult> _handleDelete(OdsAction action, OdsApp app) async {
    if (action.dataSource == null ||
        action.matchField == null ||
        action.target == null) {
      return const ActionResult(
        error: 'Delete action missing dataSource, matchField, or target',
      );
    }

    final ds = app.dataSources[action.dataSource];
    if (ds == null) {
      return const ActionResult(error: 'Unknown dataSource');
    }
    if (!ds.isLocal) {
      return const ActionResult(
        error: 'External dataSources not supported in local mode',
      );
    }

    final rowsAffected = await dataStore.delete(
      ds.tableName,
      action.matchField!,
      action.target!,
    );
    if (rowsAffected == 0) {
      logDebug('ActionHandler',
          'Delete found no match: ${action.matchField} = "${action.target}"');
      return const ActionResult(error: 'Record not found');
    }
    return const ActionResult(submitted: true);
  }

  /// Evaluates computed fields from an action and merges them into the data
  /// map. Also adds field definitions for computed columns so the table schema
  /// includes them.
  void _applyComputedFields(
    List<OdsComputedField> computedFields,
    Map<String, dynamic> data,
    List<OdsFieldDefinition> fields,
  ) {
    if (computedFields.isEmpty) return;

    final formValues = data.map((k, v) => MapEntry(k, v.toString()));
    final existingFieldNames = fields.map((f) => f.name).toSet();

    for (final cf in computedFields) {
      final value = ExpressionEvaluator.evaluate(cf.expression, formValues);
      data[cf.field] = value;
      // Ensure the computed column exists in the schema.
      if (!existingFieldNames.contains(cf.field)) {
        fields.add(OdsFieldDefinition(name: cf.field, type: 'text'));
        existingFieldNames.add(cf.field);
      }
    }
  }

  /// Checks whether a field is currently hidden by a visibleWhen condition.
  bool _isFieldHidden(OdsFieldDefinition field, Map<String, String> formData) {
    final condition = field.visibleWhen;
    if (condition == null) return false;
    final watchedValue = formData[condition.field] ?? '';
    return watchedValue != condition.equals;
  }

  /// Returns the set of field names that should be excluded from storage
  /// (computed fields + conditionally hidden fields).
  Set<String> _fieldsToExclude(
    List<OdsFieldDefinition> fields,
    Map<String, String> formData,
  ) {
    final exclude = <String>{};
    for (final field in fields) {
      if (field.isComputed) exclude.add(field.name);
      if (_isFieldHidden(field, formData)) exclude.add(field.name);
    }
    return exclude;
  }

  /// Validates all visible, non-computed fields. Returns a list of error strings.
  List<String> _validateFields(
    List<OdsFieldDefinition> fields,
    Map<String, String> formData,
  ) {
    final errors = <String>[];
    for (final field in fields) {
      if (field.isComputed) continue;
      if (field.readOnly) continue;
      if (_isFieldHidden(field, formData)) continue;

      final value = formData[field.name]?.trim() ?? '';

      // Check required.
      if (field.required && value.isEmpty) {
        errors.add('Required: ${field.label ?? field.name}');
        continue;
      }

      // Type-level checks that apply even without an explicit `validation`
      // block. `required` is handled above; empty values skip type checks.
      if (value.isNotEmpty) {
        // Gap G1: number fields must be parseable as a double.
        if (field.type == 'number' && double.tryParse(value) == null) {
          errors.add('${field.label ?? field.name}: Must be a number');
          continue;
        }

        // Bug #11: select fields with an explicit static options list must
        // receive a value that appears in that list (enum enforcement).
        if (field.type == 'select' &&
            field.options != null &&
            field.options!.isNotEmpty &&
            !field.options!.contains(value)) {
          errors.add(
            '${field.label ?? field.name}: '
            'Value must be one of: ${field.options!.join(', ')}',
          );
          continue;
        }
      }

      // Check validation rules.
      if (field.validation != null && value.isNotEmpty) {
        final error = field.validation!.validate(value, field.type);
        if (error != null) {
          errors.add('${field.label ?? field.name}: $error');
        }
      } else if (field.type == 'email' && value.isNotEmpty) {
        // Always validate email format even without an explicit validation block.
        const emailValidation = OdsValidation();
        final error = emailValidation.validate(value, 'email');
        if (error != null) {
          errors.add('${field.label ?? field.name}: $error');
        }
      }
    }
    return errors;
  }

  /// Formats a list of validation errors into a user-friendly string.
  ///
  /// Caps at 5 errors to keep SnackBar messages readable. If there are more,
  /// appends a count of the remaining errors.
  String _formatErrors(List<String> errors) {
    if (errors.length <= 5) return errors.join(', ');
    final shown = errors.take(5).join(', ');
    return '$shown, and ${errors.length - 5} more';
  }

  /// Searches all pages for a form component with the given ID and returns
  /// its field definitions. Used to auto-create table schemas.
  List<OdsFieldDefinition> _findFormFields(String formId, OdsApp app) {
    for (final page in app.pages.values) {
      for (final component in page.content) {
        if (component is OdsFormComponent && component.id == formId) {
          return component.fields;
        }
      }
    }
    return [];
  }
}

/// The outcome of executing a single action.
class ActionResult {
  /// Page ID to navigate to (from a "navigate" action).
  final String? navigateTo;

  /// Whether a "submit" action completed successfully.
  final bool submitted;

  /// Human-readable error message if the action failed.
  final String? error;

  /// Informational message to display as a snackbar (from "showMessage" action).
  final String? message;

  /// Form ID to populate after navigation.
  final String? populateForm;

  /// Data to populate in the form (values may contain {formField} references).
  final Map<String, dynamic>? populateData;

  /// Cascade rename config from an update action.
  final Map<String, String>? cascade;

  /// The match field and old value for cascade rename resolution.
  final String? cascadeMatchField;
  final String? cascadeOldValue;

  /// The `_id` of the row inserted by a successful submit. Consumed by the
  /// engine to resolve `{_id}` placeholders in subsequent chained actions
  /// (e.g., `populateData: {id: '{_id}'}`).
  final String? insertedId;

  const ActionResult({
    this.navigateTo,
    this.submitted = false,
    this.error,
    this.message,
    this.populateForm,
    this.populateData,
    this.cascade,
    this.cascadeMatchField,
    this.cascadeOldValue,
    this.insertedId,
  });
}

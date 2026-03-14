import 'package:flutter/foundation.dart';

import '../models/ods_action.dart';
import '../models/ods_app.dart';
import '../models/ods_component.dart';
import '../models/ods_field_definition.dart';
import 'data_store.dart';
import 'expression_evaluator.dart';
import 'formula_evaluator.dart';

/// Executes ODS actions (navigate, submit, update) on behalf of the [AppEngine].
///
/// ODS Spec alignment: Implements the three action types defined in the spec:
///   - "navigate" → returns a page ID for the engine to navigate to.
///   - "submit" → collects form data, ensures the table exists, inserts a row.
///   - "update" → collects form data, finds a matching row by key field, updates it.
///
/// ODS Ethos: This is where "the form is the schema" comes to life. On submit,
/// the handler looks up the form's field definitions and uses them to
/// auto-create the database table if it doesn't exist yet. The citizen
/// developer never needs to think about database design.
///
/// Architecture note: This class is separated from the engine to keep action
/// logic testable in isolation and to support adding new action types
/// without growing the engine class.
class ActionHandler {
  final DataStore dataStore;

  ActionHandler({required this.dataStore});

  /// Executes a single action and returns the result.
  Future<ActionResult> execute({
    required OdsAction action,
    required OdsApp app,
    required Map<String, Map<String, String>> formStates,
  }) async {
    switch (action.action) {
      case 'navigate':
        return ActionResult(navigateTo: action.target);

      case 'submit':
        return await _handleSubmit(action, app, formStates);

      case 'update':
        return await _handleUpdate(action, app, formStates);

      case 'navigateToRow':
        return await _handleNavigateToRow(action, app, formStates);

      default:
        // Graceful degradation: unknown action types are logged, not crashed.
        debugPrint('ODS: Unknown action type "${action.action}"');
        return const ActionResult();
    }
  }

  /// Handles the "submit" action: validates required fields, ensures the
  /// table exists, and inserts the form data as a new row.
  Future<ActionResult> _handleSubmit(
    OdsAction action,
    OdsApp app,
    Map<String, Map<String, String>> formStates,
  ) async {
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
      return ActionResult(error: errors.join(', '));
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

    await dataStore.insert(ds.tableName, storedData);
    return const ActionResult(submitted: true);
  }

  /// Handles the "update" action: validates required fields, finds the
  /// matching row by [matchField], and updates it with the form data.
  Future<ActionResult> _handleUpdate(
    OdsAction action,
    OdsApp app,
    Map<String, Map<String, String>> formStates,
  ) async {
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
      return ActionResult(error: errors.join(', '));
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

    final rowsAffected = await dataStore.update(
      ds.tableName,
      storedData,
      matchField,
      matchValue,
    );

    if (rowsAffected == 0) {
      return ActionResult(error: 'No matching record found for $matchField = "$matchValue"');
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

  /// Handles the "navigateToRow" action: queries a data source with optional
  /// filter, sort, and offset, then navigates to the target page with the
  /// matched row populating a form. If no row matches, executes a fallback.
  Future<ActionResult> _handleNavigateToRow(
    OdsAction action,
    OdsApp app,
    Map<String, Map<String, String>> formStates,
  ) async {
    final dataSourceId = action.dataSource;
    final targetPage = action.target;
    final populateFormId = action.populateForm;

    if (dataSourceId == null || targetPage == null) {
      return const ActionResult(error: 'navigateToRow missing dataSource or target');
    }

    final ds = app.dataSources[dataSourceId];
    if (ds == null || !ds.isLocal) {
      return const ActionResult(error: 'navigateToRow: unknown or non-local dataSource');
    }

    // Build a flat map of all form field values for reference resolution.
    final allValues = <String, String>{};
    for (final formState in formStates.values) {
      allValues.addAll(formState);
    }

    // Resolve {fieldName} references in filter values.
    final resolvedFilter = <String, String>{};
    if (action.filter != null) {
      for (final entry in action.filter!.entries) {
        resolvedFilter[entry.key] = _resolveReferences(entry.value, allValues);
      }
    }

    // Resolve the offset expression.
    int offset = 0;
    if (action.offset != null) {
      offset = _resolveOffset(action.offset!, allValues);
    }

    final sortField = action.sort ?? '_id';
    final sortOrder = action.sortOrder ?? 'asc';

    // Query the data store for the specific row.
    try {
      final row = await dataStore.queryFiltered(
        ds.tableName,
        filter: resolvedFilter.isNotEmpty ? resolvedFilter : null,
        sort: sortField,
        sortOrder: sortOrder,
        offset: offset,
      );

      if (row != null) {
        // Inject _rowIndex so subsequent navigateToRow can compute the next offset.
        final rowData = Map<String, dynamic>.from(row);
        rowData['_rowIndex'] = offset.toString();

        return ActionResult(
          navigateTo: targetPage,
          populateFormId: populateFormId,
          populateData: rowData,
        );
      } else {
        // No matching row — execute fallback if provided.
        if (action.fallback != null) {
          return await execute(
            action: action.fallback!,
            app: app,
            formStates: formStates,
          );
        }
        return const ActionResult();
      }
    } catch (e) {
      debugPrint('ODS navigateToRow error: $e');
      // On error (e.g., table doesn't exist yet), execute fallback.
      if (action.fallback != null) {
        return await execute(
          action: action.fallback!,
          app: app,
          formStates: formStates,
        );
      }
      return ActionResult(error: 'navigateToRow query failed: $e');
    }
  }

  /// Resolves `{fieldName}` references in a string using form field values.
  String _resolveReferences(String input, Map<String, String> values) {
    return input.replaceAllMapped(RegExp(r'\{(\w+)\}'), (match) {
      final fieldName = match.group(1)!;
      return values[fieldName] ?? '';
    });
  }

  /// Resolves an offset expression to an integer.
  ///
  /// Supports literal integers ("0", "5") and simple math expressions
  /// with field references ("{_rowIndex} + 1").
  int _resolveOffset(String offsetExpr, Map<String, String> values) {
    // Try parsing as a plain integer first.
    final plainInt = int.tryParse(offsetExpr.trim());
    if (plainInt != null) return plainInt;

    // Resolve field references and evaluate as math.
    final resolved = _resolveReferences(offsetExpr, values);
    try {
      final result = FormulaEvaluator.evaluate(offsetExpr, 'number', values);
      final parsed = double.tryParse(result);
      if (parsed != null) return parsed.toInt();
    } catch (_) {
      // Fall through.
    }

    // Last resort: try parsing the resolved string as an integer.
    return int.tryParse(resolved.trim()) ?? 0;
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
      if (_isFieldHidden(field, formData)) continue;

      final value = formData[field.name]?.trim() ?? '';

      // Check required.
      if (field.required && value.isEmpty) {
        errors.add('Required: ${field.label ?? field.name}');
        continue;
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
  /// Page ID to navigate to (from a "navigate" or "navigateToRow" action).
  final String? navigateTo;

  /// Whether a "submit" action completed successfully.
  final bool submitted;

  /// Human-readable error message if the action failed.
  final String? error;

  /// For "navigateToRow": the form ID to populate with the matched row data.
  final String? populateFormId;

  /// For "navigateToRow": the row data to populate into the form.
  final Map<String, dynamic>? populateData;

  const ActionResult({
    this.navigateTo,
    this.submitted = false,
    this.error,
    this.populateFormId,
    this.populateData,
  });
}

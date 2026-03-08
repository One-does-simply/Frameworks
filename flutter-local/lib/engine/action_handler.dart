import 'package:flutter/foundation.dart';

import '../models/ods_action.dart';
import '../models/ods_app.dart';
import '../models/ods_component.dart';
import '../models/ods_field_definition.dart';
import 'data_store.dart';

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

    // Validate required fields before persisting.
    // ODS Spec: Fields with `"required": true` must have a non-empty value.
    final formFields = _findFormFields(formId, app);
    final missingFields = <String>[];
    for (final field in formFields) {
      if (field.required) {
        final value = formData[field.name]?.trim() ?? '';
        if (value.isEmpty) {
          missingFields.add(field.label ?? field.name);
        }
      }
    }
    if (missingFields.isNotEmpty) {
      return ActionResult(
        error: 'Required fields missing: ${missingFields.join(", ")}',
      );
    }

    final ds = app.dataSources[dataSourceId];
    if (ds == null) {
      return const ActionResult(error: 'Unknown dataSource');
    }

    if (!ds.isLocal) {
      return const ActionResult(error: 'External dataSources not supported in local mode');
    }

    // "Form is the schema": use the field definitions (already fetched
    // above for required validation) to create or update the table.
    if (formFields.isNotEmpty) {
      await dataStore.ensureTable(ds.tableName, formFields);
    }

    await dataStore.insert(ds.tableName, Map<String, dynamic>.from(formData));
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

    // Validate required fields before persisting.
    final formFields = _findFormFields(formId, app);
    final missingFields = <String>[];
    for (final field in formFields) {
      if (field.required) {
        final value = formData[field.name]?.trim() ?? '';
        if (value.isEmpty) {
          missingFields.add(field.label ?? field.name);
        }
      }
    }
    if (missingFields.isNotEmpty) {
      return ActionResult(
        error: 'Required fields missing: ${missingFields.join(", ")}',
      );
    }

    final ds = app.dataSources[dataSourceId];
    if (ds == null) {
      return const ActionResult(error: 'Unknown dataSource');
    }

    if (!ds.isLocal) {
      return const ActionResult(error: 'External dataSources not supported in local mode');
    }

    // Ensure table schema is up to date.
    if (formFields.isNotEmpty) {
      await dataStore.ensureTable(ds.tableName, formFields);
    }

    final rowsAffected = await dataStore.update(
      ds.tableName,
      Map<String, dynamic>.from(formData),
      matchField,
      matchValue,
    );

    if (rowsAffected == 0) {
      return ActionResult(error: 'No matching record found for $matchField = "$matchValue"');
    }

    return const ActionResult(submitted: true);
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

  const ActionResult({this.navigateTo, this.submitted = false, this.error});
}

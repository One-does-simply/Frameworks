import '../models/ods_app.dart';
import '../models/ods_component.dart';
import '../models/ods_page.dart';

/// A single validation message with a severity level.
class ValidationMessage {
  /// Severity: 'error' blocks loading, 'warning' is informational only.
  final String level;
  final String message;

  /// Optional context string (e.g., "page: feedbackFormPage").
  final String? context;

  const ValidationMessage({
    required this.level,
    required this.message,
    this.context,
  });

  @override
  String toString() => '[$level] $message${context != null ? ' ($context)' : ''}';
}

/// Accumulator for validation messages during spec checking.
///
/// Errors block the app from loading. Warnings are surfaced in the debug
/// panel but do not prevent rendering — consistent with the ODS ethos of
/// best-effort rendering over hard failure.
class ValidationResult {
  final List<ValidationMessage> messages;

  ValidationResult() : messages = [];

  void error(String message, {String? context}) =>
      messages.add(ValidationMessage(level: 'error', message: message, context: context));

  void warning(String message, {String? context}) =>
      messages.add(ValidationMessage(level: 'warning', message: message, context: context));

  void info(String message, {String? context}) =>
      messages.add(ValidationMessage(level: 'info', message: message, context: context));

  bool get hasErrors => messages.any((m) => m.level == 'error');
  List<ValidationMessage> get errors => messages.where((m) => m.level == 'error').toList();
  List<ValidationMessage> get warnings => messages.where((m) => m.level == 'warning').toList();
}

/// Validates an [OdsApp] for structural integrity and cross-reference
/// correctness.
///
/// ODS Spec alignment: Checks the semantic rules that can't be expressed in
/// JSON Schema alone — for example, that startPage references a real page,
/// that menu items map to existing pages, and that button actions reference
/// valid targets.
///
/// ODS Ethos: Validation is helpful, not hostile. Issues that would cause
/// runtime confusion (missing startPage) are errors. Issues that degrade
/// gracefully (a button pointing to a missing page) are warnings. The goal
/// is to guide citizen developers toward correct specs, not punish mistakes.
class SpecValidator {
  ValidationResult validate(OdsApp app) {
    final result = ValidationResult();

    if (app.appName.isEmpty) {
      result.error('appName is empty');
    }

    if (!app.pages.containsKey(app.startPage)) {
      result.error('startPage "${app.startPage}" does not match any defined page');
    }

    if (app.pages.isEmpty) {
      result.error('No pages defined');
    }

    // Validate menu items point to real pages.
    for (final entry in app.menu) {
      if (!app.pages.containsKey(entry.mapsTo)) {
        result.warning('Menu item "${entry.label}" maps to unknown page "${entry.mapsTo}"');
      }
    }

    // Validate each page's component references.
    for (final pageEntry in app.pages.entries) {
      _validatePage(pageEntry.key, pageEntry.value, app, result);
    }

    return result;
  }

  /// Validates all components on a single page.
  void _validatePage(
    String pageId,
    OdsPage page,
    OdsApp app,
    ValidationResult result,
  ) {
    for (final component in page.content) {
      // Check that list components reference defined data sources and valid row actions.
      if (component is OdsListComponent) {
        if (!app.dataSources.containsKey(component.dataSource)) {
          result.warning(
            'List component references unknown dataSource "${component.dataSource}"',
            context: 'page: $pageId',
          );
        }
        for (final rowAction in component.rowActions) {
          if (!app.dataSources.containsKey(rowAction.dataSource)) {
            result.warning(
              'Row action "${rowAction.label}" references unknown dataSource "${rowAction.dataSource}"',
              context: 'page: $pageId',
            );
          }
          if (rowAction.values.isEmpty) {
            result.warning(
              'Row action "${rowAction.label}" has empty values map',
              context: 'page: $pageId',
            );
          }
        }
      }

      // Check that button actions reference valid targets.
      if (component is OdsButtonComponent) {
        for (final action in component.onClick) {
          if (action.isNavigate && action.target != null) {
            if (!app.pages.containsKey(action.target)) {
              result.warning(
                'Navigate action targets unknown page "${action.target}"',
                context: 'page: $pageId, button: "${component.label}"',
              );
            }
          }
          if (action.isSubmit && action.dataSource != null) {
            if (!app.dataSources.containsKey(action.dataSource)) {
              result.warning(
                'Submit action references unknown dataSource "${action.dataSource}"',
                context: 'page: $pageId, button: "${component.label}"',
              );
            }
          }
          if (action.isUpdate) {
            if (action.dataSource != null && !app.dataSources.containsKey(action.dataSource)) {
              result.warning(
                'Update action references unknown dataSource "${action.dataSource}"',
                context: 'page: $pageId, button: "${component.label}"',
              );
            }
            if (action.matchField == null || action.matchField!.isEmpty) {
              result.warning(
                'Update action is missing matchField',
                context: 'page: $pageId, button: "${component.label}"',
              );
            }
          }
        }
      }

      // Validate form field types and required/placeholder usage.
      if (component is OdsFormComponent) {
        for (final field in component.fields) {
          if (!_validFieldTypes.contains(field.type)) {
            result.warning(
              'Field "${field.name}" has unknown type "${field.type}"',
              context: 'page: $pageId, form: "${component.id}"',
            );
          }
          if (field.type == 'select' && (field.options == null || field.options!.isEmpty)) {
            result.warning(
              'Select field "${field.name}" is missing options array',
              context: 'page: $pageId, form: "${component.id}"',
            );
          }
        }
      }

      // Flag unknown component types for debug visibility.
      if (component is OdsUnknownComponent) {
        result.warning(
          'Unknown component type "${component.component}" will be skipped',
          context: 'page: $pageId',
        );
      }
    }
  }

  /// The set of field types defined in the ODS spec.
  static const _validFieldTypes = {'text', 'email', 'number', 'date', 'multiline', 'select', 'checkbox'};
}

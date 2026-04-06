import '../engine/formula_evaluator.dart';
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

    // Validate auth configuration.
    _validateAuth(app, result);

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
        // F3: Warn if rowColorMap is set without rowColorField.
        if (component.rowColorMap != null && component.rowColorField == null) {
          result.warning(
            'List has rowColorMap but no rowColorField — colors will not be applied',
            context: 'page: $pageId',
          );
        }
        // Validate summary rules reference existing columns.
        final columnFields = component.columns.map((c) => c.field).toSet();
        for (final rule in component.summary) {
          if (!columnFields.contains(rule.column)) {
            result.warning(
              'Summary rule references unknown column "${rule.column}"',
              context: 'page: $pageId',
            );
          }
          if (!_validSummaryFunctions.contains(rule.function)) {
            result.warning(
              'Summary rule has unknown function "${rule.function}"',
              context: 'page: $pageId',
            );
          }
        }
        for (final rowAction in component.rowActions) {
          if (!app.dataSources.containsKey(rowAction.dataSource)) {
            result.warning(
              'Row action "${rowAction.label}" references unknown dataSource "${rowAction.dataSource}"',
              context: 'page: $pageId',
            );
          }
          if (rowAction.isUpdate && rowAction.values.isEmpty) {
            result.warning(
              'Row action "${rowAction.label}" has empty values map',
              context: 'page: $pageId',
            );
          }
          if (!rowAction.isUpdate && !rowAction.isDelete) {
            result.warning(
              'Row action "${rowAction.label}" has unknown action type "${rowAction.action}"',
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
          // Validate computed field formulas.
          if (field.isComputed) {
            final deps = FormulaEvaluator.dependencies(field.formula!);
            if (deps.isEmpty) {
              result.warning(
                'Computed field "${field.name}" formula has no field references',
                context: 'page: $pageId, form: "${component.id}"',
              );
            }
            final fieldNames = component.fields.map((f) => f.name).toSet();
            for (final dep in deps) {
              if (!fieldNames.contains(dep)) {
                result.warning(
                  'Computed field "${field.name}" references unknown field "{$dep}"',
                  context: 'page: $pageId, form: "${component.id}"',
                );
              }
            }
            if (field.required) {
              result.warning(
                'Computed field "${field.name}" is marked required but computed fields are read-only',
                context: 'page: $pageId, form: "${component.id}"',
              );
            }
          }
          // Validate visibleWhen references.
          if (field.visibleWhen != null) {
            final fieldNames = component.fields.map((f) => f.name).toSet();
            if (!fieldNames.contains(field.visibleWhen!.field)) {
              result.warning(
                'Field "${field.name}" visibleWhen references unknown field "${field.visibleWhen!.field}"',
                context: 'page: $pageId, form: "${component.id}"',
              );
            }
          }
          // Validate validation rules make sense for the field type.
          if (field.validation != null) {
            final v = field.validation!;
            if ((v.min != null || v.max != null) && field.type != 'number') {
              result.warning(
                'Field "${field.name}" has min/max validation but type is "${field.type}" (not number)',
                context: 'page: $pageId, form: "${component.id}"',
              );
            }
          }
          if (field.type == 'select') {
            final hasStaticOptions = field.options != null && field.options!.isNotEmpty;
            final hasDynamicOptions = field.optionsFrom != null;
            if (!hasStaticOptions && !hasDynamicOptions) {
              result.warning(
                'Select field "${field.name}" is missing both options array and optionsFrom',
                context: 'page: $pageId, form: "${component.id}"',
              );
            }
            if (hasDynamicOptions && !app.dataSources.containsKey(field.optionsFrom!.dataSource)) {
              result.warning(
                'Select field "${field.name}" optionsFrom references unknown dataSource "${field.optionsFrom!.dataSource}"',
                context: 'page: $pageId, form: "${component.id}"',
              );
            }
          }
        }
      }

      // Validate chart components reference valid data sources.
      if (component is OdsChartComponent) {
        if (!app.dataSources.containsKey(component.dataSource)) {
          result.warning(
            'Chart component references unknown dataSource "${component.dataSource}"',
            context: 'page: $pageId',
          );
        }
        if (!{'bar', 'line', 'pie'}.contains(component.chartType)) {
          result.warning(
            'Chart component has unknown chartType "${component.chartType}"',
            context: 'page: $pageId',
          );
        }
      }

      // F4: Validate summary component data source references.
      if (component is OdsSummaryComponent) {
        // Summary components don't directly reference a data source in their
        // model, but their value expressions may use aggregates that do.
        // No additional validation needed beyond expression syntax.
      }

      // F6: Validate tabs component — each tab must have content.
      if (component is OdsTabsComponent) {
        if (component.tabs.isEmpty) {
          result.warning(
            'Tabs component has no tabs defined',
            context: 'page: $pageId',
          );
        }
        for (var i = 0; i < component.tabs.length; i++) {
          final tab = component.tabs[i];
          if (tab.content.isEmpty) {
            result.warning(
              'Tab "${tab.label}" has no content',
              context: 'page: $pageId',
            );
          }
          // Recursively validate nested components in each tab.
          for (final nested in tab.content) {
            if (nested is OdsListComponent && !app.dataSources.containsKey(nested.dataSource)) {
              result.warning(
                'List in tab "${tab.label}" references unknown dataSource "${nested.dataSource}"',
                context: 'page: $pageId',
              );
            }
          }
        }
      }

      // Validate kanban component data source and row actions.
      if (component is OdsKanbanComponent) {
        if (!app.dataSources.containsKey(component.dataSource)) {
          result.warning(
            'Kanban component references unknown dataSource "${component.dataSource}"',
            context: 'page: $pageId',
          );
        }
        for (final rowAction in component.rowActions) {
          if (!app.dataSources.containsKey(rowAction.dataSource)) {
            result.warning(
              'Kanban row action "${rowAction.label}" references unknown dataSource "${rowAction.dataSource}"',
              context: 'page: $pageId',
            );
          }
          if (rowAction.isUpdate && rowAction.values.isEmpty) {
            result.warning(
              'Kanban row action "${rowAction.label}" has empty values map',
              context: 'page: $pageId',
            );
          }
          if (!rowAction.isUpdate && !rowAction.isDelete) {
            result.warning(
              'Kanban row action "${rowAction.label}" has unknown action type "${rowAction.action}"',
              context: 'page: $pageId',
            );
          }
        }
      }

      // F9: Validate detail component data source references.
      if (component is OdsDetailComponent) {
        if (!app.dataSources.containsKey(component.dataSource)) {
          result.warning(
            'Detail component references unknown dataSource "${component.dataSource}"',
            context: 'page: $pageId',
          );
        }
      }

      // F8: Validate dependent dropdown filter references.
      if (component is OdsFormComponent) {
        for (final field in component.fields) {
          if (field.optionsFrom?.filter != null) {
            final filter = field.optionsFrom!.filter!;
            final fieldNames = component.fields.map((f) => f.name).toSet();
            if (!fieldNames.contains(filter.fromField)) {
              result.warning(
                'Field "${field.name}" optionsFrom.filter.fromField references unknown sibling field "${filter.fromField}"',
                context: 'page: $pageId, form: "${component.id}"',
              );
            }
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

  /// Validates auth configuration and role references.
  void _validateAuth(OdsApp app, ValidationResult result) {
    final auth = app.auth;
    final builtInRoles = {'guest', 'user', 'admin'};
    final allRoles = {...builtInRoles, ...auth.customRoles};

    // Warn if multiUserOnly without multiUser.
    if (auth.multiUserOnly && !auth.multiUser) {
      result.warning('auth.multiUserOnly is true but auth.multiUser is false');
    }

    // Warn about self-registration — not supported in Flutter Local.
    if (auth.selfRegistration) {
      result.warning(
        'auth.selfRegistration is enabled but self-registration is not supported '
        'in the Flutter Local framework (local/desktop apps have no public '
        'network for user sign-up). Users must be created by an admin. '
        'This feature is supported in the React Web framework.',
      );
    }

    // Warn if custom roles duplicate built-in names.
    for (final role in auth.customRoles) {
      if (builtInRoles.contains(role)) {
        result.warning('auth.roles contains built-in role "$role" — it is always present implicitly');
      }
    }

    // Warn if defaultRole is not in allRoles.
    if (!allRoles.contains(auth.defaultRole)) {
      result.warning('auth.defaultRole "${auth.defaultRole}" is not a recognized role');
    }

    // Check role references across the spec (only warn, don't error).
    void checkRoles(List<String>? roles, String context) {
      if (roles == null) return;
      for (final role in roles) {
        if (!allRoles.contains(role)) {
          result.warning('Role "$role" is not defined in auth.roles or built-in defaults', context: context);
        }
      }
    }

    // Menu items.
    for (final item in app.menu) {
      checkRoles(item.roles, 'menu: ${item.label}');
    }

    // Pages and their components.
    for (final entry in app.pages.entries) {
      checkRoles(entry.value.roles, 'page: ${entry.key}');
      for (final component in entry.value.content) {
        checkRoles(component.roles, 'page: ${entry.key}');
        if (component is OdsListComponent) {
          for (final col in component.columns) {
            checkRoles(col.roles, 'page: ${entry.key}, column: ${col.field}');
          }
          for (final action in component.rowActions) {
            checkRoles(action.roles, 'page: ${entry.key}, rowAction: ${action.label}');
          }
        }
        if (component is OdsKanbanComponent) {
          for (final action in component.rowActions) {
            checkRoles(action.roles, 'page: ${entry.key}, rowAction: ${action.label}');
          }
        }
        if (component is OdsFormComponent) {
          for (final field in component.fields) {
            checkRoles(field.roles, 'page: ${entry.key}, field: ${field.name}');
          }
        }
      }
    }

    // DataSources: warn if ownership without multiUser.
    for (final entry in app.dataSources.entries) {
      if (entry.value.ownership.enabled && !auth.multiUser) {
        result.warning(
          'DataSource "${entry.key}" has ownership enabled but auth.multiUser is false',
          context: 'dataSource: ${entry.key}',
        );
      }
    }
  }

  /// The set of field types defined in the ODS spec.
  static const _validFieldTypes = {'text', 'email', 'number', 'date', 'datetime', 'multiline', 'select', 'checkbox', 'hidden'};
  static const _validSummaryFunctions = {'sum', 'avg', 'count', 'min', 'max'};
}

import 'ods_action.dart';
import 'ods_field_definition.dart';
import 'ods_style_hint.dart';
import 'ods_visible_when.dart';

/// Base class for all ODS components, using Dart 3 sealed classes.
///
/// ODS Spec alignment: The spec defines four component types — text, list,
/// form, and button. Using a sealed class lets the renderer use exhaustive
/// switch expressions (see PageRenderer), guaranteeing every component type
/// is handled at compile time.
///
/// ODS Ethos: Four components is all you need. Text for content, List for
/// data display, Form for data entry, Button for actions. This constraint
/// is intentional — it forces simplicity and makes every ODS app instantly
/// understandable.
sealed class OdsComponent {
  /// The component type string from the spec (e.g., "text", "list").
  final String component;

  /// Optional styling hints interpreted by the renderer.
  final OdsStyleHint styleHint;

  /// Optional visibility condition. When set, the component is only shown
  /// if the condition is met (form field value or data source row count).
  final OdsComponentVisibleWhen? visibleWhen;

  const OdsComponent({required this.component, required this.styleHint, this.visibleWhen});

  /// Factory that dispatches to the correct subclass based on the
  /// `component` field. Unknown types become [OdsUnknownComponent],
  /// which are silently skipped in normal mode and shown in debug mode.
  factory OdsComponent.fromJson(Map<String, dynamic> json) {
    final type = json['component'] as String;
    switch (type) {
      case 'text':
        return OdsTextComponent.fromJson(json);
      case 'list':
        return OdsListComponent.fromJson(json);
      case 'form':
        return OdsFormComponent.fromJson(json);
      case 'button':
        return OdsButtonComponent.fromJson(json);
      case 'chart':
        return OdsChartComponent.fromJson(json);
      default:
        // Graceful degradation: unknown components are captured, not rejected.
        // This keeps forward compatibility — a spec with future component types
        // will still load in older framework versions.
        return OdsUnknownComponent.fromJson(json);
    }
  }
}

/// Displays static or dynamic text content on a page.
///
/// ODS Spec: `textComponent` — requires `content` string, optional `styleHint`
/// with a `variant` key (heading, subheading, body, caption).
class OdsTextComponent extends OdsComponent {
  final String content;

  const OdsTextComponent({
    required this.content,
    required super.styleHint,
    super.visibleWhen,
  }) : super(component: 'text');

  factory OdsTextComponent.fromJson(Map<String, dynamic> json) {
    return OdsTextComponent(
      content: json['content'] as String,
      styleHint: OdsStyleHint.fromJson(json['styleHint'] as Map<String, dynamic>?),
      visibleWhen: json['visibleWhen'] != null
          ? OdsComponentVisibleWhen.fromJson(json['visibleWhen'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Defines a column mapping for list components: a display header and the
/// data field name to read from each row.
class OdsListColumn {
  final String header;
  final String field;

  /// When true, the column header is tappable to sort the list by this field.
  final bool sortable;

  /// When true, a filter dropdown is shown above the list for this column.
  final bool filterable;

  const OdsListColumn({
    required this.header,
    required this.field,
    this.sortable = false,
    this.filterable = false,
  });

  factory OdsListColumn.fromJson(Map<String, dynamic> json) {
    return OdsListColumn(
      header: json['header'] as String,
      field: json['field'] as String,
      sortable: json['sortable'] as bool? ?? false,
      filterable: json['filterable'] as bool? ?? false,
    );
  }
}

/// Defines an inline action button rendered in each row of a list.
///
/// ODS Spec: Row actions let the builder add per-row buttons (e.g., "Mark Done",
/// "Delete") that operate on a record directly using the row's own data — no
/// separate form page needed. Supported action types:
///   - "update": sets new values on the matched row (requires `values` map)
///   - "delete": removes the matched row entirely (no `values` needed)
/// The `matchField` identifies which row to target.
class OdsRowAction {
  final String label;
  final String action;
  final String dataSource;
  final String matchField;

  /// The values to set on the matched row. Required for "update" actions,
  /// optional (and ignored) for "delete" actions.
  final Map<String, String> values;

  /// Optional confirmation text. When set, a dialog is shown before executing.
  /// For delete actions, overrides the default "Are you sure?" message.
  final String? confirm;

  const OdsRowAction({
    required this.label,
    required this.action,
    required this.dataSource,
    required this.matchField,
    this.values = const {},
    this.confirm,
  });

  bool get isDelete => action == 'delete';
  bool get isUpdate => action == 'update';

  factory OdsRowAction.fromJson(Map<String, dynamic> json) {
    return OdsRowAction(
      label: json['label'] as String,
      action: json['action'] as String,
      dataSource: json['dataSource'] as String,
      matchField: json['matchField'] as String,
      values: (json['values'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString())) ??
          const {},
      confirm: json['confirm'] as String?,
    );
  }
}

/// Defines a summary/aggregation rule for a list column.
///
/// ODS Spec: Summary rules specify a column and an aggregation function
/// (sum, avg, count, min, max). The framework computes the aggregate
/// and renders it as a summary row below the data table.
class OdsSummaryRule {
  final String column;
  final String function;
  final String? label;

  const OdsSummaryRule({
    required this.column,
    required this.function,
    this.label,
  });

  factory OdsSummaryRule.fromJson(Map<String, dynamic> json) {
    return OdsSummaryRule(
      column: json['column'] as String,
      function: json['function'] as String,
      label: json['label'] as String?,
    );
  }
}

/// Displays tabular data from a data source.
///
/// ODS Spec: `listComponent` — requires a `dataSource` ID and `columns` array.
/// Optionally includes `rowActions` for inline per-row action buttons,
/// `summary` for aggregation rows, and `filterable` columns for dropdown filters.
/// The framework queries the referenced data source and renders a DataTable.
/// Describes what happens when a list row is tapped.
class OdsRowTap {
  /// The page to navigate to.
  final String target;

  /// Optional form ID to pre-fill with the tapped row's data.
  final String? populateForm;

  const OdsRowTap({required this.target, this.populateForm});

  factory OdsRowTap.fromJson(Map<String, dynamic> json) {
    return OdsRowTap(
      target: json['target'] as String,
      populateForm: json['populateForm'] as String?,
    );
  }
}

class OdsListComponent extends OdsComponent {
  /// The ID of the data source to read rows from.
  final String dataSource;

  /// Column definitions mapping data fields to display headers.
  final List<OdsListColumn> columns;

  /// Optional action buttons rendered in each row.
  final List<OdsRowAction> rowActions;

  /// Optional summary/aggregation rules displayed below the data table.
  final List<OdsSummaryRule> summary;

  /// Optional row-tap handler — navigates to a page and optionally pre-fills a form.
  final OdsRowTap? onRowTap;

  const OdsListComponent({
    required this.dataSource,
    required this.columns,
    this.rowActions = const [],
    this.summary = const [],
    this.onRowTap,
    required super.styleHint,
    super.visibleWhen,
  }) : super(component: 'list');

  factory OdsListComponent.fromJson(Map<String, dynamic> json) {
    return OdsListComponent(
      dataSource: json['dataSource'] as String,
      columns: (json['columns'] as List<dynamic>)
          .map((c) => OdsListColumn.fromJson(c as Map<String, dynamic>))
          .toList(),
      rowActions: (json['rowActions'] as List<dynamic>?)
              ?.map((a) => OdsRowAction.fromJson(a as Map<String, dynamic>))
              .toList() ??
          const [],
      summary: (json['summary'] as List<dynamic>?)
              ?.map((s) => OdsSummaryRule.fromJson(s as Map<String, dynamic>))
              .toList() ??
          const [],
      onRowTap: json['onRowTap'] != null
          ? OdsRowTap.fromJson(json['onRowTap'] as Map<String, dynamic>)
          : null,
      styleHint: OdsStyleHint.fromJson(json['styleHint'] as Map<String, dynamic>?),
      visibleWhen: json['visibleWhen'] != null
          ? OdsComponentVisibleWhen.fromJson(json['visibleWhen'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Renders an input form for data entry.
///
/// ODS Spec: `formComponent` — requires a unique `id` and a `fields` array.
/// The form ID links this form to submit actions: when a button's onClick
/// includes `{"action": "submit", "target": "<formId>"}`, the engine collects
/// this form's field values and writes them to the specified data source.
///
/// ODS Ethos: "The form is the schema." If a data source has no explicit field
/// definitions, the form's fields implicitly define the database table columns
/// on first submission. This eliminates the need for citizen developers to
/// think about database design at all.
class OdsFormComponent extends OdsComponent {
  /// Unique identifier referenced by submit actions.
  final String id;

  /// Ordered list of input fields rendered in the form.
  final List<OdsFieldDefinition> fields;

  const OdsFormComponent({
    required this.id,
    required this.fields,
    required super.styleHint,
    super.visibleWhen,
  }) : super(component: 'form');

  factory OdsFormComponent.fromJson(Map<String, dynamic> json) {
    return OdsFormComponent(
      id: json['id'] as String,
      fields: (json['fields'] as List<dynamic>)
          .map((f) => OdsFieldDefinition.fromJson(f as Map<String, dynamic>))
          .toList(),
      styleHint: OdsStyleHint.fromJson(json['styleHint'] as Map<String, dynamic>?),
      visibleWhen: json['visibleWhen'] != null
          ? OdsComponentVisibleWhen.fromJson(json['visibleWhen'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// A tappable button that triggers one or more actions.
///
/// ODS Spec: `buttonComponent` — requires a `label` and an `onClick` array
/// of actions. Actions execute sequentially: typically a submit followed by
/// a navigate, giving the user a natural "save and go" flow.
class OdsButtonComponent extends OdsComponent {
  final String label;

  /// Actions executed in order when the button is tapped.
  final List<OdsAction> onClick;

  const OdsButtonComponent({
    required this.label,
    required this.onClick,
    required super.styleHint,
    super.visibleWhen,
  }) : super(component: 'button');

  factory OdsButtonComponent.fromJson(Map<String, dynamic> json) {
    return OdsButtonComponent(
      label: json['label'] as String,
      onClick: (json['onClick'] as List<dynamic>)
          .map((a) => OdsAction.fromJson(a as Map<String, dynamic>))
          .toList(),
      styleHint: OdsStyleHint.fromJson(json['styleHint'] as Map<String, dynamic>?),
      visibleWhen: json['visibleWhen'] != null
          ? OdsComponentVisibleWhen.fromJson(json['visibleWhen'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Renders a data visualization chart from a data source.
///
/// ODS Spec: `chartComponent` — requires a `dataSource` ID, a `chartType`
/// (bar, line, or pie), and field mappings (`labelField` and `valueField`).
/// The framework queries the data source and renders the appropriate chart.
class OdsChartComponent extends OdsComponent {
  /// The ID of the data source to read rows from.
  final String dataSource;

  /// The chart type: "bar", "line", or "pie".
  final String chartType;

  /// The field to use for category labels (X axis or pie slices).
  final String labelField;

  /// The field to use for numeric values (Y axis or pie values).
  final String valueField;

  /// Optional chart title displayed above the chart.
  final String? title;

  const OdsChartComponent({
    required this.dataSource,
    required this.chartType,
    required this.labelField,
    required this.valueField,
    this.title,
    required super.styleHint,
    super.visibleWhen,
  }) : super(component: 'chart');

  factory OdsChartComponent.fromJson(Map<String, dynamic> json) {
    return OdsChartComponent(
      dataSource: json['dataSource'] as String,
      chartType: json['chartType'] as String? ?? 'bar',
      labelField: json['labelField'] as String,
      valueField: json['valueField'] as String,
      title: json['title'] as String?,
      styleHint: OdsStyleHint.fromJson(json['styleHint'] as Map<String, dynamic>?),
      visibleWhen: json['visibleWhen'] != null
          ? OdsComponentVisibleWhen.fromJson(json['visibleWhen'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Placeholder for component types not recognized by this framework version.
///
/// ODS Ethos: Graceful degradation over hard failure. Unknown components are
/// silently skipped in normal mode and shown with a warning card in debug mode.
/// This means a spec authored for a newer ODS version will still load in an
/// older framework — it just won't render the unknown parts.
class OdsUnknownComponent extends OdsComponent {
  /// The original JSON for debugging and inspection.
  final Map<String, dynamic> rawJson;

  const OdsUnknownComponent({
    required String type,
    required this.rawJson,
    required super.styleHint,
    super.visibleWhen,
  }) : super(component: type);

  factory OdsUnknownComponent.fromJson(Map<String, dynamic> json) {
    return OdsUnknownComponent(
      type: json['component'] as String? ?? 'unknown',
      rawJson: json,
      styleHint: OdsStyleHint.fromJson(json['styleHint'] as Map<String, dynamic>?),
      visibleWhen: json['visibleWhen'] != null
          ? OdsComponentVisibleWhen.fromJson(json['visibleWhen'] as Map<String, dynamic>)
          : null,
    );
  }
}

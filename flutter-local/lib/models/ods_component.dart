import 'ods_action.dart';
import 'ods_field_definition.dart';
import 'ods_style_hint.dart';
import 'ods_visible_when.dart';

/// Base class for all ODS components, using Dart 3 sealed classes.
///
/// ODS Spec alignment: Components are the building blocks of ODS pages.
/// Using a sealed class lets the renderer use exhaustive switch expressions
/// (see PageRenderer), guaranteeing every component type is handled at
/// compile time.
sealed class OdsComponent {
  /// The component type string from the spec (e.g., "text", "list").
  final String component;

  /// Optional styling hints interpreted by the renderer.
  final OdsStyleHint styleHint;

  /// Optional visibility condition. When set, the component is only shown
  /// if the condition is met (form field value or data source row count).
  final OdsComponentVisibleWhen? visibleWhen;

  /// Optional expression-based visibility. A lightweight alternative to
  /// [visibleWhen] that evaluates a string expression against form state.
  /// e.g., `"{status} == 'Open'"`. Component is shown when truthy.
  final String? visible;

  /// Optional role restriction. When set, only users with a matching role
  /// can see this component. When null/empty, visible to everyone.
  final List<String>? roles;

  const OdsComponent({
    required this.component,
    required this.styleHint,
    this.visibleWhen,
    this.visible,
    this.roles,
  });

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
      case 'summary':
        return OdsSummaryComponent.fromJson(json);
      case 'tabs':
        return OdsTabsComponent.fromJson(json);
      case 'detail':
        return OdsDetailComponent.fromJson(json);
      case 'kanban':
        return OdsKanbanComponent.fromJson(json);
      default:
        // Graceful degradation: unknown components are captured, not rejected.
        // This keeps forward compatibility — a spec with future component types
        // will still load in older framework versions.
        return OdsUnknownComponent.fromJson(json);
    }
  }
}

// ---------------------------------------------------------------------------
// Shared helpers for parsing common base-class fields
// ---------------------------------------------------------------------------

OdsComponentVisibleWhen? _parseVisibleWhen(Map<String, dynamic> json) {
  return json['visibleWhen'] != null
      ? OdsComponentVisibleWhen.fromJson(json['visibleWhen'] as Map<String, dynamic>)
      : null;
}

OdsStyleHint _parseStyleHint(Map<String, dynamic> json) {
  return OdsStyleHint.fromJson(json['styleHint'] as Map<String, dynamic>?);
}

String? _parseVisible(Map<String, dynamic> json) {
  return json['visible'] as String?;
}

List<String>? _parseRoles(Map<String, dynamic> json) {
  return (json['roles'] as List<dynamic>?)?.cast<String>();
}

/// Normalizes aggregate strings: "Count"→"count", "Average"→"avg", "Sum"→"sum".
String? _normalizeAggregate(String? raw) {
  if (raw == null) return null;
  switch (raw.toLowerCase()) {
    case 'count':
      return 'count';
    case 'average':
    case 'avg':
      return 'avg';
    case 'sum':
      return 'sum';
    default:
      return raw.toLowerCase();
  }
}

// ---------------------------------------------------------------------------
// Text Component
// ---------------------------------------------------------------------------

/// Displays static or dynamic text content on a page.
///
/// ODS Spec: `textComponent` — requires `content` string, optional `styleHint`
/// with a `variant` key (heading, subheading, body, caption).
/// Optional `format` controls rendering: 'plain' (default) or 'markdown'.
class OdsTextComponent extends OdsComponent {
  final String content;

  /// Text format: 'plain' (default) or 'markdown'.
  final String format;

  const OdsTextComponent({
    required this.content,
    this.format = 'plain',
    required super.styleHint,
    super.visibleWhen,
    super.visible,
    super.roles,
  }) : super(component: 'text');

  factory OdsTextComponent.fromJson(Map<String, dynamic> json) {
    return OdsTextComponent(
      content: json['content'] as String,
      format: json['format'] as String? ?? 'plain',
      styleHint: _parseStyleHint(json),
      visibleWhen: _parseVisibleWhen(json),
      visible: _parseVisible(json),
      roles: _parseRoles(json),
    );
  }
}

// ---------------------------------------------------------------------------
// List Component helpers
// ---------------------------------------------------------------------------

/// Defines a column mapping for list components: a display header and the
/// data field name to read from each row.
class OdsListColumn {
  final String header;
  final String field;

  /// When true, the column header is tappable to sort the list by this field.
  final bool sortable;

  /// When true, a filter dropdown is shown above the list for this column.
  final bool filterable;

  /// When true, the column displays values with the app's currency symbol prefix.
  final bool currency;

  /// Maps cell values to color names for conditional styling.
  /// e.g., `{"1": "green", "0": "red"}` turns correct/incorrect answers green/red.
  final Map<String, String>? colorMap;

  /// Maps cell values to display labels.
  /// e.g., `{"1": "Correct", "0": "Wrong"}` transforms raw values for display.
  final Map<String, String>? displayMap;

  /// When set, the column renders as an inline checkbox toggle.
  /// Contains `dataSource` (PUT data source ID) and `matchField` (row key).
  final OdsToggle? toggle;

  /// Optional role restriction. When set, only users with a matching role
  /// can see this column. When null/empty, visible to everyone.
  final List<String>? roles;

  const OdsListColumn({
    required this.header,
    required this.field,
    this.sortable = false,
    this.filterable = false,
    this.currency = false,
    this.colorMap,
    this.displayMap,
    this.toggle,
    this.roles,
  });

  factory OdsListColumn.fromJson(Map<String, dynamic> json) {
    return OdsListColumn(
      header: json['header'] as String,
      field: json['field'] as String,
      sortable: json['sortable'] as bool? ?? false,
      filterable: json['filterable'] as bool? ?? false,
      currency: json['currency'] as bool? ?? false,
      colorMap: (json['colorMap'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v as String)),
      displayMap: (json['displayMap'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v as String)),
      toggle: json['toggle'] != null
          ? OdsToggle.fromJson(json['toggle'] as Map<String, dynamic>)
          : null,
      roles: (json['roles'] as List<dynamic>?)?.cast<String>(),
    );
  }
}

/// Configuration for an inline toggle checkbox on a list column.
class OdsToggle {
  final String dataSource;
  final String matchField;

  /// Optional: auto-update a parent record when all items in a group are checked.
  final OdsAutoComplete? autoComplete;

  const OdsToggle({required this.dataSource, required this.matchField, this.autoComplete});

  factory OdsToggle.fromJson(Map<String, dynamic> json) {
    return OdsToggle(
      dataSource: json['dataSource'] as String,
      matchField: json['matchField'] as String? ?? '_id',
      autoComplete: json['autoComplete'] != null
          ? OdsAutoComplete.fromJson(json['autoComplete'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Config for auto-completing a parent when all children in a group are toggled on.
class OdsAutoComplete {
  /// Field on children that groups them (e.g., "listName").
  final String groupField;

  /// PUT data source for updating the parent.
  final String parentDataSource;

  /// Field on the parent to match by (e.g., "name").
  final String parentMatchField;

  /// Values to set on the parent when all children are complete.
  final Map<String, String> parentValues;

  const OdsAutoComplete({
    required this.groupField,
    required this.parentDataSource,
    required this.parentMatchField,
    required this.parentValues,
  });

  factory OdsAutoComplete.fromJson(Map<String, dynamic> json) {
    return OdsAutoComplete(
      groupField: json['groupField'] as String,
      parentDataSource: json['parentDataSource'] as String,
      parentMatchField: json['parentMatchField'] as String? ?? 'name',
      parentValues: (json['parentValues'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString())) ??
          const {},
    );
  }
}

/// Defines an inline action button rendered in each row of a list.
///
/// Condition to hide a row action based on the row's field values.
class OdsRowActionHideWhen {
  final String field;
  final String? equals;
  final String? notEquals;

  const OdsRowActionHideWhen({required this.field, this.equals, this.notEquals});

  factory OdsRowActionHideWhen.fromJson(Map<String, dynamic> json) {
    return OdsRowActionHideWhen(
      field: json['field'] as String,
      equals: json['equals'] as String?,
      notEquals: json['notEquals'] as String?,
    );
  }

  /// Returns true if the action should be hidden for this row.
  bool matches(Map<String, dynamic> row) {
    final rowValue = row[field]?.toString() ?? '';
    if (equals != null && rowValue == equals) return true;
    if (notEquals != null && rowValue != notEquals) return true;
    return false;
  }
}

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

  /// Optional condition to hide this action for specific rows.
  /// e.g., hide "Mark Done" when done=true.
  final OdsRowActionHideWhen? hideWhen;

  // -- copyRows fields --

  /// For copyRows: GET data source to read child rows from.
  final String? sourceDataSource;

  /// For copyRows: POST data source to write copied child rows to.
  final String? targetDataSource;

  /// For copyRows: POST data source to create the parent copy.
  final String? parentDataSource;

  /// For copyRows: field on children that links to the parent name.
  final String? linkField;

  /// For copyRows: parent field used as the name (gets " (copy)" suffix).
  final String? nameField;

  /// For copyRows: fields to reset on copied children (e.g., done→false).
  final Map<String, String> resetValues;

  /// Optional role restriction. When set, only users with a matching role
  /// can see/use this row action. When null/empty, available to everyone.
  final List<String>? roles;

  const OdsRowAction({
    required this.label,
    required this.action,
    required this.dataSource,
    required this.matchField,
    this.values = const {},
    this.confirm,
    this.hideWhen,
    this.sourceDataSource,
    this.targetDataSource,
    this.parentDataSource,
    this.linkField,
    this.nameField,
    this.resetValues = const {},
    this.roles,
  });

  bool get isDelete => action == 'delete';
  bool get isUpdate => action == 'update';
  bool get isCopyRows => action == 'copyRows';

  factory OdsRowAction.fromJson(Map<String, dynamic> json) {
    return OdsRowAction(
      label: json['label'] as String,
      action: json['action'] as String,
      dataSource: json['dataSource'] as String? ?? '',
      matchField: json['matchField'] as String? ?? '_id',
      values: (json['values'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString())) ??
          const {},
      confirm: json['confirm'] as String?,
      hideWhen: json['hideWhen'] != null
          ? OdsRowActionHideWhen.fromJson(json['hideWhen'] as Map<String, dynamic>)
          : null,
      sourceDataSource: json['sourceDataSource'] as String?,
      targetDataSource: json['targetDataSource'] as String?,
      parentDataSource: json['parentDataSource'] as String?,
      linkField: json['linkField'] as String?,
      nameField: json['nameField'] as String?,
      resetValues: (json['resetValues'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString())) ??
          const {},
      roles: (json['roles'] as List<dynamic>?)?.cast<String>(),
    );
  }
}

/// Defines a summary/aggregation rule for a list column.
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

/// Defines the initial sort order for a list component.
class OdsDefaultSort {
  /// The field name to sort by.
  final String field;

  /// Sort direction: 'asc' (default) or 'desc'.
  final String direction;

  const OdsDefaultSort({required this.field, this.direction = 'asc'});

  factory OdsDefaultSort.fromJson(Map<String, dynamic> json) {
    return OdsDefaultSort(
      field: json['field'] as String,
      direction: json['direction'] as String? ?? 'asc',
    );
  }

  bool get isDescending => direction == 'desc';
}

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

// ---------------------------------------------------------------------------
// List Component
// ---------------------------------------------------------------------------

/// Displays tabular data from a data source, as a table or card grid.
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

  /// When true, a search bar appears above the list.
  final bool searchable;

  /// Display mode: 'table' (default DataTable) or 'cards' (card grid).
  final String displayAs;

  /// Field name to evaluate for row-level background coloring.
  final String? rowColorField;

  /// Maps field values to color names for entire rows. Requires [rowColorField].
  final Map<String, String>? rowColorMap;

  /// Optional initial sort order applied when the list first renders.
  final OdsDefaultSort? defaultSort;

  const OdsListComponent({
    required this.dataSource,
    required this.columns,
    this.rowActions = const [],
    this.summary = const [],
    this.onRowTap,
    this.searchable = false,
    this.displayAs = 'table',
    this.rowColorField,
    this.rowColorMap,
    this.defaultSort,
    required super.styleHint,
    super.visibleWhen,
    super.visible,
    super.roles,
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
      searchable: json['searchable'] as bool? ?? false,
      displayAs: json['displayAs'] as String? ?? 'table',
      rowColorField: json['rowColorField'] as String?,
      rowColorMap: (json['rowColorMap'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v as String)),
      defaultSort: json['defaultSort'] != null
          ? OdsDefaultSort.fromJson(json['defaultSort'] as Map<String, dynamic>)
          : null,
      styleHint: _parseStyleHint(json),
      visibleWhen: _parseVisibleWhen(json),
      visible: _parseVisible(json),
      roles: _parseRoles(json),
    );
  }
}

// ---------------------------------------------------------------------------
// Form Component
// ---------------------------------------------------------------------------

/// Renders an input form for data entry.
class OdsFormComponent extends OdsComponent {
  /// Unique identifier referenced by submit actions.
  final String id;

  /// Ordered list of input fields rendered in the form.
  final List<OdsFieldDefinition> fields;

  /// Optional data source ID that backs this form as a record cursor.
  final String? recordSource;

  const OdsFormComponent({
    required this.id,
    required this.fields,
    this.recordSource,
    required super.styleHint,
    super.visibleWhen,
    super.visible,
    super.roles,
  }) : super(component: 'form');

  factory OdsFormComponent.fromJson(Map<String, dynamic> json) {
    return OdsFormComponent(
      id: json['id'] as String,
      fields: (json['fields'] as List<dynamic>)
          .map((f) => OdsFieldDefinition.fromJson(f as Map<String, dynamic>))
          .toList(),
      recordSource: json['recordSource'] as String?,
      styleHint: _parseStyleHint(json),
      visibleWhen: _parseVisibleWhen(json),
      visible: _parseVisible(json),
      roles: _parseRoles(json),
    );
  }
}

// ---------------------------------------------------------------------------
// Button Component
// ---------------------------------------------------------------------------

/// A tappable button that triggers one or more actions.
class OdsButtonComponent extends OdsComponent {
  final String label;

  /// Actions executed in order when the button is tapped.
  final List<OdsAction> onClick;

  const OdsButtonComponent({
    required this.label,
    required this.onClick,
    required super.styleHint,
    super.visibleWhen,
    super.visible,
    super.roles,
  }) : super(component: 'button');

  factory OdsButtonComponent.fromJson(Map<String, dynamic> json) {
    return OdsButtonComponent(
      label: json['label'] as String,
      onClick: (json['onClick'] as List<dynamic>)
          .map((a) => OdsAction.fromJson(a as Map<String, dynamic>))
          .toList(),
      styleHint: _parseStyleHint(json),
      visibleWhen: _parseVisibleWhen(json),
      visible: _parseVisible(json),
      roles: _parseRoles(json),
    );
  }
}

// ---------------------------------------------------------------------------
// Chart Component
// ---------------------------------------------------------------------------

/// Renders a data visualization chart from a data source.
class OdsChartComponent extends OdsComponent {
  final String dataSource;
  final String chartType;
  final String labelField;
  final String valueField;
  final String? title;

  /// How to aggregate values: "count", "sum", or "avg".
  /// Defaults to "count" when labelField == valueField, otherwise "sum".
  final String aggregate;

  const OdsChartComponent({
    required this.dataSource,
    required this.chartType,
    required this.labelField,
    required this.valueField,
    this.title,
    this.aggregate = 'sum',
    required super.styleHint,
    super.visibleWhen,
    super.visible,
    super.roles,
  }) : super(component: 'chart');

  factory OdsChartComponent.fromJson(Map<String, dynamic> json) {
    final labelField = json['labelField'] as String;
    final valueField = json['valueField'] as String;
    // Default to "count" when label and value fields are the same,
    // since summing non-numeric category values produces zeros.
    final defaultAggregate = labelField == valueField ? 'count' : 'sum';
    return OdsChartComponent(
      dataSource: json['dataSource'] as String,
      chartType: json['chartType'] as String? ?? 'bar',
      labelField: labelField,
      valueField: valueField,
      title: json['title'] as String?,
      aggregate: _normalizeAggregate(json['aggregate'] as String?) ?? defaultAggregate,
      styleHint: _parseStyleHint(json),
      visibleWhen: _parseVisibleWhen(json),
      visible: _parseVisible(json),
      roles: _parseRoles(json),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary Component (NEW — Feature 4)
// ---------------------------------------------------------------------------

/// Renders a styled KPI card with a label, a large aggregate value, and
/// an optional icon. Ideal for dashboard-style displays.
class OdsSummaryComponent extends OdsComponent {
  /// The label text shown above the value (e.g., "Total Spent").
  final String label;

  /// The value expression. Supports aggregate syntax like
  /// `{SUM(expenses, amount)}` or static text.
  final String value;

  /// Optional Material icon name (e.g., "attach_money", "trending_up").
  final String? icon;

  const OdsSummaryComponent({
    required this.label,
    required this.value,
    this.icon,
    required super.styleHint,
    super.visibleWhen,
    super.visible,
    super.roles,
  }) : super(component: 'summary');

  factory OdsSummaryComponent.fromJson(Map<String, dynamic> json) {
    return OdsSummaryComponent(
      label: json['label'] as String,
      value: json['value'] as String,
      icon: json['icon'] as String?,
      styleHint: _parseStyleHint(json),
      visibleWhen: _parseVisibleWhen(json),
      visible: _parseVisible(json),
      roles: _parseRoles(json),
    );
  }
}

// ---------------------------------------------------------------------------
// Tabs Component (NEW — Feature 6)
// ---------------------------------------------------------------------------

/// A single tab definition with a label and content array.
class OdsTabDefinition {
  final String label;
  final List<OdsComponent> content;

  const OdsTabDefinition({required this.label, required this.content});

  factory OdsTabDefinition.fromJson(Map<String, dynamic> json) {
    return OdsTabDefinition(
      label: json['label'] as String,
      content: (json['content'] as List<dynamic>)
          .map((c) => OdsComponent.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Renders a tabbed layout within a page. Each tab has its own content array.
class OdsTabsComponent extends OdsComponent {
  final List<OdsTabDefinition> tabs;

  const OdsTabsComponent({
    required this.tabs,
    required super.styleHint,
    super.visibleWhen,
    super.visible,
    super.roles,
  }) : super(component: 'tabs');

  factory OdsTabsComponent.fromJson(Map<String, dynamic> json) {
    return OdsTabsComponent(
      tabs: (json['tabs'] as List<dynamic>)
          .map((t) => OdsTabDefinition.fromJson(t as Map<String, dynamic>))
          .toList(),
      styleHint: _parseStyleHint(json),
      visibleWhen: _parseVisibleWhen(json),
      visible: _parseVisible(json),
      roles: _parseRoles(json),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail Component (NEW — Feature 9)
// ---------------------------------------------------------------------------

/// Renders a read-only detail view showing field values from a data source
/// record or form state. Ideal for "view record" pages.
class OdsDetailComponent extends OdsComponent {
  /// The ID of the GET data source to read from.
  /// Optional when `fromForm` is provided instead.
  final String dataSource;

  /// Optional list of field names to display, in order.
  /// If null, all columns from the record are shown.
  final List<String>? fields;

  /// Optional map of field names to display labels.
  final Map<String, String>? labels;

  /// Optional form ID whose current state provides the record to display.
  final String? fromForm;

  const OdsDetailComponent({
    this.dataSource = '',
    this.fields,
    this.labels,
    this.fromForm,
    required super.styleHint,
    super.visibleWhen,
    super.visible,
    super.roles,
  }) : super(component: 'detail');

  factory OdsDetailComponent.fromJson(Map<String, dynamic> json) {
    return OdsDetailComponent(
      dataSource: (json['dataSource'] as String?) ?? '',
      fields: (json['fields'] as List<dynamic>?)?.cast<String>(),
      labels: (json['labels'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v as String)),
      fromForm: json['fromForm'] as String?,
      styleHint: _parseStyleHint(json),
      visibleWhen: _parseVisibleWhen(json),
      visible: _parseVisible(json),
      roles: _parseRoles(json),
    );
  }
}

// ---------------------------------------------------------------------------
// Kanban Component
// ---------------------------------------------------------------------------

/// Renders data as a kanban board with draggable cards organized by a status
/// field's select options. Cards can be dragged between columns to update
/// the status field value.
class OdsKanbanComponent extends OdsComponent {
  /// The ID of the GET data source to read rows from.
  final String dataSource;

  /// The field name whose select options define the board columns.
  final String statusField;

  /// The field name used as the card title. Falls back to the first
  /// entry in [cardFields] when not set.
  final String? titleField;

  /// Field names to display on each card.
  final List<String> cardFields;

  /// Optional action buttons rendered on each card.
  final List<OdsRowAction> rowActions;

  /// Optional initial sort order applied to cards within each column.
  final OdsDefaultSort? defaultSort;

  /// When true, a search bar appears above the board.
  final bool searchable;

  const OdsKanbanComponent({
    required this.dataSource,
    required this.statusField,
    this.titleField,
    this.cardFields = const [],
    this.rowActions = const [],
    this.defaultSort,
    this.searchable = false,
    required super.styleHint,
    super.visibleWhen,
    super.visible,
    super.roles,
  }) : super(component: 'kanban');

  factory OdsKanbanComponent.fromJson(Map<String, dynamic> json) {
    return OdsKanbanComponent(
      dataSource: json['dataSource'] as String,
      statusField: json['statusField'] as String,
      titleField: json['titleField'] as String?,
      cardFields: (json['cardFields'] as List<dynamic>?)
              ?.cast<String>() ??
          const [],
      rowActions: (json['rowActions'] as List<dynamic>?)
              ?.map((a) => OdsRowAction.fromJson(a as Map<String, dynamic>))
              .toList() ??
          const [],
      defaultSort: json['defaultSort'] != null
          ? OdsDefaultSort.fromJson(json['defaultSort'] as Map<String, dynamic>)
          : null,
      searchable: json['searchable'] as bool? ?? false,
      styleHint: _parseStyleHint(json),
      visibleWhen: _parseVisibleWhen(json),
      visible: _parseVisible(json),
      roles: _parseRoles(json),
    );
  }
}

// ---------------------------------------------------------------------------
// Unknown Component (forward compatibility)
// ---------------------------------------------------------------------------

/// Placeholder for component types not recognized by this framework version.
class OdsUnknownComponent extends OdsComponent {
  /// The original JSON for debugging and inspection.
  final Map<String, dynamic> rawJson;

  const OdsUnknownComponent({
    required String type,
    required this.rawJson,
    required super.styleHint,
    super.visibleWhen,
    super.visible,
    super.roles,
  }) : super(component: type);

  factory OdsUnknownComponent.fromJson(Map<String, dynamic> json) {
    return OdsUnknownComponent(
      type: json['component'] as String? ?? 'unknown',
      rawJson: json,
      styleHint: _parseStyleHint(json),
      visibleWhen: _parseVisibleWhen(json),
      visible: _parseVisible(json),
      roles: _parseRoles(json),
    );
  }
}

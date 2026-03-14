/// Represents a single action triggered by user interaction (e.g., button tap).
///
/// ODS Spec alignment: Maps to the `action` definition in ods-schema.json.
/// Three action types are defined:
///   - "navigate": moves the user to a different page (target = page ID)
///   - "submit": saves form data as a new row (target = form ID,
///     dataSource = POST data source ID)
///   - "update": modifies an existing row matched by a key field
///     (target = form ID, dataSource = PUT data source ID,
///     matchField = the field used to find the row to update)
///
/// ODS Ethos: Actions are the *verbs* of an ODS app. "navigate", "submit",
/// and "update" cover the core CRUD flows a citizen developer needs:
/// "where do I go?", "where does new data go?", and "how do I change
/// existing data?"
/// A field value computed at submit time from an expression.
///
/// ODS Spec: `computedFields` on submit/update actions allow derived values
/// to be calculated and stored. Supports ternary comparisons for quiz scoring,
/// math expressions, string interpolation, and magic values like "NOW".
class OdsComputedField {
  /// The field name to store the computed value in.
  final String field;

  /// The expression to evaluate. Supports:
  ///   - Ternary: `{answer} == {correctAnswer} ? '1' : '0'`
  ///   - Math: `{quantity} * {unitPrice}`
  ///   - String interpolation: `{firstName} {lastName}`
  ///   - Magic values: `NOW` (current ISO datetime)
  final String expression;

  const OdsComputedField({required this.field, required this.expression});

  factory OdsComputedField.fromJson(Map<String, dynamic> json) {
    return OdsComputedField(
      field: json['field'] as String,
      expression: json['expression'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'field': field, 'expression': expression};
}

class OdsAction {
  final String action;

  /// For "navigate": the target page ID.
  /// For "submit"/"update": the target form ID.
  /// For "navigateToRow": the target page ID to navigate to.
  final String? target;

  /// For "submit"/"update": the data source ID to write form data into.
  /// For "navigateToRow": the data source ID to query rows from.
  final String? dataSource;

  /// For "update" only: the field name used to match the row to update.
  /// The row where this field's stored value matches the form's value is
  /// updated with all other form field values.
  final String? matchField;

  /// Reserved for future use: data to pass to the target page on navigation.
  /// Parsed from the spec but not yet consumed by any framework action.
  final Map<String, dynamic>? withData;

  /// Optional confirmation text. When set, a dialog is shown before the
  /// action executes. The user must confirm to proceed.
  final String? confirm;

  /// Fields computed at submit time from expressions. Evaluated after form
  /// data is collected but before database write. The computed values are
  /// merged into the stored data.
  final List<OdsComputedField> computedFields;

  /// For "navigateToRow": key-value filter to match rows. Values can contain
  /// `{fieldName}` references resolved from current form state.
  final Map<String, String>? filter;

  /// For "navigateToRow": field to sort results by (default: "_id").
  final String? sort;

  /// For "navigateToRow": sort direction — "asc" or "desc" (default: "asc").
  final String? sortOrder;

  /// For "navigateToRow": row offset (0-based). Can be an integer literal
  /// or a `{fieldName}` expression like `"{_rowIndex} + 1"`.
  final String? offset;

  /// For "navigateToRow": form ID to populate with the matched row data.
  final String? populateForm;

  /// For "navigateToRow": action to execute if no matching row is found.
  final OdsAction? fallback;

  const OdsAction({
    required this.action,
    this.target,
    this.dataSource,
    this.matchField,
    this.withData,
    this.confirm,
    this.computedFields = const [],
    this.filter,
    this.sort,
    this.sortOrder,
    this.offset,
    this.populateForm,
    this.fallback,
  });

  bool get isNavigate => action == 'navigate';
  bool get isSubmit => action == 'submit';
  bool get isUpdate => action == 'update';

  factory OdsAction.fromJson(Map<String, dynamic> json) {
    final filterRaw = json['filter'] as Map<String, dynamic>?;
    final fallbackRaw = json['fallback'] as Map<String, dynamic>?;

    return OdsAction(
      action: json['action'] as String,
      target: json['target'] as String?,
      dataSource: json['dataSource'] as String?,
      matchField: json['matchField'] as String?,
      withData: json['withData'] as Map<String, dynamic>?,
      confirm: json['confirm'] as String?,
      computedFields: (json['computedFields'] as List<dynamic>?)
              ?.map((c) => OdsComputedField.fromJson(c as Map<String, dynamic>))
              .toList() ??
          const [],
      filter: filterRaw?.map((k, v) => MapEntry(k, v.toString())),
      sort: json['sort'] as String?,
      sortOrder: json['sortOrder'] as String?,
      offset: json['offset']?.toString(),
      populateForm: json['populateForm'] as String?,
      fallback: fallbackRaw != null ? OdsAction.fromJson(fallbackRaw) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'action': action,
        if (target != null) 'target': target,
        if (dataSource != null) 'dataSource': dataSource,
        if (matchField != null) 'matchField': matchField,
        if (withData != null) 'withData': withData,
        if (confirm != null) 'confirm': confirm,
        if (computedFields.isNotEmpty)
          'computedFields': computedFields.map((c) => c.toJson()).toList(),
        if (filter != null) 'filter': filter,
        if (sort != null) 'sort': sort,
        if (sortOrder != null) 'sortOrder': sortOrder,
        if (offset != null) 'offset': offset,
        if (populateForm != null) 'populateForm': populateForm,
        if (fallback != null) 'fallback': fallback!.toJson(),
      };
}

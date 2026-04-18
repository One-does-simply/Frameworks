/// Represents a single action triggered by user interaction (e.g., button tap).
///
/// ODS Spec alignment: Maps to the `action` definition in ods-schema.json.
/// Action types:
///   - "navigate": moves the user to a different page (target = page ID)
///   - "submit": saves form data as a new row (target = form ID,
///     dataSource = POST data source ID)
///   - "update": modifies an existing row matched by a key field
///     (target = form ID, dataSource = PUT data source ID,
///     matchField = the field used to find the row to update)
///   - "firstRecord" / "nextRecord" / "previousRecord" / "lastRecord":
///     move the record cursor for a form with a recordSource.
///
/// ODS Ethos: Actions are the *verbs* of an ODS app. "navigate", "submit",
/// and "update" cover the core CRUD flows a citizen developer needs.
/// Record cursor actions add step-through navigation for data-driven
/// flows like quizzes or wizards.

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
  /// For record cursor actions: the target form ID.
  final String? target;

  /// For "submit"/"update": the data source ID to write form data into.
  final String? dataSource;

  /// For "update" only: the field name used to match the row to update.
  final String? matchField;

  /// For "navigate": form ID to pre-populate with [withData] values.
  final String? populateForm;

  /// For "navigate": key-value pairs to pre-fill in [populateForm].
  /// Values starting with "{" and ending with "}" are resolved from
  /// the current form state (e.g., "{listName}" reads from active forms).
  final Map<String, dynamic>? withData;

  /// Optional confirmation text. When set, a dialog is shown before the
  /// action executes. The user must confirm to proceed.
  final String? confirm;

  /// Fields computed at submit time from expressions.
  final List<OdsComputedField> computedFields;

  /// For "firstRecord": optional filter to apply when loading records.
  /// Values can contain `{fieldName}` references resolved from form state.
  final Map<String, String>? filter;

  /// For "nextRecord"/"previousRecord": action to execute when there are
  /// no more records in that direction (e.g., navigate to results page).
  final OdsAction? onEnd;

  /// For "showMessage": the text to display in a snackbar notification.
  final String? message;

  /// For "update": cascade changes to linked child data sources when a
  /// parent field is renamed.
  ///
  /// Shape (aligned with React): `{childDataSourceId: fieldName}` where each
  /// key is the ID of a child data source and each value is the name of the
  /// field in that child pointing to the parent. Multiple child data sources
  /// are supported in a single cascade.
  ///
  /// The parent field being renamed is inferred from the update action's
  /// `withData` (the sole key being updated) or the `matchField` for
  /// form-submission updates.
  ///
  /// Backward-compat: specs using the old flat-key form
  /// `{childDataSource, childLinkField, parentField}` are auto-converted by
  /// [fromJson] with a warning log.
  final Map<String, String>? cascade;

  /// For "submit": field names to preserve after the form is cleared.
  /// Enables "Add & Add Another" flows where the user submits, the form
  /// resets, but contextual fields (e.g., the selected list) are kept.
  final List<String> preserveFields;

  const OdsAction({
    required this.action,
    this.target,
    this.dataSource,
    this.matchField,
    this.populateForm,
    this.withData,
    this.confirm,
    this.computedFields = const [],
    this.filter,
    this.onEnd,
    this.message,
    this.cascade,
    this.preserveFields = const [],
  });

  bool get isNavigate => action == 'navigate';
  bool get isSubmit => action == 'submit';
  bool get isUpdate => action == 'update';
  bool get isShowMessage => action == 'showMessage';
  bool get isRecordAction =>
      action == 'firstRecord' ||
      action == 'nextRecord' ||
      action == 'previousRecord' ||
      action == 'lastRecord';

  factory OdsAction.fromJson(Map<String, dynamic> json) {
    final filterRaw = json['filter'] as Map<String, dynamic>?;
    final onEndRaw = json['onEnd'] as Map<String, dynamic>?;
    final cascadeRaw = json['cascade'] as Map<String, dynamic>?;

    return OdsAction(
      action: json['action'] as String,
      target: json['target'] as String?,
      dataSource: json['dataSource'] as String?,
      matchField: json['matchField'] as String?,
      populateForm: json['populateForm'] as String?,
      withData: json['withData'] as Map<String, dynamic>?,
      confirm: json['confirm'] as String?,
      computedFields: (json['computedFields'] as List<dynamic>?)
              ?.map((c) => OdsComputedField.fromJson(c as Map<String, dynamic>))
              .toList() ??
          const [],
      // Preserve string values directly; coerce non-string values (numbers,
      // booleans) with toString(). This is intentional: filter values in ODS
      // specs should be strings, and this ensures consistent comparison.
      filter: filterRaw?.map((k, v) => MapEntry(k, v is String ? v : v.toString())),
      onEnd: onEndRaw != null ? OdsAction.fromJson(onEndRaw) : null,
      message: json['message'] as String?,
      cascade: _parseCascade(cascadeRaw),
      preserveFields: (json['preserveFields'] as List<dynamic>?)
              ?.cast<String>() ??
          const [],
    );
  }

  /// Parses the cascade map from JSON.
  ///
  /// Accepts the React-style shape `{childDsId: fieldName, ...}`. Detects the
  /// legacy flat-key form `{childDataSource, childLinkField, parentField}`
  /// and auto-converts it to the new shape, emitting a warning.
  static Map<String, String>? _parseCascade(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    final flat = raw.containsKey('childDataSource') &&
        raw.containsKey('childLinkField');
    if (flat) {
      // ignore: avoid_print
      print('[WARN] OdsAction: cascade is using legacy flat-key form '
          '(childDataSource/childLinkField/parentField). Convert to the '
          'React-aligned nested form {childDsId: fieldName}.');
      final childDs = raw['childDataSource']?.toString();
      final childField = raw['childLinkField']?.toString();
      if (childDs != null && childField != null) {
        return {childDs: childField};
      }
      return null;
    }
    return raw.map((k, v) => MapEntry(k, v.toString()));
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
        if (onEnd != null) 'onEnd': onEnd!.toJson(),
        if (message != null) 'message': message,
        if (cascade != null) 'cascade': cascade,
        if (preserveFields.isNotEmpty) 'preserveFields': preserveFields,
      };
}

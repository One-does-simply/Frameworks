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
class OdsAction {
  final String action;

  /// For "navigate": the target page ID.
  /// For "submit"/"update": the target form ID.
  final String? target;

  /// For "submit"/"update": the data source ID to write form data into.
  final String? dataSource;

  /// For "update" only: the field name used to match the row to update.
  /// The row where this field's stored value matches the form's value is
  /// updated with all other form field values.
  final String? matchField;

  /// Reserved for future use: data to pass to the target page on navigation.
  /// Parsed from the spec but not yet consumed by any framework action.
  final Map<String, dynamic>? withData;

  const OdsAction({
    required this.action,
    this.target,
    this.dataSource,
    this.matchField,
    this.withData,
  });

  bool get isNavigate => action == 'navigate';
  bool get isSubmit => action == 'submit';
  bool get isUpdate => action == 'update';

  factory OdsAction.fromJson(Map<String, dynamic> json) {
    return OdsAction(
      action: json['action'] as String,
      target: json['target'] as String?,
      dataSource: json['dataSource'] as String?,
      matchField: json['matchField'] as String?,
      withData: json['withData'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
        'action': action,
        if (target != null) 'target': target,
        if (dataSource != null) 'dataSource': dataSource,
        if (matchField != null) 'matchField': matchField,
        if (withData != null) 'withData': withData,
      };
}

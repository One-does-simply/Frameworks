/// Describes how a select field should dynamically load its options from
/// a GET data source instead of using a static [options] array.
class OdsOptionsFrom {
  /// The ID of a GET data source to fetch options from.
  final String dataSource;

  /// The field/column name whose values become the dropdown options.
  final String valueField;

  const OdsOptionsFrom({required this.dataSource, required this.valueField});

  factory OdsOptionsFrom.fromJson(Map<String, dynamic> json) {
    return OdsOptionsFrom(
      dataSource: json['dataSource'] as String,
      valueField: json['valueField'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'dataSource': dataSource,
        'valueField': valueField,
      };
}

/// Represents a single field (column) in a form or data source.
///
/// ODS Spec alignment: Maps directly to the `fieldDefinition` shared type
/// in ods-schema.json. This is the atomic building block for both user input
/// (form fields) and data storage (table columns).
///
/// ODS Ethos: Fields are intentionally simple — a name, a type, an optional
/// label, an optional required flag, an optional placeholder, and an optional
/// default value. No regex, no masks, no computed logic. Complexity is the
/// enemy of "One Does Simply."
///
/// Select fields support dynamic options via [optionsFrom], which references
/// a GET data source and a column to pull values from at render time.
class OdsFieldDefinition {
  /// The programmatic name, used as the column name in local storage.
  final String name;

  /// The data type: "text", "email", "number", "date", "datetime", or "multiline".
  ///
  /// Drives input widget selection in forms:
  ///   - "text"      → single-line text field
  ///   - "email"     → single-line with email keyboard
  ///   - "number"    → single-line with numeric keyboard
  ///   - "date"      → date picker (stored as ISO 8601 date string)
  ///   - "datetime"  → date + time picker (stored as ISO 8601 datetime string)
  ///   - "multiline" → multi-line text area for long-form content
  final String type;

  /// Optional human-readable label shown in the UI.
  /// Falls back to [name] when not provided.
  final String? label;

  /// When true, the field must have a non-empty value before the form can
  /// be submitted. Frameworks should show inline validation feedback.
  final bool required;

  /// Optional hint text displayed inside the field when it is empty.
  /// Disappears once the user starts typing. Distinct from [label] —
  /// the label says *what* the field is, the placeholder shows *what to type*.
  final String? placeholder;

  /// Optional default value to pre-fill the field when the form is first
  /// displayed. The user can change it. Useful for fields like "status"
  /// where a sensible starting value reduces friction.
  final String? defaultValue;

  /// Required when [type] is "select" (unless [optionsFrom] is provided).
  /// The list of string options the user can choose from, rendered as a
  /// dropdown menu.
  final List<String>? options;

  /// Optional. Dynamically populates dropdown options from a GET data source.
  /// When provided on a "select" field, the framework queries the referenced
  /// data source and uses [OdsOptionsFrom.valueField] as dropdown values.
  /// Takes priority over static [options] if both are present.
  final OdsOptionsFrom? optionsFrom;

  const OdsFieldDefinition({
    required this.name,
    required this.type,
    this.label,
    this.required = false,
    this.placeholder,
    this.defaultValue,
    this.options,
    this.optionsFrom,
  });

  factory OdsFieldDefinition.fromJson(Map<String, dynamic> json) {
    return OdsFieldDefinition(
      name: json['name'] as String,
      type: json['type'] as String,
      label: json['label'] as String?,
      required: json['required'] as bool? ?? false,
      placeholder: json['placeholder'] as String?,
      defaultValue: json['default'] as String?,
      options: (json['options'] as List<dynamic>?)?.cast<String>(),
      optionsFrom: json['optionsFrom'] != null
          ? OdsOptionsFrom.fromJson(json['optionsFrom'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        if (label != null) 'label': label,
        if (required) 'required': required,
        if (placeholder != null) 'placeholder': placeholder,
        if (defaultValue != null) 'default': defaultValue,
        if (options != null) 'options': options,
        if (optionsFrom != null) 'optionsFrom': optionsFrom!.toJson(),
      };
}

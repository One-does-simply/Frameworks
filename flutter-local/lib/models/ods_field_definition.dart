/// Parse options from JSON — tolerates both List and comma-separated String.
List<String>? _parseOptions(dynamic value) {
  if (value == null) return null;
  if (value is List) return value.cast<String>();
  if (value is String) return value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  return null;
}

/// Filters dynamic options based on a sibling form field's value,
/// enabling dependent/cascading dropdowns.
class OdsOptionsFilter {
  /// The column name in the data source to filter on.
  final String field;

  /// The name of a sibling form field whose current value is used as the filter.
  final String fromField;

  const OdsOptionsFilter({required this.field, required this.fromField});

  factory OdsOptionsFilter.fromJson(Map<String, dynamic> json) {
    return OdsOptionsFilter(
      field: json['field'] as String,
      fromField: json['fromField'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'field': field, 'fromField': fromField};
}

/// Describes how a select field should dynamically load its options from
/// a GET data source instead of using a static [options] array.
class OdsOptionsFrom {
  /// The ID of a GET data source to fetch options from.
  final String dataSource;

  /// The field/column name whose values become the dropdown options.
  final String valueField;

  /// Optional filter for dependent dropdowns. When set, only rows where
  /// [filter.field] matches the sibling form field [filter.fromField]'s
  /// current value are included.
  final OdsOptionsFilter? filter;

  const OdsOptionsFrom({
    required this.dataSource,
    required this.valueField,
    this.filter,
  });

  factory OdsOptionsFrom.fromJson(Map<String, dynamic> json) {
    return OdsOptionsFrom(
      dataSource: json['dataSource'] as String,
      valueField: json['valueField'] as String,
      filter: json['filter'] != null
          ? OdsOptionsFilter.fromJson(json['filter'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'dataSource': dataSource,
        'valueField': valueField,
        if (filter != null) 'filter': filter!.toJson(),
      };
}

/// Describes a condition under which a field is visible.
/// When the referenced field's value matches, this field is shown; otherwise hidden.
class OdsVisibleWhen {
  /// The name of another field in the same form to watch.
  final String field;

  /// The value the watched field must equal for this field to be visible.
  final String equals;

  const OdsVisibleWhen({required this.field, required this.equals});

  factory OdsVisibleWhen.fromJson(Map<String, dynamic> json) {
    return OdsVisibleWhen(
      field: json['field'] as String,
      equals: json['equals'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'field': field,
        'equals': equals,
      };
}

/// Describes validation constraints beyond simple `required`.
class OdsValidation {
  final num? min;
  final num? max;
  final int? minLength;
  final String? pattern;
  final String? message;

  const OdsValidation({this.min, this.max, this.minLength, this.pattern, this.message});

  factory OdsValidation.fromJson(Map<String, dynamic> json) {
    return OdsValidation(
      min: json['min'] as num?,
      max: json['max'] as num?,
      minLength: json['minLength'] as int?,
      pattern: json['pattern'] as String?,
      message: json['message'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        if (minLength != null) 'minLength': minLength,
        if (pattern != null) 'pattern': pattern,
        if (message != null) 'message': message,
      };

  /// Validates a value and returns an error message, or null if valid.
  String? validate(String value, String fieldType) {
    if (value.isEmpty) return null; // Empty check is handled by `required`.

    // Email format validation.
    if (fieldType == 'email') {
      final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
      if (!emailRegex.hasMatch(value)) {
        return message ?? 'Please enter a valid email address';
      }
    }

    if (minLength != null && value.length < minLength!) {
      return message ?? 'Must be at least $minLength characters';
    }

    if (pattern != null) {
      final regex = RegExp(pattern!);
      if (!regex.hasMatch(value)) {
        return message ?? 'Invalid format';
      }
    }

    if ((min != null || max != null) && fieldType == 'number') {
      final num? parsed = num.tryParse(value);
      if (parsed == null) return null; // Not a number — type validation handles this.
      if (min != null && parsed < min!) {
        return message ?? 'Must be at least $min';
      }
      if (max != null && parsed > max!) {
        return message ?? 'Must be at most $max';
      }
    }

    return null;
  }
}

/// Represents a single field (column) in a form or data source.
///
/// ODS Spec alignment: Maps directly to the `fieldDefinition` shared type
/// in ods-schema.json. This is the atomic building block for both user input
/// (form fields) and data storage (table columns).
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

  /// Optional. A formula that computes this field's value from other fields.
  /// Reference fields with {fieldName} syntax. Supports basic math for number
  /// fields or string interpolation for text fields. Computed fields are
  /// read-only and not stored in the database.
  final String? formula;

  /// Optional. Conditional visibility — field is only shown when the
  /// referenced field's value matches.
  final OdsVisibleWhen? visibleWhen;

  /// Optional. Validation constraints beyond `required` — min, max, minLength, pattern.
  final OdsValidation? validation;

  /// When true, the field displays values with the app's currency symbol prefix.
  final bool currency;

  /// When true, the field renders as non-editable. Useful for record-cursor
  /// forms where some fields display context (e.g., a quiz question) while
  /// others accept input (e.g., the user's answer).
  final bool readOnly;

  /// Optional display variant for readOnly fields. Supported values:
  ///   - "plain" → renders as clean text (no input borders/background)
  ///   - "heading" → renders as larger, bold text
  ///   - "caption" → renders as smaller, muted text
  /// When null, readOnly fields use the default disabled-input style.
  final String? displayVariant;

  /// Optional display labels for select options, parallel to [options].
  /// Supports `{fieldName}` references resolved from the current form state.
  /// e.g., `["A: {optionA}", "B: {optionB}"]` shows enriched labels while
  /// still storing the raw option value ("A", "B").
  final List<String>? optionLabels;

  /// Optional role restriction. When set, only users with a matching role
  /// can see this field. When null/empty, visible to everyone.
  final List<String>? roles;

  /// Whether this field is computed (has a formula).
  bool get isComputed => formula != null;

  const OdsFieldDefinition({
    required this.name,
    required this.type,
    this.label,
    this.required = false,
    this.placeholder,
    this.defaultValue,
    this.options,
    this.optionsFrom,
    this.formula,
    this.visibleWhen,
    this.validation,
    this.currency = false,
    this.readOnly = false,
    this.displayVariant,
    this.optionLabels,
    this.roles,
  });

  factory OdsFieldDefinition.fromJson(Map<String, dynamic> json) {
    return OdsFieldDefinition(
      name: json['name'] as String,
      type: json['type'] as String,
      label: json['label'] as String?,
      required: json['required'] as bool? ?? false,
      placeholder: json['placeholder'] as String?,
      defaultValue: json['default'] as String?,
      options: _parseOptions(json['options']),
      optionsFrom: json['optionsFrom'] != null
          ? OdsOptionsFrom.fromJson(json['optionsFrom'] as Map<String, dynamic>)
          : null,
      formula: json['formula'] as String?,
      visibleWhen: json['visibleWhen'] != null
          ? OdsVisibleWhen.fromJson(json['visibleWhen'] as Map<String, dynamic>)
          : null,
      validation: json['validation'] != null
          ? OdsValidation.fromJson(json['validation'] as Map<String, dynamic>)
          : null,
      currency: json['currency'] as bool? ?? false,
      readOnly: json['readOnly'] as bool? ?? false,
      displayVariant: json['displayVariant'] as String?,
      optionLabels: (json['optionLabels'] as List<dynamic>?)?.cast<String>(),
      roles: (json['roles'] as List<dynamic>?)?.cast<String>(),
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
        if (optionLabels != null) 'optionLabels': optionLabels,
        if (optionsFrom != null) 'optionsFrom': optionsFrom!.toJson(),
        if (formula != null) 'formula': formula,
        if (readOnly) 'readOnly': readOnly,
        if (displayVariant != null) 'displayVariant': displayVariant,
        if (visibleWhen != null) 'visibleWhen': visibleWhen!.toJson(),
        if (validation != null) 'validation': validation!.toJson(),
        if (roles != null) 'roles': roles,
      };
}

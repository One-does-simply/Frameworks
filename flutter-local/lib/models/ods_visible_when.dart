/// Conditional visibility rule for components.
///
/// ODS Spec: Components can be shown/hidden based on either form field
/// values or data source row counts.
///
/// Field-based: `{"field": "type", "form": "myForm", "equals": "Other"}`
/// Data-based:  `{"source": "quiz_answers", "countMin": 10}`
class OdsComponentVisibleWhen {
  /// Form field name to watch (field-based visibility).
  final String? field;

  /// Form ID containing the watched field.
  final String? form;

  /// Value the field must equal for the component to be visible.
  final String? equals;

  /// Value the field must NOT equal for the component to be visible.
  final String? notEquals;

  /// Data source ID to check row count (data-based visibility).
  final String? source;

  /// Show when row count equals this value.
  final int? countEquals;

  /// Show when row count >= this value.
  final int? countMin;

  /// Show when row count <= this value.
  final int? countMax;

  const OdsComponentVisibleWhen({
    this.field,
    this.form,
    this.equals,
    this.notEquals,
    this.source,
    this.countEquals,
    this.countMin,
    this.countMax,
  });

  bool get isFieldBased => field != null && form != null;
  bool get isDataBased => source != null;

  factory OdsComponentVisibleWhen.fromJson(Map<String, dynamic> json) {
    return OdsComponentVisibleWhen(
      field: json['field'] as String?,
      form: json['form'] as String?,
      equals: json['equals']?.toString(),
      notEquals: json['notEquals']?.toString(),
      source: json['source'] as String?,
      countEquals: json['countEquals'] as int?,
      countMin: json['countMin'] as int?,
      countMax: json['countMax'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (field != null) 'field': field,
        if (form != null) 'form': form,
        if (equals != null) 'equals': equals,
        if (notEquals != null) 'notEquals': notEquals,
        if (source != null) 'source': source,
        if (countEquals != null) 'countEquals': countEquals,
        if (countMin != null) 'countMin': countMin,
        if (countMax != null) 'countMax': countMax,
      };
}

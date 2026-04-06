/// Defines a single user-configurable app setting.
///
/// ODS Spec alignment: Maps to entries in the top-level `settings` dictionary.
/// Each key in the dictionary is the setting's programmatic name; this class
/// holds the display metadata and default value.
///
/// Settings use the same type vocabulary as form fields (text, number, select,
/// checkbox) so the Build Helper doesn't need to learn new concepts.
class OdsAppSetting {
  /// Human-readable label shown in the settings UI.
  final String label;

  /// The setting type: text, number, select, or checkbox.
  final String type;

  /// The default value used when the user hasn't changed the setting.
  final String defaultValue;

  /// For select type: the list of allowed values.
  final List<String>? options;

  const OdsAppSetting({
    required this.label,
    required this.type,
    required this.defaultValue,
    this.options,
  });

  factory OdsAppSetting.fromJson(Map<String, dynamic> json) {
    return OdsAppSetting(
      label: json['label'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
      defaultValue: json['default'] as String? ?? '',
      options: json['options'] is List
          ? (json['options'] as List<dynamic>).map((o) => o.toString()).toList()
          : json['options'] is String
              ? (json['options'] as String).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
              : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'type': type,
        'default': defaultValue,
        if (options != null) 'options': options,
      };
}

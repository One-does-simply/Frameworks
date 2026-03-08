/// An open-ended bag of styling hints attached to any ODS component.
///
/// ODS Spec alignment: Maps to the `styleHint` definition in ods-schema.json,
/// which uses `additionalProperties: true` — deliberately open-ended so
/// frameworks can evolve styling without requiring spec changes.
///
/// ODS Ethos: StyleHints are *suggestions*, not mandates. A framework SHOULD
/// interpret known hints (variant, emphasis) and MUST gracefully ignore unknown
/// ones. This keeps specs forward-compatible and lets citizen developers
/// experiment without breaking anything.
class OdsStyleHint {
  /// Raw hint map. Frameworks read known keys and skip the rest.
  final Map<String, dynamic> hints;

  const OdsStyleHint(this.hints);

  /// Type-safe accessor for any hint key.
  T? get<T>(String key) {
    final value = hints[key];
    return value is T ? value : null;
  }

  /// Text variant hint: "heading", "subheading", "body", or "caption".
  String? get variant => get<String>('variant');

  /// Button emphasis hint: "primary", "secondary", or "danger".
  String? get emphasis => get<String>('emphasis');

  bool get isEmpty => hints.isEmpty;

  factory OdsStyleHint.fromJson(Map<String, dynamic>? json) {
    return OdsStyleHint(json ?? const {});
  }
}

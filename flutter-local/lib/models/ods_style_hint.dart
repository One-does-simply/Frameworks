/// An open-ended bag of styling hints attached to any ODS component.
///
/// ODS Spec alignment: Maps to the `styleHint` definition in ods-schema.json,
/// which uses `additionalProperties: true` — deliberately open-ended so
/// frameworks can evolve styling without requiring spec changes.
///
/// ODS Ethos: StyleHints are *suggestions*, not mandates. A framework SHOULD
/// interpret known hints and MUST gracefully ignore unknown ones. This keeps
/// specs forward-compatible and lets citizen developers experiment without
/// breaking anything.
class OdsStyleHint {
  /// Raw hint map. Frameworks read known keys and skip the rest.
  final Map<String, dynamic> hints;

  const OdsStyleHint(this.hints);

  /// Type-safe accessor for any hint key.
  T? get<T>(String key) {
    final value = hints[key];
    return value is T ? value : null;
  }

  // ---------------------------------------------------------------------------
  // Text hints
  // ---------------------------------------------------------------------------

  /// Text variant: "heading", "subheading", "body", or "caption".
  String? get variant => get<String>('variant');

  /// Content alignment: "left", "center", or "right".
  String? get align => get<String>('align');

  /// Accent color name: semantic ("success", "warning", "error", "info") or
  /// named ("green", "red", "blue", "orange", "purple", "teal", "pink",
  /// "amber", "indigo", "grey").
  String? get color => get<String>('color');

  // ---------------------------------------------------------------------------
  // Button hints
  // ---------------------------------------------------------------------------

  /// Button emphasis: "primary", "secondary", or "danger".
  String? get emphasis => get<String>('emphasis');

  /// Button/summary icon: a Material icon name (e.g., "add", "check", "star").
  String? get icon => get<String>('icon');

  /// Component size: "compact", "default", or "large".
  String? get size => get<String>('size');

  // ---------------------------------------------------------------------------
  // List hints
  // ---------------------------------------------------------------------------

  /// Row density: "compact", "default", or "comfortable".
  String? get density => get<String>('density');

  // ---------------------------------------------------------------------------
  // Card/surface hints
  // ---------------------------------------------------------------------------

  /// Shadow depth: 0, 1, 2, or 3.
  int? get elevation {
    final v = hints['elevation'];
    if (v is int) return v;
    if (v is double) return v.toInt();
    return null;
  }

  bool get isEmpty => hints.isEmpty;

  factory OdsStyleHint.fromJson(Map<String, dynamic>? json) {
    return OdsStyleHint(json ?? const {});
  }
}

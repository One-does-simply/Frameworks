import 'dart:ui';

/// App-level branding and theming configuration.
///
/// ODS Spec alignment: Maps to the optional top-level `branding` object.
/// Uses named themes from the ODS theme catalog (based on DaisyUI).
/// Each framework resolves theme tokens into its native theming system.
class OdsBranding {
  /// Named theme from the catalog (e.g., 'corporate', 'nord', 'dracula').
  final String theme;

  /// Color mode: light, dark, or system.
  final String mode;

  /// URL to the app logo image for sidebar/drawer.
  final String? logo;

  /// URL to a favicon/icon.
  final String? favicon;

  /// App bar style: solid, light, or transparent.
  final String headerStyle;

  /// Preferred font family name.
  final String? fontFamily;

  /// Per-token overrides on top of the selected theme.
  final Map<String, String> overrides;

  const OdsBranding({
    this.theme = 'indigo',
    this.mode = 'system',
    this.logo,
    this.favicon,
    this.headerStyle = 'light',
    this.fontFamily,
    this.overrides = const {},
  });

  factory OdsBranding.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const OdsBranding();

    // Backward compatibility: legacy format had primaryColor/cornerStyle
    if (json.containsKey('primaryColor') && !json.containsKey('theme')) {
      final overrides = <String, String>{};
      if (json['primaryColor'] != null) overrides['primary'] = json['primaryColor'] as String;
      if (json['accentColor'] != null) overrides['accent'] = json['accentColor'] as String;
      return OdsBranding(
        theme: 'indigo',
        mode: 'system',
        logo: json['logo'] as String?,
        favicon: json['favicon'] as String?,
        headerStyle: json['headerStyle'] as String? ?? 'light',
        fontFamily: json['fontFamily'] as String?,
        overrides: overrides,
      );
    }

    var parsedTheme = json['theme'] as String? ?? 'indigo';
    if (parsedTheme == 'light') parsedTheme = 'indigo';
    if (parsedTheme == 'dark') parsedTheme = 'slate';

    return OdsBranding(
      theme: parsedTheme,
      mode: json['mode'] as String? ?? 'system',
      logo: json['logo'] as String?,
      favicon: json['favicon'] as String?,
      headerStyle: json['headerStyle'] as String? ?? 'light',
      fontFamily: json['fontFamily'] as String?,
      overrides: (json['overrides'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString())) ??
          const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'theme': theme,
        'mode': mode,
        if (logo != null) 'logo': logo,
        if (favicon != null) 'favicon': favicon,
        if (headerStyle != 'light') 'headerStyle': headerStyle,
        if (fontFamily != null) 'fontFamily': fontFamily,
        if (overrides.isNotEmpty) 'overrides': overrides,
      };
}

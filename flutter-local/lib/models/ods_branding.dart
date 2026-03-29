import 'dart:ui';

/// App-level branding and theming configuration.
///
/// ODS Spec alignment: Maps to the optional top-level `branding` object.
/// When omitted, the framework uses its built-in defaults (indigo primary,
/// system font, rounded corners).
///
/// ODS Ethos: The builder provides a hex color and a couple of style hints.
/// The framework derives a complete Material 3 theme from these inputs.
class OdsBranding {
  /// Main brand color as a hex string (e.g., '#1E40AF').
  final String primaryColor;

  /// Optional secondary brand color.
  final String? accentColor;

  /// Preferred font family name.
  final String? fontFamily;

  /// URL to the app logo image for sidebar/drawer.
  final String? logo;

  /// URL to a favicon/icon.
  final String? favicon;

  /// App bar style: solid, light, or transparent.
  final String headerStyle;

  /// Border-radius style: rounded, sharp, or pill.
  final String cornerStyle;

  const OdsBranding({
    this.primaryColor = '#4F46E5',
    this.accentColor,
    this.fontFamily,
    this.logo,
    this.favicon,
    this.headerStyle = 'light',
    this.cornerStyle = 'rounded',
  });

  factory OdsBranding.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const OdsBranding();
    return OdsBranding(
      primaryColor: json['primaryColor'] as String? ?? '#4F46E5',
      accentColor: json['accentColor'] as String?,
      fontFamily: json['fontFamily'] as String?,
      logo: json['logo'] as String?,
      favicon: json['favicon'] as String?,
      headerStyle: json['headerStyle'] as String? ?? 'light',
      cornerStyle: json['cornerStyle'] as String? ?? 'rounded',
    );
  }

  /// Parse the primaryColor hex string into a Flutter Color.
  Color get primaryColorValue {
    try {
      final hex = primaryColor.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFF4F46E5); // Default indigo
    }
  }

  /// Parse the accentColor hex string into a Flutter Color, falling back to primary.
  Color get accentColorValue {
    if (accentColor == null) return primaryColorValue;
    try {
      final hex = accentColor!.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return primaryColorValue;
    }
  }

  /// Border radius based on cornerStyle.
  double get borderRadiusValue {
    switch (cornerStyle) {
      case 'sharp':
        return 4.0;
      case 'pill':
        return 24.0;
      default:
        return 12.0; // rounded
    }
  }

  Map<String, dynamic> toJson() => {
        'primaryColor': primaryColor,
        if (accentColor != null) 'accentColor': accentColor,
        if (fontFamily != null) 'fontFamily': fontFamily,
        if (logo != null) 'logo': logo,
        if (favicon != null) 'favicon': favicon,
        if (headerStyle != 'light') 'headerStyle': headerStyle,
        if (cornerStyle != 'rounded') 'cornerStyle': cornerStyle,
      };
}

import 'package:flutter/material.dart';

import '../models/ods_style_hint.dart';

/// Translates abstract [OdsStyleHint] values into concrete Flutter styles.
///
/// ODS Spec alignment: The spec defines styleHint as an open-ended object.
/// This resolver interprets the known hint keys:
///   - `variant`: "heading", "subheading", "body", "caption" → TextStyle
///   - `emphasis`: "primary", "secondary", "danger" → ButtonStyle
///
/// Unknown hints are ignored, keeping forward compatibility.
///
/// ODS Ethos: StyleHints are suggestions, not pixel-perfect instructions.
/// The framework maps them to Material Design tokens so the app looks
/// native on every platform. The spec author says "this is a heading" —
/// they don't choose font sizes or colors. Simple for the author,
/// polished for the user.
class StyleResolver {
  const StyleResolver();

  /// Maps a text variant hint to a Material [TextStyle].
  ///
  /// Falls back to `bodyLarge` for unknown or absent variants, ensuring
  /// text is always readable even with unrecognized hints.
  TextStyle resolveTextStyle(OdsStyleHint hint, BuildContext context) {
    final theme = Theme.of(context).textTheme;

    switch (hint.variant) {
      case 'heading':
        return theme.headlineMedium ?? const TextStyle(fontSize: 24, fontWeight: FontWeight.bold);
      case 'subheading':
        return theme.titleMedium ?? const TextStyle(fontSize: 18, fontWeight: FontWeight.w500);
      case 'caption':
        return theme.bodySmall ?? const TextStyle(fontSize: 12, color: Colors.grey);
      case 'body':
      default:
        return theme.bodyLarge ?? const TextStyle(fontSize: 16);
    }
  }

  /// Maps a button emphasis hint to a Material [ButtonStyle].
  ///
  /// Uses the theme's color scheme so buttons automatically adapt to
  /// the platform's visual language. Unstyled buttons get default padding
  /// but no custom colors.
  ButtonStyle resolveButtonStyle(OdsStyleHint hint, BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (hint.emphasis) {
      case 'primary':
        return ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        );
      case 'secondary':
        return ElevatedButton.styleFrom(
          backgroundColor: colorScheme.secondary,
          foregroundColor: colorScheme.onSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        );
      case 'danger':
        return ElevatedButton.styleFrom(
          backgroundColor: colorScheme.error,
          foregroundColor: colorScheme.onError,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        );
      default:
        return ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        );
    }
  }
}

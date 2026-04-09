import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Resolves ODS theme names to Flutter ColorScheme and design tokens.
///
/// Loads theme JSON files from the bundled assets (Specification/Themes/).
/// Falls back to the default indigo seed color if a theme can't be loaded.
class ThemeResolver {
  static final Map<String, Map<String, dynamic>> _cache = {};
  static bool _catalogLoaded = false;
  static List<Map<String, dynamic>> _catalog = [];

  /// Parse an oklch color string to a Flutter Color (approximate).
  static Color? parseOklch(String oklch) {
    // oklch(L% C H) — extract L, C, H values
    final match = RegExp(r'oklch\(([\d.]+)%?\s+([\d.]+)\s+([\d.]+)\)').firstMatch(oklch);
    if (match == null) return null;

    double L = double.tryParse(match.group(1)!) ?? 0;
    final C = double.tryParse(match.group(2)!) ?? 0;
    final H = double.tryParse(match.group(3)!) ?? 0;

    // Normalize L to 0-1
    if (L > 1) L /= 100;

    // Convert oklch → oklab → linear sRGB → sRGB
    final hRad = H * 3.141592653589793 / 180;
    final a = C * _cos(hRad);
    final b = C * _sin(hRad);

    // OKLab to linear sRGB via LMS
    final l_ = L + 0.3963377774 * a + 0.2158037573 * b;
    final m_ = L - 0.1055613458 * a - 0.0638541728 * b;
    final s_ = L - 0.0894841775 * a - 1.2914855480 * b;

    final l = l_ * l_ * l_;
    final m = m_ * m_ * m_;
    final s = s_ * s_ * s_;

    final r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
    final g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
    final bSrgb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;

    return Color.fromARGB(
      255,
      _gammaEncode(r),
      _gammaEncode(g),
      _gammaEncode(bSrgb),
    );
  }

  static int _gammaEncode(double linear) {
    final clamped = linear.clamp(0.0, 1.0);
    final encoded = clamped <= 0.0031308
        ? clamped * 12.92
        : 1.055 * _pow(clamped, 1.0 / 2.4) - 0.055;
    return (encoded * 255).round().clamp(0, 255);
  }

  static double _cos(double x) => _taylorCos(x);
  static double _sin(double x) => _taylorSin(x);
  static double _pow(double base, double exp) {
    if (base <= 0) return 0;
    return _exp(exp * _ln(base));
  }

  // Simple math helpers to avoid dart:math import issues
  static double _taylorCos(double x) {
    x = x % (2 * 3.141592653589793);
    double result = 1, term = 1;
    for (int i = 1; i <= 10; i++) {
      term *= -x * x / ((2 * i - 1) * (2 * i));
      result += term;
    }
    return result;
  }

  static double _taylorSin(double x) {
    x = x % (2 * 3.141592653589793);
    double result = x, term = x;
    for (int i = 1; i <= 10; i++) {
      term *= -x * x / ((2 * i) * (2 * i + 1));
      result += term;
    }
    return result;
  }

  static double _exp(double x) {
    double result = 1, term = 1;
    for (int i = 1; i <= 20; i++) {
      term *= x / i;
      result += term;
    }
    return result;
  }

  static double _ln(double x) {
    if (x <= 0) return -999;
    double y = (x - 1) / (x + 1);
    double result = 0, term = y;
    for (int i = 0; i < 20; i++) {
      result += term / (2 * i + 1);
      term *= y * y;
    }
    return 2 * result;
  }

  /// Load theme catalog from bundled assets.
  static Future<List<Map<String, dynamic>>> loadCatalog() async {
    if (_catalogLoaded) return _catalog;
    try {
      final json = await rootBundle.loadString('assets/themes/catalog.json');
      final data = jsonDecode(json) as Map<String, dynamic>;
      _catalog = (data['themes'] as List).cast<Map<String, dynamic>>();
      _catalogLoaded = true;
    } catch (_) {
      _catalog = [];
    }
    return _catalog;
  }

  /// Load a theme by name from bundled assets.
  static Future<Map<String, dynamic>?> loadTheme(String name) async {
    if (_cache.containsKey(name)) return _cache[name];
    try {
      final json = await rootBundle.loadString('assets/themes/$name.json');
      final data = jsonDecode(json) as Map<String, dynamic>;
      _cache[name] = data;
      return data;
    } catch (_) {
      return null;
    }
  }

  /// Resolve a theme name + mode into a seed Color for ColorScheme.fromSeed.
  static Future<Color?> resolveSeedColor(String themeName, String mode) async {
    final theme = await loadTheme(themeName);
    if (theme == null) return null;

    final resolvedMode = (mode == 'dark') ? 'dark' : 'light';
    final variant = theme[resolvedMode] as Map<String, dynamic>?;
    final colors = variant?['colors'] as Map<String, dynamic>?;
    final primaryStr = colors?['primary'] as String?;
    if (primaryStr == null) return null;

    return parseOklch(primaryStr);
  }

  /// Resolve design tokens (border radius, etc.) from a theme.
  static Future<double> resolveRadius(String themeName) async {
    final theme = await loadTheme(themeName);
    if (theme == null) return 12.0;

    final design = theme['design'] as Map<String, dynamic>?;
    final radiusBox = design?['radiusBox'] as String? ?? '.5rem';

    // Parse rem value to pixels (1rem ≈ 16px)
    final match = RegExp(r'([\d.]+)rem').firstMatch(radiusBox);
    if (match != null) {
      return (double.tryParse(match.group(1)!) ?? 0.5) * 16;
    }
    return 12.0;
  }

  /// Build a full ColorScheme from a theme's color tokens.
  static Future<ColorScheme?> resolveColorScheme(String themeName, Brightness brightness) async {
    final theme = await loadTheme(themeName);
    if (theme == null) return null;

    final modeName = brightness == Brightness.dark ? 'dark' : 'light';
    final variant = theme[modeName] as Map<String, dynamic>?;
    final colors = variant?['colors'] as Map<String, dynamic>?;
    if (colors == null) return null;

    Color c(String key, Color fallback) => parseOklch(colors[key] as String? ?? '') ?? fallback;

    // Derive onSurfaceVariant from baseContent (muted toward surface) instead of
    // neutralContent. DaisyUI's neutralContent is text-on-neutral (light text for
    // dark neutral BG in light themes) — the opposite of Material's onSurfaceVariant
    // which is muted text on the main (light) surface.
    final onSurface = c('baseContent', brightness == Brightness.dark ? Colors.white : const Color(0xFF1E293B));
    final surface = c('base100', brightness == Brightness.dark ? const Color(0xFF1E293B) : Colors.white);
    final onSurfaceVariant = Color.lerp(onSurface, surface, 0.35)!;

    return ColorScheme(
      brightness: brightness,
      primary: c('primary', const Color(0xFF4F46E5)),
      onPrimary: c('primaryContent', Colors.white),
      secondary: c('secondary', const Color(0xFFEC4899)),
      onSecondary: c('secondaryContent', Colors.white),
      tertiary: c('accent', const Color(0xFF06B6D4)),
      onTertiary: c('accentContent', Colors.black),
      error: c('error', const Color(0xFFEF4444)),
      onError: c('errorContent', Colors.white),
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: c('neutral', const Color(0xFF334155)),
      onSurfaceVariant: onSurfaceVariant,
      surfaceContainer: c('base200', brightness == Brightness.dark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
      surfaceContainerHigh: c('base300', brightness == Brightness.dark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0)),
      outline: c('base300', const Color(0xFFE2E8F0)),
    );
  }
}

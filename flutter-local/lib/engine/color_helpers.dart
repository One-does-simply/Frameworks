import 'dart:math' as math;

import 'package:flutter/painting.dart';

// ---------------------------------------------------------------------------
// Color helper utilities — WCAG contrast, hex conversion, contrast fixing
// Extracted from quick_build_screen.dart for testability and reuse.
// ---------------------------------------------------------------------------

/// WCAG relative luminance for a given [Color].
double wcagLuminance(Color c) {
  double linearize(double s) {
    if (s <= 0.04045) return s / 12.92;
    return math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }
  return 0.2126 * linearize(c.r) + 0.7152 * linearize(c.g) + 0.0722 * linearize(c.b);
}

/// WCAG contrast ratio between two colors (always >= 1).
double contrastRatio(Color c1, Color c2) {
  final l1 = wcagLuminance(c1);
  final l2 = wcagLuminance(c2);
  final lighter = l1 > l2 ? l1 : l2;
  final darker = l1 > l2 ? l2 : l1;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Convert a [Color] to a hex string like `#RRGGBB`.
String colorToHex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

/// Adjust [color] toward white or black until it achieves 4.5:1 contrast
/// against [paired].
Color fixContrast(Color color, Color paired) {
  final pairedLum = wcagLuminance(paired);
  final goLighter = pairedLum < 0.2;
  final r = color.r, g = color.g, b = color.b; // 0.0-1.0

  double lo = 0, hi = 1;
  Color best = color;
  for (int i = 0; i < 30; i++) {
    final mid = (lo + hi) / 2;
    final nr = goLighter ? r + (1.0 - r) * mid : r * (1 - mid);
    final ng = goLighter ? g + (1.0 - g) * mid : g * (1 - mid);
    final nb = goLighter ? b + (1.0 - b) * mid : b * (1 - mid);
    final candidate = Color.fromARGB(255, (nr * 255).round(), (ng * 255).round(), (nb * 255).round());
    if (contrastRatio(candidate, paired) >= 4.5) {
      best = candidate;
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return best;
}

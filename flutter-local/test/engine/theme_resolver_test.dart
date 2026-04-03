import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/engine/theme_resolver.dart';

void main() {
  // =========================================================================
  // parseOklch
  // =========================================================================

  group('parseOklch', () {
    test('parses valid oklch string with percentage L', () {
      final color = ThemeResolver.parseOklch('oklch(50% 0.2 260)');
      expect(color, isNotNull);
      expect(color!.alpha, 255);
    });

    test('parses valid oklch string with decimal L', () {
      final color = ThemeResolver.parseOklch('oklch(0.5 0.2 260)');
      expect(color, isNotNull);
    });

    test('parses oklch with 0 chroma (achromatic)', () {
      final color = ThemeResolver.parseOklch('oklch(70% 0 0)');
      expect(color, isNotNull);
      // Zero chroma = grey: R, G, B should be similar (0.0-1.0 range)
      final r = color!.r;
      final g = color.g;
      final b = color.b;
      expect((r - g).abs(), lessThanOrEqualTo(0.01));
      expect((g - b).abs(), lessThanOrEqualTo(0.01));
    });

    test('parses pure black oklch(0% 0 0)', () {
      final color = ThemeResolver.parseOklch('oklch(0% 0 0)');
      expect(color, isNotNull);
      // Color channels are 0.0-1.0 in modern Flutter
      expect(color!.r, closeTo(0, 0.01));
      expect(color.g, closeTo(0, 0.01));
      expect(color.b, closeTo(0, 0.01));
    });

    test('parses pure white oklch(100% 0 0)', () {
      final color = ThemeResolver.parseOklch('oklch(100% 0 0)');
      expect(color, isNotNull);
      expect(color!.r, closeTo(1.0, 0.01));
      expect(color.g, closeTo(1.0, 0.01));
      expect(color.b, closeTo(1.0, 0.01));
    });

    test('returns null for empty string', () {
      expect(ThemeResolver.parseOklch(''), isNull);
    });

    test('returns null for garbage input', () {
      expect(ThemeResolver.parseOklch('not-a-color'), isNull);
    });

    test('returns null for rgb() input', () {
      expect(ThemeResolver.parseOklch('rgb(255, 0, 0)'), isNull);
    });

    test('returns null for hex color', () {
      expect(ThemeResolver.parseOklch('#FF0000'), isNull);
    });

    test('returns null for malformed oklch (missing parens)', () {
      expect(ThemeResolver.parseOklch('oklch 50% 0.2 260'), isNull);
    });
  });

  // =========================================================================
  // Color conversion accuracy
  // =========================================================================

  group('color conversion accuracy', () {
    test('medium grey is approximately (128, 128, 128)', () {
      // oklch(53.39% 0 0) is roughly sRGB grey #808080
      final color = ThemeResolver.parseOklch('oklch(53.39% 0 0)');
      expect(color, isNotNull);
      // Color.r/.g/.b are 0.0-1.0 in modern Flutter, convert to 0-255
      final r = (color!.r * 255).round();
      final g = (color.g * 255).round();
      final b = (color.b * 255).round();
      // Allow tolerance since our Taylor-series math is approximate
      expect(r, closeTo(128, 20));
      expect(g, closeTo(128, 20));
      expect(b, closeTo(128, 20));
    });

    test('saturated blue-ish primary is in blue range', () {
      // oklch(50% 0.2 260) — should be a blue-purple
      final color = ThemeResolver.parseOklch('oklch(50% 0.2 260)');
      expect(color, isNotNull);
      // Blue channel should dominate (0.0-1.0 range, relative comparison)
      expect(color!.b, greaterThan(color.r));
      expect(color.b, greaterThan(color.g));
    });

    test('hue 0 with chroma produces reddish color', () {
      // oklch(60% 0.15 0) — should be reddish
      final color = ThemeResolver.parseOklch('oklch(60% 0.15 0)');
      expect(color, isNotNull);
      expect(color!.r, greaterThan(color.g));
      expect(color.r, greaterThan(color.b));
    });

    test('hue 140 with chroma produces greenish color', () {
      // oklch(60% 0.15 140) — should be greenish
      final color = ThemeResolver.parseOklch('oklch(60% 0.15 140)');
      expect(color, isNotNull);
      expect(color!.g, greaterThan(color.r));
    });

    test('high lightness produces bright color', () {
      final color = ThemeResolver.parseOklch('oklch(90% 0.05 200)');
      expect(color, isNotNull);
      // All channels should be high (bright) — 180/255 ≈ 0.706
      expect(color!.r, greaterThan(0.7));
      expect(color.g, greaterThan(0.7));
      expect(color.b, greaterThan(0.7));
    });

    test('low lightness produces dark color', () {
      final color = ThemeResolver.parseOklch('oklch(20% 0.05 200)');
      expect(color, isNotNull);
      // All channels should be low (dark) — 80/255 ≈ 0.314
      expect(color!.r, lessThan(0.32));
      expect(color.g, lessThan(0.32));
      expect(color.b, lessThan(0.32));
    });
  });

  // =========================================================================
  // loadCatalog (limited — asset loading requires TestWidgetsFlutterBinding)
  // =========================================================================

  group('loadCatalog', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('returns a list (may be empty without bundled assets)', () async {
      // In unit test environment, rootBundle may not have the asset.
      // We just verify it returns a list without crashing.
      final catalog = await ThemeResolver.loadCatalog();
      expect(catalog, isA<List<Map<String, dynamic>>>());
    });
  });

  // =========================================================================
  // loadTheme
  // =========================================================================

  group('loadTheme', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('returns null for nonexistent theme', () async {
      final theme = await ThemeResolver.loadTheme('does-not-exist-xyz');
      expect(theme, isNull);
    });
  });
}

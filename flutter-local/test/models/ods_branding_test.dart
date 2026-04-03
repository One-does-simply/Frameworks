import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/models/ods_branding.dart';

void main() {
  // =========================================================================
  // Default constructor values
  // =========================================================================

  group('OdsBranding defaults', () {
    test('default theme is indigo', () {
      const b = OdsBranding();
      expect(b.theme, 'indigo');
    });

    test('default mode is system', () {
      const b = OdsBranding();
      expect(b.mode, 'system');
    });

    test('default headerStyle is light', () {
      const b = OdsBranding();
      expect(b.headerStyle, 'light');
    });

    test('default overrides is empty', () {
      const b = OdsBranding();
      expect(b.overrides, isEmpty);
    });

    test('optional fields are null by default', () {
      const b = OdsBranding();
      expect(b.logo, isNull);
      expect(b.favicon, isNull);
      expect(b.fontFamily, isNull);
    });
  });

  // =========================================================================
  // fromJson with null
  // =========================================================================

  group('fromJson null', () {
    test('returns default branding for null', () {
      final b = OdsBranding.fromJson(null);
      expect(b.theme, 'indigo');
      expect(b.mode, 'system');
      expect(b.headerStyle, 'light');
      expect(b.overrides, isEmpty);
    });
  });

  // =========================================================================
  // fromJson with valid JSON
  // =========================================================================

  group('fromJson valid', () {
    test('parses full branding object', () {
      final b = OdsBranding.fromJson({
        'theme': 'nord',
        'mode': 'dark',
        'logo': 'https://example.com/logo.png',
        'favicon': 'https://example.com/fav.ico',
        'headerStyle': 'solid',
        'fontFamily': 'Inter',
        'overrides': {'primary': 'oklch(50% 0.2 260)'},
      });
      expect(b.theme, 'nord');
      expect(b.mode, 'dark');
      expect(b.logo, 'https://example.com/logo.png');
      expect(b.favicon, 'https://example.com/fav.ico');
      expect(b.headerStyle, 'solid');
      expect(b.fontFamily, 'Inter');
      expect(b.overrides['primary'], 'oklch(50% 0.2 260)');
    });

    test('parses minimal branding with only theme', () {
      final b = OdsBranding.fromJson({'theme': 'corporate'});
      expect(b.theme, 'corporate');
      expect(b.mode, 'system');
      expect(b.headerStyle, 'light');
      expect(b.logo, isNull);
      expect(b.overrides, isEmpty);
    });

    test('defaults missing mode to system', () {
      final b = OdsBranding.fromJson({'theme': 'indigo'});
      expect(b.mode, 'system');
    });

    test('defaults missing headerStyle to light', () {
      final b = OdsBranding.fromJson({'theme': 'indigo'});
      expect(b.headerStyle, 'light');
    });
  });

  // =========================================================================
  // Legacy format backward compatibility
  // =========================================================================

  group('legacy format', () {
    test('migrates primaryColor to overrides', () {
      final b = OdsBranding.fromJson({
        'primaryColor': '#4F46E5',
      });
      expect(b.theme, 'indigo');
      expect(b.mode, 'system');
      expect(b.overrides['primary'], '#4F46E5');
    });

    test('migrates accentColor to overrides', () {
      final b = OdsBranding.fromJson({
        'primaryColor': '#4F46E5',
        'accentColor': '#EC4899',
      });
      expect(b.overrides['primary'], '#4F46E5');
      expect(b.overrides['accent'], '#EC4899');
    });

    test('preserves logo and favicon in legacy format', () {
      final b = OdsBranding.fromJson({
        'primaryColor': '#123456',
        'logo': 'https://example.com/logo.png',
        'favicon': 'https://example.com/fav.ico',
      });
      expect(b.logo, 'https://example.com/logo.png');
      expect(b.favicon, 'https://example.com/fav.ico');
    });

    test('preserves fontFamily in legacy format', () {
      final b = OdsBranding.fromJson({
        'primaryColor': '#123456',
        'fontFamily': 'Roboto',
      });
      expect(b.fontFamily, 'Roboto');
    });

    test('preserves headerStyle in legacy format', () {
      final b = OdsBranding.fromJson({
        'primaryColor': '#123456',
        'headerStyle': 'transparent',
      });
      expect(b.headerStyle, 'transparent');
    });

    test('ignores legacy primaryColor when theme is present', () {
      final b = OdsBranding.fromJson({
        'theme': 'dracula',
        'primaryColor': '#123456',
      });
      expect(b.theme, 'dracula');
      // overrides should NOT contain the legacy primaryColor
      expect(b.overrides.containsKey('primary'), false);
    });
  });

  // =========================================================================
  // Legacy theme name migration
  // =========================================================================

  group('legacy theme name migration', () {
    test('"light" migrates to "indigo"', () {
      final b = OdsBranding.fromJson({'theme': 'light'});
      expect(b.theme, 'indigo');
    });

    test('"dark" migrates to "slate"', () {
      final b = OdsBranding.fromJson({'theme': 'dark'});
      expect(b.theme, 'slate');
    });

    test('valid theme names are preserved', () {
      final b = OdsBranding.fromJson({'theme': 'nord'});
      expect(b.theme, 'nord');
    });
  });

  // =========================================================================
  // toJson round-trip
  // =========================================================================

  group('toJson', () {
    test('round-trips a full branding object', () {
      final original = OdsBranding(
        theme: 'nord',
        mode: 'dark',
        logo: 'https://example.com/logo.png',
        favicon: 'https://example.com/fav.ico',
        headerStyle: 'solid',
        fontFamily: 'Inter',
        overrides: {'primary': 'oklch(50% 0.2 260)'},
      );
      final json = original.toJson();
      final restored = OdsBranding.fromJson(json);

      expect(restored.theme, original.theme);
      expect(restored.mode, original.mode);
      expect(restored.logo, original.logo);
      expect(restored.favicon, original.favicon);
      expect(restored.headerStyle, original.headerStyle);
      expect(restored.fontFamily, original.fontFamily);
      expect(restored.overrides, original.overrides);
    });

    test('round-trips default branding', () {
      const original = OdsBranding();
      final json = original.toJson();
      final restored = OdsBranding.fromJson(json);

      expect(restored.theme, 'indigo');
      expect(restored.mode, 'system');
      expect(restored.headerStyle, 'light');
      expect(restored.overrides, isEmpty);
    });

    test('toJson omits null optional fields', () {
      const b = OdsBranding();
      final json = b.toJson();
      expect(json.containsKey('logo'), false);
      expect(json.containsKey('favicon'), false);
      expect(json.containsKey('fontFamily'), false);
    });

    test('toJson omits default headerStyle', () {
      const b = OdsBranding();
      final json = b.toJson();
      expect(json.containsKey('headerStyle'), false);
    });

    test('toJson omits empty overrides', () {
      const b = OdsBranding();
      final json = b.toJson();
      expect(json.containsKey('overrides'), false);
    });

    test('toJson includes non-default headerStyle', () {
      const b = OdsBranding(headerStyle: 'solid');
      final json = b.toJson();
      expect(json['headerStyle'], 'solid');
    });
  });
}

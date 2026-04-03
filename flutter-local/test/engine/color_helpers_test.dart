import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/engine/color_helpers.dart';

void main() {
  // -------------------------------------------------------------------------
  // wcagLuminance
  // -------------------------------------------------------------------------

  group('wcagLuminance', () {
    test('black has luminance 0', () {
      expect(wcagLuminance(const Color(0xFF000000)), closeTo(0, 1e-5));
    });

    test('white has luminance 1', () {
      expect(wcagLuminance(const Color(0xFFFFFFFF)), closeTo(1, 1e-5));
    });

    test('mid-gray has known luminance ~0.2159', () {
      expect(wcagLuminance(const Color(0xFF808080)), closeTo(0.2159, 0.01));
    });

    test('pure red has lower luminance than pure green', () {
      expect(
        wcagLuminance(const Color(0xFFFF0000)),
        lessThan(wcagLuminance(const Color(0xFF00FF00))),
      );
    });
  });

  // -------------------------------------------------------------------------
  // contrastRatio
  // -------------------------------------------------------------------------

  group('contrastRatio', () {
    test('white vs black is ~21', () {
      const white = Color(0xFFFFFFFF);
      const black = Color(0xFF000000);
      expect(contrastRatio(white, black), closeTo(21, 0.5));
    });

    test('same color yields 1', () {
      const c = Color(0xFF336699);
      expect(contrastRatio(c, c), closeTo(1, 1e-5));
    });

    test('is symmetric', () {
      const red = Color(0xFFFF0000);
      const blue = Color(0xFF0000FF);
      expect(contrastRatio(red, blue), closeTo(contrastRatio(blue, red), 1e-5));
    });

    test('known pair: white vs mid-gray', () {
      const white = Color(0xFFFFFFFF);
      const gray = Color(0xFF808080);
      final ratio = contrastRatio(white, gray);
      expect(ratio, greaterThan(3.5));
      expect(ratio, lessThan(4.5));
    });
  });

  // -------------------------------------------------------------------------
  // colorToHex
  // -------------------------------------------------------------------------

  group('colorToHex', () {
    test('converts red', () {
      expect(colorToHex(const Color(0xFFFF0000)), '#FF0000');
    });

    test('converts black', () {
      expect(colorToHex(const Color(0xFF000000)), '#000000');
    });

    test('converts white', () {
      expect(colorToHex(const Color(0xFFFFFFFF)), '#FFFFFF');
    });

    test('round-trips a known color', () {
      const original = Color(0xFF3A7BCD);
      final hex = colorToHex(original);
      expect(hex, '#3A7BCD');
    });
  });

  // -------------------------------------------------------------------------
  // fixContrast
  // -------------------------------------------------------------------------

  group('fixContrast', () {
    test('already-passing pair stays close to original', () {
      const white = Color(0xFFFFFFFF);
      const black = Color(0xFF000000);
      final result = fixContrast(white, black);
      expect(contrastRatio(result, black), greaterThanOrEqualTo(4.5));
      // Should remain very close to white
      expect(result.r, greaterThan(0.95));
      expect(result.g, greaterThan(0.95));
      expect(result.b, greaterThan(0.95));
    });

    test('fixes failing color on dark background to >= 4.5:1', () {
      const darkGray = Color(0xFF333333);
      const black = Color(0xFF000000);
      expect(contrastRatio(darkGray, black), lessThan(4.5));

      final fixed = fixContrast(darkGray, black);
      expect(contrastRatio(fixed, black), greaterThanOrEqualTo(4.5));
    });

    test('fixes failing color on light background to >= 4.5:1', () {
      const lightGray = Color(0xFFCCCCCC);
      const white = Color(0xFFFFFFFF);
      expect(contrastRatio(lightGray, white), lessThan(4.5));

      final fixed = fixContrast(lightGray, white);
      expect(contrastRatio(fixed, white), greaterThanOrEqualTo(4.5));
    });

    test('result stays as close to original as possible', () {
      const gray = Color(0xFF757575);
      const white = Color(0xFFFFFFFF);
      final fixed = fixContrast(gray, white);
      expect(contrastRatio(fixed, white), greaterThanOrEqualTo(4.5));
      // Should still be a mid-tone gray, not slammed to black
      final hexStr = colorToHex(fixed);
      // R channel should be between 30 and 200 (out of 255 range)
      expect(fixed.r * 255, greaterThan(30));
      expect(fixed.r * 255, lessThan(200));
    });
  });
}

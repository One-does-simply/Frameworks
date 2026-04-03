import { describe, it, expect } from 'vitest';
import {
  hexToRgb,
  rgbToHex,
  relativeLuminance,
  contrastRatio,
  fixContrast,
} from '../../../src/engine/color-helpers.ts';

// ---------------------------------------------------------------------------
// hexToRgb
// ---------------------------------------------------------------------------

describe('hexToRgb', () => {
  it('converts red', () => {
    expect(hexToRgb('#FF0000')).toEqual([255, 0, 0]);
  });

  it('converts black', () => {
    expect(hexToRgb('#000000')).toEqual([0, 0, 0]);
  });

  it('converts white', () => {
    expect(hexToRgb('#FFFFFF')).toEqual([255, 255, 255]);
  });

  it('handles lowercase hex', () => {
    expect(hexToRgb('#ff8800')).toEqual([255, 136, 0]);
  });

  it('handles hex without hash prefix', () => {
    expect(hexToRgb('00FF00')).toEqual([0, 255, 0]);
  });
});

// ---------------------------------------------------------------------------
// rgbToHex
// ---------------------------------------------------------------------------

describe('rgbToHex', () => {
  it('converts red', () => {
    expect(rgbToHex(255, 0, 0)).toBe('#ff0000');
  });

  it('converts black', () => {
    expect(rgbToHex(0, 0, 0)).toBe('#000000');
  });

  it('converts white', () => {
    expect(rgbToHex(255, 255, 255)).toBe('#ffffff');
  });

  it('clamps values above 255', () => {
    expect(rgbToHex(300, 0, 0)).toBe('#ff0000');
  });

  it('clamps values below 0', () => {
    expect(rgbToHex(-10, 0, 0)).toBe('#000000');
  });

  it('rounds fractional values', () => {
    expect(rgbToHex(127.6, 0, 0)).toBe('#800000');
  });
});

// ---------------------------------------------------------------------------
// hexToRgb <-> rgbToHex round-trip
// ---------------------------------------------------------------------------

describe('hex round-trip', () => {
  it('hexToRgb -> rgbToHex returns same (lowercase) value', () => {
    const original = '#3a7bcd';
    const [r, g, b] = hexToRgb(original);
    expect(rgbToHex(r, g, b)).toBe(original);
  });
});

// ---------------------------------------------------------------------------
// relativeLuminance
// ---------------------------------------------------------------------------

describe('relativeLuminance', () => {
  it('black has luminance 0', () => {
    expect(relativeLuminance('#000000')).toBeCloseTo(0, 5);
  });

  it('white has luminance 1', () => {
    expect(relativeLuminance('#FFFFFF')).toBeCloseTo(1, 5);
  });

  it('mid-gray (#808080) has known luminance ~0.2159', () => {
    // sRGB 128/255 linearized -> ~0.2159 via the WCAG formula
    expect(relativeLuminance('#808080')).toBeCloseTo(0.2159, 2);
  });

  it('pure red has lower luminance than pure green', () => {
    expect(relativeLuminance('#FF0000')).toBeLessThan(relativeLuminance('#00FF00'));
  });
});

// ---------------------------------------------------------------------------
// contrastRatio
// ---------------------------------------------------------------------------

describe('contrastRatio', () => {
  it('white vs black is 21:1', () => {
    expect(contrastRatio('#FFFFFF', '#000000')).toBeCloseTo(21, 0);
  });

  it('same color yields 1:1', () => {
    expect(contrastRatio('#336699', '#336699')).toBeCloseTo(1, 5);
  });

  it('is symmetric', () => {
    const r1 = contrastRatio('#FF0000', '#0000FF');
    const r2 = contrastRatio('#0000FF', '#FF0000');
    expect(r1).toBeCloseTo(r2, 5);
  });

  it('known pair: white vs mid-gray', () => {
    // L(white)=1, L(#808080)~0.2159 => ratio ~= (1.05)/(0.2659) ~= 3.95
    const ratio = contrastRatio('#FFFFFF', '#808080');
    expect(ratio).toBeGreaterThan(3.5);
    expect(ratio).toBeLessThan(4.5);
  });
});

// ---------------------------------------------------------------------------
// fixContrast
// ---------------------------------------------------------------------------

describe('fixContrast', () => {
  it('already-passing pair is returned unchanged or very close', () => {
    // White on black already passes
    const result = fixContrast('#FFFFFF', '#000000');
    expect(contrastRatio(result, '#000000')).toBeGreaterThanOrEqual(4.5);
    // Should be very close to white
    const [r, g, b] = hexToRgb(result);
    expect(r).toBeGreaterThanOrEqual(250);
    expect(g).toBeGreaterThanOrEqual(250);
    expect(b).toBeGreaterThanOrEqual(250);
  });

  it('fixes a failing color on dark background to >= 4.5:1', () => {
    // Dark gray (#333333) on black (#000000) fails — ratio ~1.36
    const failing = '#333333';
    const paired = '#000000';
    expect(contrastRatio(failing, paired)).toBeLessThan(4.5);

    const fixed = fixContrast(failing, paired);
    expect(contrastRatio(fixed, paired)).toBeGreaterThanOrEqual(4.5);
  });

  it('fixes a failing color on light background to >= 4.5:1', () => {
    // Light gray (#CCCCCC) on white (#FFFFFF) fails — ratio ~1.61
    const failing = '#CCCCCC';
    const paired = '#FFFFFF';
    expect(contrastRatio(failing, paired)).toBeLessThan(4.5);

    const fixed = fixContrast(failing, paired);
    expect(contrastRatio(fixed, paired)).toBeGreaterThanOrEqual(4.5);
  });

  it('result stays as close to original as possible', () => {
    // A slightly-failing color should only be nudged a little
    const failing = '#757575'; // contrast vs white ~4.6 vs black ~4.6 — let's pair with white
    const paired = '#FFFFFF';
    const fixed = fixContrast(failing, paired);
    expect(contrastRatio(fixed, paired)).toBeGreaterThanOrEqual(4.5);
    // The fixed color should still be somewhat gray, not jumped to black
    const [r] = hexToRgb(fixed);
    expect(r).toBeGreaterThan(30);
    expect(r).toBeLessThan(200);
  });
});

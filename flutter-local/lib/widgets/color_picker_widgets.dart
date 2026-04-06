import 'package:flutter/material.dart';

import '../engine/color_helpers.dart';

// ---------------------------------------------------------------------------
// Shared color-picker widgets — used by QuickBuild and Settings screens.
// ---------------------------------------------------------------------------

/// 6x8 curated color grid + grayscale row.
const colorGrid = <List<int>>[
  // Reds
  [0xFFFFCDD2, 0xFFEF9A9A, 0xFFE57373, 0xFFEF5350, 0xFFF44336, 0xFFE53935, 0xFFC62828, 0xFFB71C1C],
  // Oranges / Yellows
  [0xFFFFE0B2, 0xFFFFCC80, 0xFFFFB74D, 0xFFFFA726, 0xFFFF9800, 0xFFFB8C00, 0xFFEF6C00, 0xFFE65100],
  // Greens
  [0xFFC8E6C9, 0xFFA5D6A7, 0xFF81C784, 0xFF66BB6A, 0xFF4CAF50, 0xFF43A047, 0xFF2E7D32, 0xFF1B5E20],
  // Teals / Cyans
  [0xFFB2EBF2, 0xFF80DEEA, 0xFF4DD0E1, 0xFF26C6DA, 0xFF00BCD4, 0xFF00ACC1, 0xFF00838F, 0xFF006064],
  // Blues / Indigos
  [0xFFBBDEFB, 0xFF90CAF9, 0xFF64B5F6, 0xFF42A5F5, 0xFF2196F3, 0xFF1E88E5, 0xFF1565C0, 0xFF0D47A1],
  // Purples / Pinks
  [0xFFE1BEE7, 0xFFCE93D8, 0xFFBA68C8, 0xFFAB47BC, 0xFF9C27B0, 0xFF8E24AA, 0xFF6A1B9A, 0xFF4A148C],
  // Grays (white to black)
  [0xFFFFFFFF, 0xFFE0E0E0, 0xFFBDBDBD, 0xFF9E9E9E, 0xFF757575, 0xFF616161, 0xFF424242, 0xFF212121],
];

/// Maps each color token to its contrast-paired token.
const tokenPairs = <String, String>{
  'primary': 'primaryContent',
  'secondary': 'secondaryContent',
  'accent': 'accentContent',
  'base100': 'baseContent',
  'baseContent': 'base100',
  'error': 'errorContent',
  'success': 'successContent',
};

/// Human-readable hints for each customizable color token.
const tokenHints = <String, String>{
  'primary': 'Main action buttons and links',
  'secondary': 'Supporting actions and highlights',
  'accent': 'Decorative elements and badges',
  'base100': 'Page background color',
  'baseContent': 'Main body text color',
  'error': 'Error messages and alerts',
  'success': 'Success states and confirmations',
};

// ---------------------------------------------------------------------------
// "Why Color Contrast Matters" information dialog
// ---------------------------------------------------------------------------

/// Shows an informational dialog explaining WCAG color contrast.
void showWhyDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Why Color Contrast Matters'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Color contrast is the difference in brightness between text and its background. '
            'When contrast is too low, text becomes hard or impossible to read — especially for '
            'people with low vision, color blindness, or anyone using a screen in bright sunlight.',
            style: TextStyle(fontSize: 13),
          ),
          SizedBox(height: 12),
          Text(
            'The WCAG AA standard requires a minimum contrast ratio of 4.5:1 for normal text. '
            'This is the internationally recognized benchmark for web accessibility, and ODS '
            'enforces it for all built-in themes.',
            style: TextStyle(fontSize: 13),
          ),
          SizedBox(height: 12),
          Text(
            'Colors in the Recommended section meet this standard against the text that will '
            'appear on top of them. You can still pick any color, but low-contrast choices will '
            'show a warning.',
            style: TextStyle(fontSize: 13),
          ),
        ],
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Got it')),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// GridColorPickerDialog — full-featured grid picker with contrast checking
// ---------------------------------------------------------------------------

/// A dialog that lets the user pick a color from a curated grid, enter a hex
/// value, or adjust RGB sliders. Returns the selected [Color] via
/// `Navigator.pop`, or `null` if cancelled.
class GridColorPickerDialog extends StatefulWidget {
  /// The color initially selected (shown in the "Current" preview).
  final Color initialColor;

  /// The color that text will appear on top of (for contrast checking).
  /// When `null`, contrast checking is disabled.
  final Color? pairedColor;

  /// A human-readable hint shown below the title (e.g. "Main action buttons").
  final String label;

  const GridColorPickerDialog({
    super.key,
    required this.initialColor,
    this.pairedColor,
    required this.label,
  });

  @override
  State<GridColorPickerDialog> createState() => _GridColorPickerDialogState();
}

class _GridColorPickerDialogState extends State<GridColorPickerDialog> {
  late Color _selected;
  bool _showRgb = false;
  late TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialColor;
    _hexController = TextEditingController(text: colorToHex(widget.initialColor));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _setColor(Color c) {
    setState(() {
      _selected = c;
      _hexController.text = colorToHex(c);
    });
  }

  List<Widget> _buildColorGridSections(ThemeData theme) {
    final allColors = colorGrid.expand((row) => row).toList();
    final paired = widget.pairedColor;
    final recommended = <int>[];
    final other = <int>[];

    if (paired != null) {
      final seen = <int>{};
      for (final c in allColors) {
        if (contrastRatio(Color(c), paired) >= 4.5) {
          recommended.add(c);
          seen.add(c);
        } else {
          other.add(c);
        }
      }
      // Add fixed versions of failing colors (deduplicated)
      for (final c in other) {
        final fixed = fixContrast(Color(c), paired);
        final fixedArgb = fixed.toARGB32();
        if (!seen.contains(fixedArgb)) {
          recommended.add(fixedArgb);
          seen.add(fixedArgb);
        }
      }
    } else {
      recommended.addAll(allColors);
    }

    Widget buildGrid(List<int> colors, {double opacity = 1.0}) {
      const cols = 8;
      final rows = <List<int>>[];
      for (var i = 0; i < colors.length; i += cols) {
        rows.add(colors.sublist(i, (i + cols).clamp(0, colors.length)));
      }
      return Opacity(
        opacity: opacity,
        child: Column(
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    for (int i = 0; i < cols; i++) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(
                        child: i < row.length
                            ? GestureDetector(
                                onTap: () => _setColor(Color(row[i])),
                                child: Container(
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Color(row[i]),
                                    borderRadius: BorderRadius.circular(3),
                                    border: _selected.toARGB32() == row[i]
                                        ? Border.all(color: theme.colorScheme.primary, width: 2.5)
                                        : null,
                                  ),
                                ),
                              )
                            : const SizedBox(height: 28),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      );
    }

    return [
      if (recommended.isNotEmpty) ...[
        if (paired != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Text('Recommended (accessible)', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => showWhyDialog(context),
                  child: Text('Why?', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
                ),
              ],
            ),
          ),
        buildGrid(recommended),
      ],
      if (other.isNotEmpty) ...[
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('Other (low contrast)', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        buildGrid(other, opacity: 0.5),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = widget.pairedColor != null ? contrastRatio(_selected, widget.pairedColor!) : null;
    final passesAA = ratio != null && ratio >= 4.5;

    return AlertDialog(
      title: const Text('Pick Color'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hint
              Text(widget.label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),

              // Current vs New preview + contrast
              Row(
                children: [
                  Expanded(
                    child: Column(children: [
                      Text('Current', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: widget.initialColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: theme.colorScheme.outlineVariant),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(children: [
                      Text('New', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: _selected,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: theme.colorScheme.outlineVariant),
                        ),
                      ),
                    ]),
                  ),
                  if (ratio != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(children: [
                        Text('Contrast', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Container(
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: passesAA ? const Color(0x1A22C55E) : const Color(0x1AEF4444),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: passesAA ? const Color(0xFF22C55E) : const Color(0xFFEF4444)),
                          ),
                          child: Text(
                            '${ratio.toStringAsFixed(1)}:1 ${passesAA ? '\u2713' : '\u26A0'}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: passesAA ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),

              // Color grid — split into recommended (accessible) and other
              ..._buildColorGridSections(theme),
              const SizedBox(height: 4),

              // Contrast warning banner
              if (ratio != null && !passesAA)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: const Color(0x1AEF4444),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'This color may make text hard to read. A contrast ratio of at least 4.5:1 is needed for accessible text.',
                        style: TextStyle(fontSize: 11, color: theme.brightness == Brightness.dark ? const Color(0xFFF87171) : const Color(0xFFDC2626)),
                      ),
                      if (widget.pairedColor != null) ...[
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () => _setColor(fixContrast(_selected, widget.pairedColor!)),
                          child: Text(
                            'Fix for me',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                              color: theme.brightness == Brightness.dark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              // Hex input
              Row(
                children: [
                  Text('Hex', style: theme.textTheme.bodySmall),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _hexController,
                        style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                        onChanged: (v) {
                          final hex = v.trim();
                          if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) {
                            final parsed = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
                            if (parsed != null) {
                              setState(() => _selected = Color(0xFF000000 | parsed));
                            }
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Collapsible RGB sliders
              InkWell(
                onTap: () => setState(() => _showRgb = !_showRgb),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        _showRgb ? Icons.expand_more : Icons.chevron_right,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text('Custom RGB color', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
              if (_showRgb) ...[
                _rgbSlider('R', (_selected.r * 255).round(), const Color(0xFFE53935), (v) {
                  _setColor(Color.fromARGB(255, v, (_selected.g * 255).round(), (_selected.b * 255).round()));
                }),
                _rgbSlider('G', (_selected.g * 255).round(), const Color(0xFF43A047), (v) {
                  _setColor(Color.fromARGB(255, (_selected.r * 255).round(), v, (_selected.b * 255).round()));
                }),
                _rgbSlider('B', (_selected.b * 255).round(), const Color(0xFF1E88E5), (v) {
                  _setColor(Color.fromARGB(255, (_selected.r * 255).round(), (_selected.g * 255).round(), v));
                }),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _selected), child: const Text('Select')),
      ],
    );
  }

  Widget _rgbSlider(String label, int value, Color labelColor, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: labelColor)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: value.toDouble(),
                min: 0,
                max: 255,
                onChanged: (v) => onChanged(v.round()),
              ),
            ),
          ),
          SizedBox(
            width: 30,
            child: Text('$value', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ColorRow — a tappable row showing a color swatch, label, and edit icon
// ---------------------------------------------------------------------------

/// A row widget displaying a color swatch, label, optional "Custom" badge, a
/// reset button (when overridden), and an edit icon. Tapping opens a
/// [GridColorPickerDialog] unless [onTap] is provided (for callers that need
/// custom logic before showing the dialog, e.g. async paired-color lookup).
class ColorRow extends StatelessWidget {
  /// Human-readable label (e.g. "Primary").
  final String label;

  /// Design-token name (e.g. "primary").
  final String token;

  /// The current resolved color.
  final Color color;

  /// Whether the user has a custom override for this token.
  final bool hasOverride;

  /// The paired color for contrast checking (may be null).
  final Color? pairedColor;

  /// Called when the user picks a new color via the built-in dialog.
  /// Ignored when [onTap] is provided.
  final ValueChanged<Color>? onColorPicked;

  /// Called when the user resets the override.
  final VoidCallback? onReset;

  /// Optional custom tap handler. When provided, the built-in dialog is NOT
  /// shown — the caller is responsible for opening the picker.
  final VoidCallback? onTap;

  const ColorRow({
    super.key,
    required this.label,
    required this.token,
    required this.color,
    required this.hasOverride,
    this.pairedColor,
    this.onColorPicked,
    this.onReset,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap ?? () async {
          final picked = await showDialog<Color>(
            context: context,
            builder: (_) => GridColorPickerDialog(
              initialColor: color,
              pairedColor: pairedColor,
              label: tokenHints[token] ?? 'Choose a color',
            ),
          );
          if (picked != null) {
            onColorPicked?.call(picked);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                    if (hasOverride)
                      Text('Custom', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                  ],
                ),
              ),
              if (hasOverride && onReset != null)
                IconButton(
                  icon: Icon(Icons.undo, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  tooltip: 'Reset',
                  onPressed: onReset,
                ),
              Icon(Icons.edit, size: 16, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

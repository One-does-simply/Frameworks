import 'package:flutter/material.dart';

import '../engine/theme_resolver.dart';

// ---------------------------------------------------------------------------
// ThemePickerDialog — reusable theme selection dialog with filter chips
// ---------------------------------------------------------------------------

/// A dialog that displays the full theme catalog with Style/Palette filter
/// chips and alphabetically sorted theme cards with color-dot previews.
///
/// Returns the selected theme name via [Navigator.pop], or `null` if the user
/// cancels.
///
/// Usage:
/// ```dart
/// final picked = await showDialog<String>(
///   context: context,
///   builder: (_) => ThemePickerDialog(initialTheme: 'indigo'),
/// );
/// ```
class ThemePickerDialog extends StatefulWidget {
  final String initialTheme;

  const ThemePickerDialog({super.key, required this.initialTheme});

  @override
  State<ThemePickerDialog> createState() => _ThemePickerDialogState();
}

class _ThemePickerDialogState extends State<ThemePickerDialog> {
  List<Map<String, dynamic>> _catalog = [];
  bool _loading = true;
  late String _selected;

  String? _activeStyle;
  String? _activePalette;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialTheme;
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final catalog = await ThemeResolver.loadCatalog();
    if (!mounted) return;
    setState(() {
      _catalog = catalog;
      _loading = false;
    });
  }

  // Helpers to extract tags from a catalog entry (supports object format).
  static String? _getStyle(Map<String, dynamic> entry) {
    final tags = entry['tags'];
    if (tags is Map) return tags['style'] as String?;
    return null;
  }

  static String? _getPalette(Map<String, dynamic> entry) {
    final tags = entry['tags'];
    if (tags is Map) return tags['palette'] as String?;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Dialog(
        child: SizedBox(
          width: 400,
          height: 500,
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // Collect unique styles and palettes.
    final allStyles = <String>{};
    final allPalettes = <String>{};
    for (final entry in _catalog) {
      final s = _getStyle(entry);
      final p = _getPalette(entry);
      if (s != null) allStyles.add(s);
      if (p != null) allPalettes.add(p);
    }
    final sortedStyles = allStyles.toList()..sort();
    final sortedPalettes = allPalettes.toList()..sort();

    // Filter and sort.
    final filtered = _catalog.where((entry) {
      if (_activeStyle != null && _getStyle(entry) != _activeStyle) return false;
      if (_activePalette != null && _getPalette(entry) != _activePalette) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => ((a['displayName'] ?? a['name']) as String)
          .compareTo((b['displayName'] ?? b['name']) as String));

    return Dialog(
      child: SizedBox(
        width: 400,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Select Theme', style: theme.textTheme.titleMedium),
            ),

            // Filter chips
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (sortedStyles.isNotEmpty) ...[
                    Text(
                      'STYLE',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final tag in sortedStyles)
                          _buildChip(
                            theme,
                            tag,
                            _activeStyle == tag,
                            () => setState(() => _activeStyle =
                                _activeStyle == tag ? null : tag),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (sortedPalettes.isNotEmpty) ...[
                    Text(
                      'PALETTE',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final tag in sortedPalettes)
                          _buildChip(
                            theme,
                            tag,
                            _activePalette == tag,
                            () => setState(() => _activePalette =
                                _activePalette == tag ? null : tag),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const Divider(height: 1),

            // Scrollable theme list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final entry = filtered[index];
                  final name = entry['name'] as String;
                  final displayName = entry['displayName'] as String? ?? name;
                  final entryTags = entry['tags'];
                  final tagList = <String>[];
                  if (entryTags is Map) {
                    if (entryTags['style'] != null) {
                      tagList.add(entryTags['style'] as String);
                    }
                    if (entryTags['palette'] != null) {
                      tagList.add(entryTags['palette'] as String);
                    }
                  }
                  final isSelected = name == _selected;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _ThemeCard(
                      themeName: name,
                      displayName: displayName,
                      tags: tagList,
                      isSelected: isSelected,
                      onTap: () => setState(() => _selected = name),
                    ),
                  );
                },
              ),
            ),

            const Divider(height: 1),

            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text('Select'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(
    ThemeData theme,
    String label,
    bool isActive,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isActive
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isActive
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ThemeCard — color-dot preview card (extracted from QuickBuild)
// ---------------------------------------------------------------------------

class _ThemeCard extends StatefulWidget {
  final String themeName;
  final String displayName;
  final List<String> tags;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.themeName,
    required this.displayName,
    this.tags = const [],
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_ThemeCard> createState() => _ThemeCardState();
}

class _ThemeCardState extends State<_ThemeCard> {
  Color? _primary;
  Color? _secondary;
  Color? _accent;

  @override
  void initState() {
    super.initState();
    _loadColors();
  }

  @override
  void didUpdateWidget(covariant _ThemeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.themeName != widget.themeName) {
      _primary = null;
      _secondary = null;
      _accent = null;
      _loadColors();
    }
  }

  Future<void> _loadColors() async {
    final theme = await ThemeResolver.loadTheme(widget.themeName);
    if (theme == null || !mounted) return;
    final colors = ((theme['light'] ?? theme['dark'])
        as Map<String, dynamic>?)?['colors'] as Map<String, dynamic>?;
    if (colors == null) return;
    setState(() {
      _primary = ThemeResolver.parseOklch(colors['primary'] as String? ?? '');
      _secondary =
          ThemeResolver.parseOklch(colors['secondary'] as String? ?? '');
      _accent = ThemeResolver.parseOklch(colors['accent'] as String? ?? '');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: widget.isSelected ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: widget.isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outline.withValues(alpha: 0.3),
          width: widget.isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_primary != null) ...[
                    _dot(_primary!),
                    _dot(_secondary ?? _primary!),
                    _dot(_accent ?? _primary!),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      widget.displayName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            widget.isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.isSelected)
                    Icon(Icons.check_circle,
                        size: 18, color: theme.colorScheme.primary),
                ],
              ),
              if (widget.tags.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: widget.tags
                      .map((tag) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(tag,
                                style: TextStyle(
                                    fontSize: 9,
                                    color:
                                        theme.colorScheme.onSurfaceVariant)),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(Color color) => Container(
        width: 12,
        height: 12,
        margin: const EdgeInsets.only(right: 3),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black12, width: 0.5),
        ),
      );
}

// ---------------------------------------------------------------------------
// ThemePickerTile — drop-in ListTile that shows current theme + opens dialog
// ---------------------------------------------------------------------------

/// A convenience widget that shows the current theme name with color-dot
/// previews and opens [ThemePickerDialog] when tapped.
///
/// [currentTheme] is the currently active theme name.
/// [onThemeChanged] is called with the newly selected theme name.
class ThemePickerTile extends StatefulWidget {
  final String currentTheme;
  final ValueChanged<String> onThemeChanged;

  /// Optional leading icon (defaults to [Icons.palette_outlined]).
  final IconData icon;

  /// Optional title text (defaults to "Theme").
  final String title;

  /// Optional subtitle text.
  final String? subtitle;

  const ThemePickerTile({
    super.key,
    required this.currentTheme,
    required this.onThemeChanged,
    this.icon = Icons.palette_outlined,
    this.title = 'Theme',
    this.subtitle,
  });

  @override
  State<ThemePickerTile> createState() => _ThemePickerTileState();
}

class _ThemePickerTileState extends State<ThemePickerTile> {
  Color? _primary;
  Color? _secondary;
  Color? _accent;

  @override
  void initState() {
    super.initState();
    _loadColors();
  }

  @override
  void didUpdateWidget(covariant ThemePickerTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentTheme != widget.currentTheme) {
      _primary = null;
      _secondary = null;
      _accent = null;
      _loadColors();
    }
  }

  Future<void> _loadColors() async {
    final theme = await ThemeResolver.loadTheme(widget.currentTheme);
    if (theme == null || !mounted) return;
    final colors = ((theme['light'] ?? theme['dark'])
        as Map<String, dynamic>?)?['colors'] as Map<String, dynamic>?;
    if (colors == null) return;
    setState(() {
      _primary = ThemeResolver.parseOklch(colors['primary'] as String? ?? '');
      _secondary =
          ThemeResolver.parseOklch(colors['secondary'] as String? ?? '');
      _accent = ThemeResolver.parseOklch(colors['accent'] as String? ?? '');
    });
  }

  Future<void> _openPicker() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => ThemePickerDialog(initialTheme: widget.currentTheme),
    );
    if (picked != null && picked != widget.currentTheme) {
      widget.onThemeChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = widget.currentTheme.isNotEmpty
        ? widget.currentTheme[0].toUpperCase() + widget.currentTheme.substring(1)
        : widget.currentTheme;

    return ListTile(
      leading: Icon(widget.icon),
      title: Text(widget.title),
      subtitle: widget.subtitle != null ? Text(widget.subtitle!) : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      trailing: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _openPicker,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_primary != null) ...[
                _dot(_primary!),
                _dot(_secondary ?? _primary!),
                _dot(_accent ?? _primary!),
                const SizedBox(width: 6),
              ],
              Text(
                displayName,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
      onTap: _openPicker,
    );
  }

  Widget _dot(Color color) => Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black12, width: 0.5),
        ),
      );
}

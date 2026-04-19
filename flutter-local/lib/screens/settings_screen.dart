import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../engine/app_engine.dart';
import '../engine/auth_service.dart';
import '../engine/framework_auth_service.dart';
import '../engine/log_service.dart';
import '../engine/color_helpers.dart';
import '../engine/theme_resolver.dart';
import '../engine/settings_store.dart';
import '../models/ods_app.dart';
import '../models/ods_app_setting.dart';
import '../models/ods_branding.dart';
import '../renderer/snackbar_helper.dart';
import '../screens/app_tour_dialog.dart';
import '../widgets/color_picker_widgets.dart';
import '../widgets/framework_user_list.dart';
import '../widgets/theme_picker_dialog.dart';

/// Full-page settings screen for the Flutter Local framework.
///
/// Combines:
///   - App settings (from spec)
///   - User management (multi-user only, admin only)
///   - Framework settings (theme, backup, debug)
///   - Data management (backup, restore, import)
class SettingsScreen extends StatefulWidget {
  final AppEngine engine;
  final SettingsStore settings;
  final OdsApp app;

  const SettingsScreen({
    super.key,
    required this.engine,
    required this.settings,
    required this.app,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  AppEngine get engine => widget.engine;
  SettingsStore get settings => widget.settings;
  OdsApp get app => widget.app;

  // -----------------------------------------------------------------------
  // Data operations
  // -----------------------------------------------------------------------

  Future<void> _backupData() async {
    setState(() => _busy = true);
    try {
      final backup = await engine.backupData();
      final appName = app.appName.replaceAll(RegExp(r'[^\w]'), '_').toLowerCase();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final fileName = 'ods_backup_${appName}_$timestamp.json';
      final jsonStr = jsonEncode(backup);

      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Backup',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (outputPath != null && mounted) {
        await File(outputPath).writeAsString(jsonStr);
        showOdsSnackBar(context, message: 'Backup saved to $outputPath');
      }
    } catch (e) {
      if (mounted) showOdsSnackBar(context, message: 'Backup failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from Backup'),
        content: const Text(
          'This will replace all current app data with the backup. '
          'Any data entered since the backup was created will be lost.\n\n'
          'Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select Backup File',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result == null || result.files.single.path == null) return;

    setState(() => _busy = true);
    try {
      final file = File(result.files.single.path!);
      final jsonStr = await file.readAsString();
      final backup = jsonDecode(jsonStr) as Map<String, dynamic>;

      if (!backup.containsKey('odsBackup') && !backup.containsKey('tables')) {
        throw const FormatException('Not a valid ODS backup file');
      }

      await engine.restoreData(backup);
      if (mounted) showOdsSnackBar(context, message: 'Data restored from backup');
    } catch (e) {
      if (mounted) showOdsSnackBar(context, message: 'Restore failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importData() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select CSV or JSON file to import',
      type: FileType.custom,
      allowedExtensions: ['csv', 'json'],
    );

    if (result == null || result.files.single.path == null || !mounted) return;

    final filePath = result.files.single.path!;
    final file = File(filePath);
    final content = await file.readAsString();
    final isCsv = filePath.toLowerCase().endsWith('.csv');

    List<Map<String, dynamic>> rows;
    try {
      if (isCsv) {
        rows = _parseCsv(content);
      } else {
        final decoded = jsonDecode(content);
        if (decoded is List) {
          rows = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        } else if (decoded is Map && decoded.containsKey('rows')) {
          rows = (decoded['rows'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        } else {
          throw const FormatException('JSON must be an array of objects or {"rows": [...]}');
        }
      }
    } catch (e) {
      if (mounted) showOdsSnackBar(context, message: 'Could not parse file: $e');
      return;
    }

    if (rows.isEmpty) {
      if (mounted) showOdsSnackBar(context, message: 'File contains no data rows');
      return;
    }

    if (!mounted) return;

    final tables = engine.localTableNames;
    final columns = rows.first.keys.where((k) => k != '_id' && k != '_createdAt').toList();

    final targetTable = await showDialog<String>(
      context: context,
      builder: (ctx) => _ImportTargetDialog(
        tables: tables,
        columns: columns,
        rowCount: rows.length,
        fileName: filePath.split('/').last.split('\\').last,
      ),
    );

    if (targetTable == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final count = await engine.importTableRows(targetTable, rows);
      if (mounted) showOdsSnackBar(context, message: 'Imported $count rows into "$targetTable"');
    } catch (e) {
      if (mounted) showOdsSnackBar(context, message: 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> _parseCsv(String content) {
    final lines = content.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length < 2) return [];
    final headers = lines.first.split(',').map((h) => h.trim()).toList();
    return lines.skip(1).map((line) {
      final values = line.split(',');
      final row = <String, dynamic>{};
      for (var i = 0; i < headers.length && i < values.length; i++) {
        row[headers[i]] = values[i].trim();
      }
      return row;
    }).toList();
  }

  // -----------------------------------------------------------------------
  // Build
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // -- App Settings --
                if (app.settings.isNotEmpty) ...[
                  _SectionHeader(label: 'APP SETTINGS'),
                  _AppSettingsSection(engine: engine, settings: app.settings),
                  const Divider(),
                ],

                // -- User Management --
                if (engine.isMultiUser && engine.authService.isLoggedIn) ...[
                  _SectionHeader(label: 'USERS'),
                  Padding(
                    padding: const EdgeInsets.only(left: 24, bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          engine.authService.isAdmin ? Icons.shield : Icons.person,
                          size: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Signed in as ${engine.authService.currentDisplayName}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (engine.authService.isAdmin && widget.settings.isMultiUserEnabled)
                    FrameworkUserList(
                      authService: context.read<FrameworkAuthService>(),
                    )
                  else if (engine.authService.isAdmin)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      child: Text(
                        'Enable Multi-User Mode in Framework Settings to manage users across apps.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Sign Out'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    onTap: () {
                      engine.authService.logout();
                      engine.clearFormStates();
                      engine.notifyListeners();
                      Navigator.pop(context);
                    },
                  ),
                  const Divider(),
                ],

                // -- Branding --
                _SectionHeader(label: 'BRANDING'),
                _BrandingSection(
                  app: app,
                  settings: widget.settings,
                  onChanged: () => setState(() {}),
                ),
                const Divider(),

                // -- Data (admin-only in multi-user mode) --
                if (!engine.isMultiUser || engine.authService.isAdmin) ...[
                  _SectionHeader(label: 'DATA'),
                  ListTile(
                    leading: const Icon(Icons.backup_outlined),
                    title: const Text('Backup Data'),
                    subtitle: const Text('Save all app data to a file'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    onTap: _backupData,
                  ),
                  ListTile(
                    leading: const Icon(Icons.restore),
                    title: const Text('Restore Data'),
                    subtitle: const Text('Load data from a backup file'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    onTap: _restoreData,
                  ),
                  ListTile(
                    leading: const Icon(Icons.file_upload_outlined),
                    title: const Text('Import Data'),
                    subtitle: const Text('Add rows from a CSV or JSON file'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    onTap: _importData,
                  ),
                  const Divider(),
                ],

                // -- Framework --
                _SectionHeader(label: 'FRAMEWORK'),
                // Theme
                ListTile(
                  leading: Icon(
                    widget.settings.themeMode == ThemeMode.dark
                        ? Icons.dark_mode
                        : widget.settings.themeMode == ThemeMode.light
                            ? Icons.light_mode
                            : Icons.auto_mode,
                  ),
                  title: const Text('Mode'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  trailing: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode, size: 16)),
                      ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.auto_mode, size: 16)),
                      ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode, size: 16)),
                    ],
                    selected: {widget.settings.themeMode},
                    onSelectionChanged: (s) {
                      widget.settings.setThemeMode(s.first);
                      setState(() {});
                    },
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                // Tour
                if (app.tour.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.tour_outlined),
                    title: const Text('Replay Tour'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    onTap: () {
                      Navigator.pop(context);
                      AppTourDialog.show(
                        context,
                        steps: app.tour,
                        appName: app.appName,
                        onNavigateToPage: (pageId) => engine.navigateTo(pageId),
                      );
                    },
                  ),
                // Auto-backup
                SwitchListTile(
                  secondary: const Icon(Icons.backup_outlined),
                  title: const Text('Auto-Backup on Launch'),
                  subtitle: const Text('Back up data each time this app opens'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  value: widget.settings.autoBackup,
                  onChanged: (v) {
                    widget.settings.setAutoBackup(v);
                    setState(() {});
                  },
                ),
                // Backup retention
                if (widget.settings.autoBackup) ...[
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('Keep Last N Backups'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    trailing: DropdownButton<int>(
                      value: widget.settings.backupRetention,
                      underline: const SizedBox.shrink(),
                      items: [1, 3, 5, 10, 20, 50].map((n) {
                        return DropdownMenuItem(value: n, child: Text('$n'));
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          widget.settings.setBackupRetention(v);
                          setState(() {});
                        }
                      },
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: const Text('Backup Folder'),
                    subtitle: Text(
                      widget.settings.backupFolder ?? 'Default (Documents)',
                      overflow: TextOverflow.ellipsis,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    trailing: widget.settings.backupFolder != null
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            tooltip: 'Reset to default',
                            onPressed: () {
                              widget.settings.setBackupFolder(null);
                              setState(() {});
                            },
                          )
                        : null,
                    onTap: () async {
                      final picked = await FilePicker.platform.getDirectoryPath(
                        dialogTitle: 'Choose Backup Folder',
                      );
                      if (picked != null) {
                        widget.settings.setBackupFolder(picked);
                        setState(() {});
                      }
                    },
                  ),
                ],
                // Debug
                ListTile(
                  leading: Icon(
                    engine.debugMode ? Icons.bug_report : Icons.bug_report_outlined,
                    color: engine.debugMode ? Colors.orange : null,
                  ),
                  title: Text(engine.debugMode ? 'Hide Debug Panel' : 'Show Debug Panel'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  onTap: () {
                    engine.toggleDebugMode();
                    setState(() {});
                  },
                ),
                const Divider(),

                // -- Logging --
                _SectionHeader(label: 'LOGGING'),
                _LoggingSection(onChanged: () => setState(() {})),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// App settings section
// ---------------------------------------------------------------------------

class _AppSettingsSection extends StatefulWidget {
  final AppEngine engine;
  final Map<String, OdsAppSetting> settings;
  const _AppSettingsSection({required this.engine, required this.settings});

  @override
  State<_AppSettingsSection> createState() => _AppSettingsSectionState();
}

class _AppSettingsSectionState extends State<_AppSettingsSection> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: widget.settings.entries.map((entry) {
        final key = entry.key;
        final setting = entry.value;
        final currentValue = widget.engine.getAppSetting(key) ?? setting.defaultValue;

        if (setting.type == 'checkbox') {
          return SwitchListTile(
            title: Text(setting.label),
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            value: currentValue == 'true',
            onChanged: (v) async {
              await widget.engine.setAppSetting(key, v ? 'true' : 'false');
              setState(() {});
            },
          );
        }

        if (setting.type == 'select' && (setting.options?.isNotEmpty ?? false)) {
          return ListTile(
            title: Text(setting.label),
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            trailing: DropdownButton<String>(
              value: (setting.options?.contains(currentValue) ?? false) ? currentValue : setting.defaultValue,
              underline: const SizedBox.shrink(),
              items: setting.options!.map((opt) {
                return DropdownMenuItem(value: opt, child: Text(opt));
              }).toList(),
              onChanged: (v) async {
                if (v != null) {
                  await widget.engine.setAppSetting(key, v);
                  setState(() {});
                }
              },
            ),
          );
        }

        // text / number — tap to edit
        return ListTile(
          title: Text(setting.label),
          subtitle: Text(currentValue.isEmpty ? '(not set)' : currentValue),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          onTap: () async {
            final controller = TextEditingController(text: currentValue);
            final newValue = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(setting.label),
                content: TextField(
                  controller: controller,
                  keyboardType: setting.type == 'number'
                      ? TextInputType.number
                      : TextInputType.text,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Enter value',
                    border: const OutlineInputBorder(),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, controller.text),
                    child: const Text('Save'),
                  ),
                ],
              ),
            );
            if (newValue != null) {
              await widget.engine.setAppSetting(key, newValue);
              setState(() {});
            }
          },
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Import target dialog
// ---------------------------------------------------------------------------


// ---------------------------------------------------------------------------
// Branding section — color picker and corner style
// ---------------------------------------------------------------------------

class _BrandingSection extends StatefulWidget {
  final OdsApp app;
  final SettingsStore settings;
  final VoidCallback onChanged;
  const _BrandingSection({required this.app, required this.settings, required this.onChanged});

  @override
  State<_BrandingSection> createState() => _BrandingSectionState();
}

class _BrandingSectionState extends State<_BrandingSection> {
  late String _theme;
  bool _customizeOpen = false;
  bool _brandingOpen = false;
  late TextEditingController _logoController;
  late TextEditingController _fontFamilyController;
  late String _headerStyle;

  static const _customizableTokens = [
    ('primary', 'Primary', 'Main action color — buttons, links, active states.'),
    ('secondary', 'Secondary', 'Supporting color — secondary buttons, tags.'),
    ('accent', 'Accent', 'Highlight color — badges, notifications, emphasis.'),
    ('base100', 'Background', 'Main page background color.'),
    ('baseContent', 'Text', 'Default text color on backgrounds.'),
    ('error', 'Error', 'Danger states — delete buttons, validation errors.'),
    ('success', 'Success', 'Success states — confirmations, positive indicators.'),
  ];

  @override
  void initState() {
    super.initState();
    final overrides = widget.settings.getBrandingOverrides(widget.app.appName);
    _theme = overrides['theme'] ?? widget.app.branding.theme;
    _logoController = TextEditingController(
      text: overrides['logo'] ?? widget.app.branding.logo ?? '',
    );
    _fontFamilyController = TextEditingController(
      text: overrides['fontFamily'] ?? widget.app.branding.fontFamily ?? '',
    );
    _headerStyle = overrides['headerStyle'] ?? widget.app.branding.headerStyle;
  }

  @override
  void dispose() {
    _logoController.dispose();
    _fontFamilyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final overrides = Map<String, String>.from(
      widget.settings.getBrandingOverrides(widget.app.appName),
    );
    overrides['theme'] = _theme;
    if (_logoController.text.trim().isNotEmpty) {
      overrides['logo'] = _logoController.text.trim();
    } else {
      overrides.remove('logo');
    }
    if (_fontFamilyController.text.trim().isNotEmpty) {
      overrides['fontFamily'] = _fontFamilyController.text.trim();
    } else {
      overrides.remove('fontFamily');
    }
    if (_headerStyle != 'light') {
      overrides['headerStyle'] = _headerStyle;
    } else {
      overrides.remove('headerStyle');
    }
    await widget.settings.setBrandingOverrides(widget.app.appName, overrides);
    widget.onChanged();
  }

  Future<void> _reset() async {
    await widget.settings.setBrandingOverrides(widget.app.appName, {});
    setState(() {
      _theme = widget.app.branding.theme;
      _customizeOpen = false;
      _brandingOpen = false;
      _logoController.text = widget.app.branding.logo ?? '';
      _fontFamilyController.text = widget.app.branding.fontFamily ?? '';
      _headerStyle = widget.app.branding.headerStyle;
    });
    widget.onChanged();
  }

  Future<void> _editToken(String token, String label, String description) async {
    final overrides = widget.settings.getBrandingOverrides(widget.app.appName);
    final currentValue = overrides[token] ?? '';

    // Convert existing OKLch override to a Flutter Color, or resolve from theme
    Color initialColor;
    if (currentValue.isNotEmpty) {
      initialColor = ThemeResolver.parseOklch(currentValue) ?? const Color(0xFF888888);
    } else {
      // Load from theme data
      final themeData = await ThemeResolver.loadTheme(_theme);
      final variant = (themeData?['light'] ?? themeData?['dark']) as Map<String, dynamic>?;
      final colors = variant?['colors'] as Map<String, dynamic>?;
      final oklchStr = colors?[token] as String?;
      initialColor = (oklchStr != null ? ThemeResolver.parseOklch(oklchStr) : null) ?? const Color(0xFF888888);
    }

    // Load the paired color for contrast checking
    final pairToken = tokenPairs[token];
    Color? pairedColor;
    if (pairToken != null) {
      if (overrides.containsKey(pairToken)) {
        pairedColor = ThemeResolver.parseOklch(overrides[pairToken]!);
      } else {
        final themeData = await ThemeResolver.loadTheme(_theme);
        final variant = (themeData?['light'] ?? themeData?['dark']) as Map<String, dynamic>?;
        final colors = variant?['colors'] as Map<String, dynamic>?;
        final oklchStr = colors?[pairToken] as String?;
        if (oklchStr != null) pairedColor = ThemeResolver.parseOklch(oklchStr);
      }
    }

    if (!mounted) return;

    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => GridColorPickerDialog(
        initialColor: initialColor,
        pairedColor: pairedColor,
        label: description,
      ),
    );

    if (picked == null || !mounted) return;

    final hex = colorToHex(picked);
    final oklch = _hexToOklch(hex);
    final newOverrides = Map<String, String>.from(overrides);
    newOverrides[token] = oklch;
    newOverrides['theme'] = _theme;
    await widget.settings.setBrandingOverrides(widget.app.appName, newOverrides);
    widget.onChanged();
    setState(() {});
  }

  String _hexToOklch(String hex) {
    // Approximate hex → oklch
    final r = int.parse(hex.substring(1, 3), radix: 16) / 255;
    final g = int.parse(hex.substring(3, 5), radix: 16) / 255;
    final b = int.parse(hex.substring(5, 7), radix: 16) / 255;
    // Simple luminance approximation
    final L = (0.2126 * r + 0.7152 * g + 0.0722 * b);
    // Very rough chroma/hue — better than nothing for a picker
    final maxC = [r, g, b].reduce((a, b) => a > b ? a : b);
    final minC = [r, g, b].reduce((a, b) => a < b ? a : b);
    final C = (maxC - minC) * 0.4; // Scale down
    double H = 0;
    if (maxC == r) H = 60 * ((g - b) / (maxC - minC + 0.001)) % 360;
    else if (maxC == g) H = 60 * (2 + (b - r) / (maxC - minC + 0.001));
    else H = 60 * (4 + (r - g) / (maxC - minC + 0.001));
    if (H < 0) H += 360;
    return 'oklch(${(L * 100).toStringAsFixed(1)}% ${C.toStringAsFixed(3)} ${H.toStringAsFixed(1)})';
  }

  Color _resolveTokenColor(String token, ColorScheme cs) {
    switch (token) {
      case 'primary': return cs.primary;
      case 'secondary': return cs.secondary;
      case 'accent': return cs.tertiary;
      case 'base100': return cs.surface;
      case 'baseContent': return cs.onSurface;
      case 'error': return cs.error;
      case 'success': return const Color(0xFF22C55E); // default green
      default: return const Color(0xFF888888);
    }
  }

  void _showThemePreview(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _ThemePreviewDialog(themeName: _theme),
    );
  }

  Widget _previewLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(3)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 9, fontFamily: 'monospace')),
    ),
  );

  Widget _previewButton(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
  );

  Widget _statusBadge(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
    child: Text(label, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w500)),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overrides = widget.settings.getBrandingOverrides(widget.app.appName);
    final hasOverrides = overrides.isNotEmpty;

    return Column(
      children: [
        // Theme selector
        ThemePickerTile(
          currentTheme: _theme,
          onThemeChanged: (v) {
            setState(() => _theme = v);
            _save();
          },
        ),
        // Customize toggle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              // Preview Theme link
              InkWell(
                onTap: () => _showThemePreview(context),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'Preview Theme',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('|', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
              ),
              // Customize toggle
              InkWell(
                onTap: () => setState(() => _customizeOpen = !_customizeOpen),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _customizeOpen ? Icons.expand_less : Icons.chevron_right,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Customize',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Customize tokens
        if (_customizeOpen) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Override individual design tokens. Tap a token to set a custom value.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 4),
          ..._customizableTokens.map((t) {
            final (token, label, desc) = t;
            final hasValue = overrides.containsKey(token);
            // Resolve current color from override or fall back to theme color scheme
            Color resolvedColor = const Color(0xFF888888);
            if (hasValue) {
              resolvedColor = ThemeResolver.parseOklch(overrides[token]!) ?? resolvedColor;
            } else {
              // Best-effort: map token to current ColorScheme color
              resolvedColor = _resolveTokenColor(token, theme.colorScheme);
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ColorRow(
                label: label,
                token: token,
                color: resolvedColor,
                hasOverride: hasValue,
                onTap: () => _editToken(token, label, desc),
                onReset: hasValue
                    ? () async {
                        final newOverrides = Map<String, String>.from(overrides);
                        newOverrides.remove(token);
                        newOverrides['theme'] = _theme;
                        await widget.settings.setBrandingOverrides(widget.app.appName, newOverrides);
                        widget.onChanged();
                        setState(() {});
                      }
                    : null,
              ),
            );
          }),
        ],
        // App Branding section (collapsible)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('|', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
              ),
              InkWell(
                onTap: () => setState(() => _brandingOpen = !_brandingOpen),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _brandingOpen ? Icons.expand_less : Icons.chevron_right,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'App Branding',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_brandingOpen) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Customize logo, header style, and font. Leave empty to use spec defaults.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _logoController,
              decoration: const InputDecoration(
                labelText: 'Logo URL',
                hintText: 'https://example.com/logo.png',
                helperText: 'Displayed in the app drawer header',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _save(),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Header Style', style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
                const SizedBox(height: 4),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'light', label: Text('Light')),
                    ButtonSegment(value: 'solid', label: Text('Solid')),
                    ButtonSegment(value: 'transparent', label: Text('Transparent')),
                  ],
                  selected: {_headerStyle},
                  onSelectionChanged: (v) {
                    setState(() => _headerStyle = v.first);
                    _save();
                  },
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll(theme.textTheme.labelSmall),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _fontFamilyController,
              decoration: const InputDecoration(
                labelText: 'Font Family',
                hintText: 'e.g., Inter, Georgia',
                helperText: 'Custom font for the app',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _save(),
            ),
          ),
          const SizedBox(height: 8),
        ],
        // Reset
        if (hasOverrides)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _reset,
                child: const Text('Reset to spec defaults', style: TextStyle(fontSize: 12)),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Import target dialog
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Theme preview dialog with light/dark toggle
// ---------------------------------------------------------------------------

class _ThemePreviewDialog extends StatefulWidget {
  final String themeName;
  const _ThemePreviewDialog({required this.themeName});

  @override
  State<_ThemePreviewDialog> createState() => _ThemePreviewDialogState();
}

class _ThemePreviewDialogState extends State<_ThemePreviewDialog> {
  Brightness _mode = Brightness.light;
  ColorScheme? _cs;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pick initial mode from current app theme
    _mode = Theme.of(context).brightness;
    _loadScheme();
  }

  Future<void> _loadScheme() async {
    final cs = await ThemeResolver.resolveColorScheme(widget.themeName, _mode);
    if (mounted && cs != null) setState(() => _cs = cs);
  }

  void _toggleMode() {
    setState(() {
      _mode = _mode == Brightness.light ? Brightness.dark : Brightness.light;
    });
    _loadScheme();
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(3)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 9, fontFamily: 'monospace')),
    ),
  );

  Widget _btn(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
  );

  Widget _badge(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
    child: Text(label, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w500)),
  );

  @override
  Widget build(BuildContext context) {
    final cs = _cs ?? Theme.of(context).colorScheme;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 650),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(child: Text('Theme Preview', style: Theme.of(context).textTheme.titleLarge)),
                // Light/Dark toggle
                SegmentedButton<Brightness>(
                  segments: const [
                    ButtonSegment(value: Brightness.light, icon: Icon(Icons.light_mode, size: 14)),
                    ButtonSegment(value: Brightness.dark, icon: Icon(Icons.dark_mode, size: 14)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) {
                    setState(() => _mode = s.first);
                    _loadScheme();
                  },
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Text('Every design token labeled', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),

              // App bar
              _label('primary + onPrimary'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Icon(Icons.menu, color: cs.onPrimary, size: 20),
                  const SizedBox(width: 12),
                  Text('My App', style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w600)),
                ]),
              ),
              const SizedBox(height: 12),

              // Surface card
              _label('surface + onSurface'),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border.all(color: cs.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Page Heading', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600, fontSize: 16)),
                  Text('Body text on the surface.', style: TextStyle(color: cs.onSurface, fontSize: 12)),
                  const SizedBox(height: 12),

                  _label('outline (border)'),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.outline),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Form input...', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 12)),
                  ),
                  const SizedBox(height: 12),

                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _btn('primary', cs.primary, cs.onPrimary),
                    _btn('secondary', cs.secondary, cs.onSecondary),
                    _btn('tertiary', cs.tertiary, cs.onTertiary),
                  ]),
                  const SizedBox(height: 12),

                  _label('surfaceContainerHighest (neutral)'),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
                    child: Text('Neutral surface — sidebar, muted areas', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
                  ),
                  const SizedBox(height: 12),

                  _label('error + onError'),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    _badge('Error', cs.error, cs.onError),
                    _badge('Surface', cs.surfaceContainer, cs.onSurface),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Import target dialog
// ---------------------------------------------------------------------------

class _ImportTargetDialog extends StatefulWidget {
  final List<String> tables;
  final List<String> columns;
  final int rowCount;
  final String fileName;

  const _ImportTargetDialog({
    required this.tables,
    required this.columns,
    required this.rowCount,
    required this.fileName,
  });

  @override
  State<_ImportTargetDialog> createState() => _ImportTargetDialogState();
}

class _ImportTargetDialogState extends State<_ImportTargetDialog> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    if (widget.tables.isNotEmpty) _selected = widget.tables.first;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Import ${widget.rowCount} rows'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('File: ${widget.fileName}'),
          Text('Columns: ${widget.columns.join(", ")}'),
          const SizedBox(height: 16),
          const Text('Import into table:'),
          const SizedBox(height: 8),
          DropdownButton<String>(
            value: _selected,
            isExpanded: true,
            items: widget.tables.map((t) {
              return DropdownMenuItem(value: t, child: Text(t));
            }).toList(),
            onChanged: (v) => setState(() => _selected = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected != null ? () => Navigator.pop(context, _selected) : null,
          child: const Text('Import'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Logging section
// ---------------------------------------------------------------------------

class _LoggingSection extends StatefulWidget {
  final VoidCallback onChanged;
  const _LoggingSection({required this.onChanged});

  @override
  State<_LoggingSection> createState() => _LoggingSectionState();
}

class _LoggingSectionState extends State<_LoggingSection> {
  LogSettings get _settings => LogService.instance.settings;

  Future<void> _updateLevel(LogLevel level) async {
    await LogService.instance.updateSettings(LogSettings(
      level: level,
      retentionDays: _settings.retentionDays,
    ));
    setState(() {});
    widget.onChanged();
  }

  Future<void> _updateRetention(int days) async {
    await LogService.instance.updateSettings(LogSettings(
      level: _settings.level,
      retentionDays: days,
    ));
    setState(() {});
    widget.onChanged();
  }

  Future<void> _copyLogs() async {
    final text = LogService.instance.exportLogsAsText();
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      showOdsSnackBar(context, message: 'Logs copied to clipboard');
    }
  }

  Future<void> _downloadLogs() async {
    try {
      final path = await LogService.instance.downloadLogs();
      if (mounted) {
        showOdsSnackBar(context, message: 'Logs saved to $path');
      }
    } catch (e) {
      if (mounted) {
        showOdsSnackBar(context, message: 'Download failed: $e');
      }
    }
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Logs'),
        content: const Text(
          'This will permanently delete all stored log entries.\n\nContinue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await LogService.instance.clearLogs();
    setState(() {});
    widget.onChanged();
    if (mounted) {
      showOdsSnackBar(context, message: 'Logs cleared');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final logCount = LogService.instance.logCount;

    return Column(
      children: [
        // Log Level
        ListTile(
          leading: const Icon(Icons.filter_list),
          title: const Text('Log Level'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          trailing: DropdownButton<LogLevel>(
            value: _settings.level,
            underline: const SizedBox.shrink(),
            items: LogLevel.values.map((level) {
              return DropdownMenuItem(
                value: level,
                child: Text(level.name[0].toUpperCase() + level.name.substring(1)),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null) _updateLevel(v);
            },
          ),
        ),
        // Retention
        ListTile(
          leading: const Icon(Icons.schedule),
          title: const Text('Retention'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          trailing: DropdownButton<int>(
            value: [1, 3, 7, 14, 30].contains(_settings.retentionDays)
                ? _settings.retentionDays
                : 7,
            underline: const SizedBox.shrink(),
            items: [1, 3, 7, 14, 30].map((n) {
              return DropdownMenuItem(
                value: n,
                child: Text('$n ${n == 1 ? 'day' : 'days'}'),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null) _updateRetention(v);
            },
          ),
        ),
        // Export Logs
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Export Logs'),
          subtitle: Text('$logCount entries'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy'),
                onPressed: logCount > 0 ? _copyLogs : null,
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Download'),
                onPressed: logCount > 0 ? _downloadLogs : null,
              ),
            ],
          ),
        ),
        // Clear Logs
        ListTile(
          leading: Icon(Icons.delete_outline, color: colorScheme.error),
          title: Text(
            'Clear Logs',
            style: TextStyle(color: colorScheme.error),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          onTap: logCount > 0 ? _clearLogs : null,
        ),
      ],
    );
  }
}

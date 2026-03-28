import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/app_engine.dart';
import '../engine/settings_store.dart';
import '../models/ods_app.dart';
import '../models/ods_app_setting.dart';
import '../renderer/snackbar_helper.dart';
import '../screens/app_tour_dialog.dart';
import '../screens/user_management_screen.dart';

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
                        Icon(Icons.person, size: 16, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Text(
                          'Signed in as ${engine.authService.currentUsername}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (engine.authService.isAdmin)
                    ListTile(
                      leading: const Icon(Icons.people_outline),
                      title: const Text('Manage Users'),
                      subtitle: const Text('Add, remove, and manage user accounts'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => UserManagementScreen(
                            authService: engine.authService,
                            availableRoles: app.auth.allRoles,
                          ),
                        ));
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Sign Out'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    onTap: () {
                      engine.authService.logout();
                      engine.notifyListeners();
                      Navigator.pop(context);
                    },
                  ),
                  const Divider(),
                ],

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
                  title: const Text('Theme'),
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

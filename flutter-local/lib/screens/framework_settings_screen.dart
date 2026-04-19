import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/framework_auth_service.dart';
import '../engine/settings_store.dart';
import '../widgets/framework_user_list.dart';
import '../widgets/theme_picker_dialog.dart';
import 'framework_admin_setup_screen.dart';

/// Framework-level settings screen, accessible from the Welcome/Home screen.
///
/// Shows settings that apply across all apps: theme, backup preferences,
/// and the default branding (for new apps without a branding block).
///
/// This is separate from the per-app SettingsScreen which also includes
/// app-specific settings, user management, and data operations.
class FrameworkSettingsScreen extends StatefulWidget {
  final SettingsStore settings;

  const FrameworkSettingsScreen({super.key, required this.settings});

  @override
  State<FrameworkSettingsScreen> createState() => _FrameworkSettingsScreenState();
}

class _FrameworkSettingsScreenState extends State<FrameworkSettingsScreen> {
  SettingsStore get settings => widget.settings;

  bool get _isAdmin {
    final fwAuth = context.read<FrameworkAuthService>();
    return !settings.isMultiUserEnabled || fwAuth.isAdmin;
  }

  Future<void> _changeDataFolder() async {
    final picked = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose ODS Data Folder',
    );
    if (picked == null || !mounted) return;

    final currentDir = await settings.odsDirectory;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.drive_file_move_outlined, size: 40),
        title: const Text('Move Data?'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('All app databases, settings, logs, and backups will be copied to:'),
              const SizedBox(height: 8),
              _PathBox(path: picked),
              const SizedBox(height: 12),
              const Text('and removed from:'),
              const SizedBox(height: 8),
              _PathBox(path: currentDir.path),
              const SizedBox(height: 12),
              Text(
                'Make sure no ODS app is open. The move cannot be undone.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Move')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _runMove(() => settings.moveStorageFolder(picked));
  }

  Future<void> _resetDataFolder() async {
    final legacyDir = await getLegacyOdsDirectory();
    final currentDir = await settings.odsDirectory;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.restore, size: 40),
        title: const Text('Reset Data Folder?'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('All data will be moved back to the default location:'),
              const SizedBox(height: 8),
              _PathBox(path: legacyDir.path),
              const SizedBox(height: 12),
              const Text('and removed from:'),
              const SizedBox(height: 8),
              _PathBox(path: currentDir.path),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _runMove(() => settings.resetStorageFolder());
  }

  Future<void> _runMove(Future<void> Function() action) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    );

    String? error;
    try {
      await action();
    } catch (e) {
      error = e.toString();
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss spinner

    if (error != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.error_outline, size: 40),
          title: const Text('Move Failed'),
          content: Text(error!),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data folder updated')),
      );
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Framework Settings'),
      ),
      body: ListView(
        children: [
          // -- Appearance --
          _SectionHeader(label: 'APPEARANCE'),
          ListTile(
            leading: Icon(
              settings.themeMode == ThemeMode.dark
                  ? Icons.dark_mode
                  : settings.themeMode == ThemeMode.light
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
              selected: {settings.themeMode},
              onSelectionChanged: (s) {
                settings.setThemeMode(s.first);
                setState(() {});
              },
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          // Default theme
          ThemePickerTile(
            currentTheme: settings.defaultTheme,
            title: 'Default Theme',
            subtitle: 'Used as the initial theme for new apps',
            onThemeChanged: (v) {
              settings.setDefaultTheme(v);
              setState(() {});
            },
          ),
          const Divider(),

          // -- Backup --
          _SectionHeader(label: 'BACKUP'),
          SwitchListTile(
            secondary: const Icon(Icons.backup_outlined),
            title: const Text('Auto-Backup on Launch'),
            subtitle: const Text('Back up data each time an app opens'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            value: settings.autoBackup,
            onChanged: (v) {
              settings.setAutoBackup(v);
              setState(() {});
            },
          ),
          if (settings.autoBackup) ...[
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Keep Last N Backups'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              trailing: DropdownButton<int>(
                value: settings.backupRetention,
                underline: const SizedBox.shrink(),
                items: [1, 3, 5, 10, 20, 50].map((n) {
                  return DropdownMenuItem(value: n, child: Text('$n'));
                }).toList(),
                onChanged: (v) {
                  if (v != null) {
                    settings.setBackupRetention(v);
                    setState(() {});
                  }
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Backup Folder'),
              subtitle: Text(
                settings.backupFolder ?? 'Default (Documents)',
                overflow: TextOverflow.ellipsis,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              trailing: settings.backupFolder != null
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      tooltip: 'Reset to default',
                      onPressed: () {
                        settings.setBackupFolder(null);
                        setState(() {});
                      },
                    )
                  : null,
              onTap: () async {
                final picked = await FilePicker.platform.getDirectoryPath(
                  dialogTitle: 'Choose Backup Folder',
                );
                if (picked != null) {
                  settings.setBackupFolder(picked);
                  setState(() {});
                }
              },
            ),
          ],
          // -- Storage (admin-only) --
          if (_isAdmin) ...[
            const Divider(),
            _SectionHeader(label: 'STORAGE'),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Data Folder'),
              subtitle: Text(
                settings.storageFolder ?? 'Default (Documents / One Does Simply)',
                overflow: TextOverflow.ellipsis,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              trailing: settings.storageFolder != null
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      tooltip: 'Reset to default',
                      onPressed: () => _resetDataFolder(),
                    )
                  : null,
              onTap: () => _changeDataFolder(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'All app databases, user data, backups, and settings are stored in this folder. '
                'Changing this moves all existing data to the new location.',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // -- Users & Multi-User (admin-only) --
          if (_isAdmin) ...[
          const Divider(),
          _SectionHeader(label: 'USERS'),
          SwitchListTile(
            secondary: const Icon(Icons.people_outline),
            title: const Text('Multi-User Mode'),
            subtitle: Text(
              settings.isMultiUserEnabled
                  ? 'Enabled — requires login on every launch'
                  : 'Enable to require login, manage users, and restrict access.',
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            value: settings.isMultiUserEnabled,
            onChanged: settings.isMultiUserEnabled
                ? null
                : (v) async {
                    if (!v) return;
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Enable Multi-User Mode'),
                        content: const Text(
                          'This will require a login on every launch. '
                          'You\'ll create an admin account next.\n\n'
                          'Multi-user mode cannot be disabled once users exist.\n\n'
                          'Continue?',
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enable')),
                        ],
                      ),
                    );
                    if (confirmed != true || !mounted) return;

                    await settings.setMultiUserEnabled(true);
                    final fwAuth = context.read<FrameworkAuthService>();
                    await fwAuth.initialize(storageFolder: settings.storageFolder);

                    if (!mounted) return;
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FrameworkAdminSetupScreen(
                          authService: fwAuth,
                          onSetupComplete: () => Navigator.pop(context),
                          onCancel: () {
                            settings.setMultiUserEnabled(false);
                            Navigator.pop(context);
                          },
                        ),
                      ),
                    );
                    setState(() {});
                  },
          ),
          if (settings.isMultiUserEnabled) ...[
            FrameworkUserList(authService: context.read<FrameworkAuthService>()),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              onTap: () {
                final fwAuth = context.read<FrameworkAuthService>();
                fwAuth.logout();
                Navigator.pop(context);
              },
            ),
          ],
          ], // end _isAdmin
          const Divider(),

          // -- About --
          _SectionHeader(label: 'ABOUT'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('ODS Flutter Local Framework'),
            subtitle: const Text('Vibe Coding with Guardrails'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'One Does Simply',
                applicationVersion: 'Flutter Local Framework',
                applicationLegalese: 'Open source — github.com/One-does-simply',
                children: [
                  const SizedBox(height: 16),
                  const Text(
                    'A local implementation that runs completely on-device. '
                    'No internet or cloud required. Your data stays on your device.',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _PathBox extends StatelessWidget {
  final String path;
  const _PathBox({required this.path});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        path,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
      ),
    );
  }
}

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

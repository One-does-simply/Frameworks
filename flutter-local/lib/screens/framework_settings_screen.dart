import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../engine/settings_store.dart';

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
            title: const Text('Theme'),
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
          const Divider(),

          // -- About --
          _SectionHeader(label: 'ABOUT'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('ODS Flutter Local Framework'),
            subtitle: const Text('Vibe Coding with Guardrails'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          ),
          const SizedBox(height: 24),
        ],
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

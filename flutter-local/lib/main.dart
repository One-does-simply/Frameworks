import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'debug/debug_panel.dart';
import 'engine/app_engine.dart';
import 'engine/loaded_apps_store.dart';
import 'engine/settings_store.dart';
import 'loader/spec_loader.dart';
import 'renderer/page_renderer.dart';
import 'screens/app_help_screen.dart';
import 'screens/app_tour_dialog.dart';
import 'screens/ods_about_screen.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

void main() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
    debugPrint('Stack: ${details.stack}');
  };

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppEngine()),
        ChangeNotifierProvider(create: (_) => SettingsStore()),
      ],
      child: const OdsFrameworkApp(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Color palette — a refined indigo/slate palette for a premium feel
// ---------------------------------------------------------------------------

const _seedColor = Color(0xFF4F46E5); // Indigo 600

ColorScheme _lightScheme() => ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    );

ColorScheme _darkScheme() => ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    );

ThemeData _buildTheme(ColorScheme colorScheme) {
  final isDark = colorScheme.brightness == Brightness.dark;
  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    fontFamily: 'Segoe UI',
    scaffoldBackgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
    ),
    dividerTheme: DividerThemeData(
      color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

// ---------------------------------------------------------------------------
// Root widget
// ---------------------------------------------------------------------------

class OdsFrameworkApp extends StatefulWidget {
  const OdsFrameworkApp({super.key});

  @override
  State<OdsFrameworkApp> createState() => _OdsFrameworkAppState();
}

class _OdsFrameworkAppState extends State<OdsFrameworkApp> {
  bool _settingsReady = false;

  @override
  void initState() {
    super.initState();
    _initSettings();
  }

  Future<void> _initSettings() async {
    final settings = context.read<SettingsStore>();
    await settings.initialize();
    if (mounted) setState(() => _settingsReady = true);
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AppEngine>();
    final settings = context.watch<SettingsStore>();
    final appName = engine.app?.appName ?? 'One Does Simply';

    if (!_settingsReady) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(_lightScheme()),
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(_lightScheme()),
      darkTheme: _buildTheme(_darkScheme()),
      themeMode: settings.themeMode,
      home: engine.app == null ? const WelcomeScreen() : const AppShell(),
    );
  }
}

// ---------------------------------------------------------------------------
// Welcome / Home Screen
// ---------------------------------------------------------------------------

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _loadedAppsStore = LoadedAppsStore();
  bool _isLoading = false;
  bool _storeReady = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initStore();
  }

  Future<void> _initStore() async {
    await _loadedAppsStore.initialize();
    if (mounted) setState(() => _storeReady = true);
  }

  Future<void> _runSpec(String jsonString) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final engine = context.read<AppEngine>();
    final success = await engine.loadSpec(jsonString);

    if (!success && mounted) {
      setState(() {
        _isLoading = false;
        _error = engine.loadError;
      });
    }
  }

  Future<void> _pickFile() async {
    try {
      final json = await SpecLoader().loadFromFilePicker();
      if (json != null) await _handleNewSpec(json);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load file: $e');
    }
  }

  Future<void> _loadFromUrl() async {
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => _UrlInputDialog(),
    );
    if (url == null || url.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final json = await SpecLoader().loadFromUrl(url);
      setState(() => _isLoading = false);
      await _handleNewSpec(json);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load from URL: $e';
        });
      }
    }
  }

  Future<void> _handleNewSpec(String specJson) async {
    if (!mounted) return;

    String appName = 'Untitled App';
    String appDescription = '';
    try {
      final parsed = jsonDecode(specJson) as Map<String, dynamic>;
      appName = parsed['appName'] as String? ?? appName;
      final help = parsed['help'] as Map<String, dynamic>?;
      if (help != null) {
        appDescription = help['overview'] as String? ?? '';
      }
    } catch (_) {}

    final action = await showDialog<_NewSpecAction>(
      context: context,
      builder: (ctx) => _RunOrAddDialog(appName: appName),
    );

    if (action == null) return;

    if (action == _NewSpecAction.addAndRun) {
      await _loadedAppsStore.addApp(
        name: appName,
        description: appDescription,
        specJson: specJson,
      );
      if (mounted) setState(() {});
    }

    await _runSpec(specJson);
  }

  Future<void> _removeApp(LoadedAppEntry app) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove App'),
        content: Text('Remove "${app.name}" from your apps?'),
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _loadedAppsStore.removeApp(app.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _editApp(LoadedAppEntry app) async {
    final controller = TextEditingController(text: app.specJson);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _SpecEditorDialog(controller: controller, appName: app.name),
    );
    controller.dispose();

    if (result != null && result != app.specJson) {
      String newName = app.name;
      String newDesc = app.description;
      try {
        final parsed = jsonDecode(result) as Map<String, dynamic>;
        newName = parsed['appName'] as String? ?? newName;
        final help = parsed['help'] as Map<String, dynamic>?;
        if (help != null) {
          newDesc = help['overview'] as String? ?? '';
        }
      } catch (_) {}

      await _loadedAppsStore.updateApp(
        id: app.id,
        name: newName,
        description: newDesc,
        specJson: result,
      );
      if (mounted) setState(() {});
    }
  }

  void _showCreateNew() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _CreateNewScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final settings = context.watch<SettingsStore>();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // -- Hero header --
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF1E1B4B), const Color(0xFF0F172A)]
                      : [const Color(0xFF4F46E5), const Color(0xFF7C3AED)],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top bar with settings
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _ThemeToggle(
                            themeMode: settings.themeMode,
                            onChanged: (mode) => settings.setThemeMode(mode),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Title
                      Text(
                        'One Does Simply',
                        style: theme.textTheme.headlineLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Vibe Coding with Guardrails',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Flutter Local Framework',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Description
                      Text(
                        'A local implementation of the One Does Simply Framework that runs '
                        'completely locally — no Internet or Cloud required.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const OdsAboutScreen()),
                        ),
                        icon: const Icon(Icons.arrow_forward, size: 16),
                        label: const Text('Learn More'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // -- My Apps section --
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
              child: Row(
                children: [
                  Text(
                    'My Apps',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  _AddAppButton(
                    onPickFile: _pickFile,
                    onLoadUrl: _loadFromUrl,
                    onCreateNew: _showCreateNew,
                  ),
                ],
              ),
            ),
          ),

          // -- Loading / Error states --
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),

          if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: colorScheme.onErrorContainer, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, size: 18, color: colorScheme.onErrorContainer),
                        onPressed: () => setState(() => _error = null),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // -- App list --
          if (!_storeReady)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_loadedAppsStore.apps.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  children: [
                    Icon(Icons.apps_outlined, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      'No apps yet',
                      style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap + to add your first app',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final app = _loadedAppsStore.apps[index];
                    return _AppListTile(
                      app: app,
                      isLoading: _isLoading,
                      onRun: () => _runSpec(app.specJson),
                      onEdit: app.isBundled ? null : () => _editApp(app),
                      onRemove: app.isBundled ? null : () => _removeApp(app),
                    );
                  },
                  childCount: _loadedAppsStore.apps.length,
                ),
              ),
            ),

          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Theme toggle widget
// ---------------------------------------------------------------------------

class _ThemeToggle extends StatelessWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onChanged;

  const _ThemeToggle({required this.themeMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _themeButton(Icons.light_mode, ThemeMode.light, 'Light'),
          _themeButton(Icons.auto_mode, ThemeMode.system, 'Auto'),
          _themeButton(Icons.dark_mode, ThemeMode.dark, 'Dark'),
        ],
      ),
    );
  }

  Widget _themeButton(IconData icon, ThemeMode mode, String tooltip) {
    final isActive = themeMode == mode;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onChanged(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: isActive
              ? BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: Icon(icon, size: 18, color: Colors.white.withValues(alpha: isActive ? 1.0 : 0.5)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add App button (dropdown with options)
// ---------------------------------------------------------------------------

class _AddAppButton extends StatelessWidget {
  final VoidCallback onPickFile;
  final VoidCallback onLoadUrl;
  final VoidCallback onCreateNew;

  const _AddAppButton({
    required this.onPickFile,
    required this.onLoadUrl,
    required this.onCreateNew,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'file':
            onPickFile();
          case 'url':
            onLoadUrl();
          case 'new':
            onCreateNew();
        }
      },
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          value: 'file',
          child: ListTile(
            leading: Icon(Icons.folder_open),
            title: Text('Open Spec File'),
            subtitle: Text('Load a .json file from your device'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'url',
          child: ListTile(
            leading: Icon(Icons.link),
            title: Text('Load from URL'),
            subtitle: Text('Fetch a spec from the web'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'new',
          child: ListTile(
            leading: Icon(Icons.auto_awesome),
            title: Text('Create New'),
            subtitle: Text('Build an app with AI assistance'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 18, color: Theme.of(context).colorScheme.onPrimary),
            const SizedBox(width: 6),
            Text(
              'Add App',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// App list tile — rich card with run/edit/remove actions
// ---------------------------------------------------------------------------

class _AppListTile extends StatelessWidget {
  final LoadedAppEntry app;
  final bool isLoading;
  final VoidCallback onRun;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  const _AppListTile({
    required this.app,
    required this.isLoading,
    required this.onRun,
    this.onEdit,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isLoading ? null : onRun,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // App icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    app.isBundled ? Icons.apps_rounded : Icons.description_outlined,
                    color: colorScheme.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                // App info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (app.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          app.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        app.isBundled ? 'Example' : 'Custom',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: app.isBundled
                              ? colorScheme.primary
                              : colorScheme.tertiary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Action buttons
                if (onEdit != null || onRemove != null) ...[
                  if (onEdit != null)
                    IconButton(
                      icon: Icon(Icons.edit_outlined, size: 20, color: colorScheme.onSurfaceVariant),
                      tooltip: 'Edit Spec',
                      onPressed: onEdit,
                    ),
                  if (onRemove != null)
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 20, color: colorScheme.error),
                      tooltip: 'Remove',
                      onPressed: onRemove,
                    ),
                ],
                Icon(Icons.play_arrow_rounded, color: colorScheme.primary, size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// URL input dialog
// ---------------------------------------------------------------------------

class _UrlInputDialog extends StatefulWidget {
  @override
  State<_UrlInputDialog> createState() => _UrlInputDialogState();
}

class _UrlInputDialogState extends State<_UrlInputDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Load from URL'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'https://example.com/my-app.json',
        ),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Load'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// "Just Run" vs "Add to My Apps" dialog
// ---------------------------------------------------------------------------

enum _NewSpecAction { justRun, addAndRun }

class _RunOrAddDialog extends StatelessWidget {
  final String appName;
  const _RunOrAddDialog({required this.appName});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(appName),
      content: const Text('What would you like to do with this app?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(context, _NewSpecAction.justRun),
          child: const Text('Just Run'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _NewSpecAction.addAndRun),
          child: const Text('Add to My Apps & Run'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Create New screen — Build Helper prompt with copy-to-clipboard
// ---------------------------------------------------------------------------

class _CreateNewScreen extends StatefulWidget {
  const _CreateNewScreen();

  @override
  State<_CreateNewScreen> createState() => _CreateNewScreenState();
}

class _CreateNewScreenState extends State<_CreateNewScreen> {
  String? _prompt;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _loadPrompt();
  }

  Future<void> _loadPrompt() async {
    final text = await rootBundle.loadString('assets/build-helper-prompt.txt');
    if (mounted) setState(() => _prompt = text);
  }

  Future<void> _copyPrompt() async {
    if (_prompt == null) return;
    await Clipboard.setData(ClipboardData(text: _prompt!));
    if (mounted) {
      setState(() => _copied = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Build Helper prompt copied to clipboard!'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Create a New App')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero section
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [const Color(0xFF1E1B4B), const Color(0xFF312E81)]
                          : [const Color(0xFF4F46E5), const Color(0xFF7C3AED)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.auto_awesome, size: 36, color: Colors.white),
                      const SizedBox(height: 12),
                      Text(
                        'Build with AI Assistance',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Use any AI chatbot to create your ODS app. Just paste the Build Helper '
                        'prompt and describe the app you want — the AI will generate a complete, '
                        'valid spec file for you.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Steps
                Text(
                  'How It Works',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                _StepTile(
                  number: '1',
                  colorScheme: colorScheme,
                  title: 'Copy the Build Helper Prompt',
                  body: 'Tap the button below to copy the ODS Build Helper prompt to your clipboard.',
                ),
                _StepTile(
                  number: '2',
                  colorScheme: colorScheme,
                  title: 'Open Any AI Chatbot',
                  body: 'Works with ChatGPT, Claude, Gemini, Copilot, or any other AI assistant — free tiers included.',
                ),
                _StepTile(
                  number: '3',
                  colorScheme: colorScheme,
                  title: 'Paste & Describe Your App',
                  body: 'Paste the prompt as your first message, then describe the app you want to build. '
                      'The AI will walk you through it step by step.',
                ),
                _StepTile(
                  number: '4',
                  colorScheme: colorScheme,
                  title: 'Save & Load',
                  body: 'Save the generated JSON as a .json file, then open it here with "Open Spec File".',
                ),

                const SizedBox(height: 28),

                // Copy button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _prompt == null ? null : _copyPrompt,
                    icon: Icon(_copied ? Icons.check : Icons.copy),
                    label: Text(_copied ? 'Copied!' : 'Copy Build Helper Prompt'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // What's in the prompt
                Card(
                  child: ExpansionTile(
                    leading: Icon(Icons.visibility_outlined, color: colorScheme.primary),
                    title: const Text('Preview the prompt'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black26 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        constraints: const BoxConstraints(maxHeight: 300),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _prompt ?? 'Loading...',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final String number;
  final ColorScheme colorScheme;
  final String title;
  final String body;

  const _StepTile({
    required this.number,
    required this.colorScheme,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(body, style: theme.textTheme.bodySmall?.copyWith(height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Spec editor dialog (for editing user-added app specs)
// ---------------------------------------------------------------------------

class _SpecEditorDialog extends StatelessWidget {
  final TextEditingController controller;
  final String appName;

  const _SpecEditorDialog({required this.controller, required this.appName});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit $appName Spec'),
      content: SizedBox(
        width: 600,
        height: 400,
        child: TextField(
          controller: controller,
          maxLines: null,
          expands: true,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(12),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Main App Shell (after spec is loaded)
// ---------------------------------------------------------------------------

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _tourChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_tourChecked) {
      _tourChecked = true;
      final engine = context.read<AppEngine>();
      final settings = context.read<SettingsStore>();
      final app = engine.app;
      if (app != null && app.tour.isNotEmpty) {
        // Build a stable ID from the app name for tour tracking
        final appId = app.appName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
        if (!settings.hasSeenTour(appId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            settings.markTourSeen(appId);
            AppTourDialog.show(
              context,
              steps: app.tour,
              appName: app.appName,
              onNavigateToPage: (pageId) => engine.navigateTo(pageId),
            );
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AppEngine>();
    final settings = context.watch<SettingsStore>();
    final app = engine.app!;
    final currentPageId = engine.currentPageId;
    final currentPage = currentPageId != null ? app.pages[currentPageId] : null;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (engine.canGoBack())
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => engine.goBack(),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.arrow_back, size: 20),
                  ),
                ),
              ),
            Flexible(child: Text(currentPage?.title ?? app.appName)),
          ],
        ),
        // Always show the hamburger menu (don't let back nav replace it)
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          // Help is the only button in the top right
          if (app.help != null)
            IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: 'Help',
              onPressed: () {
                final pageTitles = app.pages.map(
                  (key, page) => MapEntry(key, page.title),
                );
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AppHelpScreen(
                      help: app.help!,
                      appName: app.appName,
                      pageTitles: pageTitles,
                    ),
                  ),
                );
              },
            ),
        ],
      ),

      // -- Navigation drawer with settings --
      drawer: Drawer(
        child: ListView(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colorScheme.primary, colorScheme.tertiary],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    app.appName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (app.help != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        app.help!.overview.length > 80
                            ? '${app.help!.overview.substring(0, 80)}...'
                            : app.help!.overview,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // -- Navigation --
            if (app.menu.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 8, bottom: 4),
                child: Text(
                  'NAVIGATION',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ...app.menu.map((item) {
              final isSelected = item.mapsTo == currentPageId;
              return ListTile(
                title: Text(item.label),
                selected: isSelected,
                selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                onTap: () {
                  Navigator.pop(context);
                  engine.navigateTo(item.mapsTo);
                },
              );
            }),
            const Divider(),
            // -- Settings section --
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 4, bottom: 4),
              child: Text(
                'SETTINGS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ),
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
            ListTile(
              leading: Icon(
                engine.debugMode ? Icons.bug_report : Icons.bug_report_outlined,
                color: engine.debugMode ? Colors.orange : null,
              ),
              title: Text(engine.debugMode ? 'Hide Debug Panel' : 'Show Debug Panel'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              onTap: () {
                Navigator.pop(context);
                engine.toggleDebugMode();
              },
            ),
            // Theme sub-section
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
                onSelectionChanged: (s) => settings.setThemeMode(s.first),
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Close App'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              onTap: () async {
                Navigator.pop(context);
                await engine.reset();
              },
            ),
          ],
        ),
      ),

      // -- Body --
      body: Column(
        children: [
          if (app.help != null &&
              currentPageId != null &&
              app.help!.pages.containsKey(currentPageId))
            _PageHelpBanner(helpText: app.help!.pages[currentPageId]!),
          Expanded(
            child: currentPage != null
                ? PageRenderer(page: currentPage)
                : const Center(child: Text('Page not found')),
          ),
          if (engine.debugMode)
            const SizedBox(
              height: 250,
              child: DebugPanel(),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page Help Banner
// ---------------------------------------------------------------------------

class _PageHelpBanner extends StatefulWidget {
  final String helpText;
  const _PageHelpBanner({required this.helpText});

  @override
  State<_PageHelpBanner> createState() => _PageHelpBannerState();
}

class _PageHelpBannerState extends State<_PageHelpBanner> {
  bool _dismissed = false;

  @override
  void didUpdateWidget(covariant _PageHelpBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.helpText != widget.helpText) {
      _dismissed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(color: colorScheme.primaryContainer),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline, size: 18, color: colorScheme.onPrimaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.helpText,
              style: TextStyle(fontSize: 13, color: colorScheme.onPrimaryContainer),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: colorScheme.onPrimaryContainer),
            onPressed: () => setState(() => _dismissed = true),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

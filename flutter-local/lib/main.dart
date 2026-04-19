import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'debug/debug_panel.dart';
import 'engine/app_engine.dart';
import 'engine/log_service.dart';
import 'engine/backup_manager.dart';
import 'engine/framework_auth_service.dart';
import 'engine/theme_resolver.dart';
import 'engine/code_generator.dart';
import 'engine/data_exporter.dart';
import 'engine/data_store.dart';
import 'engine/loaded_apps_store.dart';
import 'parser/spec_parser.dart';
import 'engine/settings_store.dart';
import 'loader/spec_loader.dart';
import 'models/ods_app.dart';
import 'models/ods_app_setting.dart';
import 'renderer/page_renderer.dart';
import 'renderer/snackbar_helper.dart';
import 'screens/admin_setup_screen.dart';
import 'screens/app_help_screen.dart';
import 'screens/app_tour_dialog.dart';
import 'screens/login_screen.dart';
import 'screens/ods_about_screen.dart';
import 'screens/framework_admin_setup_screen.dart';
import 'screens/framework_login_screen.dart';
import 'screens/framework_settings_screen.dart';
import 'screens/quick_build_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/framework_user_list.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    logError('Flutter', 'Unhandled error: ${details.exception}', details.stack?.toString());
  };

  // SettingsStore must initialize BEFORE anything that writes to disk so the
  // bootstrap-chosen storage folder is known up-front.
  final settings = SettingsStore();
  await settings.initialize();

  // Log service uses getOdsDirectory() which respects the bootstrap.
  await LogService.instance.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppEngine()),
        ChangeNotifierProvider<SettingsStore>.value(value: settings),
        ChangeNotifierProvider(create: (_) => FrameworkAuthService()),
      ],
      child: const OdsFrameworkApp(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Color palette — a refined indigo/slate palette for a premium feel
// ---------------------------------------------------------------------------

const _defaultSeedColor = Color(0xFF4F46E5); // Indigo 600

ColorScheme _lightScheme([Color? seed]) => ColorScheme.fromSeed(
      seedColor: seed ?? _defaultSeedColor,
      brightness: Brightness.light,
    );

ColorScheme _darkScheme([Color? seed]) => ColorScheme.fromSeed(
      seedColor: seed ?? _defaultSeedColor,
      brightness: Brightness.dark,
    );

ThemeData _buildTheme(ColorScheme colorScheme, {String? fontFamily, double borderRadius = 12, String headerStyle = 'light'}) {
  final isDark = colorScheme.brightness == Brightness.dark;
  final radius = borderRadius;

  // Resolve AppBar theme based on headerStyle
  AppBarTheme appBarTheme;
  switch (headerStyle) {
    case 'solid':
      appBarTheme = AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      );
      break;
    case 'transparent':
      appBarTheme = AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
      );
      break;
    default: // 'light'
      appBarTheme = AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
      );
  }

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    fontFamily: fontFamily ?? 'Segoe UI',
    scaffoldBackgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
    appBarTheme: appBarTheme,
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius - 2)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius - 2)),
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
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      width: 450,
      dismissDirection: DismissDirection.horizontal,
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
  ColorScheme? _resolvedLightScheme;
  ColorScheme? _resolvedDarkScheme;
  double _resolvedRadius = 12.0;
  String? _resolvedThemeName;

  @override
  void initState() {
    super.initState();
    _initSettings();
  }

  Future<void> _resolveTheme(String themeName) async {
    final light = await ThemeResolver.resolveColorScheme(themeName, Brightness.light);
    final dark = await ThemeResolver.resolveColorScheme(themeName, Brightness.dark);
    final radius = await ThemeResolver.resolveRadius(themeName);
    if (mounted) {
      setState(() {
        _resolvedLightScheme = light;
        _resolvedDarkScheme = dark;
        _resolvedRadius = radius;
      });
    }
  }

  Future<void> _initSettings() async {
    final settings = context.read<SettingsStore>();
    await settings.initialize();

    // Initialize framework auth if multi-user is enabled
    if (settings.isMultiUserEnabled) {
      final fwAuth = context.read<FrameworkAuthService>();
      await fwAuth.initialize(storageFolder: settings.storageFolder);
    }

    if (mounted) setState(() => _settingsReady = true);

    // Brand new install: prompt the user to pick (or accept) a data folder.
    if (!settings.hasPickedStorageFolder) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showFirstRunStoragePrompt();
      });
    }
  }

  Future<void> _showFirstRunStoragePrompt() async {
    if (!mounted) return;
    final settings = context.read<SettingsStore>();
    if (settings.hasPickedStorageFolder) return;

    final defaultDir = await settings.odsDirectory;
    if (!mounted) return;

    String chosenPath = defaultDir.path;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          icon: Icon(
            Icons.folder_outlined,
            size: 40,
            color: Theme.of(ctx).colorScheme.primary,
          ),
          title: const Text('Choose Data Folder'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ODS stores app databases, settings, backups, and logs in this '
                  'folder. You can change it later from Framework Settings.',
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    chosenPath,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Browse...'),
                    onPressed: () async {
                      final picked = await FilePicker.platform.getDirectoryPath(
                        dialogTitle: 'Choose ODS Data Folder',
                      );
                      if (picked != null) {
                        setDialogState(() => chosenPath = picked);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () async {
                final current = await settings.odsDirectory;
                final differs = !p.equals(current.path, chosenPath);
                try {
                  if (differs) {
                    await settings.moveStorageFolder(chosenPath);
                  } else {
                    await settings.markStoragePromptShown();
                  }
                } catch (e) {
                  debugPrint('First-run storage setup failed: $e');
                  await settings.markStoragePromptShown();
                }
                if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
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

    // Derive theme from app branding with user overrides
    final branding = engine.app?.branding;
    final userOverrides = engine.app != null
        ? settings.getBrandingOverrides(engine.app!.appName)
        : <String, String>{};
    final themeName = userOverrides['theme'] ?? branding?.theme ?? 'indigo';
    final fontFamily = userOverrides['fontFamily'] ?? branding?.fontFamily;
    final headerStyle = userOverrides['headerStyle'] ?? branding?.headerStyle ?? 'light';

    // Resolve theme asynchronously (cached after first load)
    if (themeName != _resolvedThemeName) {
      _resolvedThemeName = themeName;
      _resolveTheme(themeName);
    }

    final lightScheme = _resolvedLightScheme ?? _lightScheme();
    final darkScheme = _resolvedDarkScheme ?? _darkScheme();
    final borderRadius = _resolvedRadius;

    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(lightScheme, fontFamily: fontFamily, borderRadius: borderRadius, headerStyle: headerStyle),
      darkTheme: _buildTheme(darkScheme, fontFamily: fontFamily, borderRadius: borderRadius, headerStyle: headerStyle),
      themeMode: settings.themeMode,
      home: _buildHome(engine, settings),
    );
  }

  Widget _buildHome(AppEngine engine, SettingsStore settings) {
    // If an app is loaded, show it
    if (engine.app != null) return const AppShell();

    // Single-user mode: go straight to WelcomeScreen (My Apps)
    if (!settings.isMultiUserEnabled) return const WelcomeScreen();

    // Multi-user mode: check framework auth state
    final fwAuth = context.watch<FrameworkAuthService>();

    // Admin not set up yet: show setup screen
    if (!fwAuth.isAdminSetUp) {
      return FrameworkAdminSetupScreen(
        authService: fwAuth,
        onSetupComplete: () => setState(() {}),
      );
    }

    // Not logged in: show login screen
    if (!fwAuth.isLoggedIn) {
      return FrameworkLoginScreen(
        authService: fwAuth,
        onLoginSuccess: () => setState(() {}),
      );
    }

    // Admin logged in: show WelcomeScreen (admin home)
    if (fwAuth.isAdmin) return const WelcomeScreen();

    // Regular user logged in: auto-load the default app
    return _RegularUserHome(
      onLogout: () {
        fwAuth.logout();
        setState(() {});
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Regular User Home — auto-loads the default app for non-admin users
// ---------------------------------------------------------------------------

class _RegularUserHome extends StatefulWidget {
  final VoidCallback onLogout;
  const _RegularUserHome({required this.onLogout});

  @override
  State<_RegularUserHome> createState() => _RegularUserHomeState();
}

class _RegularUserHomeState extends State<_RegularUserHome> {
  final _store = LoadedAppsStore();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _autoLaunch();
  }

  Future<void> _autoLaunch() async {
    final settings = context.read<SettingsStore>();
    _store.storageFolder = settings.storageFolder;
    await _store.initialize(syncCatalog: false);

    final defaultId = settings.defaultAppId;
    LoadedAppEntry? target;
    if (defaultId != null) {
      target = _store.activeApps.cast<LoadedAppEntry?>().firstWhere(
            (a) => a!.id == defaultId,
            orElse: () => null,
          );
    }
    // Fallback: load the first active app
    target ??= _store.activeApps.isNotEmpty ? _store.activeApps.first : null;

    if (target == null) {
      if (mounted) setState(() { _loading = false; _error = 'No apps available. Ask an admin to set a default app.'; });
      return;
    }

    final engine = context.read<AppEngine>();
    engine.storageFolder = settings.storageFolder;

    // Framework auth is active — bypass per-app auth, inject framework roles.
    final fwAuth = context.read<FrameworkAuthService>();
    engine.skipAppAuth = true;
    engine.frameworkRoles = fwAuth.currentRoles;
    engine.frameworkUsername = fwAuth.currentUsername;
    engine.frameworkEmail = fwAuth.currentEmail;
    engine.frameworkDisplayName = fwAuth.currentDisplayName;

    final ok = await engine.loadSpec(target.specJson);
    if (!ok && mounted) {
      setState(() { _loading = false; _error = engine.loadError ?? 'Failed to load app'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fwAuth = context.watch<FrameworkAuthService>();

    if (_loading && _error == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Loading...', style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    // Error or no default app
    return Scaffold(
      appBar: AppBar(
        title: const Text('One Does Simply'),
        actions: [
          PopupMenuButton<String>(
            icon: CircleAvatar(
              radius: 14,
              child: Text(
                fwAuth.currentDisplayName.isNotEmpty ? fwAuth.currentDisplayName[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            onSelected: (v) { if (v == 'logout') widget.onLogout(); },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text('Signed in as ${fwAuth.currentDisplayName}'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'logout', child: Text('Logout')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                _error ?? 'No default app configured.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Contact your administrator.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
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
    final settings = context.read<SettingsStore>();
    _loadedAppsStore.storageFolder = settings.storageFolder;
    await _loadedAppsStore.initialize();
    if (mounted) setState(() => _storeReady = true);
  }

  Future<void> _runSpec(String jsonString) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final engine = context.read<AppEngine>();
    final settings = context.read<SettingsStore>();
    engine.storageFolder = settings.storageFolder;

    // When framework multi-user is active, bypass per-app auth and inject
    // the framework user's roles so the app uses them for RBAC + startPage.
    if (settings.isMultiUserEnabled) {
      final fwAuth = context.read<FrameworkAuthService>();
      if (fwAuth.isLoggedIn) {
        engine.skipAppAuth = true;
        engine.frameworkRoles = fwAuth.currentRoles;
      }
    }

    final success = await engine.loadSpec(jsonString);

    if (success) {
      // Run auto-backup in the background if enabled.
      if (settings.autoBackup) {
        BackupManager.runAutoBackup(
          engine,
          retention: settings.backupRetention,
          backupFolder: settings.backupFolder,
        );
      }
    }

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

  Future<void> _editWithAi(LoadedAppEntry app) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _EditWithAiScreen(
          app: app,
          onSpecUpdated: (updatedJson) async {
            String newName = app.name;
            String newDesc = app.description;
            try {
              final parsed = jsonDecode(updatedJson) as Map<String, dynamic>;
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
              specJson: updatedJson,
            );
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  Future<void> _archiveApp(LoadedAppEntry app) async {
    await _loadedAppsStore.archiveApp(app.id);
    if (mounted) {
      setState(() {});
      showOdsSnackBar(
        context,
        message: '"${app.name}" archived',
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await _loadedAppsStore.unarchiveApp(app.id);
            if (mounted) setState(() {});
          },
        ),
      );
    }
  }

  Future<void> _unarchiveApp(LoadedAppEntry app) async {
    await _loadedAppsStore.unarchiveApp(app.id);
    if (mounted) setState(() {});
  }

  Future<void> _exportAppData(LoadedAppEntry app) async {
    // Parse spec to get app name for database lookup.
    String appName;
    try {
      final parsed = jsonDecode(app.specJson) as Map<String, dynamic>;
      appName = parsed['appName'] as String? ?? app.name;
    } catch (_) {
      appName = app.name;
    }

    // Pick export format.
    final format = await showDialog<ExportFormat>(
      context: context,
      builder: (ctx) => const _ExportFormatDialog(),
    );
    if (format == null) return;

    try {
      // Open a temporary DataStore to read existing data.
      final settings = context.read<SettingsStore>();
      final dataStore = DataStore();
      await dataStore.initialize(appName, storageFolder: settings.storageFolder);
      final tables = await dataStore.exportAllData();
      await dataStore.close();

      final exportData = {
        'odsExport': {
          'appName': appName,
          'exportedAt': DateTime.now().toIso8601String(),
          'version': '1.0',
        },
        'tables': tables,
      };

      final exporter = DataExporter();
      final outputPath = await exporter.export(
        appName: appName,
        exportData: exportData,
        format: format,
      );

      if (outputPath != null && mounted) {
        showOdsSnackBar(context, message: 'Data exported to $outputPath');
      }
    } catch (e) {
      if (mounted) {
        showOdsSnackBar(context, message: 'Export failed: $e');
      }
    }
  }

  Future<void> _generateAppCode(LoadedAppEntry app) async {
    // Parse the spec to get an OdsApp model.
    final parser = SpecParser();
    final result = parser.parse(app.specJson);
    if (result.app == null) {
      if (mounted) {
        showOdsSnackBar(context, message: 'Could not parse spec: ${result.parseError ?? "unknown error"}');
      }
      return;
    }
    final odsApp = result.app!;

    // Show the generation dialog with explanation and folder picker.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate Flutter Project'),
        content: const SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This will generate a standalone Flutter project from your ODS '
                'app — complete source code that you fully own and can customize '
                'without limits.',
              ),
              SizedBox(height: 12),
              Text(
                'The generated project includes:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 4),
              Text('  • main.dart with MaterialApp and routing'),
              Text('  • One page widget per screen'),
              Text('  • SQLite database helper with CRUD'),
              Text('  • Forms, lists, buttons, and charts'),
              Text('  • pubspec.yaml with all dependencies'),
              SizedBox(height: 12),
              Text(
                'Choose an empty folder to write the project files into. '
                'A README.md is included with step-by-step instructions '
                'for getting the app running — even if you\'ve never '
                'used Flutter before.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.folder_open),
            label: const Text('Choose Folder'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    // Pick a folder.
    final outputDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose folder for generated project',
    );
    if (outputDir == null || !context.mounted) return;

    try {
      final generator = CodeGenerator();
      final files = generator.generate(odsApp);

      int fileCount = 0;
      for (final entry in files.entries) {
        final file = File('$outputDir/${entry.key}');
        await file.parent.create(recursive: true);
        await file.writeAsString(entry.value);
        fileCount++;
      }

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(Icons.check_circle_outline, color: Theme.of(ctx).colorScheme.primary, size: 48),
            title: const Text('Code Generation Complete'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Generated $fileCount files in:'),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      outputDir,
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Open the folder and follow the README.md to get your app running.',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showOdsSnackBar(context, message: 'Code generation failed: $e', isError: true);
      }
    }
  }

  void _showCreateNew() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _CreateNewScreen()),
    );
  }

  Future<void> _quickBuild() async {
    final specJson = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QuickBuildScreen()),
    );
    if (specJson != null && mounted) {
      await _handleNewSpec(specJson);
    }
  }

  Future<void> _browseExamples() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ExampleCatalogDialog(store: _loadedAppsStore),
    );
    if (added == true && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show onboarding on first run.
    if (_storeReady && _loadedAppsStore.isFirstRun) {
      return _OnboardingScreen(
        store: _loadedAppsStore,
        onComplete: () {
          if (mounted) setState(() {});
        },
      );
    }

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
                      // Top bar with theme toggle and settings
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _ThemeToggle(
                            themeMode: settings.themeMode,
                            onChanged: (mode) => settings.setThemeMode(mode),
                          ),
                          const SizedBox(width: 8),
                          if (!settings.isMultiUserEnabled || context.read<FrameworkAuthService>().isAdmin)
                          IconButton(
                            icon: const Icon(Icons.settings, color: Colors.white70),
                            tooltip: 'Framework Settings',
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FrameworkSettingsScreen(settings: settings),
                              ),
                            ),
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
                    onBrowseExamples: _browseExamples,
                    onQuickBuild: _quickBuild,
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
          else if (_loadedAppsStore.activeApps.isEmpty)
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
                    final app = _loadedAppsStore.activeApps[index];
                    return _AppListTile(
                      app: app,
                      isLoading: _isLoading,
                      isDefault: settings.defaultAppId == app.id,
                      onRun: () => _runSpec(app.specJson),
                      onEditSpec: () => _editApp(app),
                      onEditWithAi: () => _editWithAi(app),
                      onArchive: () => _archiveApp(app),
                      onExportData: () => _exportAppData(app),
                      onGenerateCode: () => _generateAppCode(app),
                      onRemove: app.isBundled ? null : () => _removeApp(app),
                      onSetDefault: settings.isMultiUserEnabled
                          ? () {
                              settings.setDefaultAppId(app.id);
                              setState(() {});
                            }
                          : null,
                    );
                  },
                  childCount: _loadedAppsStore.activeApps.length,
                ),
              ),
            ),

          // -- Archived section --
          if (_storeReady && _loadedAppsStore.archivedApps.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Row(
                  children: [
                    Icon(Icons.archive_outlined, size: 18, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      'Archived',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final app = _loadedAppsStore.archivedApps[index];
                    return _ArchivedAppTile(
                      app: app,
                      onUnarchive: () => _unarchiveApp(app),
                      onRemove: app.isBundled ? null : () => _removeApp(app),
                    );
                  },
                  childCount: _loadedAppsStore.archivedApps.length,
                ),
              ),
            ),
          ],

          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Onboarding screen — shown on first run to let the user pick examples
// ---------------------------------------------------------------------------

class _OnboardingScreen extends StatefulWidget {
  final LoadedAppsStore store;
  final VoidCallback onComplete;

  const _OnboardingScreen({
    required this.store,
    required this.onComplete,
  });

  @override
  State<_OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<_OnboardingScreen> {
  int _step = 0; // 0 = welcome, 1 = pick examples, 2 = downloading
  List<CatalogEntry>? _catalog;
  final Set<String> _selectedIds = {};
  bool _loadingCatalog = true;
  String? _catalogError;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final catalog = await widget.store.fetchCatalog();
    if (!mounted) return;
    setState(() {
      _catalog = catalog;
      _loadingCatalog = false;
      if (catalog == null) {
        _catalogError = 'Could not reach the example catalog. '
            'Check your internet connection and try again.';
      } else {
        // Pre-select all examples by default.
        _selectedIds.addAll(catalog.map((e) => e.id));
      }
    });
  }

  Future<void> _downloadSelected() async {
    if (_catalog == null) return;
    setState(() => _step = 2);

    final selected =
        _catalog!.where((e) => _selectedIds.contains(e.id)).toList();
    await widget.store.addSelectedExamples(selected);
    widget.onComplete();
  }

  Future<void> _skip() async {
    await widget.store.completeFirstRun();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
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
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _step == 0
                    ? _buildWelcome(theme)
                    : _step == 1
                        ? _buildPicker(theme, colorScheme)
                        : _buildDownloading(theme),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcome(ThemeData theme) {
    return Padding(
      key: const ValueKey('welcome'),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 64, color: Colors.white),
          const SizedBox(height: 24),
          Text(
            'Welcome to\nOne Does Simply',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Describe your app idea and let an AI Build Helper create it for you '
            '— vibe coding with guardrails. Or explore some example apps to see '
            'what\'s possible.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 40),
          FilledButton.icon(
            onPressed: () => setState(() => _step = 1),
            icon: const Icon(Icons.explore),
            label: const Text('Browse Example Apps'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF4F46E5),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _skip,
            child: Text(
              'Skip — I\'ll start from scratch',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPicker(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      key: const ValueKey('picker'),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pick Your Examples',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Select the apps you\'d like to add. You can always find more later.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (_loadingCatalog)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_catalogError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(Icons.cloud_off, size: 40, color: colorScheme.error),
                    const SizedBox(height: 12),
                    Text(
                      _catalogError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.error),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _loadingCatalog = true;
                          _catalogError = null;
                        });
                        _loadCatalog();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else ...[
              // Select all / none toggle
              Row(
                children: [
                  Text(
                    '${_selectedIds.length} of ${_catalog!.length} selected',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        if (_selectedIds.length == _catalog!.length) {
                          _selectedIds.clear();
                        } else {
                          _selectedIds.addAll(_catalog!.map((e) => e.id));
                        }
                      });
                    },
                    child: Text(
                      _selectedIds.length == _catalog!.length
                          ? 'Deselect All'
                          : 'Select All',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _catalog!.map((entry) {
                      final selected = _selectedIds.contains(entry.id);
                      return CheckboxListTile(
                        value: selected,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedIds.add(entry.id);
                            } else {
                              _selectedIds.remove(entry.id);
                            }
                          });
                        },
                        title: Text(
                          entry.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          entry.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: _skip,
                  child: const Text('Skip'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed:
                      (_catalog != null && _selectedIds.isNotEmpty) ? _downloadSelected : null,
                  icon: const Icon(Icons.download, size: 18),
                  label: Text(
                    _selectedIds.isEmpty
                        ? 'Add Apps'
                        : 'Add ${_selectedIds.length} App${_selectedIds.length == 1 ? '' : 's'}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloading(ThemeData theme) {
    return Padding(
      key: const ValueKey('downloading'),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Setting up your apps...',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Downloading example specs',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
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
  final VoidCallback onBrowseExamples;
  final VoidCallback onQuickBuild;

  const _AddAppButton({
    required this.onPickFile,
    required this.onLoadUrl,
    required this.onCreateNew,
    required this.onBrowseExamples,
    required this.onQuickBuild,
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
          case 'quickBuild':
            onQuickBuild();
          case 'examples':
            onBrowseExamples();
        }
      },
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          value: 'quickBuild',
          child: ListTile(
            leading: Icon(Icons.bolt),
            title: Text('Quick Build'),
            subtitle: Text('Build an app in seconds from a template'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'examples',
          child: ListTile(
            leading: Icon(Icons.explore),
            title: Text('Browse Examples'),
            subtitle: Text('Pick from the example catalog'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
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
  final bool isDefault;
  final VoidCallback onRun;
  final VoidCallback onEditSpec;
  final VoidCallback onEditWithAi;
  final VoidCallback onArchive;
  final VoidCallback? onRemove;
  final VoidCallback onExportData;
  final VoidCallback onGenerateCode;
  final VoidCallback? onSetDefault;

  const _AppListTile({
    required this.app,
    required this.isLoading,
    this.isDefault = false,
    required this.onRun,
    required this.onEditSpec,
    required this.onEditWithAi,
    required this.onArchive,
    required this.onExportData,
    required this.onGenerateCode,
    this.onRemove,
    this.onSetDefault,
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              app.name,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isDefault) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade700,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Default',
                                style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ],
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
                // More actions menu
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: colorScheme.onSurfaceVariant, size: 20),
                  tooltip: 'More actions',
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (value) {
                    switch (value) {
                      case 'editWithAi':
                        onEditWithAi();
                      case 'editSpec':
                        onEditSpec();
                      case 'exportData':
                        onExportData();
                      case 'generateCode':
                        onGenerateCode();
                      case 'setDefault':
                        onSetDefault?.call();
                      case 'archive':
                        onArchive();
                      case 'remove':
                        onRemove?.call();
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'editWithAi',
                      child: ListTile(
                        leading: Icon(Icons.auto_awesome),
                        title: Text('Edit with AI'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    if (!app.isBundled)
                      const PopupMenuItem(
                        value: 'editSpec',
                        child: ListTile(
                          leading: Icon(Icons.code),
                          title: Text('Edit JSON Spec'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'exportData',
                      child: ListTile(
                        leading: Icon(Icons.download_outlined),
                        title: Text('Export Data'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'generateCode',
                      child: ListTile(
                        leading: Icon(Icons.code),
                        title: Text('Generate Code'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    if (onSetDefault != null && !isDefault)
                      const PopupMenuItem(
                        value: 'setDefault',
                        child: ListTile(
                          leading: Icon(Icons.star_outline),
                          title: Text('Set as Default'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'archive',
                      child: ListTile(
                        leading: Icon(Icons.archive_outlined),
                        title: Text('Archive'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    if (onRemove != null)
                      PopupMenuItem(
                        value: 'remove',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline, color: colorScheme.error),
                          title: Text('Delete', style: TextStyle(color: colorScheme.error)),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                  ],
                ),
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
// Archived app tile — compact with restore/delete options
// ---------------------------------------------------------------------------

class _ArchivedAppTile extends StatelessWidget {
  final LoadedAppEntry app;
  final VoidCallback onUnarchive;
  final VoidCallback? onRemove;

  const _ArchivedAppTile({
    required this.app,
    required this.onUnarchive,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Card(
        color: colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.archive_outlined, size: 20, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  app.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onUnarchive,
                icon: const Icon(Icons.unarchive_outlined, size: 16),
                label: const Text('Restore'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
              if (onRemove != null)
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: colorScheme.error),
                  tooltip: 'Delete permanently',
                  onPressed: onRemove,
                  visualDensity: VisualDensity.compact,
                ),
            ],
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
      showOdsSnackBar(context, message: 'Build Helper prompt copied to clipboard!', duration: const Duration(seconds: 3));
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
// Edit with AI screen — copy spec, edit with chatbot, paste back
// ---------------------------------------------------------------------------

class _EditWithAiScreen extends StatefulWidget {
  final LoadedAppEntry app;
  final Future<void> Function(String updatedJson) onSpecUpdated;

  const _EditWithAiScreen({required this.app, required this.onSpecUpdated});

  @override
  State<_EditWithAiScreen> createState() => _EditWithAiScreenState();
}

class _EditWithAiScreenState extends State<_EditWithAiScreen> {
  bool _specCopied = false;
  bool _promptCopied = false;
  final _pasteController = TextEditingController();
  String? _importError;

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _copySpec() async {
    await Clipboard.setData(ClipboardData(text: widget.app.specJson));
    if (mounted) {
      setState(() => _specCopied = true);
      showOdsSnackBar(context, message: 'App spec JSON copied to clipboard!', duration: const Duration(seconds: 3));
    }
  }

  Future<void> _copyEditPrompt() async {
    final prompt = await rootBundle.loadString('assets/build-helper-prompt.txt');
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: prompt));
    if (mounted) {
      setState(() => _promptCopied = true);
      showOdsSnackBar(context, message: 'Build Helper prompt copied to clipboard!', duration: const Duration(seconds: 3));
    }
  }

  Future<void> _importUpdatedSpec() async {
    final text = _pasteController.text.trim();
    if (text.isEmpty) {
      setState(() => _importError = 'Paste the updated JSON spec first.');
      return;
    }

    try {
      jsonDecode(text); // Validate it's valid JSON
    } catch (e) {
      setState(() => _importError = 'Invalid JSON: $e');
      return;
    }

    await widget.onSpecUpdated(text);
    if (mounted) {
      showOdsSnackBar(context, message: '"${widget.app.name}" updated successfully!');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text('Edit ${widget.app.name}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero
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
                      const Icon(Icons.edit_note, size: 36, color: Colors.white),
                      const SizedBox(height: 12),
                      Text(
                        'Edit with AI Assistance',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Copy your app\'s current spec, paste it into any AI chatbot along with '
                        'the Build Helper prompt, describe your changes, and paste the updated '
                        'spec back here.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Step 1: Copy prompt
                Text('Step 1: Copy the Build Helper Prompt',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  'If you haven\'t already pasted the Build Helper prompt into your AI chatbot, copy it first.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _copyEditPrompt,
                    icon: Icon(_promptCopied ? Icons.check : Icons.copy, size: 18),
                    label: Text(_promptCopied ? 'Prompt Copied!' : 'Copy Build Helper Prompt'),
                  ),
                ),
                const SizedBox(height: 24),

                // Step 2: Copy spec
                Text('Step 2: Copy Your App Spec',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  'Copy the current JSON spec for "${widget.app.name}" and paste it into the AI chatbot. '
                  'Tell the AI what changes you\'d like to make.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _copySpec,
                    icon: Icon(_specCopied ? Icons.check : Icons.copy, size: 18),
                    label: Text(_specCopied ? 'Spec Copied!' : 'Copy App Spec JSON'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),

                // Preview the spec
                const SizedBox(height: 8),
                Card(
                  child: ExpansionTile(
                    leading: Icon(Icons.visibility_outlined, color: colorScheme.primary, size: 20),
                    title: const Text('Preview current spec'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black26 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            widget.app.specJson,
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
                const SizedBox(height: 24),

                // Step 3: Paste back
                Text('Step 3: Paste Updated Spec',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  'After the AI generates the updated spec, copy it and paste it below.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _pasteController,
                  maxLines: 8,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Paste the updated JSON spec here...',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.all(12),
                    errorText: _importError,
                  ),
                  onChanged: (_) {
                    if (_importError != null) setState(() => _importError = null);
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _importUpdatedSpec,
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('Save Updated Spec'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
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
  bool _tourCheckedAndShown = false;

  /// Show the guided tour after the auth gate is clear.
  /// Called from build() so it re-evaluates after login/admin-setup.
  void _maybeShowTour() {
    if (_tourCheckedAndShown) return;
    final engine = context.read<AppEngine>();
    // Don't show tour while auth gate is active.
    if (engine.needsAdminSetup || engine.needsLogin) return;
    _tourCheckedAndShown = true;

    final settings = context.read<SettingsStore>();
    final app = engine.app;
    if (app != null && app.tour.isNotEmpty) {
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

  /// Whether the given app allows guest (unauthenticated) access.
  ///
  /// Guest access is allowed when the app is NOT [multiUserOnly] and the
  /// start page either has no role restriction or explicitly includes 'guest'.
  bool _shouldAllowGuest(OdsApp app) {
    if (app.auth.multiUserOnly) return false;
    final startPage = app.pages[app.startPage];
    if (startPage == null) return false;
    final roles = startPage.roles;
    return roles == null || roles.isEmpty || roles.contains('guest');
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AppEngine>();
    final settings = context.watch<SettingsStore>();
    final app = engine.app!;
    final brandingOverrides = settings.getBrandingOverrides(app.appName);
    final effectiveLogoUrl = brandingOverrides['logo'] ?? app.branding.logo;

    // Auth gate: show admin setup or login screen when multi-user is enabled.
    if (engine.needsAdminSetup) {
      return Scaffold(
        appBar: AppBar(title: Text(app.appName)),
        body: AdminSetupScreen(
          authService: engine.authService,
          onSetupComplete: (email, password) async {
            // Also create a framework admin and enable framework multi-user
            // so the login gate is active on future launches.
            if (!settings.isMultiUserEnabled) {
              await settings.setMultiUserEnabled(true);
              final fwAuth = context.read<FrameworkAuthService>();
              await fwAuth.initialize(storageFolder: settings.storageFolder);
              await fwAuth.setupAdmin(
                email: email,
                password: password,
              );
            }
            engine.resolveStartPage();
          },
          onSkip: app.auth.multiUserOnly
              ? null
              : () => engine.resolveStartPage(),
        ),
      );
    }

    if (engine.needsLogin) {
      return Scaffold(
        appBar: AppBar(title: Text(app.appName)),
        body: LoginScreen(
          authService: engine.authService,
          onLoginSuccess: () => engine.resolveStartPage(),
          onContinueAsGuest: _shouldAllowGuest(app) ? () => engine.resolveStartPage() : null,
        ),
      );
    }

    // If the current page is role-restricted and the user doesn't have access,
    // redirect to the first accessible page (e.g., non-admin on an admin-only startPage).
    if (engine.isMultiUser) {
      final page = engine.currentPageId != null ? app.pages[engine.currentPageId] : null;
      if (page != null && !engine.authService.hasAccess(page.roles)) {
        // Find the first accessible menu page, or first accessible page.
        final accessiblePageId = app.menu
            .where((m) => engine.authService.hasAccess(m.roles))
            .map((m) => m.mapsTo)
            .firstOrNull
          ?? app.pages.entries
            .where((e) => engine.authService.hasAccess(e.value.roles))
            .map((e) => e.key)
            .firstOrNull;
        if (accessiblePageId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) engine.navigateTo(accessiblePageId);
          });
        }
      }
    }

    // Auth gate is clear — show guided tour if first time.
    _maybeShowTour();

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
          // User/guest indicator with popup menu
          if (engine.isMultiUser)
            engine.authService.isLoggedIn
                ? PopupMenuButton<String>(
                    tooltip: engine.authService.currentDisplayName,
                    offset: const Offset(0, 40),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.white,
                            child: Text(
                              engine.authService.currentDisplayName.isNotEmpty ? engine.authService.currentDisplayName[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.arrow_drop_down, size: 18, color: Colors.white70),
                        ],
                      ),
                    ),
                    onSelected: (value) async {
                      if (value == 'logout') {
                        if (settings.isMultiUserEnabled) {
                          await engine.reset();
                          final fwAuth = context.read<FrameworkAuthService>();
                          fwAuth.logout();
                        } else {
                          engine.authService.logout();
                          engine.clearFormStates();
                          engine.notifyListeners();
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        enabled: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              engine.authService.currentDisplayName,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              engine.authService.currentRoles.join(', '),
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'logout', child: Text('Logout')),
                    ],
                  )
                : TextButton.icon(
                    icon: const Icon(Icons.login, size: 16),
                    label: const Text('Sign In', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      engine.authService.logout();
                      engine.clearFormStates();
                      engine.notifyListeners();
                    },
                  ),
          // Help button
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
                  if (effectiveLogoUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Image.network(
                        effectiveLogoUrl,
                        height: 32,
                        fit: BoxFit.contain,
                        alignment: Alignment.centerLeft,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
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
            ...app.menu
                .where((item) => !engine.isMultiUser || engine.authService.hasAccess(item.roles))
                .map((item) {
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
            // Settings — admin-only in multi-user mode
            if (!engine.isMultiUser || engine.authService.isAdmin) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Settings'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                      engine: engine,
                      settings: settings,
                      app: app,
                    ),
                  ));
                },
              ),
            ],
            // Multi-user section
            if (engine.isMultiUser) ...[
              const Divider(),
              if (engine.authService.isLoggedIn) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 24, top: 4, bottom: 4),
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
                if (engine.authService.isAdmin && settings.isMultiUserEnabled)
                  ListTile(
                    leading: const Icon(Icons.people_outline),
                    title: const Text('Manage Users'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    onTap: () {
                      Navigator.pop(context);
                      final fwAuth = context.read<FrameworkAuthService>();
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Manage Users')),
                          body: ListView(
                            children: [
                              FrameworkUserList(authService: fwAuth),
                            ],
                          ),
                        ),
                      ));
                    },
                  ),
                // Only show per-app Sign Out when framework multi-user is off
                // (otherwise the framework Logout at the bottom covers both).
                if (!settings.isMultiUserEnabled)
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Sign Out'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    onTap: () {
                      Navigator.pop(context);
                      engine.authService.logout();
                      engine.clearFormStates();
                      engine.notifyListeners();
                    },
                  ),
              ] else ...[
                // Guest — show sign in option
                Padding(
                  padding: const EdgeInsets.only(left: 24, top: 4, bottom: 4),
                  child: Text(
                    'Browsing as Guest',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.login),
                  title: const Text('Sign In'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  onTap: () {
                    Navigator.pop(context);
                    engine.authService.logout();
                    engine.clearFormStates();
                    engine.notifyListeners();
                  },
                ),
              ],
            ],
            const Divider(),
            // In multi-user mode with framework auth: show Logout instead of Close App for regular users
            if (settings.isMultiUserEnabled) ...[
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                onTap: () async {
                  Navigator.pop(context);
                  await engine.reset();
                  final fwAuth = context.read<FrameworkAuthService>();
                  fwAuth.logout();
                },
              ),
            ] else ...[
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
// Settings dialog
// ---------------------------------------------------------------------------

class _SettingsDialog extends StatefulWidget {
  final AppEngine engine;
  final SettingsStore settings;
  final OdsApp app;

  const _SettingsDialog({
    required this.engine,
    required this.settings,
    required this.app,
  });

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  bool _busy = false;

  Future<void> _backupData() async {
    setState(() => _busy = true);
    try {
      final backup = await widget.engine.backupData();
      final appName = widget.app.appName.replaceAll(RegExp(r'[^\w]'), '_').toLowerCase();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final fileName = 'ods_backup_${appName}_$timestamp.json';
      final jsonStr = jsonEncode(backup);

      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Backup',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (outputPath != null) {
        await File(outputPath).writeAsString(jsonStr);
        if (mounted) {
          Navigator.pop(context);
          showOdsSnackBar(context, message: 'Backup saved to $outputPath');
        }
      }
    } catch (e) {
      if (mounted) {
        showOdsSnackBar(context, message: 'Backup failed: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreData() async {
    // Confirm before overwriting.
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

      // Basic validation.
      if (!backup.containsKey('odsBackup') && !backup.containsKey('tables')) {
        throw FormatException('Not a valid ODS backup file');
      }

      await widget.engine.restoreData(backup);

      if (mounted) {
        Navigator.pop(context);
        showOdsSnackBar(context, message: 'Data restored from backup');
      }
    } catch (e) {
      if (mounted) {
        showOdsSnackBar(context, message: 'Restore failed: $e');
      }
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

    // Parse rows from the file.
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
      if (mounted) {
        showOdsSnackBar(context, message: 'Could not parse file: $e');
      }
      return;
    }

    if (rows.isEmpty) {
      if (mounted) {
        showOdsSnackBar(context, message: 'File contains no data rows');
      }
      return;
    }

    if (!mounted) return;

    // Let the user pick which table to import into.
    final tables = widget.engine.localTableNames;
    final columns = rows.first.keys.where((k) => k != '_id' && k != '_createdAt').toList();

    final targetTable = await showDialog<String>(
      context: context,
      builder: (ctx) => _ImportPreviewDialog(
        tables: tables,
        columns: columns,
        rowCount: rows.length,
        fileName: filePath.split('/').last.split('\\').last,
      ),
    );

    if (targetTable == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final count = await widget.engine.importTableRows(targetTable, rows);
      if (mounted) {
        Navigator.pop(context);
        showOdsSnackBar(context, message: 'Imported $count rows into "$targetTable"');
      }
    } catch (e) {
      if (mounted) {
        showOdsSnackBar(context, message: 'Import failed: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Parses a CSV string into a list of row maps.
  /// Handles quoted fields with commas and newlines.
  List<Map<String, dynamic>> _parseCsv(String content) {
    final lines = _parseCsvLines(content);
    if (lines.length < 2) return [];

    final headers = lines.first;
    final rows = <Map<String, dynamic>>[];
    for (var i = 1; i < lines.length; i++) {
      final values = lines[i];
      if (values.length != headers.length) continue; // skip malformed rows
      final row = <String, dynamic>{};
      for (var j = 0; j < headers.length; j++) {
        row[headers[j]] = values[j];
      }
      rows.add(row);
    }
    return rows;
  }

  /// Splits CSV content into a list of rows, each being a list of field values.
  /// Handles RFC 4180 quoting (double-quote escaping, embedded commas/newlines).
  List<List<String>> _parseCsvLines(String content) {
    final rows = <List<String>>[];
    var fields = <String>[];
    var field = StringBuffer();
    var inQuotes = false;
    var i = 0;

    while (i < content.length) {
      final c = content[i];

      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < content.length && content[i + 1] == '"') {
            field.write('"');
            i += 2;
          } else {
            inQuotes = false;
            i++;
          }
        } else {
          field.write(c);
          i++;
        }
      } else {
        if (c == '"') {
          inQuotes = true;
          i++;
        } else if (c == ',') {
          fields.add(field.toString().trim());
          field = StringBuffer();
          i++;
        } else if (c == '\r') {
          i++;
        } else if (c == '\n') {
          fields.add(field.toString().trim());
          if (fields.any((f) => f.isNotEmpty)) rows.add(fields);
          fields = <String>[];
          field = StringBuffer();
          i++;
        } else {
          field.write(c);
          i++;
        }
      }
    }

    // Last row (no trailing newline).
    fields.add(field.toString().trim());
    if (fields.any((f) => f.isNotEmpty)) rows.add(fields);

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.engine;
    final settings = widget.settings;
    final app = widget.app;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('Settings'),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      content: SizedBox(
        width: 360,
        child: _busy
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Please wait...'),
                  ],
                ),
              )
            : SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // -- App settings (from spec) --
                  if (app.settings.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'APP SETTINGS',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _AppSettingsList(engine: engine, settings: app.settings),
                    const Divider(),
                  ],
                  // -- Data section --
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'DATA',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
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
                  // -- Framework settings --
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'FRAMEWORK',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Theme
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
                      onSelectionChanged: (s) => settings.setThemeMode(s.first),
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
                    value: settings.autoBackup,
                    onChanged: (v) => settings.setAutoBackup(v),
                  ),
                  // Backup retention
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
                          if (v != null) settings.setBackupRetention(v);
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
                              onPressed: () => settings.setBackupFolder(null),
                            )
                          : null,
                      onTap: () async {
                        final picked = await FilePicker.platform.getDirectoryPath(
                          dialogTitle: 'Choose Backup Folder',
                        );
                        if (picked != null) {
                          settings.setBackupFolder(picked);
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
                      Navigator.pop(context);
                      engine.toggleDebugMode();
                    },
                  ),
                ],
              ),
              ),
      ),
      actions: _busy
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
    );
  }
}

// ---------------------------------------------------------------------------
// Example catalog dialog — browse and add examples from the remote catalog
// ---------------------------------------------------------------------------

class _ExampleCatalogDialog extends StatefulWidget {
  final LoadedAppsStore store;

  const _ExampleCatalogDialog({required this.store});

  @override
  State<_ExampleCatalogDialog> createState() => _ExampleCatalogDialogState();
}

class _ExampleCatalogDialogState extends State<_ExampleCatalogDialog> {
  List<CatalogEntry>? _catalog;
  final Set<String> _selectedIds = {};
  bool _loading = true;
  bool _adding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final catalog = await widget.store.fetchCatalog();
    if (!mounted) return;

    // Filter out examples the user already has.
    final existingIds = widget.store.apps
        .where((a) => a.isBundled)
        .map((a) => a.id)
        .toSet();

    final available = catalog
        ?.where((e) => !existingIds.contains('example_${e.id}'))
        .toList();

    setState(() {
      _catalog = available;
      _loading = false;
      if (catalog == null) {
        _error = 'Could not reach the example catalog. '
            'Check your internet connection and try again.';
      }
    });
  }

  Future<void> _addSelected() async {
    if (_catalog == null) return;
    setState(() => _adding = true);

    final selected =
        _catalog!.where((e) => _selectedIds.contains(e.id)).toList();
    await widget.store.addSelectedExamples(selected);

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('Browse Examples'),
      content: SizedBox(
        width: 420,
        child: _adding
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Downloading...'),
                  ],
                ),
              )
            : _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _error != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off,
                              size: 40, color: colorScheme.error),
                          const SizedBox(height: 12),
                          Text(_error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colorScheme.error)),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _loading = true;
                                _error = null;
                              });
                              _loadCatalog();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      )
                    : _catalog!.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              'You already have all the example apps!',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Select examples to add to your apps.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Text(
                                    '${_selectedIds.length} of ${_catalog!.length} selected',
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        if (_selectedIds.length ==
                                            _catalog!.length) {
                                          _selectedIds.clear();
                                        } else {
                                          _selectedIds.addAll(
                                              _catalog!.map((e) => e.id));
                                        }
                                      });
                                    },
                                    child: Text(
                                      _selectedIds.length == _catalog!.length
                                          ? 'Deselect All'
                                          : 'Select All',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Flexible(
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: _catalog!.map((entry) {
                                      final selected =
                                          _selectedIds.contains(entry.id);
                                      return CheckboxListTile(
                                        value: selected,
                                        onChanged: (val) {
                                          setState(() {
                                            if (val == true) {
                                              _selectedIds.add(entry.id);
                                            } else {
                                              _selectedIds.remove(entry.id);
                                            }
                                          });
                                        },
                                        title: Text(
                                          entry.name,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600),
                                        ),
                                        subtitle: Text(
                                          entry.description,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        dense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 4),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ],
                          ),
      ),
      actions: _adding || _loading
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              if (_catalog != null && _catalog!.isNotEmpty)
                FilledButton.icon(
                  onPressed: _selectedIds.isNotEmpty ? _addSelected : null,
                  icon: const Icon(Icons.download, size: 18),
                  label: Text(
                    _selectedIds.isEmpty
                        ? 'Add'
                        : 'Add ${_selectedIds.length} App${_selectedIds.length == 1 ? '' : 's'}',
                  ),
                ),
            ],
    );
  }
}

// ---------------------------------------------------------------------------
// Export format picker dialog
// ---------------------------------------------------------------------------

class _ExportFormatDialog extends StatelessWidget {
  const _ExportFormatDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('Export Format'),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: ExportFormat.values.map((format) {
            final icon = switch (format) {
              ExportFormat.json => Icons.data_object,
              ExportFormat.csv => Icons.table_chart_outlined,
              ExportFormat.sql => Icons.storage_outlined,
            };
            return ListTile(
              leading: Icon(icon, color: colorScheme.primary),
              title: Text(format.label),
              subtitle: Text(
                format.description,
                style: theme.textTheme.bodySmall,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              onTap: () => Navigator.pop(context, format),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// Renders the app-level settings defined in the ODS spec's `settings` property.
class _AppSettingsList extends StatefulWidget {
  final AppEngine engine;
  final Map<String, OdsAppSetting> settings;

  const _AppSettingsList({required this.engine, required this.settings});

  @override
  State<_AppSettingsList> createState() => _AppSettingsListState();
}

class _AppSettingsListState extends State<_AppSettingsList> {
  @override
  Widget build(BuildContext context) {
    final entries = widget.settings.entries.toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: entries.map((entry) {
        final key = entry.key;
        final setting = entry.value;
        final currentValue = widget.engine.getAppSetting(key) ?? setting.defaultValue;

        if (setting.type == 'checkbox') {
          return SwitchListTile(
            title: Text(setting.label),
            value: currentValue == 'true',
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            onChanged: (v) async {
              await widget.engine.setAppSetting(key, v ? 'true' : 'false');
              setState(() {});
            },
          );
        }

        if (setting.type == 'select' && setting.options != null) {
          return ListTile(
            title: Text(setting.label),
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            trailing: DropdownButton<String>(
              value: setting.options!.contains(currentValue)
                  ? currentValue
                  : setting.defaultValue,
              underline: const SizedBox.shrink(),
              items: setting.options!
                  .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                  .toList(),
              onChanged: (v) async {
                if (v != null) {
                  await widget.engine.setAppSetting(key, v);
                  setState(() {});
                }
              },
            ),
          );
        }

        // text, number, etc. — show current value with tap-to-edit
        return ListTile(
          title: Text(setting.label),
          subtitle: Text(currentValue.isEmpty ? '(not set)' : currentValue),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          onTap: () async {
            final controller = TextEditingController(text: currentValue);
            final result = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(setting.label),
                content: TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: setting.type == 'number'
                      ? TextInputType.number
                      : TextInputType.text,
                  onSubmitted: (v) => Navigator.pop(ctx, v),
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
            controller.dispose();
            if (result != null) {
              await widget.engine.setAppSetting(key, result);
              setState(() {});
            }
          },
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Import Preview Dialog
// ---------------------------------------------------------------------------

class _ImportPreviewDialog extends StatefulWidget {
  final List<String> tables;
  final List<String> columns;
  final int rowCount;
  final String fileName;

  const _ImportPreviewDialog({
    required this.tables,
    required this.columns,
    required this.rowCount,
    required this.fileName,
  });

  @override
  State<_ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<_ImportPreviewDialog> {
  String? _selectedTable;

  @override
  void initState() {
    super.initState();
    if (widget.tables.isNotEmpty) _selectedTable = widget.tables.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Import Data'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.fileName,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text('${widget.rowCount} row${widget.rowCount == 1 ? '' : 's'} detected'),
            const SizedBox(height: 4),
            Text(
              'Columns: ${widget.columns.join(', ')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            if (widget.tables.isEmpty)
              Text(
                'No tables available. Load a spec with local data sources first.',
                style: TextStyle(color: theme.colorScheme.error),
              )
            else ...[
              Text('Import into:', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                value: _selectedTable,
                items: widget.tables
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedTable = v),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: widget.tables.isEmpty || _selectedTable == null
              ? null
              : () => Navigator.pop(context, _selectedTable),
          child: const Text('Import'),
        ),
      ],
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

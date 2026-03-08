import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'debug/debug_panel.dart';
import 'engine/app_engine.dart';
import 'engine/loaded_apps_store.dart';
import 'loader/spec_loader.dart';
import 'renderer/page_renderer.dart';
import 'screens/app_help_screen.dart';
import 'screens/app_tour_dialog.dart';
import 'screens/ods_about_screen.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

/// Application entry point.
///
/// Sets up a global [FlutterError.onError] handler so crashes are logged
/// to the console (useful during development and in debug mode), then
/// wraps the widget tree in a [ChangeNotifierProvider] that makes the
/// single [AppEngine] instance available everywhere via `context.read`
/// and `context.watch`.
///
/// ODS Architecture: One engine, one provider, one widget tree. The engine
/// owns all state; widgets are pure projections of that state. This is the
/// simplest reactive architecture Flutter offers, and it aligns perfectly
/// with ODS's "keep it simple" philosophy.
void main() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
    debugPrint('Stack: ${details.stack}');
  };

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppEngine(),
      child: const OdsFrameworkApp(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Root widget
// ---------------------------------------------------------------------------

/// The root [MaterialApp] that switches between two screens:
///   - [WelcomeScreen] when no spec is loaded (engine.app == null).
///   - [AppShell] when a spec has been successfully loaded and parsed.
///
/// Watches the engine so the transition happens automatically when
/// [AppEngine.loadSpec] succeeds.
class OdsFrameworkApp extends StatelessWidget {
  const OdsFrameworkApp({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AppEngine>();
    final appName = engine.app?.appName ?? 'ODS Framework';

    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: engine.app == null ? const WelcomeScreen() : const AppShell(),
    );
  }
}

// ---------------------------------------------------------------------------
// Welcome / Spec Loader Screen
// ---------------------------------------------------------------------------

/// The home screen shown before any spec is loaded.
///
/// Layout (top to bottom):
///   1. "My Apps" — saved apps from [LoadedAppsStore] (bundled examples +
///      user-added specs). Tapping one runs it immediately.
///   2. "Load New App" — file picker button and URL text field for loading
///      a fresh spec. New specs trigger a dialog asking "Just Run" or
///      "Add to My Apps & Run".
///
/// ODS Ethos: Getting started should take one tap. The bundled example
/// apps are always there in "My Apps" so a new user can explore without
/// having to find or create a spec first.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _urlController = TextEditingController();
  final _loadedAppsStore = LoadedAppsStore();
  bool _isLoading = false;
  bool _storeReady = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initStore();
  }

  /// Initializes the [LoadedAppsStore], which reads saved apps from disk
  /// and seeds the bundled examples on first run.
  Future<void> _initStore() async {
    await _loadedAppsStore.initialize();
    if (mounted) setState(() => _storeReady = true);
  }

  /// Hands a JSON string to the engine for parsing and rendering.
  /// On failure, captures the error message for display.
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

  /// Opens the native file picker for `.json` files.
  Future<void> _pickFile() async {
    try {
      final json = await SpecLoader().loadFromFilePicker();
      if (json != null) await _handleNewSpec(json);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load file: $e');
    }
  }

  /// Fetches a spec from the URL typed into the text field.
  Future<void> _loadFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

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

  /// Shows a dialog letting the user choose between "Just Run" (ephemeral)
  /// and "Add to My Apps & Run" (persisted to [LoadedAppsStore]).
  ///
  /// Extracts the app name and description from the raw JSON for display
  /// in the dialog and for storage if the user chooses to save.
  Future<void> _handleNewSpec(String specJson) async {
    if (!mounted) return;

    // Best-effort metadata extraction — if the JSON is malformed, the
    // engine will catch it later during full parsing.
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

    if (action == null) return; // User tapped Cancel.

    if (action == _NewSpecAction.addAndRun) {
      await _loadedAppsStore.addApp(
        name: appName,
        description: appDescription,
        specJson: specJson,
      );
      if (mounted) setState(() {}); // Refresh the app list.
    }

    await _runSpec(specJson);
  }

  /// Confirms and removes a user-added app from [LoadedAppsStore].
  /// Bundled apps cannot be removed (their cards don't show the X button).
  Future<void> _removeApp(LoadedAppEntry app) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove App'),
        content: Text('Remove "${app.name}" from your loaded apps?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
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

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ODS Framework'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About ODS',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OdsAboutScreen()),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            // Cap width for readability on wide screens.
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // -- Header --
                Text(
                  'One Does Simply',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Load a spec to get started, or launch a saved app.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // -- My Apps section --
                _sectionDivider('My Apps'),
                const SizedBox(height: 12),

                if (!_storeReady)
                  const Center(child: CircularProgressIndicator())
                else if (_loadedAppsStore.apps.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No apps yet. Load a spec below to get started.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  )
                else
                  ..._loadedAppsStore.apps.map((app) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _LoadedAppCard(
                          app: app,
                          onTap: _isLoading
                              ? null
                              : () => _runSpec(app.specJson),
                          onRemove: app.isBundled
                              ? null
                              : () => _removeApp(app),
                        ),
                      )),

                const SizedBox(height: 24),

                // -- Load New App section --
                _sectionDivider('Load New App'),
                const SizedBox(height: 12),

                // File picker button.
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _pickFile,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Open Spec File'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // URL input row.
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        decoration: const InputDecoration(
                          hintText: 'Enter spec URL...',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _loadFromUrl(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _loadFromUrl,
                      child: const Text('Load'),
                    ),
                  ],
                ),

                // Loading indicator.
                if (_isLoading) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ],

                // Error display.
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _error!,
                        style: TextStyle(color: Colors.red.shade800),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the labeled divider used to separate "My Apps" and "Load New App".
  static Widget _sectionDivider(String label) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(label, style: const TextStyle(color: Colors.grey)),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// "Just Run" vs "Add to My Apps" dialog
// ---------------------------------------------------------------------------

/// The two actions a user can take with a newly loaded spec.
enum _NewSpecAction { justRun, addAndRun }

/// A simple three-button dialog: Cancel / Just Run / Add to My Apps & Run.
///
/// "Just Run" loads the spec ephemerally — it won't appear in "My Apps"
/// next time. "Add to My Apps & Run" persists it to disk so it's always
/// available from the home screen.
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
// Loaded App Card
// ---------------------------------------------------------------------------

/// A card widget for each app in the "My Apps" list.
///
/// Bundled (example) apps show an `apps` icon; user-added apps show a
/// `description` icon. User-added apps also show an X button to remove
/// them. Tapping the card runs the app immediately.
class _LoadedAppCard extends StatelessWidget {
  final LoadedAppEntry app;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const _LoadedAppCard({required this.app, this.onTap, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(
          app.isBundled ? Icons.apps : Icons.description_outlined,
          color: theme.colorScheme.primary,
        ),
        title: Text(app.name),
        subtitle: app.description.isNotEmpty
            ? Text(
                app.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        onTap: onTap,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onRemove != null)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Remove',
                onPressed: onRemove,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main App Shell (after spec is loaded)
// ---------------------------------------------------------------------------

/// The primary app chrome displayed after a spec has been loaded.
///
/// Provides:
///   - An [AppBar] with the current page title, back navigation, and
///     action buttons (help, tour replay, debug toggle, home).
///   - A [Drawer] built from the spec's `menu` array for page navigation.
///   - A [PageRenderer] that renders the current page's components.
///   - An optional [DebugPanel] at the bottom when debug mode is active.
///   - A [_PageHelpBanner] at the top when the current page has help text.
///
/// ODS Spec alignment:
///   - `menu` items map to Drawer ListTiles.
///   - `help.pages[currentPageId]` drives the contextual help banner.
///   - `tour` drives the auto-launch tour and the replay button.
///
/// ODS Ethos: The shell is deliberately simple — a flat list of pages,
/// a side menu, a back button. No nested navigation, no tabs, no bottom
/// bar. Constraints breed simplicity.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// Tracks whether the auto-launch tour has already been shown this
  /// session, so it doesn't re-trigger on every rebuild.
  bool _tourShown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Auto-launch the tour on first display if the spec defines one.
    if (!_tourShown) {
      final engine = context.read<AppEngine>();
      final app = engine.app;
      if (app != null && app.tour.isNotEmpty) {
        _tourShown = true;
        // Post-frame callback ensures the Scaffold is fully built before
        // the dialog appears, preventing "no Overlay" errors.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AppEngine>();
    final app = engine.app!;
    final currentPageId = engine.currentPageId;
    final currentPage =
        currentPageId != null ? app.pages[currentPageId] : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(currentPage?.title ?? app.appName),
        // Show a back arrow when the navigation stack has history.
        leading: engine.canGoBack()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => engine.goBack(),
              )
            : null,
        actions: [
          // Help button — only shown if the spec declares help content.
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
          // Tour replay button — only shown if the spec declares a tour.
          if (app.tour.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.tour_outlined),
              tooltip: 'Replay Tour',
              onPressed: () {
                AppTourDialog.show(
                  context,
                  steps: app.tour,
                  appName: app.appName,
                  onNavigateToPage: (pageId) => engine.navigateTo(pageId),
                );
              },
            ),
          // Debug toggle — always available. Orange when active.
          IconButton(
            icon: Icon(
              engine.debugMode ? Icons.bug_report : Icons.bug_report_outlined,
              color: engine.debugMode ? Colors.orange : null,
            ),
            tooltip: 'Toggle Debug Mode',
            onPressed: () => engine.toggleDebugMode(),
          ),
          // Home button — resets the engine and returns to WelcomeScreen.
          IconButton(
            icon: const Icon(Icons.home),
            tooltip: 'Load New Spec',
            onPressed: () async => engine.reset(),
          ),
        ],
      ),

      // -- Navigation drawer --
      // Built from the spec's `menu` array. Each menu item maps to a page.
      drawer: app.menu.isNotEmpty
          ? Drawer(
              child: ListView(
                children: [
                  DrawerHeader(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
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
                          ),
                        ),
                        // Show a truncated overview in the drawer header
                        // for context.
                        if (app.help != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              app.help!.overview.length > 80
                                  ? '${app.help!.overview.substring(0, 80)}...'
                                  : app.help!.overview,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  ...app.menu.map((item) => ListTile(
                        title: Text(item.label),
                        selected: item.mapsTo == currentPageId,
                        onTap: () {
                          Navigator.pop(context); // Close the drawer.
                          engine.navigateTo(item.mapsTo);
                        },
                      )),
                ],
              ),
            )
          : null,

      // -- Body --
      body: Column(
        children: [
          // Contextual help banner for the current page (dismissible).
          if (app.help != null &&
              currentPageId != null &&
              app.help!.pages.containsKey(currentPageId))
            _PageHelpBanner(helpText: app.help!.pages[currentPageId]!),

          // The page content rendered by the component dispatch system.
          Expanded(
            child: currentPage != null
                ? PageRenderer(page: currentPage)
                : const Center(child: Text('Page not found')),
          ),

          // Debug panel pinned to the bottom when debug mode is on.
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

/// A dismissible banner shown at the top of the page body when the spec
/// provides per-page help text via `help.pages.<pageId>`.
///
/// ODS Spec: The `help.pages` map is keyed by page ID. If the current
/// page has an entry, this banner displays it.
///
/// The banner resets (un-dismisses) when the help text changes — i.e.,
/// when navigating to a different page that also has help text.
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
    // New page, new help text — show the banner again.
    if (oldWidget.helpText != widget.helpText) {
      _dismissed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Row(
        children: [
          Icon(
            Icons.lightbulb_outline,
            size: 18,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.helpText,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => setState(() => _dismissed = true),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

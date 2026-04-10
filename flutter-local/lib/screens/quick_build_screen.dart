import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../engine/log_service.dart';
import '../engine/template_engine.dart';
import '../engine/theme_resolver.dart';
import '../widgets/color_picker_widgets.dart';

/// Base URL for the ODS template catalog on GitHub Pages.
const _templateBaseUrl =
    'https://one-does-simply.github.io/Specification/Templates';

// ---------------------------------------------------------------------------
// Template catalog model
// ---------------------------------------------------------------------------

class TemplateCatalogEntry {
  final String id;
  final String name;
  final String description;
  final String file;

  const TemplateCatalogEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.file,
  });

  factory TemplateCatalogEntry.fromJson(Map<String, dynamic> json) =>
      TemplateCatalogEntry(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        file: json['file'] as String,
      );
}

// ---------------------------------------------------------------------------
// Quick Build screen — template picker + question wizard + text review
// ---------------------------------------------------------------------------

/// Full-screen flow: pick a template → answer questions → review text → done.
///
/// Returns the rendered ODS spec JSON string via Navigator.pop, or null if
/// the user cancels.
class QuickBuildScreen extends StatefulWidget {
  const QuickBuildScreen({super.key});

  @override
  State<QuickBuildScreen> createState() => _QuickBuildScreenState();
}

class _QuickBuildScreenState extends State<QuickBuildScreen> {
  // Phase 1: template catalog
  List<TemplateCatalogEntry>? _catalog;
  bool _loadingCatalog = true;
  String? _catalogError;

  // Phase 2: template loaded, answering questions
  Map<String, dynamic>? _templateJson;
  String? _templateName;
  List<dynamic>? _questions;

  // Question answers keyed by question id
  final Map<String, dynamic> _answers = {};

  // Field-list builders: questionId -> list of field maps
  final Map<String, List<Map<String, dynamic>>> _fieldLists = {};

  // Rendering
  bool _rendering = false;
  String? _renderError;

  // Phase 2.5: Theme selection
  bool _inThemePhase = false;
  String _selectedTheme = 'indigo';
  Map<String, String> _colorOverrides = {}; // token name -> hex color
  List<Map<String, dynamic>>? _themeCatalog;
  String? _activeStyle; // style filter for theme list
  String? _activePalette; // palette filter for theme list
  ColorScheme? _themePreviewLightCs;
  ColorScheme? _themePreviewDarkCs;

  // Phase 2.5: Branding fields
  final TextEditingController _logoUrlController = TextEditingController();
  final TextEditingController _faviconUrlController = TextEditingController();
  final TextEditingController _fontFamilyController = TextEditingController();
  String _headerStyle = 'light';
  bool _brandingExpanded = false;

  // Phase 3: text review
  Map<String, dynamic>? _renderedSpec;
  List<_ReviewableText>? _reviewTexts;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _logoUrlController.dispose();
    _faviconUrlController.dispose();
    _fontFamilyController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    try {
      final response = await http
          .get(Uri.parse('$_templateBaseUrl/catalog.json'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        setState(() {
          _loadingCatalog = false;
          _catalogError = 'Could not load template catalog (${response.statusCode})';
        });
        return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final templates = (data['templates'] as List)
          .map((e) => TemplateCatalogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _catalog = templates;
        _loadingCatalog = false;
      });
    } catch (e) {
      setState(() {
        _loadingCatalog = false;
        _catalogError = 'Failed to fetch templates: $e';
      });
    }
  }

  Future<void> _selectTemplate(TemplateCatalogEntry entry) async {
    setState(() {
      _loadingCatalog = true;
      _catalogError = null;
    });

    try {
      final response = await http
          .get(Uri.parse('$_templateBaseUrl/${entry.file}'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        setState(() {
          _loadingCatalog = false;
          _catalogError = 'Could not load template (${response.statusCode})';
        });
        return;
      }
      final template = jsonDecode(response.body) as Map<String, dynamic>;
      setState(() {
        _loadingCatalog = false;
        _templateJson = template;
        _templateName = template['templateName'] as String? ?? entry.name;
        _questions = template['questions'] as List<dynamic>? ?? [];
        // Initialize defaults
        for (final q in _questions!) {
          final question = q as Map<String, dynamic>;
          final id = question['id'] as String;
          final type = question['type'] as String;
          if (type == 'checkbox') {
            _answers[id] = question['default'] == true;
          } else if (type == 'field-list') {
            _fieldLists[id] = [];
          } else if (question['default'] != null) {
            _answers[id] = question['default'];
          }
        }
      });
    } catch (e) {
      setState(() {
        _loadingCatalog = false;
        _catalogError = 'Failed to load template: $e';
      });
    }
  }

  void _renderTemplate() {
    setState(() {
      _rendering = true;
      _renderError = null;
    });

    try {
      // Build context from answers
      final context = Map<String, dynamic>.from(_answers);

      // Add field-list answers as arrays
      for (final entry in _fieldLists.entries) {
        context[entry.key] = entry.value;
      }

      final templateBody = _templateJson!['template'];
      final rendered = TemplateEngine.render(templateBody, context);
      final spec = rendered as Map<String, dynamic>;

      // Inject branding from theme selection
      final branding = (spec['branding'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      branding['theme'] = _selectedTheme;
      branding['mode'] = 'system';
      if (_colorOverrides.isNotEmpty) {
        branding['overrides'] = Map<String, String>.from(_colorOverrides);
      }
      if (_logoUrlController.text.trim().isNotEmpty) {
        branding['logo'] = _logoUrlController.text.trim();
      }
      if (_faviconUrlController.text.trim().isNotEmpty) {
        branding['favicon'] = _faviconUrlController.text.trim();
      }
      if (_headerStyle != 'light') {
        branding['headerStyle'] = _headerStyle;
      }
      if (_fontFamilyController.text.trim().isNotEmpty) {
        branding['fontFamily'] = _fontFamilyController.text.trim();
      }
      spec['branding'] = branding;

      logDebug('QuickBuild', 'Rendered spec', const JsonEncoder.withIndent('  ').convert(spec));

      // Extract reviewable text strings and move to Phase 3.
      final texts = _extractReviewableTexts(spec);
      setState(() {
        _rendering = false;
        _renderedSpec = spec;
        _reviewTexts = texts;
      });
    } catch (e) {
      setState(() {
        _rendering = false;
        _renderError = 'Failed to build app: $e';
      });
    }
  }

  void _finishWithSpec() {
    // Apply any text edits back into the rendered spec.
    if (_reviewTexts != null && _renderedSpec != null) {
      for (final rt in _reviewTexts!) {
        _setNestedValue(_renderedSpec!, rt.path, rt.controller.text);
      }
    }
    final specJson = const JsonEncoder.withIndent('  ').convert(_renderedSpec);
    Navigator.pop(context, specJson);
  }

  // ---------------------------------------------------------------------------
  // Phase 2.5: Theme selection — navigation helpers
  // ---------------------------------------------------------------------------

  Future<void> _goToThemePhase() async {
    final catalog = await ThemeResolver.loadCatalog();
    // Resolve theme: use answer, but fall back to 'indigo' if the answered theme doesn't exist
    var themeFromAnswers = _answers['theme'] as String? ?? 'indigo';
    // Handle legacy 'light'/'dark' theme names from old templates
    if (themeFromAnswers == 'light') themeFromAnswers = 'indigo';
    if (themeFromAnswers == 'dark') themeFromAnswers = 'slate';
    final lightCs = await ThemeResolver.resolveColorScheme(themeFromAnswers, Brightness.light);
    final darkCs = await ThemeResolver.resolveColorScheme(themeFromAnswers, Brightness.dark);
    if (!mounted) return;
    setState(() {
      _inThemePhase = true;
      _themeCatalog = catalog;
      _selectedTheme = themeFromAnswers;
      _themePreviewLightCs = lightCs;
      _themePreviewDarkCs = darkCs;
      _colorOverrides = {};
    });
  }

  void _backToWizardFromTheme() {
    setState(() {
      _inThemePhase = false;
      _themeCatalog = null;
      _activeStyle = null;
      _activePalette = null;
      _themePreviewLightCs = null;
      _themePreviewDarkCs = null;
      _colorOverrides = {};
    });
  }

  void _backToTheme() {
    setState(() {
      _renderedSpec = null;
      _reviewTexts = null;
      _inThemePhase = true;
    });
  }

  Future<void> _selectTheme(String themeName) async {
    final lightCs = await ThemeResolver.resolveColorScheme(themeName, Brightness.light);
    final darkCs = await ThemeResolver.resolveColorScheme(themeName, Brightness.dark);
    if (!mounted) return;
    setState(() {
      _selectedTheme = themeName;
      _themePreviewLightCs = lightCs;
      _themePreviewDarkCs = darkCs;
      _colorOverrides = {};
    });
  }

  Future<Color?> _getPairedColor(String token) async {
    final pairToken = tokenPairs[token];
    if (pairToken == null) return null;

    // Check if the paired token has a user override
    if (_colorOverrides.containsKey(pairToken)) {
      final hex = _colorOverrides[pairToken]!;
      final parsed = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
      if (parsed != null) return Color(0xFF000000 | parsed);
    }

    // Load directly from theme data to avoid ColorScheme mapping issues
    final theme = await ThemeResolver.loadTheme(_selectedTheme);
    if (theme == null) return null;
    // Use light mode for contrast reference
    final variant = (theme['light'] ?? theme['dark']) as Map<String, dynamic>?;
    final colors = variant?['colors'] as Map<String, dynamic>?;
    final oklchStr = colors?[pairToken] as String?;
    if (oklchStr == null) return null;
    return ThemeResolver.parseOklch(oklchStr);
  }

  Future<void> _pickColor(String token, Color currentColor) async {
    final pairedColor = await _getPairedColor(token);
    if (!mounted) return;
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => GridColorPickerDialog(
        initialColor: currentColor,
        pairedColor: pairedColor,
        label: tokenHints[token] ?? 'Choose a color',
      ),
    );
    if (picked != null && mounted) {
      final hex = '#${picked.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
      setState(() => _colorOverrides[token] = hex);
      _rebuildPreviewWithOverrides();
    }
  }

  Future<void> _rebuildPreviewWithOverrides() async {
    final theme = await ThemeResolver.loadTheme(_selectedTheme);
    if (theme == null || !mounted) return;

    ColorScheme buildCs(String modeName, Brightness brightness) {
      final colors = (theme[modeName] as Map<String, dynamic>?)?['colors'] as Map<String, dynamic>? ?? {};
      Color c(String key, Color fallback) {
        if (_colorOverrides.containsKey(key)) {
          final hex = _colorOverrides[key]!;
          final parsed = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
          if (parsed != null) return Color(0xFF000000 | parsed);
        }
        return ThemeResolver.parseOklch(colors[key] as String? ?? '') ?? fallback;
      }
      final isDark = brightness == Brightness.dark;
      return ColorScheme(
        brightness: brightness,
        primary: c('primary', const Color(0xFF4F46E5)),
        onPrimary: c('primaryContent', Colors.white),
        secondary: c('secondary', const Color(0xFFEC4899)),
        onSecondary: c('secondaryContent', Colors.white),
        tertiary: c('accent', const Color(0xFF06B6D4)),
        onTertiary: c('accentContent', Colors.black),
        error: c('error', const Color(0xFFEF4444)),
        onError: c('errorContent', Colors.white),
        surface: c('base100', isDark ? const Color(0xFF1E293B) : Colors.white),
        onSurface: c('baseContent', isDark ? Colors.white : const Color(0xFF1E293B)),
        surfaceContainerHighest: c('neutral', const Color(0xFF334155)),
        onSurfaceVariant: c('neutralContent', const Color(0xFF94A3B8)),
        surfaceContainer: c('base200', isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
        surfaceContainerHigh: c('base300', isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0)),
        outline: c('base300', const Color(0xFFE2E8F0)),
      );
    }

    setState(() {
      _themePreviewLightCs = buildCs('light', Brightness.light);
      _themePreviewDarkCs = buildCs('dark', Brightness.dark);
    });
  }

  void _continueFromTheme() {
    // Inject theme name into answers so template rendering picks it up.
    _answers['theme'] = _selectedTheme;
    _renderTemplate();
  }

  bool _validateRequired() {
    if (_questions == null) return false;
    for (final q in _questions!) {
      final question = q as Map<String, dynamic>;
      if (question['required'] != true) continue;
      final id = question['id'] as String;
      final type = question['type'] as String;
      if (type == 'field-list') {
        if (_fieldLists[id] == null || _fieldLists[id]!.isEmpty) return false;
      } else {
        final answer = _answers[id];
        if (answer == null || (answer is String && answer.trim().isEmpty)) {
          return false;
        }
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Determine current phase for the app bar.
    final bool inTextReview = _reviewTexts != null;
    final bool inCatalog = _questions == null && !_inThemePhase && !inTextReview;
    // Breadcrumb step: 1=details, 2=theme, 3=text review (0=catalog, no breadcrumb)
    final int breadcrumbStep = inTextReview ? 3 : _inThemePhase ? 2 : _questions != null ? 1 : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_templateName ?? 'Quick Build'),
        leading: IconButton(
          icon: Icon(inTextReview || _inThemePhase ? Icons.arrow_back : Icons.close),
          onPressed: inTextReview
              ? _backToTheme
              : _inThemePhase
                  ? _backToWizardFromTheme
                  : () => Navigator.pop(context),
        ),
        bottom: !inCatalog
            ? PreferredSize(
                preferredSize: const Size.fromHeight(32),
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                  child: Row(
                    children: [
                      for (int i = 0; i < 3; i++) ...[
                        if (i > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.chevron_right, size: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.25)),
                          ),
                        _buildBreadcrumbItem(
                          theme,
                          ['Enter App Details', 'Choose Theme', 'Customize App Text'][i],
                          step: i + 1,
                          currentStep: breadcrumbStep,
                          onTap: i + 1 < breadcrumbStep
                              ? () {
                                  if (i + 1 == 1 && breadcrumbStep >= 2) {
                                    if (inTextReview) {
                                      _backToTheme();
                                      WidgetsBinding.instance.addPostFrameCallback((_) => _backToWizardFromTheme());
                                    } else {
                                      _backToWizardFromTheme();
                                    }
                                  }
                                  if (i + 1 == 2 && inTextReview) _backToTheme();
                                }
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: inTextReview
          ? _buildTextReview(theme)
          : _inThemePhase
              ? _buildThemePhase(theme)
              : _questions != null
                  ? _buildWizard(theme)
                  : _buildCatalogPicker(theme),
    );
  }

  Widget _buildBreadcrumbItem(ThemeData theme, String label, {required int step, required int currentStep, VoidCallback? onTap}) {
    final isCurrent = step == currentStep;
    final isPast = step < currentStep;
    final color = isCurrent
        ? theme.colorScheme.primary
        : isPast
            ? theme.colorScheme.onSurface.withValues(alpha: 0.6)
            : theme.colorScheme.onSurface.withValues(alpha: 0.25);
    final widget = Text(
      label,
      style: theme.textTheme.bodySmall?.copyWith(
        color: color,
        fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
      ),
    );
    if (isPast && onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: widget,
        ),
      );
    }
    return widget;
  }

  // ---------------------------------------------------------------------------
  // Phase 1: Template catalog picker
  // ---------------------------------------------------------------------------

  Widget _buildCatalogPicker(ThemeData theme) {
    if (_loadingCatalog) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_catalogError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(_catalogError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
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
        ),
      );
    }

    if (_catalog == null || _catalog!.isEmpty) {
      return const Center(child: Text('No templates available yet.'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Pick a template to get started',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Answer a few questions and your app will be ready to go.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        ..._catalog!.map((entry) => Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: const Icon(Icons.bolt, size: 28),
                title: Text(entry.name),
                subtitle: Text(entry.description),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _selectTemplate(entry),
              ),
            )),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Phase 2: Question wizard
  // ---------------------------------------------------------------------------

  Widget _buildWizard(ThemeData theme) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final q in _questions!)
                if ((q as Map<String, dynamic>)['id'] != 'theme')
                  _buildQuestion(q, theme),
              if (_renderError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _renderError!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        // Build button
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _rendering
                  ? null
                  : _validateRequired()
                      ? _goToThemePhase
                      : null,
              icon: _rendering
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.palette),
              label: Text(_rendering ? 'Loading...' : 'Choose Theme'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestion(Map<String, dynamic> question, ThemeData theme) {
    final id = question['id'] as String;
    final label = question['label'] as String;
    final type = question['type'] as String;
    final isRequired = question['required'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: label,
                style: theme.textTheme.titleSmall,
              ),
              if (isRequired)
                TextSpan(
                  text: ' *',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          switch (type) {
            'text' => _buildTextQuestion(id, question),
            'select' => _buildSelectQuestion(id, question),
            'checkbox' => _buildCheckboxQuestion(id, question),
            'field-list' => _buildFieldListQuestion(id, question, theme),
            'field-ref' => _buildFieldRefQuestion(id, question),
            _ => Text('Unsupported question type: $type'),
          },
        ],
      ),
    );
  }

  Widget _buildTextQuestion(String id, Map<String, dynamic> question) {
    return TextField(
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        hintText: question['placeholder'] as String?,
      ),
      onChanged: (value) => setState(() => _answers[id] = value),
      controller: TextEditingController.fromValue(
        TextEditingValue(
          text: (_answers[id] as String?) ?? '',
          selection: TextSelection.collapsed(
            offset: ((_answers[id] as String?) ?? '').length,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectQuestion(String id, Map<String, dynamic> question) {
    final options = (question['options'] as List<dynamic>?)?.cast<String>() ?? [];
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(border: OutlineInputBorder()),
      value: _answers[id] as String?,
      items: options
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: (value) => setState(() => _answers[id] = value),
    );
  }

  Widget _buildCheckboxQuestion(String id, Map<String, dynamic> question) {
    return SwitchListTile(
      value: _answers[id] == true,
      onChanged: (value) => setState(() => _answers[id] = value),
      title: Text(question['label'] as String),
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildFieldRefQuestion(String id, Map<String, dynamic> question) {
    final ref = question['ref'] as String?;
    final fields = ref != null ? (_fieldLists[ref] ?? []) : <Map<String, dynamic>>[];

    if (fields.isEmpty) {
      return Text(
        'Add fields above first',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }

    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        hintText: question['placeholder'] as String?,
      ),
      value: _answers[id] as String?,
      items: fields
          .map((f) => DropdownMenuItem(
                value: f['name'] as String,
                child: Text(f['label'] as String? ?? f['name'] as String),
              ))
          .toList(),
      onChanged: (value) => setState(() => _answers[id] = value),
    );
  }

  // ---------------------------------------------------------------------------
  // Field-list question type
  // ---------------------------------------------------------------------------

  Widget _buildFieldListQuestion(
    String id,
    Map<String, dynamic> question,
    ThemeData theme,
  ) {
    final fields = _fieldLists[id] ??= [];
    final presets =
        (question['presets'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
            [];

    // Track which presets are already added (by name).
    final addedNames = fields.map((f) => f['name'] as String).toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Preset chips
        if (presets.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: presets.map((preset) {
              final name = preset['name'] as String;
              final presetLabel = preset['label'] as String;
              final isAdded = addedNames.contains(name);
              return FilterChip(
                label: Text(presetLabel),
                selected: isAdded,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      fields.add(Map<String, dynamic>.from(preset));
                    } else {
                      fields.removeWhere((f) => f['name'] == name);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
        ],
        // Current fields list (drag to reorder)
        if (fields.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(Icons.swap_vert, size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'Drag to reorder fields',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        if (fields.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: fields.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final item = fields.removeAt(oldIndex);
                fields.insert(newIndex, item);
              });
            },
            itemBuilder: (context, idx) {
              final field = fields[idx];
              return Card(
                key: ValueKey('${id}_field_$idx'),
                child: ListTile(
                  dense: true,
                  leading: ReorderableDragStartListener(
                    index: idx,
                    child: Icon(Icons.drag_handle, size: 20, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  title: Row(
                    children: [
                      _fieldTypeIcon(field['type'] as String),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(field['label'] as String? ?? field['name'] as String),
                      ),
                    ],
                  ),
                  subtitle: Text(field['type'] as String),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        tooltip: 'Rename field',
                        onPressed: () => _editField(id, idx),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, size: 18, color: theme.colorScheme.error),
                        tooltip: 'Remove',
                        onPressed: () => setState(() => fields.removeAt(idx)),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 8),
        // Add custom field button
        OutlinedButton.icon(
          onPressed: () => _addCustomField(id),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Custom Field'),
        ),
      ],
    );
  }

  Widget _fieldTypeIcon(String type) {
    final icon = switch (type) {
      'text' => Icons.short_text,
      'email' => Icons.email_outlined,
      'number' => Icons.tag,
      'date' => Icons.calendar_today,
      'datetime' => Icons.access_time,
      'multiline' => Icons.notes,
      'select' => Icons.arrow_drop_down_circle_outlined,
      'checkbox' => Icons.check_box_outlined,
      _ => Icons.text_fields,
    };
    return Icon(icon, size: 20);
  }

  Future<void> _addCustomField(String questionId) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => const _AddFieldDialog(),
    );
    if (result != null) {
      setState(() {
        _fieldLists[questionId] ??= [];
        _fieldLists[questionId]!.add(result);
      });
    }
  }

  /// Opens a dialog to rename a field and (for select fields) edit options.
  Future<void> _editField(String questionId, int fieldIdx) async {
    final field = _fieldLists[questionId]![fieldIdx];
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _EditFieldDialog(field: field),
    );
    if (result != null) {
      setState(() {
        _fieldLists[questionId]![fieldIdx] = result;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Phase 2.5: Theme selection UI
  // ---------------------------------------------------------------------------

  Widget _buildThemePhase(ThemeData theme) {
    final catalog = _themeCatalog ?? [];
    final lightCs = _themePreviewLightCs ?? theme.colorScheme;
    final darkCs = _themePreviewDarkCs ?? theme.colorScheme;

    // Extract style/palette from tags (supports both old array and new object format)
    String? getStyle(Map<String, dynamic> entry) {
      final tags = entry['tags'];
      if (tags is Map) return tags['style'] as String?;
      return null;
    }
    String? getPalette(Map<String, dynamic> entry) {
      final tags = entry['tags'];
      if (tags is Map) return tags['palette'] as String?;
      return null;
    }

    // Collect unique styles and palettes
    final allStyles = <String>{};
    final allPalettes = <String>{};
    for (final entry in catalog) {
      final s = getStyle(entry);
      final p = getPalette(entry);
      if (s != null) allStyles.add(s);
      if (p != null) allPalettes.add(p);
    }
    final sortedStyles = allStyles.toList()..sort();
    final sortedPalettes = allPalettes.toList()..sort();

    // Filter by active style/palette and sort alphabetically
    final filteredCatalog = catalog.where((entry) {
      if (_activeStyle != null && getStyle(entry) != _activeStyle) return false;
      if (_activePalette != null && getPalette(entry) != _activePalette) return false;
      return true;
    }).toList()
      ..sort((a, b) => ((a['displayName'] ?? a['name']) as String)
          .compareTo((b['displayName'] ?? b['name']) as String));

    Widget buildChip(String label, bool isActive, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isActive ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isActive ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left pane — scrollable theme list
              SizedBox(
                width: 230,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: Text('Themes', style: theme.textTheme.titleSmall),
                    ),
                    // Two-dimension tag filters
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (sortedStyles.isNotEmpty) ...[
                            Text('STYLE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1, color: theme.colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 3),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                for (final tag in sortedStyles)
                                  buildChip(tag, _activeStyle == tag, () => setState(() => _activeStyle = _activeStyle == tag ? null : tag)),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                          if (sortedPalettes.isNotEmpty) ...[
                            Text('PALETTE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1, color: theme.colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 3),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                for (final tag in sortedPalettes)
                                  buildChip(tag, _activePalette == tag, () => setState(() => _activePalette = _activePalette == tag ? null : tag)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: filteredCatalog.length,
                        itemBuilder: (context, index) {
                          final entry = filteredCatalog[index];
                          final name = entry['name'] as String;
                          final displayName = entry['displayName'] as String? ?? name;
                          final entryTags = entry['tags'];
                          final tagList = <String>[];
                          if (entryTags is Map) {
                            if (entryTags['style'] != null) tagList.add(entryTags['style'] as String);
                            if (entryTags['palette'] != null) tagList.add(entryTags['palette'] as String);
                          }
                          final isSelected = name == _selectedTheme;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: _ThemeCard(
                              themeName: name,
                              displayName: displayName,
                              tags: tagList,
                              isSelected: isSelected,
                              onTap: () => _selectTheme(name),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              // Right pane — preview + color customization
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Dual light/dark previews
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Light Mode', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              _buildInlinePreview(lightCs),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Dark Mode', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              _buildInlinePreview(darkCs),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Customize Colors', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    _colorRow('Primary', 'primary', lightCs.primary, theme),
                    _colorRow('Secondary', 'secondary', lightCs.secondary, theme),
                    _colorRow('Accent', 'accent', lightCs.tertiary, theme),
                    _colorRow('Background', 'base100', lightCs.surface, theme),
                    _colorRow('Text', 'baseContent', lightCs.onSurface, theme),
                    _colorRow('Error', 'error', lightCs.error, theme),
                    const SizedBox(height: 16),
                    // Collapsible App Branding section
                    InkWell(
                      onTap: () => setState(() => _brandingExpanded = !_brandingExpanded),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              _brandingExpanded ? Icons.expand_less : Icons.expand_more,
                              size: 20,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text('App Branding', style: theme.textTheme.titleSmall),
                          ],
                        ),
                      ),
                    ),
                    if (_brandingExpanded) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _logoUrlController,
                        decoration: const InputDecoration(
                          labelText: 'Logo URL',
                          hintText: 'https://example.com/logo.png',
                          helperText: 'Optional — displayed in the app drawer',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _faviconUrlController,
                        decoration: const InputDecoration(
                          labelText: 'Favicon URL',
                          hintText: 'https://example.com/favicon.ico',
                          helperText: 'Optional — for web framework compatibility',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
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
                              onSelectionChanged: (v) => setState(() => _headerStyle = v.first),
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
                      TextField(
                        controller: _fontFamilyController,
                        decoration: const InputDecoration(
                          labelText: 'Font Family',
                          hintText: 'e.g., Inter, Georgia',
                          helperText: 'Optional — custom font for the app',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        // Continue button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _rendering ? null : _continueFromTheme,
              icon: _rendering
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.arrow_forward),
              label: Text(_rendering ? 'Building...' : 'Continue'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInlinePreview(ColorScheme cs) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: cs.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // App bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: cs.primary,
            child: Row(children: [
              Icon(Icons.menu, color: cs.onPrimary, size: 18),
              const SizedBox(width: 10),
              Text('My App', style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
          ),
          // Body
          Container(
            color: cs.surface,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Page Heading', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 2),
                Text('Body text on the surface.', style: TextStyle(color: cs.onSurface, fontSize: 12)),
                const SizedBox(height: 8),
                // Input field
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.outline),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Form input...', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 12)),
                ),
                const SizedBox(height: 10),
                // Buttons
                Wrap(spacing: 8, runSpacing: 6, children: [
                  _previewBtn('Primary', cs.primary, cs.onPrimary),
                  _previewBtn('Secondary', cs.secondary, cs.onSecondary),
                  _previewBtn('Accent', cs.tertiary, cs.onTertiary),
                ]),
                const SizedBox(height: 10),
                // Badges
                Wrap(spacing: 6, runSpacing: 6, children: [
                  _previewBadge('Success', const Color(0xFF22C55E), Colors.white),
                  _previewBadge('Error', cs.error, cs.onError),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewBtn(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
  );

  Widget _previewBadge(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
    child: Text(label, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w500)),
  );

  Widget _colorRow(String label, String token, Color color, ThemeData theme) {
    return ColorRow(
      label: label,
      token: token,
      color: color,
      hasOverride: _colorOverrides.containsKey(token),
      onTap: () => _pickColor(token, color),
      onReset: _colorOverrides.containsKey(token)
          ? () {
              setState(() => _colorOverrides.remove(token));
              _rebuildPreviewWithOverrides();
            }
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Phase 3: Text review
  // ---------------------------------------------------------------------------

  Widget _buildTextReview(ThemeData theme) {
    final texts = _reviewTexts!;

    if (texts.isEmpty) {
      // No reviewable texts — go straight to finish.
      WidgetsBinding.instance.addPostFrameCallback((_) => _finishWithSpec());
      return const Center(child: CircularProgressIndicator());
    }

    // Group texts by category.
    final grouped = <String, List<_ReviewableText>>{};
    for (final rt in texts) {
      grouped.putIfAbsent(rt.category, () => []).add(rt);
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Review the text in your app',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'These are the labels, titles, and messages your users will see. '
                'Edit any you\'d like to customize.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              for (final categoryEntry in grouped.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 12),
                  child: Text(
                    categoryEntry.key,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                ...categoryEntry.value.map((rt) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: rt.controller,
                        decoration: InputDecoration(
                          labelText: rt.label,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        maxLines: rt.isMultiline ? 3 : 1,
                        minLines: 1,
                      ),
                    )),
              ],
            ],
          ),
        ),
        // Finish button
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _finishWithSpec,
              icon: const Icon(Icons.check),
              label: const Text('Looks Good — Launch App'),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reviewable text extraction
// ---------------------------------------------------------------------------

/// A single text string in the rendered spec that the user can review/edit.
class _ReviewableText {
  /// Dot-separated path into the spec JSON (e.g., "pages.listPage.title").
  final List<String> path;

  /// Human-friendly label shown above the text field.
  final String label;

  /// Category for grouping in the review UI.
  final String category;

  /// Whether the text might be multi-line (e.g., help overview).
  final bool isMultiline;

  /// Controller holding the current (possibly edited) value.
  final TextEditingController controller;

  _ReviewableText({
    required this.path,
    required this.label,
    required this.category,
    required String value,
    this.isMultiline = false,
  }) : controller = TextEditingController(text: value);
}

/// Walks a rendered ODS spec and extracts all user-facing text strings.
List<_ReviewableText> _extractReviewableTexts(Map<String, dynamic> spec) {
  final results = <_ReviewableText>[];

  // App name
  if (spec['appName'] is String) {
    results.add(_ReviewableText(
      path: ['appName'],
      label: 'App Name',
      category: 'App',
      value: spec['appName'] as String,
    ));
  }

  // Help overview
  final help = spec['help'] as Map<String, dynamic>?;
  if (help != null && help['overview'] is String) {
    results.add(_ReviewableText(
      path: ['help', 'overview'],
      label: 'Help Overview',
      category: 'Help & Guidance',
      value: help['overview'] as String,
      isMultiline: true,
    ));
    // Per-page help
    final pageHelp = help['pages'] as Map<String, dynamic>?;
    if (pageHelp != null) {
      for (final entry in pageHelp.entries) {
        if (entry.value is String) {
          results.add(_ReviewableText(
            path: ['help', 'pages', entry.key],
            label: 'Help: ${entry.key}',
            category: 'Help & Guidance',
            value: entry.value as String,
            isMultiline: true,
          ));
        }
      }
    }
  }

  // Tour steps
  final tour = spec['tour'] as List<dynamic>?;
  if (tour != null) {
    for (var i = 0; i < tour.length; i++) {
      final step = tour[i] as Map<String, dynamic>;
      if (step['title'] is String) {
        results.add(_ReviewableText(
          path: ['tour', '$i', 'title'],
          label: 'Tour Step ${i + 1} Title',
          category: 'Help & Guidance',
          value: step['title'] as String,
        ));
      }
      if (step['content'] is String) {
        results.add(_ReviewableText(
          path: ['tour', '$i', 'content'],
          label: 'Tour Step ${i + 1} Text',
          category: 'Help & Guidance',
          value: step['content'] as String,
          isMultiline: true,
        ));
      }
    }
  }

  // Pages
  final pages = spec['pages'] as Map<String, dynamic>?;
  if (pages != null) {
    for (final pageEntry in pages.entries) {
      final pageId = pageEntry.key;
      final page = pageEntry.value as Map<String, dynamic>;
      final pageTitle = page['title'] as String? ?? pageId;

      // Page title
      if (page['title'] is String) {
        results.add(_ReviewableText(
          path: ['pages', pageId, 'title'],
          label: 'Page Title',
          category: 'Page: $pageTitle',
          value: page['title'] as String,
        ));
      }

      // Walk content array
      final content = page['content'] as List<dynamic>?;
      if (content != null) {
        _extractFromComponents(content, ['pages', pageId, 'content'], pageTitle, results);
      }
    }
  }

  // Menu labels
  final menu = spec['menu'] as List<dynamic>?;
  if (menu != null) {
    for (var i = 0; i < menu.length; i++) {
      final item = menu[i] as Map<String, dynamic>;
      if (item['label'] is String) {
        results.add(_ReviewableText(
          path: ['menu', '$i', 'label'],
          label: 'Menu Item ${i + 1}',
          category: 'Navigation',
          value: item['label'] as String,
        ));
      }
    }
  }

  return results;
}

/// Extracts reviewable texts from a component content array.
void _extractFromComponents(
  List<dynamic> components,
  List<String> basePath,
  String pageTitle,
  List<_ReviewableText> results,
) {
  for (var i = 0; i < components.length; i++) {
    final comp = components[i] as Map<String, dynamic>;
    final type = comp['component'] as String?;
    final path = [...basePath, '$i'];

    switch (type) {
      case 'text':
        final content = comp['content'] as String?;
        // Skip aggregate-heavy text (mostly data, not prose).
        if (content != null && !_isAggregateOnly(content)) {
          results.add(_ReviewableText(
            path: [...path, 'content'],
            label: 'Text',
            category: 'Page: $pageTitle',
            value: content,
            isMultiline: content.length > 60,
          ));
        }
        break;

      case 'button':
        if (comp['label'] is String) {
          results.add(_ReviewableText(
            path: [...path, 'label'],
            label: 'Button Label',
            category: 'Page: $pageTitle',
            value: comp['label'] as String,
          ));
        }
        // showMessage inside onClick
        final onClick = comp['onClick'] as List<dynamic>?;
        if (onClick != null) {
          for (var j = 0; j < onClick.length; j++) {
            final action = onClick[j] as Map<String, dynamic>;
            if (action['action'] == 'showMessage' && action['message'] is String) {
              results.add(_ReviewableText(
                path: [...path, 'onClick', '$j', 'message'],
                label: 'Success Message',
                category: 'Page: $pageTitle',
                value: action['message'] as String,
              ));
            }
          }
        }
        break;

      case 'summary':
        if (comp['label'] is String) {
          results.add(_ReviewableText(
            path: [...path, 'label'],
            label: 'Summary Card Label',
            category: 'Page: $pageTitle',
            value: comp['label'] as String,
          ));
        }
        break;

      case 'chart':
        if (comp['title'] is String) {
          results.add(_ReviewableText(
            path: [...path, 'title'],
            label: 'Chart Title',
            category: 'Page: $pageTitle',
            value: comp['title'] as String,
          ));
        }
        break;

      case 'list':
        // Row action labels
        final rowActions = comp['rowActions'] as List<dynamic>?;
        if (rowActions != null) {
          for (var j = 0; j < rowActions.length; j++) {
            final action = rowActions[j] as Map<String, dynamic>;
            if (action['label'] is String) {
              results.add(_ReviewableText(
                path: [...path, 'rowActions', '$j', 'label'],
                label: 'Row Action',
                category: 'Page: $pageTitle',
                value: action['label'] as String,
              ));
            }
            if (action['confirm'] is String) {
              results.add(_ReviewableText(
                path: [...path, 'rowActions', '$j', 'confirm'],
                label: 'Confirmation Text',
                category: 'Page: $pageTitle',
                value: action['confirm'] as String,
              ));
            }
          }
        }
        break;

      case 'tabs':
        final tabs = comp['tabs'] as List<dynamic>?;
        if (tabs != null) {
          for (var t = 0; t < tabs.length; t++) {
            final tab = tabs[t] as Map<String, dynamic>;
            if (tab['label'] is String) {
              results.add(_ReviewableText(
                path: [...path, 'tabs', '$t', 'label'],
                label: 'Tab Label',
                category: 'Page: $pageTitle',
                value: tab['label'] as String,
              ));
            }
            // Recurse into tab content
            final tabContent = tab['content'] as List<dynamic>?;
            if (tabContent != null) {
              _extractFromComponents(
                tabContent,
                [...path, 'tabs', '$t', 'content'],
                pageTitle,
                results,
              );
            }
          }
        }
        break;
    }
  }
}

/// Returns true if a text string is purely aggregate expressions (no prose).
bool _isAggregateOnly(String text) {
  final stripped = text.replaceAll(RegExp(r'\{[A-Z]+\([^}]*\)\}'), '').trim();
  // If removing all aggregate expressions leaves only whitespace, %, or commas,
  // it's not useful prose for the user to review.
  return stripped.isEmpty || RegExp(r'^[%,\s]*$').hasMatch(stripped);
}

/// Sets a value at a nested path in a JSON structure.
///
/// Handles both Map keys and List indices (numeric strings).
void _setNestedValue(dynamic root, List<String> path, String value) {
  dynamic current = root;
  for (var i = 0; i < path.length - 1; i++) {
    final key = path[i];
    if (current is Map<String, dynamic>) {
      current = current[key];
    } else if (current is List) {
      final idx = int.tryParse(key);
      if (idx != null && idx < current.length) {
        current = current[idx];
      } else {
        return; // Path broken — skip silently.
      }
    } else {
      return;
    }
  }
  final lastKey = path.last;
  if (current is Map<String, dynamic>) {
    current[lastKey] = value;
  } else if (current is List) {
    final idx = int.tryParse(lastKey);
    if (idx != null && idx < current.length) {
      current[idx] = value;
    }
  }
}

// ---------------------------------------------------------------------------
// Add Custom Field dialog
// ---------------------------------------------------------------------------

class _AddFieldDialog extends StatefulWidget {
  const _AddFieldDialog();

  @override
  State<_AddFieldDialog> createState() => _AddFieldDialogState();
}

class _AddFieldDialogState extends State<_AddFieldDialog> {
  final _nameController = TextEditingController();
  String _type = 'text';
  final _optionsController = TextEditingController();

  static const _types = [
    ('text', 'Text'),
    ('number', 'Number'),
    ('date', 'Date'),
    ('datetime', 'Date & Time'),
    ('select', 'Dropdown'),
    ('multiline', 'Long Text'),
    ('email', 'Email'),
    ('checkbox', 'Checkbox'),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _optionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Field'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Field Name',
              border: OutlineInputBorder(),
              hintText: 'e.g., Due Date, Priority',
            ),
            textCapitalization: TextCapitalization.words,
            autofocus: true,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(
              labelText: 'Type',
              border: OutlineInputBorder(),
            ),
            value: _type,
            items: _types
                .map((t) => DropdownMenuItem(value: t.$1, child: Text(t.$2)))
                .toList(),
            onChanged: (v) => setState(() => _type = v ?? 'text'),
          ),
          if (_type == 'select') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _optionsController,
              decoration: const InputDecoration(
                labelText: 'Options (comma-separated)',
                border: OutlineInputBorder(),
                hintText: 'e.g., Low, Medium, High',
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;

            // Convert display name to camelCase programmatic name.
            final progName = _toCamelCase(name);

            final field = <String, dynamic>{
              'name': progName,
              'label': name,
              'type': _type,
            };

            if (_type == 'select') {
              final opts = _optionsController.text
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
              if (opts.isNotEmpty) field['options'] = opts;
            }

            Navigator.pop(context, field);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }

  static String _toCamelCase(String input) {
    final words = input.split(RegExp(r'[\s_-]+'));
    if (words.isEmpty) return input.toLowerCase();
    final first = words.first.toLowerCase();
    final rest = words.skip(1).map((w) {
      if (w.isEmpty) return '';
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    });
    return first + rest.join();
  }
}

// ---------------------------------------------------------------------------
// Edit Field dialog — rename + edit options for select fields
// ---------------------------------------------------------------------------

class _EditFieldDialog extends StatefulWidget {
  final Map<String, dynamic> field;

  const _EditFieldDialog({required this.field});

  @override
  State<_EditFieldDialog> createState() => _EditFieldDialogState();
}

class _EditFieldDialogState extends State<_EditFieldDialog> {
  late final TextEditingController _labelController;
  late final TextEditingController _optionsController;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(
      text: widget.field['label'] as String? ?? widget.field['name'] as String,
    );
    final options = (widget.field['options'] as List<dynamic>?)?.cast<String>() ?? [];
    _optionsController = TextEditingController(text: options.join(', '));
  }

  @override
  void dispose() {
    _labelController.dispose();
    _optionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSelect = widget.field['type'] == 'select';

    return AlertDialog(
      title: const Text('Edit Field'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _labelController,
            decoration: const InputDecoration(
              labelText: 'Display Name',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            autofocus: true,
          ),
          if (isSelect) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _optionsController,
              decoration: const InputDecoration(
                labelText: 'Options (comma-separated)',
                border: OutlineInputBorder(),
                hintText: 'e.g., To Do, In Progress, Done',
              ),
              maxLines: 3,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final label = _labelController.text.trim();
            if (label.isEmpty) return;

            final updated = Map<String, dynamic>.from(widget.field);
            updated['label'] = label;
            updated['name'] = _AddFieldDialogState._toCamelCase(label);

            if (isSelect) {
              final opts = _optionsController.text
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
              if (opts.isNotEmpty) updated['options'] = opts;
            }

            Navigator.pop(context, updated);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Edit Options dialog (legacy — kept for compatibility but _EditFieldDialog
// now handles this inline)
// ---------------------------------------------------------------------------

class _EditOptionsDialog extends StatefulWidget {
  final List<String> options;

  const _EditOptionsDialog({required this.options});

  @override
  State<_EditOptionsDialog> createState() => _EditOptionsDialogState();
}

class _EditOptionsDialogState extends State<_EditOptionsDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.options.join(', '));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Options'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          labelText: 'Options (comma-separated)',
          border: OutlineInputBorder(),
          hintText: 'e.g., To Do, In Progress, Done',
        ),
        maxLines: 3,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final opts = _controller.text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            Navigator.pop(context, opts);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Theme card — shows theme name + 3 color dots
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
    final colors = ((theme['light'] ?? theme['dark']) as Map<String, dynamic>?)?['colors'] as Map<String, dynamic>?;
    if (colors == null) return;
    setState(() {
      _primary = ThemeResolver.parseOklch(colors['primary'] as String? ?? '');
      _secondary = ThemeResolver.parseOklch(colors['secondary'] as String? ?? '');
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
          color: widget.isSelected ? theme.colorScheme.primary : theme.colorScheme.outline.withValues(alpha: 0.3),
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
                        fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.isSelected)
                    Icon(Icons.check_circle, size: 18, color: theme.colorScheme.primary),
                ],
              ),
              if (widget.tags.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: widget.tags.map((tag) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(tag, style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurfaceVariant)),
                  )).toList(),
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


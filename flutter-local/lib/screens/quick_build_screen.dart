import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../engine/template_engine.dart';
import '../engine/theme_resolver.dart';

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

  // Phase 3: text review
  Map<String, dynamic>? _renderedSpec;
  List<_ReviewableText>? _reviewTexts;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
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
      spec['branding'] = branding;

      debugPrint('ODS Quick Build rendered spec:\n${const JsonEncoder.withIndent('  ').convert(spec)}');

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

  static const _tokenPairs = {
    'primary': 'primaryContent',
    'secondary': 'secondaryContent',
    'accent': 'accentContent',
    'base100': 'baseContent',
    'baseContent': 'base100',
    'error': 'errorContent',
  };

  static const _tokenHints = {
    'primary': 'Main action buttons and links',
    'secondary': 'Supporting actions and highlights',
    'accent': 'Decorative elements and badges',
    'base100': 'Page background color',
    'baseContent': 'Main body text color',
    'error': 'Error messages and alerts',
  };

  Future<Color?> _getPairedColor(String token) async {
    final pairToken = _tokenPairs[token];
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
      builder: (_) => _GridColorPickerDialog(
        initialColor: currentColor,
        pairedColor: pairedColor,
        label: _tokenHints[token] ?? 'Choose a color',
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
    final hasOverride = _colorOverrides.containsKey(token);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _pickColor(token, color),
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
              if (hasOverride)
                IconButton(
                  icon: Icon(Icons.undo, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  tooltip: 'Reset',
                  onPressed: () {
                    setState(() => _colorOverrides.remove(token));
                    _rebuildPreviewWithOverrides();
                  },
                ),
              Icon(Icons.edit, size: 16, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
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

// ---------------------------------------------------------------------------
// Grid color picker dialog
// ---------------------------------------------------------------------------

/// 6x8 curated color grid + grayscale row.
const _colorGrid = <List<int>>[
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

double _wcagLuminance(Color c) {
  // Color.r/.g/.b are 0.0-1.0 doubles in modern Flutter
  double linearize(double s) {
    if (s <= 0.04045) return s / 12.92;
    return math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }
  return 0.2126 * linearize(c.r) + 0.7152 * linearize(c.g) + 0.0722 * linearize(c.b);
}

double _contrastRatio(Color c1, Color c2) {
  final l1 = _wcagLuminance(c1);
  final l2 = _wcagLuminance(c2);
  final lighter = l1 > l2 ? l1 : l2;
  final darker = l1 > l2 ? l2 : l1;
  return (lighter + 0.05) / (darker + 0.05);
}

String _colorToHex(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

/// Adjust [color] toward white or black until it achieves 4.5:1 contrast against [paired].
Color _fixContrast(Color color, Color paired) {
  final pairedLum = _wcagLuminance(paired);
  final goLighter = pairedLum < 0.2;
  final r = color.r, g = color.g, b = color.b; // 0.0-1.0

  double lo = 0, hi = 1;
  Color best = color;
  for (int i = 0; i < 30; i++) {
    final mid = (lo + hi) / 2;
    final nr = goLighter ? r + (1.0 - r) * mid : r * (1 - mid);
    final ng = goLighter ? g + (1.0 - g) * mid : g * (1 - mid);
    final nb = goLighter ? b + (1.0 - b) * mid : b * (1 - mid);
    final candidate = Color.fromARGB(255, (nr * 255).round(), (ng * 255).round(), (nb * 255).round());
    if (_contrastRatio(candidate, paired) >= 4.5) {
      best = candidate;
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return best;
}

class _GridColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  final Color? pairedColor;
  final String label;
  const _GridColorPickerDialog({required this.initialColor, this.pairedColor, required this.label});

  @override
  State<_GridColorPickerDialog> createState() => _GridColorPickerDialogState();
}

class _GridColorPickerDialogState extends State<_GridColorPickerDialog> {
  late Color _selected;
  bool _showRgb = false;
  late TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialColor;
    _hexController = TextEditingController(text: _colorToHex(widget.initialColor));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _setColor(Color c) {
    setState(() {
      _selected = c;
      _hexController.text = _colorToHex(c);
    });
  }

  void _showWhyDialog(BuildContext context) {
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

  List<Widget> _buildColorGridSections(ThemeData theme) {
    final allColors = _colorGrid.expand((row) => row).toList();
    final paired = widget.pairedColor;
    final recommended = <int>[];
    final other = <int>[];

    if (paired != null) {
      final seen = <int>{};
      for (final c in allColors) {
        if (_contrastRatio(Color(c), paired) >= 4.5) {
          recommended.add(c);
          seen.add(c);
        } else {
          other.add(c);
        }
      }
      // Add fixed versions of failing colors (deduplicated)
      for (final c in other) {
        final fixed = _fixContrast(Color(c), paired);
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
                  onTap: () => _showWhyDialog(context),
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
    final ratio = widget.pairedColor != null ? _contrastRatio(_selected, widget.pairedColor!) : null;
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
                          onTap: () => _setColor(_fixContrast(_selected, widget.pairedColor!)),
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

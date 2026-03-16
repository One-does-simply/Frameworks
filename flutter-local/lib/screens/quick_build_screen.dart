import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../engine/template_engine.dart';

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

  /// Navigates back from text review to the question wizard.
  void _backToWizard() {
    setState(() {
      _renderedSpec = null;
      _reviewTexts = null;
    });
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
    final String title;
    if (inTextReview) {
      title = 'Review & Customize';
    } else {
      title = _templateName ?? 'Quick Build';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: Icon(inTextReview ? Icons.arrow_back : Icons.close),
          onPressed: inTextReview ? _backToWizard : () => Navigator.pop(context),
        ),
      ),
      body: inTextReview
          ? _buildTextReview(theme)
          : _questions != null
              ? _buildWizard(theme)
              : _buildCatalogPicker(theme),
    );
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
              Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.outline),
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
            color: theme.colorScheme.outline,
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
                _buildQuestion(q as Map<String, dynamic>, theme),
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
                      ? _renderTemplate
                      : null,
              icon: _rendering
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.rocket_launch),
              label: Text(_rendering ? 'Building...' : 'Build My App'),
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
        style: TextStyle(color: Theme.of(context).colorScheme.outline),
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
                    child: const Icon(Icons.drag_handle, size: 20),
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
                  color: theme.colorScheme.outline,
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

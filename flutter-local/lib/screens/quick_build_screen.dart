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
// Quick Build screen — template picker + question wizard
// ---------------------------------------------------------------------------

/// Full-screen flow: pick a template → answer questions → get a rendered spec.
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
      final specJson = jsonEncode(rendered);

      Navigator.pop(this.context, specJson);
    } catch (e) {
      setState(() {
        _rendering = false;
        _renderError = 'Failed to build app: $e';
      });
    }
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

    return Scaffold(
      appBar: AppBar(
        title: Text(_templateName ?? 'Quick Build'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _questions != null
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
        // Current fields list
        ...fields.asMap().entries.map((entry) {
          final idx = entry.key;
          final field = entry.value;
          return Card(
            child: ListTile(
              dense: true,
              leading: _fieldTypeIcon(field['type'] as String),
              title: Text(field['label'] as String? ?? field['name'] as String),
              subtitle: Text(field['type'] as String),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (field['type'] == 'select')
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      tooltip: 'Edit options',
                      onPressed: () => _editFieldOptions(id, idx),
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
        }),
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

  Future<void> _editFieldOptions(String questionId, int fieldIdx) async {
    final field = _fieldLists[questionId]![fieldIdx];
    final currentOptions =
        (field['options'] as List<dynamic>?)?.cast<String>() ?? [];
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => _EditOptionsDialog(options: currentOptions),
    );
    if (result != null) {
      setState(() {
        _fieldLists[questionId]![fieldIdx]['options'] = result;
      });
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
// Edit Options dialog (for select fields in field-list)
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

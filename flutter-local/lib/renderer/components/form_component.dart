import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/app_engine.dart';
import '../../engine/formula_evaluator.dart';
import '../../models/ods_component.dart';
import '../../models/ods_field_definition.dart';

/// Renders an [OdsFormComponent] as a vertical list of input fields.
///
/// ODS Spec: The form component has a unique `id` (referenced by submit
/// actions) and an ordered array of field definitions. Each field becomes
/// an appropriate input widget based on its type.
///
/// Computed fields (those with a `formula`) render as read-only and update
/// live as the user fills in the referenced fields.
///
/// Conditionally visible fields (`visibleWhen`) are shown/hidden based on
/// another field's current value.
///
/// Validation rules (`validation`) provide inline error feedback when the
/// user submits invalid data.
class OdsFormWidget extends StatefulWidget {
  final OdsFormComponent model;

  const OdsFormWidget({super.key, required this.model});

  @override
  State<OdsFormWidget> createState() => _OdsFormWidgetState();
}

class _OdsFormWidgetState extends State<OdsFormWidget> {
  /// Notifier used to trigger computed field recalculation and visibility
  /// re-evaluation when any field in the form changes.
  final _fieldChangeNotifier = ValueNotifier<int>(0);

  void _onFieldChanged() {
    _fieldChangeNotifier.value++;
  }

  @override
  void dispose() {
    _fieldChangeNotifier.dispose();
    super.dispose();
  }

  /// Checks whether a field should be visible based on its `visibleWhen` condition
  /// and role-based access control.
  bool _isFieldVisible(OdsFieldDefinition field, Map<String, String> formState, [AppEngine? engine]) {
    // Hidden fields carry data (e.g., correct answers in quizzes) but never render.
    if (field.type == 'hidden') return false;
    // Role-based visibility: hide fields the user can't access.
    if (field.roles != null && field.roles!.isNotEmpty && engine != null) {
      if (engine.isMultiUser && !engine.authService.hasAccess(field.roles)) {
        return false;
      }
    }
    final condition = field.visibleWhen;
    if (condition == null) return true;
    final watchedValue = formState[condition.field] ?? '';
    return watchedValue == condition.equals;
  }

  /// Initializes default values for hidden fields so they participate in form
  /// state without rendering any UI.
  void _initHiddenDefaults(AppEngine engine) {
    final formState = engine.getFormState(widget.model.id);
    for (final field in widget.model.fields) {
      if (field.type != 'hidden') continue;
      if (formState.containsKey(field.name)) continue;
      if (field.defaultValue != null) {
        engine.updateFormField(widget.model.id, field.name, field.defaultValue!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ValueListenableBuilder<int>(
        valueListenable: _fieldChangeNotifier,
        builder: (context, _, __) {
          final engine = context.watch<AppEngine>();
          _initHiddenDefaults(engine);
          final formState = engine.getFormState(widget.model.id);

          // Use recordGeneration in keys so that when a record cursor moves,
          // all fields (especially dropdowns) are fully recreated with new values.
          final recordGen = engine.recordGeneration;
          final cursor = engine.getRecordCursor(widget.model.id);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Show record position indicator for forms backed by a record cursor.
              if (cursor != null && cursor.count > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Record ${cursor.currentIndex + 1} of ${cursor.count}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ...widget.model.fields.where((field) {
              return _isFieldVisible(field, formState, engine);
            }).map((field) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: field.isComputed
                    ? _OdsComputedFieldWidget(
                        formId: widget.model.id,
                        field: field,
                        allFields: widget.model.fields,
                        changeNotifier: _fieldChangeNotifier,
                      )
                    : _OdsFieldWidget(
                        key: ValueKey('${widget.model.id}_${field.name}_$recordGen'),
                        formId: widget.model.id,
                        field: field,
                        onChanged: _onFieldChanged,
                      ),
              );
            }),
            ],
          );
        },
      ),
    );
  }
}

/// Renders a computed (formula-based) field as a read-only display that
/// updates live as dependency fields change.
class _OdsComputedFieldWidget extends StatelessWidget {
  final String formId;
  final OdsFieldDefinition field;
  final List<OdsFieldDefinition> allFields;
  final ValueNotifier<int> changeNotifier;

  const _OdsComputedFieldWidget({
    required this.formId,
    required this.field,
    required this.allFields,
    required this.changeNotifier,
  });

  String _labelText() {
    final base = field.label ?? field.name;
    return '$base (computed)';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: changeNotifier,
      builder: (context, _, __) {
        final engine = context.read<AppEngine>();
        final formState = engine.getFormState(formId);

        // Build the values map from form state for formula evaluation.
        final values = <String, String?>{};
        for (final f in allFields) {
          values[f.name] = formState[f.name];
        }

        final result = FormulaEvaluator.evaluate(
          field.formula!,
          field.type,
          values,
        );

        // Push the computed value into the engine so it's available for display
        // in lists (but it won't be stored — the action handler will skip it
        // based on the field definition).
        if (result.isNotEmpty) {
          engine.updateFormField(formId, field.name, result);
        }

        // Apply currency symbol for fields marked with currency: true,
        // or fall back to all number computed fields when no field opts in.
        var displayResult = result;
        final anyCurrency = allFields.any((f) => f.currency);
        if (field.currency || (!anyCurrency && field.type == 'number')) {
          final currency = engine.getAppSetting('currency');
          if (currency != null &&
              currency.isNotEmpty &&
              num.tryParse(result) != null) {
            displayResult = '$currency$result';
          }
        }

        return TextField(
          controller: TextEditingController(text: displayResult),
          readOnly: true,
          enabled: false,
          decoration: InputDecoration(
            labelText: _labelText(),
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            suffixIcon: const Icon(Icons.functions, size: 20),
          ),
        );
      },
    );
  }
}

/// Renders a single form field as the appropriate Material input widget.
class _OdsFieldWidget extends StatefulWidget {
  final String formId;
  final OdsFieldDefinition field;
  final VoidCallback? onChanged;

  const _OdsFieldWidget({
    super.key,
    required this.formId,
    required this.field,
    this.onChanged,
  });

  @override
  State<_OdsFieldWidget> createState() => _OdsFieldWidgetState();
}

class _OdsFieldWidgetState extends State<_OdsFieldWidget> {
  late final TextEditingController _controller;

  /// Inline validation error text, set by the engine when submit fails.
  String? _validationError;

  @override
  void initState() {
    super.initState();
    final engine = context.read<AppEngine>();
    var currentValue = engine.getFormState(widget.formId)[widget.field.name] ?? '';
    if (currentValue.isEmpty && widget.field.defaultValue != null) {
      currentValue = _resolveDefault(widget.field.defaultValue!, widget.field.type, engine);
      engine.updateFormField(widget.formId, widget.field.name, currentValue);
    }
    _controller = TextEditingController(text: currentValue);
  }

  @override
  void didUpdateWidget(covariant _OdsFieldWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final engine = context.read<AppEngine>();
    final currentValue = engine.getFormState(widget.formId)[widget.field.name] ?? '';
    if (_controller.text != currentValue) {
      _controller.text = currentValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String _resolveDefault(String defaultValue, String fieldType, AppEngine engine) {
    final upper = defaultValue.toUpperCase();

    // User-context magic defaults: CURRENT_USER.NAME, CURRENT_USER.EMAIL, etc.
    // For logged-in users: resolve to their info. For guests: return empty string.
    if (upper.startsWith('CURRENT_USER.') || upper == 'CURRENT_USER') {
      if (!engine.isMultiUser || !engine.authService.isLoggedIn) return '';
      if (upper == 'CURRENT_USER') return engine.authService.currentDisplayName;
      final prop = upper.substring('CURRENT_USER.'.length);
      switch (prop) {
        case 'NAME':
          return engine.authService.currentDisplayName;
        case 'EMAIL':
          return engine.authService.currentEmail;
        case 'USERNAME':
          return engine.authService.currentUsername;
        default:
          return '';
      }
    }

    if (upper == 'NOW' || upper == 'CURRENTDATE') {
      return _formatDateTime(DateTime.now(), fieldType);
    }
    // Relative date: "+7d" means 7 days from now, "-3d" means 3 days ago.
    final relativeMatch = RegExp(r'^([+-]?\d+)d$', caseSensitive: false).firstMatch(defaultValue);
    if (relativeMatch != null) {
      final days = int.parse(relativeMatch.group(1)!);
      return _formatDateTime(DateTime.now().add(Duration(days: days)), fieldType);
    }
    return defaultValue;
  }

  static String _formatDateTime(DateTime dt, String fieldType) {
    if (fieldType == 'datetime') {
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  TextInputType _inputType() {
    switch (widget.field.type) {
      case 'email':
        return TextInputType.emailAddress;
      case 'number':
        return TextInputType.number;
      case 'multiline':
        return TextInputType.multiline;
      default:
        return TextInputType.text;
    }
  }

  String _labelText() {
    final base = widget.field.label ?? widget.field.name;
    return widget.field.required ? '$base *' : base;
  }

  /// Runs validation rules and updates the inline error state.
  /// Called on every change so the user sees feedback as they type.
  void _runValidation(String value) {
    final validation = widget.field.validation;
    String? error;
    if (validation != null) {
      error = validation.validate(value, widget.field.type);
    } else if (widget.field.type == 'email' && value.isNotEmpty) {
      // Always validate email format even without explicit validation rules.
      const emailValidation = OdsValidation();
      error = emailValidation.validate(value, 'email');
    }
    if (error != _validationError) {
      setState(() => _validationError = error);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _parseDate(_controller.text) ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final formatted = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      _controller.text = formatted;
      if (mounted) {
        context.read<AppEngine>().updateFormField(
              widget.formId,
              widget.field.name,
              formatted,
            );
        widget.onChanged?.call();
      }
    }
  }

  DateTime? _parseDate(String text) {
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AppEngine>();
    final currentValue = engine.getFormState(widget.formId)[widget.field.name] ?? '';

    if (_controller.text.isNotEmpty && currentValue.isEmpty) {
      _controller.clear();
      if (_validationError != null) {
        _validationError = null;
      }
    }

    // Read-only fields display their value but don't accept input.
    if (widget.field.readOnly) {
      return _buildReadOnly(currentValue);
    }

    switch (widget.field.type) {
      case 'select':
        return _buildSelect(currentValue);
      case 'checkbox':
        return _buildCheckbox(currentValue);
      case 'date':
        return _buildDate();
      case 'datetime':
        return _buildDateTime();
      case 'user':
        return _buildUserField(currentValue);
      default:
        return _buildTextField();
    }
  }

  Widget _buildReadOnly(String currentValue) {
    final variant = widget.field.displayVariant;
    final label = widget.field.label ?? widget.field.name;

    // Plain/heading/caption variants render as clean text, not a form field.
    if (variant == 'plain' || variant == 'heading' || variant == 'caption') {
      TextStyle? valueStyle;
      switch (variant) {
        case 'heading':
          valueStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              );
          break;
        case 'caption':
          valueStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              );
          break;
        default: // plain
          valueStyle = Theme.of(context).textTheme.bodyLarge;
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 4),
          Text(currentValue, style: valueStyle),
        ],
      );
    }

    // Default: disabled input style.
    return TextField(
      controller: _controller,
      readOnly: true,
      enabled: false,
      maxLines: widget.field.type == 'multiline' ? null : 1,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
    );
  }

  Widget _buildSelect(String currentValue) {
    final optionsFrom = widget.field.optionsFrom;
    if (optionsFrom != null) {
      return _buildDynamicSelect(currentValue, optionsFrom);
    }
    return _buildStaticSelect(currentValue, widget.field.options ?? []);
  }

  /// Resolves `{fieldName}` references in a template string using form state.
  String _resolveTemplate(String template) {
    final engine = context.read<AppEngine>();
    final formState = engine.getFormState(widget.formId);
    final fieldPattern = RegExp(r'\{(\w+)\}');
    return template.replaceAllMapped(fieldPattern, (match) {
      return formState[match.group(1)!] ?? '';
    });
  }

  Widget _buildStaticSelect(String currentValue, List<String> options) {
    final effectiveValue = options.contains(currentValue) ? currentValue : null;
    final labels = widget.field.optionLabels;

    return DropdownButtonFormField<String>(
      initialValue: effectiveValue,
      decoration: InputDecoration(
        labelText: _labelText(),
        hintText: widget.field.placeholder,
        border: const OutlineInputBorder(),
        errorText: _validationError,
      ),
      items: options.asMap().entries.map((entry) {
        final option = entry.value;
        // Use resolved optionLabel if available, otherwise plain option text.
        final displayText = (labels != null && entry.key < labels.length)
            ? _resolveTemplate(labels[entry.key])
            : option;
        return DropdownMenuItem<String>(
          value: option,
          child: Text(displayText),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          context.read<AppEngine>().updateFormField(
                widget.formId,
                widget.field.name,
                value,
              );
          _runValidation(value);
          widget.onChanged?.call();
        }
      },
    );
  }

  Widget _buildDynamicSelect(
      String currentValue, OdsOptionsFrom optionsFrom) {
    final engine = context.read<AppEngine>();

    // When a filter is defined, key the FutureBuilder on the sibling field's
    // value so that changing the dependency rebuilds the options list.
    String? filterKey;
    if (optionsFrom.filter != null) {
      final formState = engine.getFormState(widget.formId);
      filterKey = formState[optionsFrom.filter!.fromField] ?? '';
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      key: filterKey != null ? ValueKey('${optionsFrom.dataSource}_$filterKey') : null,
      future: engine.queryDataSource(optionsFrom.dataSource),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return InputDecorator(
            decoration: InputDecoration(
              labelText: _labelText(),
              border: const OutlineInputBorder(),
            ),
            child: const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        var rows = snapshot.data ?? [];

        // Apply dependent dropdown filter: only show options where the
        // filter field matches the sibling form field's current value.
        if (optionsFrom.filter != null) {
          final formState = engine.getFormState(widget.formId);
          final siblingValue = formState[optionsFrom.filter!.fromField] ?? '';
          if (siblingValue.isNotEmpty) {
            rows = rows
                .where((row) =>
                    row[optionsFrom.filter!.field]?.toString() == siblingValue)
                .toList();
          }
        }

        final options = rows
            .map((row) => row[optionsFrom.valueField]?.toString())
            .where((v) => v != null && v.isNotEmpty)
            .cast<String>()
            .toSet()
            .toList();

        if (options.isEmpty) {
          return InputDecorator(
            decoration: InputDecoration(
              labelText: _labelText(),
              hintText: 'No options available — add data first',
              border: const OutlineInputBorder(),
            ),
            child: const Text(
              'No options available',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return _buildStaticSelect(currentValue, options);
      },
    );
  }

  Widget _buildCheckbox(String currentValue) {
    final isChecked = currentValue.toLowerCase() == 'true' || currentValue == 'Yes';

    return SwitchListTile(
      title: Text(_labelText()),
      value: isChecked,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onChanged: (value) {
        context.read<AppEngine>().updateFormField(
              widget.formId,
              widget.field.name,
              value ? 'true' : 'false',
            );
        widget.onChanged?.call();
        setState(() {});
      },
    );
  }

  Widget _buildDate() {
    return TextField(
      controller: _controller,
      readOnly: true,
      onTap: _pickDate,
      decoration: InputDecoration(
        labelText: _labelText(),
        hintText: widget.field.placeholder,
        border: const OutlineInputBorder(),
        suffixIcon: const Icon(Icons.calendar_today),
        errorText: _validationError,
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final existingDt = _parseDate(_controller.text);

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: existingDt ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null || !mounted) return;

    final initialTime = existingDt != null
        ? TimeOfDay(hour: existingDt.hour, minute: existingDt.minute)
        : TimeOfDay(hour: now.hour, minute: now.minute);

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (pickedTime == null || !mounted) return;

    final formatted =
        '${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')} '
        '${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}';
    _controller.text = formatted;
    context.read<AppEngine>().updateFormField(
          widget.formId,
          widget.field.name,
          formatted,
        );
    widget.onChanged?.call();
  }

  Widget _buildDateTime() {
    return TextField(
      controller: _controller,
      readOnly: true,
      onTap: _pickDateTime,
      decoration: InputDecoration(
        labelText: _labelText(),
        hintText: widget.field.placeholder,
        border: const OutlineInputBorder(),
        suffixIcon: const Icon(Icons.access_time),
        errorText: _validationError,
      ),
    );
  }

  Widget _buildUserField(String currentValue) {
    final engine = context.read<AppEngine>();
    if (!engine.isMultiUser) {
      // Single-user mode: render as a plain text field.
      return _buildTextField();
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: engine.authService.listUsers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return InputDecorator(
            decoration: InputDecoration(
              labelText: _labelText(),
              border: const OutlineInputBorder(),
            ),
            child: const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final users = snapshot.data ?? [];
        if (users.isEmpty) {
          return InputDecorator(
            decoration: InputDecoration(
              labelText: _labelText(),
              hintText: 'No users available',
              border: const OutlineInputBorder(),
            ),
            child: const Text(
              'No users available',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        // Build list of usernames for matching.
        final usernames = users
            .map((u) => u['username']?.toString() ?? '')
            .where((u) => u.isNotEmpty)
            .toList();
        final effectiveValue =
            usernames.contains(currentValue) ? currentValue : null;

        return DropdownButtonFormField<String>(
          value: effectiveValue,
          decoration: InputDecoration(
            labelText: _labelText(),
            hintText: widget.field.placeholder,
            border: const OutlineInputBorder(),
            errorText: _validationError,
          ),
          items: users.map((u) {
            final displayName =
                u['display_name']?.toString() ?? u['username']?.toString() ?? '';
            final username = u['username']?.toString() ?? '';
            return DropdownMenuItem<String>(
              value: username,
              child: Text(displayName.isNotEmpty ? displayName : username),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              context.read<AppEngine>().updateFormField(
                    widget.formId,
                    widget.field.name,
                    value,
                  );
              _runValidation(value);
              widget.onChanged?.call();
            }
          },
        );
      },
    );
  }

  Widget _buildTextField() {
    final isMultiline = widget.field.type == 'multiline';

    return TextField(
      controller: _controller,
      keyboardType: _inputType(),
      maxLines: isMultiline ? 5 : 1,
      minLines: isMultiline ? 3 : 1,
      decoration: InputDecoration(
        labelText: _labelText(),
        hintText: widget.field.placeholder,
        border: const OutlineInputBorder(),
        alignLabelWithHint: isMultiline,
        errorText: _validationError,
      ),
      onChanged: (value) {
        context.read<AppEngine>().updateFormField(
              widget.formId,
              widget.field.name,
              value,
            );
        _runValidation(value);
        widget.onChanged?.call();
      },
    );
  }
}

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

  /// Checks whether a field should be visible based on its `visibleWhen` condition.
  bool _isFieldVisible(OdsFieldDefinition field, Map<String, String> formState) {
    final condition = field.visibleWhen;
    if (condition == null) return true;
    final watchedValue = formState[condition.field] ?? '';
    return watchedValue == condition.equals;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ValueListenableBuilder<int>(
        valueListenable: _fieldChangeNotifier,
        builder: (context, _, __) {
          final engine = context.watch<AppEngine>();
          final formState = engine.getFormState(widget.model.id);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: widget.model.fields.where((field) {
              return _isFieldVisible(field, formState);
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
                        formId: widget.model.id,
                        field: field,
                        onChanged: _onFieldChanged,
                      ),
              );
            }).toList(),
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

        return TextField(
          controller: TextEditingController(text: result),
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
      currentValue = _resolveDefault(widget.field.defaultValue!, widget.field.type);
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

  static String _resolveDefault(String defaultValue, String fieldType) {
    final upper = defaultValue.toUpperCase();
    if (upper == 'NOW' || upper == 'CURRENTDATE') {
      final now = DateTime.now();
      if (fieldType == 'datetime') {
        return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      }
      return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    }
    return defaultValue;
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
    if (validation == null) {
      if (_validationError != null) {
        setState(() => _validationError = null);
      }
      return;
    }
    final error = validation.validate(value, widget.field.type);
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

    switch (widget.field.type) {
      case 'select':
        return _buildSelect(currentValue);
      case 'checkbox':
        return _buildCheckbox(currentValue);
      case 'date':
        return _buildDate();
      case 'datetime':
        return _buildDateTime();
      default:
        return _buildTextField();
    }
  }

  Widget _buildSelect(String currentValue) {
    final optionsFrom = widget.field.optionsFrom;
    if (optionsFrom != null) {
      return _buildDynamicSelect(currentValue, optionsFrom);
    }
    return _buildStaticSelect(currentValue, widget.field.options ?? []);
  }

  Widget _buildStaticSelect(String currentValue, List<String> options) {
    final effectiveValue = options.contains(currentValue) ? currentValue : null;

    return DropdownButtonFormField<String>(
      initialValue: effectiveValue,
      decoration: InputDecoration(
        labelText: _labelText(),
        hintText: widget.field.placeholder,
        border: const OutlineInputBorder(),
        errorText: _validationError,
      ),
      items: options.map((option) {
        return DropdownMenuItem<String>(
          value: option,
          child: Text(option),
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

    return FutureBuilder<List<Map<String, dynamic>>>(
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

        final rows = snapshot.data ?? [];
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

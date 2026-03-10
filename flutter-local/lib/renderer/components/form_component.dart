import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/app_engine.dart';
import '../../models/ods_component.dart';
import '../../models/ods_field_definition.dart';

/// Renders an [OdsFormComponent] as a vertical list of input fields.
///
/// ODS Spec: The form component has a unique `id` (referenced by submit
/// actions) and an ordered array of field definitions. Each field becomes
/// an appropriate input widget based on its type:
///   - "text"      -> single-line TextField
///   - "email"     -> single-line TextField with email keyboard
///   - "number"    -> single-line TextField with numeric keyboard
///   - "date"      -> read-only TextField that opens a date picker on tap
///   - "datetime"  -> read-only TextField that opens date + time pickers on tap
///   - "multiline" -> multi-line TextField for long-form content
///   - "select"    -> dropdown menu with predefined options
///   - "checkbox"  -> switch toggle for boolean values
///
/// ODS Ethos: "The form is the schema." Form fields implicitly define the
/// database structure. A citizen developer designs a form, and the framework
/// creates the storage automatically. No ER diagrams, no migrations.
class OdsFormWidget extends StatelessWidget {
  final OdsFormComponent model;

  const OdsFormWidget({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: model.fields.map((field) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _OdsFieldWidget(formId: model.id, field: field),
          );
        }).toList(),
      ),
    );
  }
}

/// Renders a single form field as the appropriate Material input widget.
///
/// Dispatches to specialized builders for select, checkbox, date, and
/// text-based fields. Uses a [TextEditingController] for text-based types
/// that syncs bidirectionally with the engine's form state map.
class _OdsFieldWidget extends StatefulWidget {
  final String formId;
  final OdsFieldDefinition field;

  const _OdsFieldWidget({required this.formId, required this.field});

  @override
  State<_OdsFieldWidget> createState() => _OdsFieldWidgetState();
}

class _OdsFieldWidgetState extends State<_OdsFieldWidget> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    // Initialize with any existing value (e.g., when navigating back),
    // falling back to the field's default value on first display.
    final engine = context.read<AppEngine>();
    var currentValue = engine.getFormState(widget.formId)[widget.field.name] ?? '';
    if (currentValue.isEmpty && widget.field.defaultValue != null) {
      currentValue = _resolveDefault(widget.field.defaultValue!, widget.field.type);
      // Push the default into the engine so it's included in submit/update.
      engine.updateFormField(widget.formId, widget.field.name, currentValue);
    }
    _controller = TextEditingController(text: currentValue);
  }

  @override
  void didUpdateWidget(covariant _OdsFieldWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync controller when the widget rebuilds (e.g., after form clear).
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

  /// Resolves magic default tokens like "NOW" and "CURRENTDATE" to actual values.
  ///
  /// ODS Spec: Date and datetime fields can use "NOW" or "CURRENTDATE" as their
  /// default value. The framework replaces these with the current date or
  /// datetime at render time, so the form opens pre-filled with "today".
  static String _resolveDefault(String defaultValue, String fieldType) {
    final upper = defaultValue.toUpperCase();
    if (upper == 'NOW' || upper == 'CURRENTDATE') {
      final now = DateTime.now();
      if (fieldType == 'datetime') {
        return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      }
      // For "date" or any other type, return just the date portion.
      return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    }
    return defaultValue;
  }

  /// Maps ODS field types to Flutter keyboard types.
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

  /// Builds the label string, appending an asterisk for required fields.
  String _labelText() {
    final base = widget.field.label ?? widget.field.name;
    return widget.field.required ? '$base *' : base;
  }

  /// Opens a Material date picker and writes the selected date (ISO 8601)
  /// to both the controller and the engine's form state.
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

    // Detect form clear: engine state is empty but controller has stale text.
    if (_controller.text.isNotEmpty && currentValue.isEmpty) {
      _controller.clear();
    }

    // Dispatch to the appropriate widget builder based on field type.
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

  /// Builds a dropdown menu for "select" fields.
  ///
  /// Options can come from a static [OdsFieldDefinition.options] array or
  /// dynamically from a data source via [OdsFieldDefinition.optionsFrom].
  /// When optionsFrom is present, the framework queries the referenced GET
  /// data source and extracts the specified column values as options.
  /// optionsFrom takes priority over static options if both are present.
  Widget _buildSelect(String currentValue) {
    final optionsFrom = widget.field.optionsFrom;

    // Dynamic options: fetch from a data source.
    if (optionsFrom != null) {
      return _buildDynamicSelect(currentValue, optionsFrom);
    }

    // Static options: use the inline options array.
    return _buildStaticSelect(currentValue, widget.field.options ?? []);
  }

  /// Builds a dropdown with static options from the spec's options array.
  Widget _buildStaticSelect(String currentValue, List<String> options) {
    final effectiveValue = options.contains(currentValue) ? currentValue : null;

    return DropdownButtonFormField<String>(
      initialValue: effectiveValue,
      decoration: InputDecoration(
        labelText: _labelText(),
        hintText: widget.field.placeholder,
        border: const OutlineInputBorder(),
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
        }
      },
    );
  }

  /// Builds a dropdown whose options are loaded from a GET data source.
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
            .toSet() // deduplicate
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

  /// Builds a switch toggle for "checkbox" fields.
  ///
  /// Stores "true" or "false" as strings in the form state. The framework
  /// renders a Material SwitchListTile so the builder only writes:
  ///   { "type": "checkbox" }
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
        // SwitchListTile is a controlled widget — its visual state depends on
        // the `value` prop. Since updateFormField() doesn't call
        // notifyListeners() (to avoid rebuilding text fields on every
        // keystroke), we trigger a local rebuild so the switch reflects the
        // new value from the engine's form state map.
        setState(() {});
      },
    );
  }

  /// Builds a date picker field.
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
      ),
    );
  }

  /// Opens a Material date picker followed by a time picker, writing the
  /// combined datetime (YYYY-MM-DD HH:MM) to the controller and engine state.
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
  }

  /// Builds a datetime picker field (date + time).
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
      ),
    );
  }

  /// Builds a standard text field for text, email, number, and multiline types.
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
      ),
      onChanged: (value) {
        context.read<AppEngine>().updateFormField(
              widget.formId,
              widget.field.name,
              value,
            );
      },
    );
  }
}

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
      currentValue = widget.field.defaultValue!;
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
      default:
        return _buildTextField();
    }
  }

  /// Builds a dropdown menu for "select" fields.
  ///
  /// The options come from [OdsFieldDefinition.options]. The framework
  /// renders a Material dropdown so the builder only writes:
  ///   { "type": "select", "options": ["High", "Medium", "Low"] }
  Widget _buildSelect(String currentValue) {
    final options = widget.field.options ?? [];
    // If the current value isn't in the options list, treat it as unselected.
    final effectiveValue = options.contains(currentValue) ? currentValue : null;

    return DropdownButtonFormField<String>(
      value: effectiveValue,
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

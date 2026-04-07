import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/app_engine.dart';
import '../../models/ods_component.dart';
import '../../models/ods_field_definition.dart';

/// Renders an [OdsKanbanComponent] as a board with draggable cards organized
/// into columns by a status field's select options.
///
/// ODS Spec: The kanban component references a GET data source and uses the
/// `statusField` to group rows into columns. The column order is determined
/// by the select options defined on the matching form field. Cards can be
/// dragged between columns to update the status value.
///
/// ODS Ethos: The builder writes `"component": "kanban"` and names the status
/// field. The framework handles drag-and-drop, column layout, search, sort,
/// and the status update mechanism. Complexity is the framework's job.
class OdsKanbanWidget extends StatefulWidget {
  final OdsKanbanComponent model;

  const OdsKanbanWidget({super.key, required this.model});

  @override
  State<OdsKanbanWidget> createState() => _OdsKanbanWidgetState();
}

class _OdsKanbanWidgetState extends State<OdsKanbanWidget> {
  /// Column width for each kanban column.
  static const double _columnWidth = 280.0;

  /// Cached query results so the FutureBuilder doesn't flash a loading spinner
  /// on every rebuild (search/sort are local operations on already-loaded data).
  List<Map<String, dynamic>>? _cachedRows;

  /// Current search query for searchable boards.
  String _searchQuery = '';

  /// Stable random rotations per card (_id -> rotation degrees).
  final Map<String, double> _cardRotations = {};

  /// Random generator for sticky-note rotation effect.
  final _random = math.Random(42);

  /// Returns the effective title field name.
  String get _titleField =>
      widget.model.titleField ??
      (widget.model.cardFields.isNotEmpty ? widget.model.cardFields.first : '');

  /// Returns row actions filtered by the current user's roles.
  List<OdsRowAction> _visibleRowActions(AppEngine engine) {
    if (!engine.isMultiUser) return widget.model.rowActions;
    return widget.model.rowActions
        .where((action) => engine.authService.hasAccess(action.roles))
        .toList();
  }

  /// Discovers the select options for the statusField by searching all forms
  /// in the app for a select field matching the statusField name.
  List<String> _discoverStatusOptions(AppEngine engine) {
    final app = engine.app;
    if (app == null) return [];

    for (final page in app.pages.values) {
      for (final component in page.content) {
        if (component is OdsFormComponent) {
          for (final field in component.fields) {
            if (field.name == widget.model.statusField &&
                field.type == 'select' &&
                field.options != null &&
                field.options!.isNotEmpty) {
              return field.options!;
            }
          }
        }
      }
    }

    // Also check dataSource field definitions.
    final ds = app.dataSources[widget.model.dataSource];
    if (ds?.fields != null) {
      for (final field in ds!.fields!) {
        if (field.name == widget.model.statusField &&
            field.type == 'select' &&
            field.options != null &&
            field.options!.isNotEmpty) {
          return field.options!;
        }
      }
    }

    return [];
  }

  /// Finds a POST data source that points to the same local:// table as the
  /// kanban's GET data source. Used for inline card creation.
  String? _findPostDataSourceId(AppEngine engine) {
    final app = engine.app;
    if (app == null) return null;

    final getDs = app.dataSources[widget.model.dataSource];
    if (getDs == null || !getDs.isLocal) return null;

    final targetTable = getDs.tableName;
    for (final entry in app.dataSources.entries) {
      if (entry.value.method.toUpperCase() == 'POST' &&
          entry.value.isLocal &&
          entry.value.tableName == targetTable) {
        return entry.key;
      }
    }
    return null;
  }

  /// Finds a PUT data source that points to the same local:// table as the
  /// kanban's GET data source. Used for drag-and-drop status updates.
  String? _findPutDataSourceId(AppEngine engine) {
    final app = engine.app;
    if (app == null) return null;

    final getDs = app.dataSources[widget.model.dataSource];
    if (getDs == null || !getDs.isLocal) return null;

    final targetTable = getDs.tableName;
    for (final entry in app.dataSources.entries) {
      if (entry.value.method.toUpperCase() == 'PUT' &&
          entry.value.isLocal &&
          entry.value.tableName == targetTable) {
        return entry.key;
      }
    }
    return null;
  }

  /// Discovers field definitions for the card fields by searching forms and
  /// dataSource field declarations. Returns a map of fieldName -> OdsFieldDefinition.
  Map<String, OdsFieldDefinition> _discoverFieldDefinitions(AppEngine engine) {
    final app = engine.app;
    if (app == null) return {};

    final result = <String, OdsFieldDefinition>{};
    final targetFields = {...widget.model.cardFields, widget.model.statusField};

    // Search forms first (richer definitions with options, labels, etc.).
    for (final page in app.pages.values) {
      for (final component in page.content) {
        if (component is OdsFormComponent) {
          for (final field in component.fields) {
            if (targetFields.contains(field.name) &&
                !result.containsKey(field.name)) {
              result[field.name] = field;
            }
          }
        }
      }
    }

    // Fall back to dataSource field definitions for any still missing.
    final ds = app.dataSources[widget.model.dataSource];
    if (ds?.fields != null) {
      for (final field in ds!.fields!) {
        if (targetFields.contains(field.name) &&
            !result.containsKey(field.name)) {
          result[field.name] = field;
        }
      }
    }

    return result;
  }

  /// Shows a quick-add dialog for creating a new card in the given column.
  void _showAddCardDialog(
    BuildContext context,
    AppEngine engine,
    String columnStatus,
  ) {
    final theme = Theme.of(context);
    final fieldDefs = _discoverFieldDefinitions(engine);
    final fields = widget.model.cardFields
        .where((f) => f != widget.model.statusField)
        .toList();

    // Build controllers for each field.
    final controllers = <String, TextEditingController>{};
    for (final fieldName in fields) {
      controllers[fieldName] = TextEditingController();
    }

    // Track selected values for dropdowns.
    final dropdownValues = <String, String?>{};

    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            'Add to $columnStatus',
            style: theme.textTheme.titleMedium,
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status badge (read-only).
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Text(
                          _prettifyFieldName(widget.model.statusField),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Chip(
                          label: Text(columnStatus),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  // Dynamic fields.
                  ...fields.map((fieldName) {
                    final def = fieldDefs[fieldName];
                    final label = def?.label ?? _prettifyFieldName(fieldName);
                    final fieldType = def?.type ?? 'text';
                    final isTitle = fieldName == _titleField;
                    final isRequired = isTitle || (def?.required ?? false);

                    if (fieldType == 'select' &&
                        def?.options != null &&
                        def!.options!.isNotEmpty) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: DropdownButtonFormField<String>(
                          initialValue: dropdownValues[fieldName],
                          decoration: InputDecoration(
                            labelText: label,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: def.options!
                              .map((opt) => DropdownMenuItem(
                                    value: opt,
                                    child: Text(opt),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            setDialogState(
                                () => dropdownValues[fieldName] = val);
                          },
                          validator: isRequired
                              ? (val) => (val == null || val.isEmpty)
                                  ? '$label is required'
                                  : null
                              : null,
                        ),
                      );
                    }

                    if (fieldType == 'checkbox') {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Checkbox(
                              value:
                                  controllers[fieldName]?.text == 'true',
                              onChanged: (val) {
                                setDialogState(() {
                                  controllers[fieldName]!.text =
                                      val == true ? 'true' : 'false';
                                });
                              },
                            ),
                            Text(label),
                          ],
                        ),
                      );
                    }

                    if (fieldType == 'date') {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextFormField(
                          controller: controllers[fieldName],
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: label,
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: const Icon(Icons.calendar_today),
                          ),
                          onTap: () async {
                            final now = DateTime.now();
                            final existing = DateTime.tryParse(
                                controllers[fieldName]?.text ?? '');
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: existing ?? now,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              final formatted =
                                  '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                              setDialogState(() {
                                controllers[fieldName]!.text = formatted;
                              });
                            }
                          },
                          validator: isRequired
                              ? (val) => (val == null || val.trim().isEmpty)
                                  ? '$label is required'
                                  : null
                              : null,
                        ),
                      );
                    }

                    if (fieldType == 'datetime') {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextFormField(
                          controller: controllers[fieldName],
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: label,
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: const Icon(Icons.access_time),
                          ),
                          onTap: () async {
                            final now = DateTime.now();
                            final existing = DateTime.tryParse(
                                controllers[fieldName]?.text ?? '');
                            final pickedDate = await showDatePicker(
                              context: ctx,
                              initialDate: existing ?? now,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (pickedDate == null || !ctx.mounted) return;
                            final initialTime = existing != null
                                ? TimeOfDay(
                                    hour: existing.hour,
                                    minute: existing.minute)
                                : TimeOfDay(
                                    hour: now.hour, minute: now.minute);
                            final pickedTime = await showTimePicker(
                              context: ctx,
                              initialTime: initialTime,
                            );
                            if (pickedTime == null || !ctx.mounted) return;
                            final formatted =
                                '${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')} '
                                '${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}';
                            setDialogState(() {
                              controllers[fieldName]!.text = formatted;
                            });
                          },
                          validator: isRequired
                              ? (val) => (val == null || val.trim().isEmpty)
                                  ? '$label is required'
                                  : null
                              : null,
                        ),
                      );
                    }

                    if (fieldType == 'user') {
                      if (engine.isMultiUser) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: FutureBuilder<List<Map<String, dynamic>>>(
                            future: engine.authService.listUsers(),
                            builder: (context, userSnapshot) {
                              final users = userSnapshot.data ?? [];
                              return DropdownButtonFormField<String>(
                                value: dropdownValues[fieldName],
                                decoration: InputDecoration(
                                  labelText: label,
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: users.map((u) {
                                  final displayName =
                                      u['display_name']?.toString() ??
                                          u['username']?.toString() ??
                                          '';
                                  final username =
                                      u['username']?.toString() ?? '';
                                  return DropdownMenuItem<String>(
                                    value: username,
                                    child: Text(displayName.isNotEmpty
                                        ? displayName
                                        : username),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  setDialogState(
                                      () => dropdownValues[fieldName] = val);
                                },
                                validator: isRequired
                                    ? (val) =>
                                        (val == null || val.isEmpty)
                                            ? '$label is required'
                                            : null
                                    : null,
                              );
                            },
                          ),
                        );
                      }
                      // Single-user mode: fall through to plain text field.
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: controllers[fieldName],
                        decoration: InputDecoration(
                          labelText: label,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: fieldType == 'number'
                            ? TextInputType.number
                            : fieldType == 'email'
                                ? TextInputType.emailAddress
                                : TextInputType.text,
                        maxLines: fieldType == 'multiline' ? 3 : 1,
                        validator: isRequired
                            ? (val) => (val == null || val.trim().isEmpty)
                                ? '$label is required'
                                : null
                            : null,
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;

                // Build the row data.
                final data = <String, dynamic>{
                  widget.model.statusField: columnStatus,
                };
                for (final fieldName in fields) {
                  final def = fieldDefs[fieldName];
                  final fieldType = def?.type ?? 'text';
                  if (fieldType == 'select' &&
                      def?.options != null &&
                      def!.options!.isNotEmpty) {
                    final val = dropdownValues[fieldName];
                    if (val != null && val.isNotEmpty) {
                      data[fieldName] = val;
                    }
                  } else if (fieldType == 'user' &&
                      engine.isMultiUser) {
                    final val = dropdownValues[fieldName];
                    if (val != null && val.isNotEmpty) {
                      data[fieldName] = val;
                    }
                  } else {
                    final val = controllers[fieldName]?.text ?? '';
                    if (val.isNotEmpty) {
                      data[fieldName] = val;
                    }
                  }
                }

                // Find the POST dataSource and insert.
                final postDsId = _findPostDataSourceId(engine);
                final app = engine.app;
                if (app != null) {
                  final dsId = postDsId ?? widget.model.dataSource;
                  final ds = app.dataSources[dsId] ??
                      app.dataSources[widget.model.dataSource];
                  if (ds != null && ds.isLocal) {
                    // Ensure the table schema is up to date.
                    final allFieldDefs = fields
                        .map((f) =>
                            fieldDefs[f] ??
                            OdsFieldDefinition(name: f, type: 'text'))
                        .toList();
                    // Include the status field definition.
                    final statusDef = fieldDefs[widget.model.statusField] ??
                        OdsFieldDefinition(
                            name: widget.model.statusField, type: 'text');
                    allFieldDefs.add(statusDef);

                    await engine.dataStore
                        .ensureTable(ds.tableName, allFieldDefs);
                    await engine.dataStore.insert(ds.tableName, data);
                  }
                }

                if (ctx.mounted) Navigator.of(ctx).pop();

                // Clear cache and trigger rebuild.
                setState(() {
                  _cachedRows = null;
                });
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    // Dispose controllers when the dialog route is removed.
    // We rely on the dialog being popped, which triggers a rebuild.
    // Since controllers are local to this invocation, they'll be GC'd.
  }

  /// Updates the status of a card when it is dropped onto a new column.
  Future<void> _updateStatus(
    AppEngine engine,
    Map<String, dynamic> row,
    String newStatus,
  ) async {
    final matchValue = row['_id']?.toString() ?? '';
    if (matchValue.isEmpty) return;

    final putDsId = _findPutDataSourceId(engine);
    if (putDsId != null) {
      await engine.executeRowAction(
        dataSourceId: putDsId,
        matchField: '_id',
        matchValue: matchValue,
        values: {widget.model.statusField: newStatus},
      );
    } else {
      // Fallback: use the GET dataSource directly (engine.executeRowAction
      // resolves the table from the dataSource config).
      await engine.executeRowAction(
        dataSourceId: widget.model.dataSource,
        matchField: '_id',
        matchValue: matchValue,
        values: {widget.model.statusField: newStatus},
      );
    }
  }

  /// Sorts rows in-memory by the defaultSort field and direction.
  List<Map<String, dynamic>> _sortRows(List<Map<String, dynamic>> rows) {
    final sort = widget.model.defaultSort;
    if (sort == null) return rows;

    final sorted = List<Map<String, dynamic>>.from(rows);
    sorted.sort((a, b) {
      final aVal = a[sort.field]?.toString() ?? '';
      final bVal = b[sort.field]?.toString() ?? '';
      final aNum = num.tryParse(aVal);
      final bNum = num.tryParse(bVal);
      int cmp;
      if (aNum != null && bNum != null) {
        cmp = aNum.compareTo(bNum);
      } else {
        cmp = aVal.compareTo(bVal);
      }
      return sort.isDescending ? -cmp : cmp;
    });
    return sorted;
  }

  /// Filters rows by the search query across all card fields.
  List<Map<String, dynamic>> _searchRows(List<Map<String, dynamic>> rows) {
    if (_searchQuery.isEmpty) return rows;
    final query = _searchQuery.toLowerCase();
    return rows.where((row) {
      for (final field in widget.model.cardFields) {
        final value = (row[field]?.toString() ?? '').toLowerCase();
        if (value.contains(query)) return true;
      }
      // Also check the title field.
      final titleVal = (row[_titleField]?.toString() ?? '').toLowerCase();
      if (titleVal.contains(query)) return true;
      return false;
    }).toList();
  }

  /// Gets a stable random rotation for a card (subtle sticky-note feel).
  double _getRotation(String cardId) {
    return _cardRotations.putIfAbsent(
      cardId,
      () => (_random.nextDouble() * 3.0) - 1.5, // -1.5 to +1.5 degrees
    );
  }

  /// Shows a confirmation dialog before executing a row action.
  Future<void> _confirmRowAction(
    BuildContext context,
    AppEngine engine,
    OdsRowAction action,
    Map<String, dynamic> row,
  ) async {
    final message = action.confirm ??
        (action.isDelete
            ? 'Are you sure you want to delete this record? This cannot be undone.'
            : 'Are you sure you want to perform this action?');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(action.isDelete ? 'Delete Record' : 'Confirm Action'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: action.isDelete
                ? TextButton.styleFrom(
                    foregroundColor: Theme.of(ctx).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action.isDelete ? 'Delete' : 'Confirm'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _executeRowAction(engine, action, row);
    }
  }

  /// Dispatches a row action to the appropriate engine method.
  void _executeRowAction(
      AppEngine engine, OdsRowAction action, Map<String, dynamic> row) {
    if (action.isDelete) {
      final matchValue = row[action.matchField]?.toString() ?? '';
      engine.executeDeleteRowAction(
        dataSourceId: action.dataSource,
        matchField: action.matchField,
        matchValue: matchValue,
      );
    } else if (action.isCopyRows) {
      engine.executeCopyRowsAction(
        row: row,
        sourceDataSourceId: action.sourceDataSource ?? '',
        targetDataSourceId: action.targetDataSource ?? '',
        parentDataSourceId: action.parentDataSource ?? '',
        linkField: action.linkField ?? '',
        nameField: action.nameField ?? 'name',
        resetValues: action.resetValues,
      );
    } else {
      final matchValue = row[action.matchField]?.toString() ?? '';
      engine.executeRowAction(
        dataSourceId: action.dataSource,
        matchField: action.matchField,
        matchValue: matchValue,
        values: action.values,
      );
    }
  }

  /// Finds a DELETE row action defined in the kanban's rowActions list.
  OdsRowAction? _findDeleteRowAction() {
    for (final action in widget.model.rowActions) {
      if (action.isDelete) return action;
    }
    return null;
  }

  /// Shows an editable form dialog for a tapped kanban card.
  void _showEditCardDialog(
    BuildContext context,
    AppEngine engine,
    Map<String, dynamic> row,
  ) {
    final theme = Theme.of(context);
    final fieldDefs = _discoverFieldDefinitions(engine);
    final statusOptions = _discoverStatusOptions(engine);
    final fields = widget.model.cardFields
        .where((f) => f != widget.model.statusField)
        .toList();

    // Build controllers pre-populated with existing values.
    final controllers = <String, TextEditingController>{};
    for (final fieldName in fields) {
      controllers[fieldName] = TextEditingController(
        text: row[fieldName]?.toString() ?? '',
      );
    }

    // Track selected values for dropdowns (pre-populated).
    final dropdownValues = <String, String?>{};
    for (final fieldName in fields) {
      final def = fieldDefs[fieldName];
      if (def != null &&
          def.type == 'select' &&
          def.options != null &&
          def.options!.isNotEmpty) {
        final currentVal = row[fieldName]?.toString() ?? '';
        dropdownValues[fieldName] =
            def.options!.contains(currentVal) ? currentVal : null;
      }
      // Pre-populate user field dropdown values.
      if (def != null && def.type == 'user') {
        final currentVal = row[fieldName]?.toString() ?? '';
        dropdownValues[fieldName] = currentVal.isNotEmpty ? currentVal : null;
      }
    }

    // Status dropdown value.
    String? selectedStatus = row[widget.model.statusField]?.toString() ?? '';
    if (statusOptions.isNotEmpty && !statusOptions.contains(selectedStatus)) {
      selectedStatus = statusOptions.first;
    }

    final formKey = GlobalKey<FormState>();
    final titleValue = row[_titleField]?.toString() ?? 'Card';
    final deleteAction = _findDeleteRowAction();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            'Edit $titleValue',
            style: theme.textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status dropdown (editable).
                  if (statusOptions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DropdownButtonFormField<String>(
                        value: selectedStatus,
                        decoration: InputDecoration(
                          labelText: _prettifyFieldName(
                              widget.model.statusField),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: statusOptions
                            .map((opt) => DropdownMenuItem(
                                  value: opt,
                                  child: Text(opt),
                                ))
                            .toList(),
                        onChanged: (val) {
                          setDialogState(() => selectedStatus = val);
                        },
                      ),
                    ),
                  // Dynamic fields (same pattern as add dialog).
                  ...fields.map((fieldName) {
                    final def = fieldDefs[fieldName];
                    final label = def?.label ?? _prettifyFieldName(fieldName);
                    final fieldType = def?.type ?? 'text';
                    final isTitle = fieldName == _titleField;
                    final isRequired = isTitle || (def?.required ?? false);

                    if (fieldType == 'select' &&
                        def?.options != null &&
                        def!.options!.isNotEmpty) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: DropdownButtonFormField<String>(
                          value: dropdownValues[fieldName],
                          decoration: InputDecoration(
                            labelText: label,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: def.options!
                              .map((opt) => DropdownMenuItem(
                                    value: opt,
                                    child: Text(opt),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            setDialogState(
                                () => dropdownValues[fieldName] = val);
                          },
                          validator: isRequired
                              ? (val) => (val == null || val.isEmpty)
                                  ? '$label is required'
                                  : null
                              : null,
                        ),
                      );
                    }

                    if (fieldType == 'checkbox') {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Checkbox(
                              value:
                                  controllers[fieldName]?.text == 'true',
                              onChanged: (val) {
                                setDialogState(() {
                                  controllers[fieldName]!.text =
                                      val == true ? 'true' : 'false';
                                });
                              },
                            ),
                            Text(label),
                          ],
                        ),
                      );
                    }

                    if (fieldType == 'date') {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextFormField(
                          controller: controllers[fieldName],
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: label,
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: const Icon(Icons.calendar_today),
                          ),
                          onTap: () async {
                            final now = DateTime.now();
                            final existing = DateTime.tryParse(
                                controllers[fieldName]?.text ?? '');
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: existing ?? now,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              final formatted =
                                  '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                              setDialogState(() {
                                controllers[fieldName]!.text = formatted;
                              });
                            }
                          },
                          validator: isRequired
                              ? (val) => (val == null || val.trim().isEmpty)
                                  ? '$label is required'
                                  : null
                              : null,
                        ),
                      );
                    }

                    if (fieldType == 'datetime') {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextFormField(
                          controller: controllers[fieldName],
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: label,
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: const Icon(Icons.access_time),
                          ),
                          onTap: () async {
                            final now = DateTime.now();
                            final existing = DateTime.tryParse(
                                controllers[fieldName]?.text ?? '');
                            final pickedDate = await showDatePicker(
                              context: ctx,
                              initialDate: existing ?? now,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (pickedDate == null || !ctx.mounted) return;
                            final initialTime = existing != null
                                ? TimeOfDay(
                                    hour: existing.hour,
                                    minute: existing.minute)
                                : TimeOfDay(
                                    hour: now.hour, minute: now.minute);
                            final pickedTime = await showTimePicker(
                              context: ctx,
                              initialTime: initialTime,
                            );
                            if (pickedTime == null || !ctx.mounted) return;
                            final formatted =
                                '${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')} '
                                '${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}';
                            setDialogState(() {
                              controllers[fieldName]!.text = formatted;
                            });
                          },
                          validator: isRequired
                              ? (val) => (val == null || val.trim().isEmpty)
                                  ? '$label is required'
                                  : null
                              : null,
                        ),
                      );
                    }

                    if (fieldType == 'user') {
                      if (engine.isMultiUser) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: FutureBuilder<List<Map<String, dynamic>>>(
                            future: engine.authService.listUsers(),
                            builder: (context, userSnapshot) {
                              final users = userSnapshot.data ?? [];
                              return DropdownButtonFormField<String>(
                                value: dropdownValues[fieldName],
                                decoration: InputDecoration(
                                  labelText: label,
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: users.map((u) {
                                  final displayName =
                                      u['display_name']?.toString() ??
                                          u['username']?.toString() ??
                                          '';
                                  final username =
                                      u['username']?.toString() ?? '';
                                  return DropdownMenuItem<String>(
                                    value: username,
                                    child: Text(displayName.isNotEmpty
                                        ? displayName
                                        : username),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  setDialogState(
                                      () => dropdownValues[fieldName] = val);
                                },
                                validator: isRequired
                                    ? (val) =>
                                        (val == null || val.isEmpty)
                                            ? '$label is required'
                                            : null
                                    : null,
                              );
                            },
                          ),
                        );
                      }
                      // Single-user mode: fall through to plain text field.
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        controller: controllers[fieldName],
                        decoration: InputDecoration(
                          labelText: label,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: fieldType == 'number'
                            ? TextInputType.number
                            : fieldType == 'email'
                                ? TextInputType.emailAddress
                                : TextInputType.text,
                        maxLines: fieldType == 'multiline' ? 3 : 1,
                        validator: isRequired
                            ? (val) => (val == null || val.trim().isEmpty)
                                ? '$label is required'
                                : null
                            : null,
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            // Delete button (if a delete row action exists).
            if (deleteAction != null)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: ctx,
                    builder: (confirmCtx) => AlertDialog(
                      title: const Text('Delete Card'),
                      content: Text(
                        deleteAction.confirm ??
                            'Are you sure you want to delete this card? This cannot be undone.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(confirmCtx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                          ),
                          onPressed: () =>
                              Navigator.of(confirmCtx).pop(true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    _executeRowAction(engine, deleteAction, row);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    setState(() {
                      _cachedRows = null;
                    });
                  }
                },
                child: const Text('Delete'),
              ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;

                // Build the updated row data.
                final data = <String, dynamic>{
                  widget.model.statusField: selectedStatus ?? '',
                };
                for (final fieldName in fields) {
                  final def = fieldDefs[fieldName];
                  final fieldType = def?.type ?? 'text';
                  if (fieldType == 'select' &&
                      def?.options != null &&
                      def!.options!.isNotEmpty) {
                    final val = dropdownValues[fieldName];
                    if (val != null && val.isNotEmpty) {
                      data[fieldName] = val;
                    }
                  } else if (fieldType == 'user' &&
                      engine.isMultiUser) {
                    final val = dropdownValues[fieldName];
                    if (val != null && val.isNotEmpty) {
                      data[fieldName] = val;
                    }
                  } else {
                    final val = controllers[fieldName]?.text ?? '';
                    if (val.isNotEmpty) {
                      data[fieldName] = val;
                    }
                  }
                }

                // Update via the PUT dataSource, matching on _id.
                final matchValue = row['_id']?.toString() ?? '';
                if (matchValue.isNotEmpty) {
                  final putDsId = _findPutDataSourceId(engine);
                  await engine.executeRowAction(
                    dataSourceId: putDsId ?? widget.model.dataSource,
                    matchField: '_id',
                    matchValue: matchValue,
                    values: data.map((k, v) => MapEntry(k, v.toString())),
                  );
                }

                if (ctx.mounted) Navigator.of(ctx).pop();

                // Clear cache and trigger rebuild.
                setState(() {
                  _cachedRows = null;
                });
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// Converts a camelCase field name to a human-readable label.
  String _prettifyFieldName(String name) {
    // Insert spaces before uppercase letters and capitalize the first letter.
    final spaced =
        name.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  /// Assigns a subtle column tint based on the column index.
  Color _columnTint(int index, ThemeData theme) {
    final hues = [
      Colors.blue,
      Colors.teal,
      Colors.orange,
      Colors.purple,
      Colors.pink,
      Colors.green,
      Colors.indigo,
      Colors.amber,
    ];
    final base = hues[index % hues.length];
    return theme.brightness == Brightness.dark
        ? base.withOpacity(0.08)
        : base.withOpacity(0.06);
  }

  /// Builds a single kanban card widget.
  Widget _buildCard(
    Map<String, dynamic> row, {
    double opacity = 1.0,
    bool showActions = true,
    AppEngine? engine,
  }) {
    final theme = Theme.of(context);
    final cardId = row['_id']?.toString() ?? row.hashCode.toString();
    final rotation = _getRotation(cardId) * math.pi / 180;
    final titleValue = row[_titleField]?.toString() ?? '';

    // Determine secondary fields (cardFields minus titleField).
    final secondaryFields = widget.model.cardFields
        .where((f) => f != _titleField)
        .toList();

    final visibleActions = engine != null ? _visibleRowActions(engine) : <OdsRowAction>[];

    return Transform.rotate(
      angle: rotation,
      child: Opacity(
        opacity: opacity,
        child: SizedBox(
          width: _columnWidth - 24,
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title
                  if (titleValue.isNotEmpty)
                    Text(
                      titleValue,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (titleValue.isNotEmpty && secondaryFields.isNotEmpty)
                    const SizedBox(height: 6),
                  // Secondary fields
                  ...secondaryFields.map((field) {
                    final value = row[field]?.toString() ?? '';
                    if (value.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '${_prettifyFieldName(field)}: $value',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }),
                  // Row actions
                  if (showActions && visibleActions.isNotEmpty && engine != null) ...[
                    const SizedBox(height: 6),
                    const Divider(height: 1),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      children: visibleActions
                          .where((action) =>
                              action.hideWhen == null ||
                              !action.hideWhen!.matches(row))
                          .map((action) {
                        final needsConfirm =
                            action.confirm != null || action.isDelete;
                        return SizedBox(
                          height: 28,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: action.isDelete
                                  ? theme.colorScheme.error
                                  : null,
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () {
                              if (needsConfirm) {
                                _confirmRowAction(
                                    context, engine, action, row);
                              } else {
                                _executeRowAction(engine, action, row);
                              }
                            },
                            child: Text(action.label),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the search bar for searchable kanban boards.
  Widget _buildSearchBar() {
    if (!widget.model.searchable) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Search cards...',
          border: OutlineInputBorder(),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        ),
        onChanged: (value) {
          setState(() => _searchQuery = value);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AppEngine>();
    final theme = Theme.of(context);
    final statusOptions = _discoverStatusOptions(engine);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: engine.queryDataSource(widget.model.dataSource),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _cachedRows == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasData) {
            _cachedRows = snapshot.data;
          }
          final allRows = _cachedRows ?? [];

          // Apply search and sort.
          final searchedRows = _searchRows(allRows);
          final sortedRows = _sortRows(searchedRows);

          // If no status options were found in forms, derive them from the data.
          final columns = statusOptions.isNotEmpty
              ? statusOptions
              : _deriveColumnsFromData(sortedRows);

          if (columns.isEmpty) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  allRows.isEmpty
                      ? 'No data yet.'
                      : 'Could not determine columns for the kanban board. '
                          'Ensure the "${widget.model.statusField}" field is a select type '
                          'with options defined in a form.',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            );
          }

          // Group rows by status.
          final grouped = <String, List<Map<String, dynamic>>>{};
          for (final col in columns) {
            grouped[col] = [];
          }
          for (final row in sortedRows) {
            final status = row[widget.model.statusField]?.toString() ?? '';
            if (grouped.containsKey(status)) {
              grouped[status]!.add(row);
            } else {
              // Row has a status not in the options list; add to first column.
              grouped[columns.first]?.add(row);
            }
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSearchBar(),
              if (_searchQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Showing ${searchedRows.length} of ${allRows.length} cards',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              SizedBox(
                height: 500, // Fixed height for the board area.
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: columns.asMap().entries.map((entry) {
                      final colIndex = entry.key;
                      final status = entry.value;
                      final columnRows = grouped[status] ?? [];
                      return _buildColumn(
                        status,
                        columnRows,
                        colIndex,
                        engine,
                        theme,
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Derives unique status values from the data when no form options are found.
  List<String> _deriveColumnsFromData(List<Map<String, dynamic>> rows) {
    final seen = <String>{};
    final result = <String>[];
    for (final row in rows) {
      final status = row[widget.model.statusField]?.toString() ?? '';
      if (status.isNotEmpty && seen.add(status)) {
        result.add(status);
      }
    }
    return result;
  }

  /// Builds a single kanban column with header and draggable cards.
  Widget _buildColumn(
    String status,
    List<Map<String, dynamic>> rows,
    int colIndex,
    AppEngine engine,
    ThemeData theme,
  ) {
    final tint = _columnTint(colIndex, theme);
    final headerColor = tint.withOpacity(
        theme.brightness == Brightness.dark ? 0.25 : 0.18);

    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (details) {
        // Accept if the card is coming from a different column.
        final row = details.data;
        final currentStatus =
            row[widget.model.statusField]?.toString() ?? '';
        return currentStatus != status;
      },
      onAcceptWithDetails: (details) {
        final row = details.data;
        _updateStatus(engine, row, status);
      },
      builder: (context, candidateData, rejectedData) {
        final isHighlighted = candidateData.isNotEmpty;

        return Container(
          width: _columnWidth,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: isHighlighted
                ? theme.colorScheme.primaryContainer.withOpacity(0.3)
                : tint,
            borderRadius: BorderRadius.circular(12),
            border: isHighlighted
                ? Border.all(
                    color: theme.colorScheme.primary.withOpacity(0.5),
                    width: 2,
                  )
                : null,
          ),
          child: Column(
            children: [
              // Column header.
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: headerColor,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        status,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${rows.length}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Card list.
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No cards',
                            style: TextStyle(
                              color: theme.colorScheme.outline,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 6),
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Draggable<Map<String, dynamic>>(
                              data: row,
                              feedback: Material(
                                color: Colors.transparent,
                                child: _buildCard(row, opacity: 0.85),
                              ),
                              childWhenDragging: Opacity(
                                opacity: 0.3,
                                child: _buildCard(row, showActions: false),
                              ),
                              child: GestureDetector(
                                onTap: () =>
                                    _showEditCardDialog(context, engine, row),
                                child: _buildCard(
                                  row,
                                  engine: engine,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              // "+ Add" button at the bottom of each column.
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add'),
                    onPressed: () =>
                        _showAddCardDialog(context, engine, status),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

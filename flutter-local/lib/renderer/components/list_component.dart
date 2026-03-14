import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/app_engine.dart';
import '../../engine/formula_evaluator.dart';
import '../../models/ods_component.dart';
import '../../models/ods_field_definition.dart';

/// Renders an [OdsListComponent] as a DataTable populated from local storage.
///
/// ODS Spec: The list component references a GET data source and defines
/// columns that map field names to display headers. Columns with
/// `"sortable": true` get tappable headers that sort the data. Columns with
/// `"filterable": true` get dropdown filters above the table. Optional
/// `rowActions` add per-row action buttons (e.g., "Mark Done"). Optional
/// `summary` adds aggregation rows below the table.
///
/// Computed columns: If a column's field matches a computed field definition
/// (one with a `formula`) from the data source, the value is evaluated
/// on-the-fly from each row's stored data rather than read from the database.
///
/// ODS Ethos: The builder writes `"sortable": true`, `"filterable": true`,
/// or adds a `summary` array and the framework handles the rest — sort icons,
/// filter dropdowns, aggregation math, and layout. Complexity is the
/// framework's job.
class OdsListWidget extends StatefulWidget {
  final OdsListComponent model;

  const OdsListWidget({super.key, required this.model});

  @override
  State<OdsListWidget> createState() => _OdsListWidgetState();
}

class _OdsListWidgetState extends State<OdsListWidget> {
  /// The field currently used for sorting, or null if unsorted.
  String? _sortField;

  /// True for ascending, false for descending.
  bool _sortAscending = true;

  /// Active filter values keyed by field name. Null or "All" means no filter.
  final Map<String, String?> _filters = {};

  /// Sorts rows in-memory by the current sort field and direction.
  List<Map<String, dynamic>> _sortRows(List<Map<String, dynamic>> rows) {
    if (_sortField == null) return rows;
    final sorted = List<Map<String, dynamic>>.from(rows);
    sorted.sort((a, b) {
      final aVal = a[_sortField]?.toString() ?? '';
      final bVal = b[_sortField]?.toString() ?? '';
      // Try numeric comparison first for natural number sorting.
      final aNum = num.tryParse(aVal);
      final bNum = num.tryParse(bVal);
      int cmp;
      if (aNum != null && bNum != null) {
        cmp = aNum.compareTo(bNum);
      } else {
        cmp = aVal.compareTo(bVal);
      }
      return _sortAscending ? cmp : -cmp;
    });
    return sorted;
  }

  /// Filters rows based on active filter selections.
  List<Map<String, dynamic>> _filterRows(List<Map<String, dynamic>> rows) {
    if (_filters.isEmpty) return rows;
    return rows.where((row) {
      for (final entry in _filters.entries) {
        if (entry.value == null) continue;
        final rowVal = row[entry.key]?.toString() ?? '';
        if (rowVal != entry.value) return false;
      }
      return true;
    }).toList();
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
      final matchValue = row[action.matchField]?.toString() ?? '';
      if (action.isDelete) {
        engine.executeDeleteRowAction(
          dataSourceId: action.dataSource,
          matchField: action.matchField,
          matchValue: matchValue,
        );
      } else {
        engine.executeRowAction(
          dataSourceId: action.dataSource,
          matchField: action.matchField,
          matchValue: matchValue,
          values: action.values,
        );
      }
    }
  }

  /// Builds a map of computed field definitions from the data source's fields.
  Map<String, OdsFieldDefinition> _getComputedFields(AppEngine engine) {
    final ds = engine.app?.dataSources[widget.model.dataSource];
    if (ds?.fields == null) return {};
    final computed = <String, OdsFieldDefinition>{};
    for (final field in ds!.fields!) {
      if (field.isComputed) {
        computed[field.name] = field;
      }
    }
    return computed;
  }

  /// Returns the set of field names that are number type (for fallback currency).
  Set<String> _getNumericFields(AppEngine engine) {
    final ds = engine.app?.dataSources[widget.model.dataSource];
    if (ds?.fields == null) return {};
    return ds!.fields!
        .where((f) => f.type == 'number')
        .map((f) => f.name)
        .toSet();
  }

  /// Formats a value with currency prefix if the column is marked `currency: true`.
  String _formatCurrency(String value, String? currencySymbol) {
    if (currencySymbol == null || currencySymbol.isEmpty) return value;
    if (num.tryParse(value) != null) return '$currencySymbol$value';
    return value;
  }

  /// Resolves a color name from a colorMap value.
  Color? _resolveColor(String colorName) {
    switch (colorName.toLowerCase()) {
      case 'green':
        return Colors.green;
      case 'red':
        return Colors.red;
      case 'orange':
        return Colors.orange;
      case 'blue':
        return Colors.blue;
      case 'grey':
      case 'gray':
        return Colors.grey;
      default:
        return null;
    }
  }

  /// Gets the display value for a cell, evaluating formulas for computed columns.
  String _getCellValue(
    Map<String, dynamic> row,
    String fieldName,
    Map<String, OdsFieldDefinition> computedFields,
  ) {
    final computedField = computedFields[fieldName];
    if (computedField != null) {
      final values = <String, String?>{};
      for (final key in row.keys) {
        values[key] = row[key]?.toString();
      }
      return FormulaEvaluator.evaluate(
        computedField.formula!,
        computedField.type,
        values,
      );
    }
    return row[fieldName]?.toString() ?? '';
  }

  /// Computes the numeric value for a cell (for aggregation purposes).
  double _getNumericValue(
    Map<String, dynamic> row,
    String fieldName,
    Map<String, OdsFieldDefinition> computedFields,
  ) {
    final str = _getCellValue(row, fieldName, computedFields);
    return double.tryParse(str) ?? 0;
  }

  /// Computes an aggregation for a summary rule across the given rows.
  String _computeAggregate(
    OdsSummaryRule rule,
    List<Map<String, dynamic>> rows,
    Map<String, OdsFieldDefinition> computedFields,
  ) {
    if (rows.isEmpty) {
      return rule.function == 'count' ? '0' : '-';
    }

    switch (rule.function) {
      case 'count':
        return rows.length.toString();
      case 'sum':
        final sum = rows.fold<double>(
          0,
          (acc, row) => acc + _getNumericValue(row, rule.column, computedFields),
        );
        return _formatNumber(sum);
      case 'avg':
        final sum = rows.fold<double>(
          0,
          (acc, row) => acc + _getNumericValue(row, rule.column, computedFields),
        );
        return _formatNumber(sum / rows.length);
      case 'min':
        final values = rows.map((row) => _getNumericValue(row, rule.column, computedFields));
        return _formatNumber(values.reduce(math.min));
      case 'max':
        final values = rows.map((row) => _getNumericValue(row, rule.column, computedFields));
        return _formatNumber(values.reduce(math.max));
      default:
        return '-';
    }
  }

  String _formatNumber(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
  }

  /// Builds filter dropdown widgets for filterable columns.
  Widget _buildFilters(
    List<Map<String, dynamic>> allRows,
    Map<String, OdsFieldDefinition> computedFields,
  ) {
    final filterableColumns =
        widget.model.columns.where((col) => col.filterable).toList();
    if (filterableColumns.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: filterableColumns.map((col) {
          // Collect distinct values for this column.
          final distinctValues = <String>{};
          for (final row in allRows) {
            final val = _getCellValue(row, col.field, computedFields);
            if (val.isNotEmpty) distinctValues.add(val);
          }
          final sortedValues = distinctValues.toList()..sort();

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${col.header}: ',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              DropdownButton<String?>(
                value: _filters[col.field],
                hint: const Text('All'),
                underline: const SizedBox.shrink(),
                isDense: true,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All'),
                  ),
                  ...sortedValues.map((v) => DropdownMenuItem<String?>(
                        value: v,
                        child: Text(
                          v.length > 20 ? '${v.substring(0, 20)}...' : v,
                        ),
                      )),
                ],
                onChanged: (value) {
                  setState(() {
                    if (value == null) {
                      _filters.remove(col.field);
                    } else {
                      _filters[col.field] = value;
                    }
                  });
                },
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  /// Builds the summary row displayed below the data table.
  /// Checks if a column should show currency formatting.
  bool _isColumnCurrency(String fieldName, Set<String> fallbackFields) {
    for (final col in widget.model.columns) {
      if (col.field == fieldName) return col.currency;
    }
    return fallbackFields.contains(fieldName);
  }

  Widget _buildSummaryRow(
    List<Map<String, dynamic>> filteredRows,
    Map<String, OdsFieldDefinition> computedFields, {
    String? currencySymbol,
    Set<String> fallbackCurrencyFields = const {},
  }) {
    if (widget.model.summary.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 24,
            runSpacing: 8,
            children: widget.model.summary.map((rule) {
              var value = _computeAggregate(rule, filteredRows, computedFields);
              // Apply currency formatting to summary values for currency columns.
              if (rule.function != 'count' &&
                  _isColumnCurrency(rule.column, fallbackCurrencyFields)) {
                value = _formatCurrency(value, currencySymbol);
              }
              final label = rule.label ??
                  '${rule.function[0].toUpperCase()}${rule.function.substring(1)} of ${_columnHeader(rule.column)}';
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$label: ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  /// Finds the display header for a field name, or falls back to the field name.
  String _columnHeader(String fieldName) {
    for (final col in widget.model.columns) {
      if (col.field == fieldName) return col.header;
    }
    return fieldName;
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AppEngine>();
    final hasRowActions = widget.model.rowActions.isNotEmpty;
    final computedFields = _getComputedFields(engine);
    final currencySymbol = engine.getAppSetting('currency');
    // If no columns explicitly opt in to currency, fall back to applying
    // the currency symbol to all number-type columns (backwards compat).
    final anyColumnHasCurrency =
        widget.model.columns.any((col) => col.currency);
    final fallbackCurrencyFields = !anyColumnHasCurrency && currencySymbol != null
        ? _getNumericFields(engine)
        : <String>{};

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: engine.queryDataSource(widget.model.dataSource),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allRows = snapshot.data ?? [];

          if (allRows.isEmpty) {
            return const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No data yet.', style: TextStyle(color: Colors.grey)),
              ),
            );
          }

          // Apply filters, then sort.
          final filteredRows = _filterRows(allRows);
          final sortedRows = _sortRows(filteredRows);

          // Find the column index for the current sort field (for DataTable).
          int? sortColumnIndex;
          if (_sortField != null) {
            for (var i = 0; i < widget.model.columns.length; i++) {
              if (widget.model.columns[i].field == _sortField) {
                sortColumnIndex = i;
                break;
              }
            }
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Filter dropdowns above the table.
              _buildFilters(allRows, computedFields),
              // Data table.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  showCheckboxColumn: false,
                  sortColumnIndex: sortColumnIndex,
                  sortAscending: _sortAscending,
                  columns: [
                    ...widget.model.columns.map((col) {
                      return DataColumn(
                        label: Text(col.header),
                        onSort: col.sortable
                            ? (columnIndex, ascending) {
                                setState(() {
                                  if (_sortField == col.field) {
                                    _sortAscending = !_sortAscending;
                                  } else {
                                    _sortField = col.field;
                                    _sortAscending = true;
                                  }
                                });
                              }
                            : null,
                      );
                    }),
                    // Add an "Actions" column when rowActions are defined.
                    if (hasRowActions)
                      const DataColumn(label: Text('Actions')),
                  ],
                  rows: sortedRows.map((row) {
                    final rowTap = widget.model.onRowTap;
                    return DataRow(
                      onSelectChanged: rowTap != null
                          ? (_) {
                              if (rowTap.populateForm != null) {
                                engine.populateFormAndNavigate(
                                  formId: rowTap.populateForm!,
                                  pageId: rowTap.target,
                                  rowData: row,
                                );
                              } else {
                                engine.navigateTo(rowTap.target);
                              }
                            }
                          : null,
                      cells: [
                        ...widget.model.columns.map((col) {
                          final value = _getCellValue(row, col.field, computedFields);
                          final useCurrency = col.currency ||
                              fallbackCurrencyFields.contains(col.field);
                          var display = useCurrency
                              ? _formatCurrency(value, currencySymbol)
                              : value;
                          // Apply displayMap to transform raw values.
                          if (col.displayMap != null &&
                              col.displayMap!.containsKey(value)) {
                            display = col.displayMap![value]!;
                          }
                          // Apply colorMap styling if defined.
                          Color? textColor;
                          if (col.colorMap != null) {
                            final colorName = col.colorMap![value];
                            if (colorName != null) {
                              textColor = _resolveColor(colorName);
                            }
                          }
                          return DataCell(Text(
                            display,
                            style: textColor != null
                                ? TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.w600,
                                  )
                                : null,
                          ));
                        }),
                        // Render action buttons for each row.
                        if (hasRowActions)
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: widget.model.rowActions
                                  .where((action) =>
                                      action.hideWhen == null ||
                                      !action.hideWhen!.matches(row))
                                  .map((action) {
                                final needsConfirm = action.confirm != null || action.isDelete;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: TextButton(
                                    style: action.isDelete
                                        ? TextButton.styleFrom(
                                            foregroundColor:
                                                Theme.of(context).colorScheme.error,
                                          )
                                        : null,
                                    onPressed: () {
                                      if (needsConfirm) {
                                        _confirmRowAction(
                                          context,
                                          engine,
                                          action,
                                          row,
                                        );
                                      } else {
                                        final matchValue =
                                            row[action.matchField]?.toString() ?? '';
                                        engine.executeRowAction(
                                          dataSourceId: action.dataSource,
                                          matchField: action.matchField,
                                          matchValue: matchValue,
                                          values: action.values,
                                        );
                                      }
                                    },
                                    child: Text(action.label),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                      ],
                    );
                  }).toList(),
                ),
              ),
              // Summary/aggregation row below the table.
              _buildSummaryRow(filteredRows, computedFields,
                  currencySymbol: currencySymbol,
                  fallbackCurrencyFields: fallbackCurrencyFields),
              // Show filtered count when filters are active.
              if (_filters.values.any((v) => v != null))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Showing ${filteredRows.length} of ${allRows.length} records',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

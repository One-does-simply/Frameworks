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
  /// Width of each card in card layout mode.
  static const double _cardWidth = 280;

  /// Returns columns filtered by the current user's roles.
  List<OdsListColumn> _visibleColumns(AppEngine engine) {
    if (!engine.isMultiUser) return widget.model.columns;
    return widget.model.columns
        .where((col) => engine.authService.hasAccess(col.roles))
        .toList();
  }

  /// Returns row actions filtered by the current user's roles.
  List<OdsRowAction> _visibleRowActions(AppEngine engine) {
    if (!engine.isMultiUser) return widget.model.rowActions;
    return widget.model.rowActions
        .where((action) => engine.authService.hasAccess(action.roles))
        .toList();
  }

  /// The field currently used for sorting, or null if unsorted.
  String? _sortField;

  /// True for ascending, false for descending.
  bool _sortAscending = true;

  /// Whether the defaultSort has been applied as initial state.
  bool _defaultSortApplied = false;

  /// Active filter values keyed by field name. Null or "All" means no filter.
  final Map<String, String?> _filters = {};

  /// Current search query for searchable lists (F2).
  String _searchQuery = '';

  /// Cached query results so the FutureBuilder doesn't flash a loading spinner
  /// on every rebuild (search, filter, sort are all local operations on the
  /// already-loaded data).
  List<Map<String, dynamic>>? _cachedRows;

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

  /// Filters rows based on search query across all displayed columns (F2).
  List<Map<String, dynamic>> _searchRows(
    List<Map<String, dynamic>> rows,
    Map<String, OdsFieldDefinition> computedFields,
  ) {
    if (_searchQuery.isEmpty) return rows;
    final query = _searchQuery.toLowerCase();
    return rows.where((row) {
      for (final col in widget.model.columns) {
        final value = _getCellValue(row, col.field, computedFields).toLowerCase();
        if (value.contains(query)) return true;
      }
      return false;
    }).toList();
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
      _executeRowAction(engine, action, row);
    }
  }

  /// Dispatches a row action to the appropriate engine method.
  void _executeRowAction(AppEngine engine, OdsRowAction action, Map<String, dynamic> row) {
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

  /// Handles a toggle checkbox tap: updates the value, then checks auto-complete.
  Future<void> _handleToggle(
    AppEngine engine,
    OdsListColumn col,
    Map<String, dynamic> row,
    bool currentlyChecked,
  ) async {
    final newValue = currentlyChecked ? 'false' : 'true';
    final matchValue = row[col.toggle!.matchField]?.toString() ?? '';
    await engine.executeRowAction(
      dataSourceId: col.toggle!.dataSource,
      matchField: col.toggle!.matchField,
      matchValue: matchValue,
      values: {col.field: newValue},
    );

    // Auto-complete parent: if we just checked an item ON, see if all
    // sibling items in the same group are now done.
    final ac = col.toggle!.autoComplete;
    if (ac != null && newValue == 'true') {
      final groupValue = row[ac.groupField]?.toString() ?? '';
      await engine.checkAutoComplete(
        listDataSourceId: widget.model.dataSource,
        toggleField: col.field,
        groupField: ac.groupField,
        groupValue: groupValue,
        parentDataSourceId: ac.parentDataSource,
        parentMatchField: ac.parentMatchField,
        parentValues: ac.parentValues,
      );
    }
  }

  /// Returns true if any toggle column in this list is checked for this row.
  bool _isRowChecked(
    Map<String, dynamic> row,
    Map<String, OdsFieldDefinition> computedFields,
  ) {
    for (final col in widget.model.columns) {
      if (col.toggle != null) {
        final val = _getCellValue(row, col.field, computedFields);
        if (val == 'true') return true;
      }
    }
    return false;
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

  /// Builds the search bar for searchable lists (F2).
  Widget _buildSearchBar() {
    if (!widget.model.searchable) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Search...',
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

  /// Resolves the background color for a row based on rowColorField/rowColorMap (F3).
  WidgetStateProperty<Color?>? _resolveRowColor(Map<String, dynamic> row) {
    final colorField = widget.model.rowColorField;
    final colorMap = widget.model.rowColorMap;
    if (colorField == null || colorMap == null) return null;
    final fieldValue = row[colorField]?.toString() ?? '';
    final colorName = colorMap[fieldValue];
    if (colorName == null) return null;
    final color = _resolveColor(colorName);
    if (color == null) return null;
    return WidgetStatePropertyAll(color.withOpacity(0.15));
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
    // Apply defaultSort as initial sort state on first build.
    if (!_defaultSortApplied && widget.model.defaultSort != null) {
      _sortField = widget.model.defaultSort!.field;
      _sortAscending = !widget.model.defaultSort!.isDescending;
      _defaultSortApplied = true;
    }

    final engine = context.watch<AppEngine>();
    final visibleCols = _visibleColumns(engine);
    final visibleActions = _visibleRowActions(engine);
    final hasRowActions = visibleActions.isNotEmpty;
    final computedFields = _getComputedFields(engine);
    final currencySymbol = engine.getAppSetting('currency');
    // If no columns explicitly opt in to currency, fall back to applying
    // the currency symbol to all number-type columns (backwards compat).
    final anyColumnHasCurrency =
        visibleCols.any((col) => col.currency);
    final fallbackCurrencyFields = !anyColumnHasCurrency && currencySymbol != null
        ? _getNumericFields(engine)
        : <String>{};

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: engine.queryDataSource(widget.model.dataSource),
        builder: (context, snapshot) {
          // Use cached data while a new query is in flight so that
          // local operations (search, filter, sort) don't flash a spinner.
          if (snapshot.connectionState == ConnectionState.waiting && _cachedRows == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasData) {
            _cachedRows = snapshot.data;
          }
          final allRows = _cachedRows ?? [];

          if (allRows.isEmpty) {
            return const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No data yet.', style: TextStyle(color: Colors.grey)),
              ),
            );
          }

          // Apply filters, search, then sort.
          final filteredRows = _filterRows(allRows);
          final searchedRows = _searchRows(filteredRows, computedFields);
          final sortedRows = _sortRows(searchedRows);

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
              // Search bar for searchable lists (F2).
              _buildSearchBar(),
              // Filter dropdowns above the table.
              _buildFilters(allRows, computedFields),
              // Data display — table or cards (F5).
              if (widget.model.displayAs == 'cards')
                _buildCards(
                  sortedRows,
                  computedFields,
                  engine,
                  currencySymbol: currencySymbol,
                  fallbackCurrencyFields: fallbackCurrencyFields,
                  visibleCols: visibleCols,
                  visibleActions: visibleActions,
                )
              else
                _buildTable(
                  sortedRows,
                  computedFields,
                  engine,
                  sortColumnIndex: sortColumnIndex,
                  hasRowActions: hasRowActions,
                  currencySymbol: currencySymbol,
                  fallbackCurrencyFields: fallbackCurrencyFields,
                  visibleCols: visibleCols,
                  visibleActions: visibleActions,
                ),
              // Tap-to-edit hint when rows are tappable.
              if (widget.model.onRowTap != null && sortedRows.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.touch_app, size: 14, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(width: 4),
                      Text(
                        'Tap a row to edit',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              // Summary/aggregation row below the table.
              _buildSummaryRow(searchedRows, computedFields,
                  currencySymbol: currencySymbol,
                  fallbackCurrencyFields: fallbackCurrencyFields),
              // Show filtered/searched count when active.
              if (_filters.values.any((v) => v != null) || _searchQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Showing ${searchedRows.length} of ${allRows.length} records',
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

  /// Builds the DataTable view (default display mode).
  Widget _buildTable(
    List<Map<String, dynamic>> sortedRows,
    Map<String, OdsFieldDefinition> computedFields,
    AppEngine engine, {
    int? sortColumnIndex,
    required bool hasRowActions,
    String? currencySymbol,
    Set<String> fallbackCurrencyFields = const {},
    required List<OdsListColumn> visibleCols,
    required List<OdsRowAction> visibleActions,
  }) {
    // Resolve density hint for row spacing.
    final density = widget.model.styleHint.density;
    final dataRowMinHeight = switch (density) {
      'compact' => 36.0,
      'comfortable' => 56.0,
      _ => 48.0,
    };
    final dataRowMaxHeight = switch (density) {
      'compact' => 40.0,
      'comfortable' => 64.0,
      _ => 52.0,
    };
    final headingRowHeight = switch (density) {
      'compact' => 40.0,
      'comfortable' => 60.0,
      _ => 56.0,
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        sortColumnIndex: sortColumnIndex,
        sortAscending: _sortAscending,
        dataRowMinHeight: dataRowMinHeight,
        dataRowMaxHeight: dataRowMaxHeight,
        headingRowHeight: headingRowHeight,
        columns: [
          ...visibleCols.map((col) {
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
          if (hasRowActions)
            const DataColumn(label: Text('Actions')),
        ],
        rows: sortedRows.map((row) {
          final rowTap = widget.model.onRowTap;
          return DataRow(
            key: ValueKey(row['_id'] ?? row.hashCode),
            color: _resolveRowColor(row),
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
              ...visibleCols.map((col) {
                // Toggle column: render as checkbox.
                if (col.toggle != null) {
                  final checked = _getCellValue(row, col.field, computedFields) == 'true';
                  return DataCell(
                    Checkbox(
                      value: checked,
                      onChanged: (_) => _handleToggle(engine, col, row, checked),
                    ),
                  );
                }

                final value = _getCellValue(row, col.field, computedFields);
                final useCurrency = col.currency ||
                    fallbackCurrencyFields.contains(col.field);
                var display = useCurrency
                    ? _formatCurrency(value, currencySymbol)
                    : value;
                if (col.displayMap != null &&
                    col.displayMap!.containsKey(value)) {
                  display = col.displayMap![value]!;
                }
                Color? textColor;
                if (col.colorMap != null) {
                  final colorName = col.colorMap![value];
                  if (colorName != null) {
                    textColor = _resolveColor(colorName);
                  }
                }

                // Strikethrough text when a sibling toggle column is checked.
                final isStruck = _isRowChecked(row, computedFields);

                final cellColor = isStruck && textColor == null
                    ? Theme.of(context).colorScheme.outline
                    : textColor;

                return DataCell(Text(
                  display,
                  style: TextStyle(
                    color: cellColor,
                    fontWeight: textColor != null ? FontWeight.w600 : null,
                    decoration: isStruck ? TextDecoration.lineThrough : null,
                    decorationColor: Theme.of(context).colorScheme.outline,
                  ),
                ));
              }),
              if (hasRowActions)
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: visibleActions
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
                              _confirmRowAction(context, engine, action, row);
                            } else {
                              _executeRowAction(engine, action, row);
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
    );
  }

  /// Builds a card-based layout for list data (F5: displayAs = 'cards').
  Widget _buildCards(
    List<Map<String, dynamic>> sortedRows,
    Map<String, OdsFieldDefinition> computedFields,
    AppEngine engine, {
    String? currencySymbol,
    Set<String> fallbackCurrencyFields = const {},
    required List<OdsListColumn> visibleCols,
    required List<OdsRowAction> visibleActions,
  }) {
    final hasRowActions = visibleActions.isNotEmpty;
    final theme = Theme.of(context);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: sortedRows.map((row) {
        final rowKey = ValueKey(row['_id'] ?? row.hashCode);
        // Resolve row background color (F3).
        Color? cardColor;
        final colorField = widget.model.rowColorField;
        final colorMap = widget.model.rowColorMap;
        if (colorField != null && colorMap != null) {
          final fieldValue = row[colorField]?.toString() ?? '';
          final colorName = colorMap[fieldValue];
          if (colorName != null) {
            cardColor = _resolveColor(colorName)?.withOpacity(0.15);
          }
        }

        final rowTap = widget.model.onRowTap;
        return SizedBox(
          key: rowKey,
          width: _cardWidth,
          child: Card(
            color: cardColor,
            elevation: 1,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: rowTap != null
                  ? () {
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
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...visibleCols.map((col) {
                      // Toggle column in card view: render as checkbox row.
                      if (col.toggle != null) {
                        final checked = _getCellValue(row, col.field, computedFields) == 'true';
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(col.header),
                          value: checked,
                          onChanged: (_) => _handleToggle(engine, col, row, checked),
                        );
                      }

                      final value = _getCellValue(row, col.field, computedFields);
                      final useCurrency = col.currency ||
                          fallbackCurrencyFields.contains(col.field);
                      var display = useCurrency
                          ? _formatCurrency(value, currencySymbol)
                          : value;
                      if (col.displayMap != null &&
                          col.displayMap!.containsKey(value)) {
                        display = col.displayMap![value]!;
                      }
                      Color? textColor;
                      if (col.colorMap != null) {
                        final colorName = col.colorMap![value];
                        if (colorName != null) {
                          textColor = _resolveColor(colorName);
                        }
                      }

                      final isStruck = _isRowChecked(row, computedFields);
                      final cellColor = isStruck && textColor == null
                          ? theme.colorScheme.outline
                          : textColor;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 90,
                              child: Text(
                                col.header,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                display,
                                style: TextStyle(
                                  color: cellColor,
                                  fontWeight: textColor != null ? FontWeight.w600 : null,
                                  decoration: isStruck ? TextDecoration.lineThrough : null,
                                  decorationColor: theme.colorScheme.outline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (hasRowActions) ...[
                      const Divider(),
                      Wrap(
                        spacing: 4,
                        children: visibleActions
                            .where((action) =>
                                action.hideWhen == null ||
                                !action.hideWhen!.matches(row))
                            .map((action) {
                          final needsConfirm = action.confirm != null || action.isDelete;
                          return TextButton(
                            style: action.isDelete
                                ? TextButton.styleFrom(
                                    foregroundColor: theme.colorScheme.error,
                                  )
                                : null,
                            onPressed: () {
                              if (needsConfirm) {
                                _confirmRowAction(context, engine, action, row);
                              } else {
                                _executeRowAction(engine, action, row);
                              }
                            },
                            child: Text(action.label),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/app_engine.dart';
import '../../models/ods_component.dart';

/// Renders an [OdsListComponent] as a DataTable populated from local storage.
///
/// ODS Spec: The list component references a GET data source and defines
/// columns that map field names to display headers. Columns with
/// `"sortable": true` get tappable headers that sort the data. Optional
/// `rowActions` add per-row action buttons (e.g., "Mark Done").
///
/// ODS Ethos: The builder writes `"sortable": true` or adds a `rowActions`
/// array and the framework handles the rest — sort icons, action buttons,
/// database updates, and list refresh. Complexity is the framework's job.
///
/// Implementation note: Sort state is local to this widget. Sorting is done
/// in-memory after the query returns, keeping the DataStore simple.
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

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AppEngine>();
    final hasRowActions = widget.model.rowActions.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: engine.queryDataSource(widget.model.dataSource),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final rows = snapshot.data ?? [];

          if (rows.isEmpty) {
            return const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No data yet.', style: TextStyle(color: Colors.grey)),
              ),
            );
          }

          final sortedRows = _sortRows(rows);

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

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
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
                return DataRow(
                  cells: [
                    ...widget.model.columns.map((col) {
                      final value = row[col.field]?.toString() ?? '';
                      return DataCell(Text(value));
                    }),
                    // Render action buttons for each row.
                    if (hasRowActions)
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: widget.model.rowActions.map((action) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: TextButton(
                                onPressed: () {
                                  final matchValue =
                                      row[action.matchField]?.toString() ?? '';
                                  engine.executeRowAction(
                                    dataSourceId: action.dataSource,
                                    matchField: action.matchField,
                                    matchValue: matchValue,
                                    values: action.values,
                                  );
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
        },
      ),
    );
  }
}

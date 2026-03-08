import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/app_engine.dart';

/// A three-tab debug panel that renders at the bottom of the screen when
/// the user toggles debug mode via the bug icon in the app bar.
///
/// ODS Spec: Debug mode is a framework feature, not a spec feature. The
/// spec says nothing about debugging — that's intentional. Debugging is
/// a framework concern, and each framework can implement it differently.
///
/// ODS Ethos: "Citizen developers need guardrails, not guesswork." When
/// something isn't working, the debug panel gives immediate visibility
/// into validation issues, navigation state, and stored data — all in
/// context, without leaving the app.
///
/// Tabs:
///   1. Validation — shows spec validation messages (errors, warnings, info).
///   2. Navigation — shows current page, navigation stack, and all page IDs.
///   3. Data — lets the user browse SQLite tables and their rows.
class DebugPanel extends StatefulWidget {
  const DebugPanel({super.key});

  @override
  State<DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends State<DebugPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch the engine so the panel updates when navigation or form state
    // changes (e.g., after a submit clears form data).
    final engine = context.watch<AppEngine>();

    return Container(
      color: Colors.grey.shade900,
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue,
            tabs: const [
              Tab(text: 'Validation'),
              Tab(text: 'Navigation'),
              Tab(text: 'Data'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _ValidationTab(engine: engine),
                _NavigationTab(engine: engine),
                _DataTab(engine: engine),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Validation tab
// ---------------------------------------------------------------------------

/// Displays spec validation messages collected by [SpecValidator].
///
/// Color-coded by severity: red for errors, orange for warnings, blue for
/// informational notes. An empty list shows a green "No issues found"
/// message — positive reinforcement for well-formed specs.
class _ValidationTab extends StatelessWidget {
  final AppEngine engine;
  const _ValidationTab({required this.engine});

  @override
  Widget build(BuildContext context) {
    final validation = engine.validation;
    if (validation == null) {
      return const Center(
        child: Text('No spec loaded', style: TextStyle(color: Colors.grey)),
      );
    }

    final messages = validation.messages;
    if (messages.isEmpty) {
      return const Center(
        child: Text('No issues found', style: TextStyle(color: Colors.green)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        // Map severity levels to colors and icons.
        final color = switch (msg.level) {
          'error' => Colors.red,
          'warning' => Colors.orange,
          _ => Colors.blue,
        };
        final icon = switch (msg.level) {
          'error' => Icons.error,
          'warning' => Icons.warning,
          _ => Icons.info,
        };
        return ListTile(
          dense: true,
          leading: Icon(icon, color: color, size: 18),
          title: Text(
            msg.message,
            style: TextStyle(color: color, fontSize: 13),
          ),
          subtitle: msg.context != null
              ? Text(
                  msg.context!,
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                )
              : null,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Navigation tab
// ---------------------------------------------------------------------------

/// Shows the engine's current page, navigation stack, and all available
/// page IDs. The current page is highlighted with a `>>` prefix and
/// blue text so it's easy to spot at a glance.
class _NavigationTab extends StatelessWidget {
  final AppEngine engine;
  const _NavigationTab({required this.engine});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Page: ${engine.currentPageId ?? "none"}',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 8),
          // The breadcrumb-style stack trace shows how the user got here.
          Text(
            'Stack: ${engine.navigationStack.join(" > ")}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),
          const Text(
            'Pages:',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          // List every page in the spec, highlighting the active one.
          ...?engine.app?.pages.keys.map((pageId) {
            final isCurrent = pageId == engine.currentPageId;
            return Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Text(
                '${isCurrent ? ">> " : "   "}$pageId',
                style: TextStyle(
                  color: isCurrent ? Colors.blue : Colors.grey,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data tab
// ---------------------------------------------------------------------------

/// An interactive SQLite table browser. Lists all tables as chips; tapping
/// one loads its rows into a [DataTable]. A refresh button reloads both
/// the table list and the selected table's data.
///
/// This is invaluable for debugging "form is the schema" behavior — the
/// developer can submit a form and immediately verify that the data landed
/// in the expected table with the expected columns.
class _DataTab extends StatefulWidget {
  final AppEngine engine;
  const _DataTab({required this.engine});

  @override
  State<_DataTab> createState() => _DataTabState();
}

class _DataTabState extends State<_DataTab> {
  List<String> _tables = [];
  String? _selectedTable;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _loadTables();
  }

  /// Queries the data store for all user-created table names.
  Future<void> _loadTables() async {
    final tables = await widget.engine.dataStore.listTables();
    setState(() => _tables = tables);
  }

  /// Loads all rows from a given table and updates the display.
  Future<void> _loadRows(String tableName) async {
    final rows = await widget.engine.dataStore.query(tableName);
    setState(() {
      _selectedTable = tableName;
      _rows = rows;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // -- Table selector row --
          Row(
            children: [
              const Text(
                'Tables: ',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(width: 8),
              ..._tables.map((t) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(t, style: const TextStyle(fontSize: 12)),
                      backgroundColor:
                          t == _selectedTable ? Colors.blue : Colors.grey.shade700,
                      labelStyle: const TextStyle(color: Colors.white),
                      onPressed: () => _loadRows(t),
                    ),
                  )),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.grey, size: 18),
                onPressed: () {
                  _loadTables();
                  if (_selectedTable != null) _loadRows(_selectedTable!);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          // -- Table data display --
          Expanded(
            child: _rows.isEmpty
                ? Center(
                    child: Text(
                      _selectedTable == null ? 'Select a table' : 'No rows',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                // Double-scroll (horizontal + vertical) handles tables of
                // any width and height within the fixed 250px panel.
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                        headingTextStyle: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        dataTextStyle: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                        columns: _rows.first.keys
                            .map((key) => DataColumn(label: Text(key)))
                            .toList(),
                        rows: _rows
                            .map((row) => DataRow(
                                  cells: row.values
                                      .map((v) =>
                                          DataCell(Text(v?.toString() ?? '')))
                                      .toList(),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

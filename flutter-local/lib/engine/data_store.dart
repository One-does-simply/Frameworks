import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/ods_data_source.dart';
import '../models/ods_field_definition.dart';

/// SQLite-backed local storage for ODS applications.
///
/// ODS Spec alignment: Implements the `local://` data source convention.
/// Each `local://<tableName>` URL maps to a SQLite table. The DataStore
/// handles table creation, schema evolution, seed data, reads, and writes.
///
/// ODS Ethos: "Your data stays on your device." This class is the reason
/// ODS apps need no internet, no server, and no account. Everything lives
/// in a single SQLite file in the user's documents directory.
///
/// Design decisions:
///   - All columns are stored as TEXT for simplicity. Type information from
///     field definitions is used for UI hints, not storage constraints.
///   - Every row gets an auto-increment `_id` and a `_createdAt` timestamp.
///   - Tables are created lazily (on first submit or when explicit fields
///     are declared) and columns are added non-destructively via ALTER TABLE.
///   - Each app gets its own database file, named by sanitized appName.
class DataStore {
  Database? _db;

  /// Cache of tables we've already confirmed exist in this session,
  /// avoiding repeated sqlite_master queries.
  final Set<String> _knownTables = {};

  /// Timestamped log of all database operations, shown in the debug panel.
  final List<String> _debugLog = [];

  List<String> get debugLog => List.unmodifiable(_debugLog);

  void _log(String message) {
    _debugLog.add('[${DateTime.now().toIso8601String()}] $message');
  }

  /// Opens (or creates) the SQLite database for the given app.
  ///
  /// On desktop platforms (Windows, macOS, Linux), initializes the FFI-based
  /// SQLite driver since the default mobile driver is not available.
  Future<void> initialize(String appName) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dir = await getApplicationDocumentsDirectory();
    // Sanitize the app name to produce a safe filename.
    final safeAppName = appName.replaceAll(RegExp(r'[^\w]'), '_').toLowerCase();
    final dbPath = p.join(dir.path, 'ods_$safeAppName.db');

    _db = await databaseFactory.openDatabase(dbPath);
    _log('Database opened at $dbPath');
  }

  /// Creates a table if it doesn't exist, or adds any missing columns.
  ///
  /// This is the core of ODS's "auto-schema" capability. Called both during
  /// data source setup (when explicit fields are declared) and on first form
  /// submit (when the form's fields define the schema implicitly).
  Future<void> ensureTable(String tableName, List<OdsFieldDefinition> fields) async {
    final db = _db!;

    // Fast path: if we already know the table exists, just check for new columns.
    if (_knownTables.contains(tableName)) {
      await _addMissingColumns(tableName, fields);
      return;
    }

    // Check sqlite_master to see if the table was created in a previous session.
    // Uses parameterized query to avoid SQL injection from table names.
    final existing = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [tableName],
    );

    if (existing.isNotEmpty) {
      _knownTables.add(tableName);
      await _addMissingColumns(tableName, fields);
      _log('Table "$tableName" already exists, ensured columns');
      return;
    }

    // Create the table with all declared fields plus framework columns.
    final columnDefs = fields.map((f) => '"${f.name}" TEXT').join(', ');
    final sql =
        'CREATE TABLE "$tableName" (_id INTEGER PRIMARY KEY AUTOINCREMENT, $columnDefs, _createdAt TEXT)';
    await db.execute(sql);
    _knownTables.add(tableName);
    _log('Created table "$tableName" with fields: ${fields.map((f) => f.name).join(', ')}');
  }

  /// Adds columns for any fields not yet present in the table.
  ///
  /// This supports schema evolution: if a spec author adds a new field to a
  /// form, the column is added non-destructively on next launch. Existing
  /// rows get NULL for the new column. No data is ever deleted.
  Future<void> _addMissingColumns(String tableName, List<OdsFieldDefinition> fields) async {
    final db = _db!;
    final info = await db.rawQuery('PRAGMA table_info("$tableName")');
    final existingColumns = info.map((row) => row['name'] as String).toSet();

    for (final field in fields) {
      if (!existingColumns.contains(field.name)) {
        await db.execute('ALTER TABLE "$tableName" ADD COLUMN "${field.name}" TEXT');
        _log('Added column "${field.name}" to table "$tableName"');
      }
    }
  }

  /// Processes all local:// data sources: creates tables from explicit field
  /// definitions and inserts seed data into empty tables.
  ///
  /// ODS Spec: `seedData` is only inserted when the table has zero rows,
  /// preventing duplicate seeding on subsequent app launches.
  Future<void> setupDataSources(Map<String, OdsDataSource> dataSources) async {
    for (final entry in dataSources.entries) {
      final ds = entry.value;
      if (!ds.isLocal) continue;

      // Create table from explicit field definitions if provided.
      if (ds.fields != null && ds.fields!.isNotEmpty) {
        await ensureTable(ds.tableName, ds.fields!);
      }

      // Insert seed data into empty tables (first-run only).
      if (ds.seedData != null && ds.seedData!.isNotEmpty) {
        final count = await getRowCount(ds.tableName);
        if (count == 0) {
          for (final row in ds.seedData!) {
            await insert(ds.tableName, row);
          }
          _log('Seeded ${ds.seedData!.length} rows into "${ds.tableName}"');
        }
      }
    }
  }

  /// Inserts a single row, automatically adding a `_createdAt` timestamp.
  Future<int> insert(String tableName, Map<String, dynamic> data) async {
    final db = _db!;
    final row = Map<String, dynamic>.from(data);
    row['_createdAt'] = DateTime.now().toIso8601String();
    final id = await db.insert(tableName, row);
    _log('INSERT into "$tableName": $data → id=$id');
    return id;
  }

  /// Updates rows where [matchField] equals [matchValue] with the given [data].
  ///
  /// ODS Spec: The "update" action finds the row where a specific field
  /// matches and updates it with new values. Returns the number of rows
  /// affected (typically 1, or 0 if no match was found).
  Future<int> update(
    String tableName,
    Map<String, dynamic> data,
    String matchField,
    String matchValue,
  ) async {
    final db = _db!;
    final row = Map<String, dynamic>.from(data);
    // Remove the match field from the update data — it's the WHERE clause,
    // not a value to change.
    row.remove(matchField);
    final count = await db.update(
      tableName,
      row,
      where: '"$matchField" = ?',
      whereArgs: [matchValue],
    );
    _log('UPDATE "$tableName" SET $row WHERE $matchField=$matchValue → $count rows');
    return count;
  }

  /// Deletes rows where [matchField] equals [matchValue].
  ///
  /// ODS Spec: The "delete" row action removes a record identified by a key
  /// field. Returns the number of rows deleted (typically 1, or 0 if no match).
  Future<int> delete(
    String tableName,
    String matchField,
    String matchValue,
  ) async {
    final db = _db!;
    final count = await db.delete(
      tableName,
      where: '"$matchField" = ?',
      whereArgs: [matchValue],
    );
    _log('DELETE from "$tableName" WHERE $matchField=$matchValue → $count rows');
    return count;
  }

  /// Returns all rows from a table, ordered by most recent first.
  Future<List<Map<String, dynamic>>> query(String tableName) async {
    final db = _db!;
    final rows = await db.query(tableName, orderBy: '_id DESC');
    _log('SELECT from "$tableName": ${rows.length} rows');
    return rows;
  }

  /// Queries a table with an optional WHERE filter, returning all matching rows.
  ///
  /// Used by the record cursor to load a filtered dataset (e.g., all questions
  /// for a specific quiz). Results are ordered by `_id ASC` for stable ordering.
  Future<List<Map<String, dynamic>>> queryWithFilter(
    String tableName,
    Map<String, String> filter,
  ) async {
    final db = _db!;

    final whereClauses = <String>[];
    final whereArgs = <String>[];
    for (final entry in filter.entries) {
      whereClauses.add('"${entry.key}" = ?');
      whereArgs.add(entry.value);
    }

    final rows = await db.query(
      tableName,
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      orderBy: '_id ASC',
    );

    _log('SELECT FILTERED from "$tableName" WHERE $filter → ${rows.length} rows');
    return rows;
  }

  /// Returns the number of rows in a table, or 0 if the table doesn't exist.
  Future<int> getRowCount(String tableName) async {
    final db = _db!;
    try {
      final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM "$tableName"');
      return result.first['cnt'] as int;
    } catch (_) {
      return 0;
    }
  }

  /// Lists all user-created tables (excludes SQLite internal tables).
  /// Used by the debug panel's data explorer.
  Future<List<String>> listTables() async {
    final db = _db!;
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    return result.map((row) => row['name'] as String).toList();
  }

  /// Returns column metadata for a table. Used by the debug panel.
  Future<List<Map<String, dynamic>>> getTableInfo(String tableName) async {
    final db = _db!;
    return await db.rawQuery('PRAGMA table_info("$tableName")');
  }

  // ---------------------------------------------------------------------------
  // App settings storage — uses a special _ods_settings key-value table
  // ---------------------------------------------------------------------------

  /// Ensures the internal settings table exists.
  Future<void> _ensureSettingsTable() async {
    final db = _db!;
    if (_knownTables.contains('_ods_settings')) return;

    final existing = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='_ods_settings'",
    );
    if (existing.isEmpty) {
      await db.execute(
        'CREATE TABLE "_ods_settings" (key TEXT PRIMARY KEY, value TEXT)',
      );
      _log('Created internal settings table');
    }
    _knownTables.add('_ods_settings');
  }

  /// Gets a single app setting value, or null if not set.
  Future<String?> getAppSetting(String key) async {
    await _ensureSettingsTable();
    final db = _db!;
    final rows = await db.query(
      '_ods_settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  /// Sets a single app setting value (upsert).
  Future<void> setAppSetting(String key, String value) async {
    await _ensureSettingsTable();
    final db = _db!;
    await db.rawInsert(
      'INSERT OR REPLACE INTO "_ods_settings" (key, value) VALUES (?, ?)',
      [key, value],
    );
    _log('Setting "$key" = "$value"');
  }

  /// Gets all app settings as a map.
  Future<Map<String, String>> getAllAppSettings() async {
    if (_db == null) return {};
    await _ensureSettingsTable();
    final db = _db!;
    final rows = await db.query('_ods_settings');
    return {for (final row in rows) row['key'] as String: row['value'] as String};
  }

  /// Exports all user data tables as a map of table name → list of row maps.
  /// Internal tables (prefixed with `_ods_`) are excluded.
  /// Returns an empty map if the database is not open.
  Future<Map<String, List<Map<String, dynamic>>>> exportAllData() async {
    if (_db == null) return {};
    final db = _db!;
    final tables = await listTables();
    final result = <String, List<Map<String, dynamic>>>{};
    for (final table in tables) {
      if (table.startsWith('_ods_')) continue;
      final rows = await db.query(table, orderBy: '_id ASC');
      result[table] = rows;
    }
    _log('Exported ${result.length} tables');
    return result;
  }

  /// Imports data from a backup, replacing all existing user data.
  /// Each key in [tables] is a table name, each value is a list of row maps.
  /// Internal tables (prefixed with `_ods_`) are skipped.
  Future<void> importAllData(Map<String, List<Map<String, dynamic>>> tables) async {
    final db = _db!;

    for (final entry in tables.entries) {
      final tableName = entry.key;
      if (tableName.startsWith('_ods_')) continue;

      // Clear existing data.
      try {
        await db.delete(tableName);
      } catch (_) {
        // Table may not exist yet — will be created on first insert.
      }

      // Insert rows, recreating the table schema from column names if needed.
      for (final row in entry.value) {
        // Strip _id so SQLite auto-generates new IDs.
        final cleanRow = Map<String, dynamic>.from(row)..remove('_id');

        // Ensure table exists with all columns from this row.
        if (!_knownTables.contains(tableName)) {
          final cols = cleanRow.keys
              .where((k) => k != '_createdAt')
              .map((k) => OdsFieldDefinition(name: k, type: 'text'))
              .toList();
          await ensureTable(tableName, cols);
        }

        await db.insert(tableName, cleanRow);
      }
    }

    _log('Imported ${tables.length} tables');
  }

  /// Appends rows to a specific table without clearing existing data.
  /// Ensures the table exists and has all necessary columns before inserting.
  /// Returns the number of rows imported.
  Future<int> importTableRows(
      String tableName, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return 0;

    // Ensure table exists with columns from the first row.
    if (!_knownTables.contains(tableName)) {
      final cols = rows.first.keys
          .where((k) => k != '_id' && k != '_createdAt')
          .map((k) => OdsFieldDefinition(name: k, type: 'text'))
          .toList();
      await ensureTable(tableName, cols);
    }

    int count = 0;
    for (final row in rows) {
      final cleanRow = Map<String, dynamic>.from(row)
        ..remove('_id')
        ..putIfAbsent('_createdAt', () => DateTime.now().toIso8601String());
      await _db!.insert(tableName, cleanRow);
      count++;
    }

    _log('Imported $count rows into "$tableName"');
    return count;
  }

  /// Closes the database connection. Called on app reset and dispose.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

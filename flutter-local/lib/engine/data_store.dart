import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/ods_data_source.dart';
import '../models/ods_field_definition.dart';
import 'log_service.dart';
import 'settings_store.dart';

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
/// Generates a 15-character random alphanumeric string matching PocketBase's
/// ID format, enabling portable data between Flutter and React.
String _generateId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rng = math.Random.secure();
  return String.fromCharCodes(
    List.generate(15, (_) => chars.codeUnitAt(rng.nextInt(chars.length))),
  );
}

final _validFieldName = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');
const _reservedNames = {'__proto__', 'constructor', 'prototype'};
const _frameworkFields = {'_id', '_createdAt'};
const _maxImportRows = 100000;

bool _isValidTableName(String name) {
  return RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(name) &&
      !_reservedNames.contains(name);
}

Map<String, dynamic> _sanitizeRow(Map<String, dynamic> row) {
  return Map.fromEntries(
    row.entries.where((e) =>
        _frameworkFields.contains(e.key) ||
        (_validFieldName.hasMatch(e.key) && !_reservedNames.contains(e.key))),
  );
}

void _validateFieldName(String name) {
  if (_frameworkFields.contains(name)) return;
  if (!_validFieldName.hasMatch(name)) {
    throw ArgumentError('Invalid field name: "$name"');
  }
  if (_reservedNames.contains(name)) {
    throw ArgumentError('Reserved field name: "$name"');
  }
}

class DataStore {
  Database? _db;

  /// Cache of tables we've already confirmed exist in this session,
  /// avoiding repeated sqlite_master queries.
  final Set<String> _knownTables = {};

  /// Opens (or creates) the SQLite database for the given app.
  ///
  /// On desktop platforms (Windows, macOS, Linux), initializes the FFI-based
  /// SQLite driver since the default mobile driver is not available.
  ///
  /// If [storageFolder] is provided, the database is placed there instead of
  /// the default ODS data directory.
  Future<void> initialize(String appName, {String? storageFolder}) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dir = await getOdsDirectory(customPath: storageFolder);
    // Sanitize the app name to produce a safe filename.
    final safeAppName = appName.replaceAll(RegExp(r'[^\w]'), '_').toLowerCase();
    final dbPath = p.join(dir.path, 'ods_$safeAppName.db');

    // Clear stale table cache from any previously loaded app.
    _knownTables.clear();

    _db = await databaseFactory.openDatabase(dbPath);
    logInfo('DataStore', 'Database opened at $dbPath');
  }

  /// Creates a table if it doesn't exist, or adds any missing columns.
  ///
  /// This is the core of ODS's "auto-schema" capability. Called both during
  /// data source setup (when explicit fields are declared) and on first form
  /// submit (when the form's fields define the schema implicitly).
  Future<void> ensureTable(String tableName, List<OdsFieldDefinition> fields) async {
    final db = _db!;

    // Validate all field names before touching the database.
    for (final f in fields) {
      _validateFieldName(f.name);
    }

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
      logDebug('DataStore', 'Table "$tableName" already exists, ensured columns');
      return;
    }

    // Create the table with all declared fields plus framework columns.
    final columnDefs = fields.map((f) => '"${f.name}" TEXT').join(', ');
    final sql =
        'CREATE TABLE "$tableName" (_id TEXT PRIMARY KEY, $columnDefs, _createdAt TEXT)';
    await db.execute(sql);
    _knownTables.add(tableName);
    logInfo('DataStore', 'Created table "$tableName" with fields: ${fields.map((f) => f.name).join(', ')}');
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
        logInfo('DataStore', 'Added column "${field.name}" to table "$tableName"');
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
          logInfo('DataStore', 'Seeded ${ds.seedData!.length} rows into "${ds.tableName}"');
        }
      }
    }
  }

  /// Inserts a single row, automatically adding a `_createdAt` timestamp
  /// and generating a PocketBase-style 15-character string ID.
  Future<String> insert(String tableName, Map<String, dynamic> data) async {
    final db = _db!;
    final row = Map<String, dynamic>.from(data);
    final id = _generateId();
    row['_id'] = id;
    row['_createdAt'] = DateTime.now().toIso8601String();
    await db.insert(tableName, row);
    logDebug('DataStore', 'INSERT into "$tableName": $data → id=$id');
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
    _validateFieldName(matchField);
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
    logDebug('DataStore', 'UPDATE "$tableName" SET $row WHERE $matchField=$matchValue → $count rows');
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
    _validateFieldName(matchField);
    final db = _db!;
    final count = await db.delete(
      tableName,
      where: '"$matchField" = ?',
      whereArgs: [matchValue],
    );
    logDebug('DataStore', 'DELETE from "$tableName" WHERE $matchField=$matchValue → $count rows');
    return count;
  }

  /// Returns all rows from a table, ordered by most recent first.
  ///
  /// Falls back to no ORDER BY if the table lacks an `_id` column (e.g.,
  /// `_ods_settings` uses `key TEXT PRIMARY KEY` instead).
  Future<List<Map<String, dynamic>>> query(String tableName) async {
    final db = _db!;
    final hasId = await _tableHasColumn(tableName, '_id');
    final rows = await db.query(tableName, orderBy: hasId ? '_id DESC' : null);
    logDebug('DataStore', 'SELECT from "$tableName": ${rows.length} rows');
    return rows;
  }

  /// Checks whether a table has a specific column.
  Future<bool> _tableHasColumn(String tableName, String column) async {
    final db = _db!;
    final info = await db.rawQuery('PRAGMA table_info("$tableName")');
    return info.any((row) => row['name'] == column);
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
      _validateFieldName(entry.key);
      whereClauses.add('"${entry.key}" = ?');
      whereArgs.add(entry.value);
    }

    final rows = await db.query(
      tableName,
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      orderBy: '_id ASC',
    );

    logDebug('DataStore', 'SELECT FILTERED from "$tableName" WHERE $filter → ${rows.length} rows');
    return rows;
  }

  /// Queries a table with ownership filtering applied.
  /// When [ownerField] is set and [ownerId] is provided, adds a WHERE clause.
  /// When [isAdmin] is true and admin override is allowed, skips the filter.
  Future<List<Map<String, dynamic>>> queryWithOwnership(
    String tableName, {
    String? ownerField,
    String? ownerId,
    bool isAdmin = false,
    bool adminOverride = true,
  }) async {
    final db = _db!;
    String? where;
    List<String>? whereArgs;

    if (ownerField != null && ownerId != null && !(isAdmin && adminOverride)) {
      _validateFieldName(ownerField);
      where = '"$ownerField" = ?';
      whereArgs = [ownerId];
    }

    final rows = await db.query(
      tableName,
      where: where,
      whereArgs: whereArgs,
      orderBy: '_id DESC',
    );
    logDebug('DataStore', 'SELECT from "$tableName"${where != null ? ' WHERE $ownerField=$ownerId' : ''}: ${rows.length} rows');
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
      logInfo('DataStore', 'Created internal settings table');
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
    logDebug('DataStore', 'Setting "$key" = "$value"');
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
    logInfo('DataStore', 'Exported ${result.length} tables');
    return result;
  }

  /// Imports data from a backup, replacing all existing user data.
  /// Each key in [tables] is a table name, each value is a list of row maps.
  /// Internal tables (prefixed with `_ods_`) are skipped.
  Future<void> importAllData(Map<String, List<Map<String, dynamic>>> tables) async {
    final db = _db!;

    // Validate total row count before importing anything.
    int totalRows = 0;
    for (final entry in tables.entries) {
      if (entry.key.startsWith('_ods_')) continue;
      totalRows += entry.value.length;
    }
    if (totalRows > _maxImportRows) {
      throw ArgumentError(
          'Import exceeds maximum of $_maxImportRows rows (got $totalRows)');
    }

    for (final entry in tables.entries) {
      final tableName = entry.key;
      if (tableName.startsWith('_ods_')) continue;

      // Validate table name.
      if (!_isValidTableName(tableName)) {
        logWarn('DataStore', 'Skipping invalid table name: "$tableName"');
        continue;
      }

      // Clear existing data.
      try {
        await db.delete(tableName);
      } catch (_) {
        // Table may not exist yet — will be created on first insert.
      }

      // Insert rows, recreating the table schema from column names if needed.
      for (final row in entry.value) {
        // Sanitize field names and strip _id so new IDs are generated.
        final cleanRow = _sanitizeRow(row)..remove('_id');

        // Ensure table exists with all columns from this row.
        if (!_knownTables.contains(tableName)) {
          final cols = cleanRow.keys
              .where((k) => k != '_createdAt')
              .map((k) => OdsFieldDefinition(name: k, type: 'text'))
              .toList();
          await ensureTable(tableName, cols);
        }

        cleanRow['_id'] = _generateId();
        await db.insert(tableName, cleanRow);
      }
    }

    logInfo('DataStore', 'Imported ${tables.length} tables');
  }

  /// Appends rows to a specific table without clearing existing data.
  /// Ensures the table exists and has all necessary columns before inserting.
  /// Returns the number of rows imported.
  Future<int> importTableRows(
      String tableName, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return 0;

    // Validate table name.
    if (!_isValidTableName(tableName)) {
      throw ArgumentError('Invalid table name: "$tableName"');
    }

    // Enforce row count limit.
    if (rows.length > _maxImportRows) {
      throw ArgumentError(
          'Import exceeds maximum of $_maxImportRows rows (got ${rows.length})');
    }

    // Ensure table exists with columns from the first sanitized row.
    final firstSanitized = _sanitizeRow(rows.first);
    if (!_knownTables.contains(tableName)) {
      final cols = firstSanitized.keys
          .where((k) => k != '_id' && k != '_createdAt')
          .map((k) => OdsFieldDefinition(name: k, type: 'text'))
          .toList();
      await ensureTable(tableName, cols);
    }

    int count = 0;
    for (final row in rows) {
      final cleanRow = _sanitizeRow(row)
        ..remove('_id')
        ..putIfAbsent('_createdAt', () => DateTime.now().toIso8601String());
      cleanRow['_id'] = _generateId();
      await _db!.insert(tableName, cleanRow);
      count++;
    }

    logInfo('DataStore', 'Imported $count rows into "$tableName"');
    return count;
  }

  // ---------------------------------------------------------------------------
  // Auth tables — framework-managed user/role storage for multi-user mode
  // ---------------------------------------------------------------------------

  /// Creates the internal auth tables if they don't exist.
  /// Called during engine init when auth.multiUser is true.
  Future<void> ensureAuthTables() async {
    final db = _db!;

    if (!_knownTables.contains('_ods_users')) {
      final existing = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='_ods_users'",
      );
      if (existing.isEmpty) {
        await db.execute('''
          CREATE TABLE "_ods_users" (
            _id TEXT PRIMARY KEY,
            email TEXT UNIQUE NOT NULL,
            username TEXT,
            password_hash TEXT NOT NULL,
            salt TEXT NOT NULL,
            display_name TEXT,
            _createdAt TEXT
          )
        ''');
        logInfo('DataStore', 'Created auth table "_ods_users"');
      }
      _knownTables.add('_ods_users');
    }

    if (!_knownTables.contains('_ods_user_roles')) {
      final existing = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='_ods_user_roles'",
      );
      if (existing.isEmpty) {
        await db.execute('''
          CREATE TABLE "_ods_user_roles" (
            _id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            role TEXT NOT NULL,
            _createdAt TEXT,
            UNIQUE(user_id, role)
          )
        ''');
        logInfo('DataStore', 'Created auth table "_ods_user_roles"');
      }
      _knownTables.add('_ods_user_roles');
    }
  }

  /// Creates a new user and returns their ID.
  Future<String> createUser({
    required String email,
    required String passwordHash,
    required String salt,
    String? username,
    String? displayName,
  }) async {
    final db = _db!;
    final id = _generateId();
    await db.insert('_ods_users', {
      '_id': id,
      'email': email,
      'username': username ?? email,
      'password_hash': passwordHash,
      'salt': salt,
      'display_name': displayName ?? username ?? email,
      '_createdAt': DateTime.now().toIso8601String(),
    });
    logInfo('DataStore', 'Created user "$email" (id=$id)');
    return id;
  }

  /// Looks up a user by email. Returns null if not found.
  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    final db = _db!;
    final rows = await db.query(
      '_ods_users',
      where: 'email = ?',
      whereArgs: [email],
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Returns all roles for a given user ID.
  Future<List<String>> getUserRoles(String userId) async {
    final db = _db!;
    final rows = await db.query(
      '_ods_user_roles',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return rows.map((r) => r['role'] as String).toList();
  }

  /// Assigns a role to a user. Silently ignores duplicates.
  Future<void> assignRole(String userId, String role) async {
    final db = _db!;
    try {
      await db.insert('_ods_user_roles', {
        '_id': _generateId(),
        'user_id': userId,
        'role': role,
        '_createdAt': DateTime.now().toIso8601String(),
      });
      logDebug('DataStore', 'Assigned role "$role" to user $userId');
    } catch (_) {
      // UNIQUE constraint — role already assigned, ignore.
    }
  }

  /// Removes a role from a user.
  Future<void> removeRole(String userId, String role) async {
    final db = _db!;
    await db.delete(
      '_ods_user_roles',
      where: 'user_id = ? AND role = ?',
      whereArgs: [userId, role],
    );
    logDebug('DataStore', 'Removed role "$role" from user $userId');
  }

  /// Returns all users with their roles.
  Future<List<Map<String, dynamic>>> listUsers() async {
    final db = _db!;
    final users = await db.query('_ods_users', orderBy: '_id ASC');
    final result = <Map<String, dynamic>>[];
    for (final user in users) {
      final userId = user['_id'] as String;
      final roles = await getUserRoles(userId);
      result.add({...user, 'roles': roles});
    }
    return result;
  }

  /// Deletes a user and all their role assignments.
  Future<void> deleteUser(String userId) async {
    final db = _db!;
    await db.delete('_ods_user_roles', where: 'user_id = ?', whereArgs: [userId]);
    await db.delete('_ods_users', where: '_id = ?', whereArgs: [userId]);
    logInfo('DataStore', 'Deleted user $userId');
  }

  /// Updates a user's password hash and salt.
  Future<void> updateUserPassword(String userId, String passwordHash, String salt) async {
    final db = _db!;
    await db.update(
      '_ods_users',
      {'password_hash': passwordHash, 'salt': salt},
      where: '_id = ?',
      whereArgs: [userId],
    );
    logInfo('DataStore', 'Updated password for user $userId');
  }

  /// Updates a user's display name.
  Future<void> updateUserDisplayName(String userId, String displayName) async {
    final db = _db!;
    await db.update(
      '_ods_users',
      {'display_name': displayName},
      where: '_id = ?',
      whereArgs: [userId],
    );
    logInfo('DataStore', 'Updated display name for user $userId');
  }

  /// Checks whether any user with the 'admin' role exists.
  Future<bool> hasAdminUser() async {
    final db = _db!;
    final rows = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM _ods_user_roles WHERE role = 'admin'",
    );
    return (rows.first['cnt'] as int) > 0;
  }

  /// Closes the database connection. Called on app reset and dispose.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

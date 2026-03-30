import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'password_hasher.dart';

/// Framework-level authentication service with its own SQLite database.
///
/// Manages users across all apps (not per-app). When multi-user mode is
/// enabled, this service handles login, user management, and sessions
/// independently of any loaded app's DataStore.
class FrameworkAuthService extends ChangeNotifier {
  Database? _db;
  bool _isAdminSetUp = false;
  bool _isInitialized = false;

  // Session state
  int? _currentUserId;
  String? _currentUsername;
  String? _currentDisplayName;
  List<String> _currentRoles = [];

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isAdminSetUp => _isAdminSetUp;
  bool get isLoggedIn => _currentUserId != null;
  bool get isGuest => !isLoggedIn;
  bool get isAdmin => _currentRoles.contains('admin');
  int? get currentUserId => _currentUserId;
  String get currentUsername => _currentUsername ?? 'guest';
  String get currentDisplayName => _currentDisplayName ?? 'Guest';
  List<String> get currentRoles => isGuest ? const ['guest'] : _currentRoles;

  /// Initialize: open the framework auth database and check if admin exists.
  Future<void> initialize() async {
    if (_isInitialized) return;

    sqfliteFfiInit();
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'ods_framework_auth.db');

    _db = await databaseFactoryFfi.openDatabase(dbPath);
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS _ods_fw_users (
        _id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        display_name TEXT,
        _createdAt TEXT
      )
    ''');
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS _ods_fw_user_roles (
        _id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        role TEXT NOT NULL,
        UNIQUE(user_id, role)
      )
    ''');

    // Check if admin exists
    final admins = await _db!.rawQuery('''
      SELECT u._id FROM _ods_fw_users u
      JOIN _ods_fw_user_roles r ON r.user_id = u._id
      WHERE r.role = 'admin'
      LIMIT 1
    ''');
    _isAdminSetUp = admins.isNotEmpty;
    _isInitialized = true;
    notifyListeners();
  }

  /// Create the initial admin account.
  Future<bool> setupAdmin({
    required String username,
    required String password,
    String? displayName,
  }) async {
    final db = _db!;
    final salt = PasswordHasher.generateSalt();
    final hash = PasswordHasher.hash(password, salt);

    try {
      final id = await db.insert('_ods_fw_users', {
        'username': username,
        'password_hash': hash,
        'salt': salt,
        'display_name': displayName ?? username,
        '_createdAt': DateTime.now().toIso8601String(),
      });
      await db.insert('_ods_fw_user_roles', {'user_id': id, 'role': 'admin'});
      await db.insert('_ods_fw_user_roles', {'user_id': id, 'role': 'user'});

      _isAdminSetUp = true;
      // Auto-login
      _currentUserId = id;
      _currentUsername = username;
      _currentDisplayName = displayName ?? username;
      _currentRoles = ['admin', 'user'];
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('FrameworkAuthService: setupAdmin failed: $e');
      return false;
    }
  }

  /// Log in with username and password. Returns true on success.
  Future<bool> login(String username, String password) async {
    final db = _db!;
    final rows = await db.query(
      '_ods_fw_users',
      where: 'username = ?',
      whereArgs: [username],
    );
    if (rows.isEmpty) return false;

    final user = rows.first;
    if (!PasswordHasher.verify(password, user['salt'] as String, user['password_hash'] as String)) {
      return false;
    }

    final userId = user['_id'] as int;
    final roleRows = await db.query(
      '_ods_fw_user_roles',
      where: 'user_id = ?',
      whereArgs: [userId],
    );

    _currentUserId = userId;
    _currentUsername = user['username'] as String;
    _currentDisplayName = user['display_name'] as String? ?? _currentUsername;
    _currentRoles = roleRows.map((r) => r['role'] as String).toList();
    notifyListeners();
    return true;
  }

  /// Log out the current user.
  void logout() {
    _currentUserId = null;
    _currentUsername = null;
    _currentDisplayName = null;
    _currentRoles = [];
    notifyListeners();
  }

  /// Register a new user.
  Future<int?> registerUser({
    required String username,
    required String password,
    required String role,
    String? displayName,
  }) async {
    final db = _db!;
    final salt = PasswordHasher.generateSalt();
    final hash = PasswordHasher.hash(password, salt);

    try {
      final id = await db.insert('_ods_fw_users', {
        'username': username,
        'password_hash': hash,
        'salt': salt,
        'display_name': displayName ?? username,
        '_createdAt': DateTime.now().toIso8601String(),
      });
      await db.insert('_ods_fw_user_roles', {'user_id': id, 'role': role});
      if (role != 'user' && role != 'guest') {
        await db.insert('_ods_fw_user_roles', {'user_id': id, 'role': 'user'});
      }
      return id;
    } catch (e) {
      debugPrint('FrameworkAuthService: registerUser failed: $e');
      return null;
    }
  }

  /// List all users.
  Future<List<Map<String, dynamic>>> listUsers() async {
    final db = _db!;
    final users = await db.query('_ods_fw_users', orderBy: '_id ASC');
    final result = <Map<String, dynamic>>[];
    for (final user in users) {
      final roles = await db.query(
        '_ods_fw_user_roles',
        where: 'user_id = ?',
        whereArgs: [user['_id']],
      );
      result.add({
        '_id': user['_id'],
        'username': user['username'],
        'display_name': user['display_name'] ?? user['username'],
        'roles': roles.map((r) => r['role'] as String).toList(),
      });
    }
    return result;
  }

  /// Delete a user by ID.
  Future<void> deleteUser(int userId) async {
    final db = _db!;
    await db.delete('_ods_fw_user_roles', where: 'user_id = ?', whereArgs: [userId]);
    await db.delete('_ods_fw_users', where: '_id = ?', whereArgs: [userId]);
  }

  /// Update a user's display name and/or roles.
  Future<bool> updateUser(int userId, {String? displayName, List<String>? roles}) async {
    final db = _db!;
    try {
      if (displayName != null) {
        await db.update(
          '_ods_fw_users',
          {'display_name': displayName},
          where: '_id = ?',
          whereArgs: [userId],
        );
      }
      if (roles != null) {
        await db.delete('_ods_fw_user_roles', where: 'user_id = ?', whereArgs: [userId]);
        for (final role in roles) {
          await db.insert('_ods_fw_user_roles', {'user_id': userId, 'role': role});
        }
      }
      return true;
    } catch (e) {
      debugPrint('FrameworkAuthService: updateUser failed: $e');
      return false;
    }
  }

  /// Change a user's password.
  Future<bool> changePassword(int userId, String newPassword) async {
    final db = _db!;
    final rows = await db.query('_ods_fw_users', where: '_id = ?', whereArgs: [userId]);
    if (rows.isEmpty) return false;
    final salt = rows.first['salt'] as String;
    final hash = PasswordHasher.hash(newPassword, salt);
    await db.update(
      '_ods_fw_users',
      {'password_hash': hash},
      where: '_id = ?',
      whereArgs: [userId],
    );
    return true;
  }

  /// Close the database.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

}

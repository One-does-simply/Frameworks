import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'auth_service.dart' show LoginResult;
import 'log_service.dart';
import 'password_hasher.dart';
import 'settings_store.dart';

/// Generates a 15-character random alphanumeric string matching PocketBase's ID format.
String _generateFwId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rng = math.Random.secure();
  return String.fromCharCodes(
    List.generate(15, (_) => chars.codeUnitAt(rng.nextInt(chars.length))),
  );
}

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
  String? _currentUserId;
  String? _currentUsername;
  String? _currentEmail;
  String? _currentDisplayName;
  List<String> _currentRoles = [];

  // Rate limiting: track failed login attempts per email.
  static const int _maxFailedAttempts = 5;
  static const Duration _lockoutWindow = Duration(minutes: 5);
  final Map<String, List<DateTime>> _failedAttempts = {};

  // Session timeout tracking.
  DateTime? _lastActivity;
  static const Duration _sessionTimeout = Duration(minutes: 30);

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isAdminSetUp => _isAdminSetUp;
  bool get isLoggedIn => _currentUserId != null;
  bool get isGuest => !isLoggedIn;
  bool get isAdmin => _currentRoles.contains('admin');
  String? get currentUserId => _currentUserId;
  String get currentUsername => _currentUsername ?? 'guest';
  String get currentEmail => _currentEmail ?? '';
  String get currentDisplayName => _currentDisplayName ?? 'Guest';
  List<String> get currentRoles => isGuest ? const ['guest'] : _currentRoles;

  /// Initialize: open the framework auth database and check if admin exists.
  ///
  /// If [storageFolder] is provided, the database is placed there instead of
  /// the default ODS data directory.
  Future<void> initialize({String? storageFolder}) async {
    if (_isInitialized) return;

    sqfliteFfiInit();
    final dir = await getOdsDirectory(customPath: storageFolder);
    final dbPath = p.join(dir.path, 'ods_framework_auth.db');

    _db = await databaseFactoryFfi.openDatabase(dbPath);
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS _ods_fw_users (
        _id TEXT PRIMARY KEY,
        email TEXT UNIQUE NOT NULL,
        username TEXT,
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        display_name TEXT,
        _createdAt TEXT
      )
    ''');
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS _ods_fw_user_roles (
        _id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
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
    required String email,
    required String password,
    String? username,
    String? displayName,
  }) async {
    final db = _db!;
    final salt = PasswordHasher.generateSalt();
    final hash = PasswordHasher.hash(password, salt);

    try {
      final id = _generateFwId();
      await db.insert('_ods_fw_users', {
        '_id': id,
        'email': email,
        'username': username ?? email,
        'password_hash': hash,
        'salt': salt,
        'display_name': (displayName != null && displayName.trim().isNotEmpty)
            ? displayName.trim()
            : (username?.trim().isNotEmpty == true ? username!.trim() : email.split('@').first),
        '_createdAt': DateTime.now().toIso8601String(),
      });
      await db.insert('_ods_fw_user_roles', {'_id': _generateFwId(), 'user_id': id, 'role': 'admin'});
      await db.insert('_ods_fw_user_roles', {'_id': _generateFwId(), 'user_id': id, 'role': 'user'});

      _isAdminSetUp = true;
      // Auto-login
      _currentUserId = id;
      _currentUsername = username ?? email;
      _currentEmail = email;
      _currentDisplayName = (displayName != null && displayName.trim().isNotEmpty)
          ? displayName.trim()
          : (username?.trim().isNotEmpty == true ? username!.trim() : email.split('@').first);
      _currentRoles = ['admin', 'user'];
      _lastActivity = DateTime.now();
      logInfo('FrameworkAuthService', '[SECURITY] admin_setup: $email (id=$id)');
      notifyListeners();
      return true;
    } catch (e) {
      logError('FrameworkAuthService', '[SECURITY] admin_setup_failed', e);
      return false;
    }
  }

  /// Checks whether the given email is currently rate-limited.
  int _checkRateLimit(String email) {
    final key = email.toLowerCase();
    final attempts = _failedAttempts[key];
    if (attempts == null) return 0;
    final cutoff = DateTime.now().subtract(_lockoutWindow);
    attempts.removeWhere((t) => t.isBefore(cutoff));
    if (attempts.length >= _maxFailedAttempts) {
      final unlockTime = attempts.first.add(_lockoutWindow);
      final remaining = unlockTime.difference(DateTime.now()).inMinutes + 1;
      return remaining > 0 ? remaining : 0;
    }
    return 0;
  }

  void _recordFailedAttempt(String email) {
    _failedAttempts.putIfAbsent(email.toLowerCase(), () => []).add(DateTime.now());
  }

  void _clearFailedAttempts(String email) {
    _failedAttempts.remove(email.toLowerCase());
  }

  /// Checks whether the current session has timed out due to inactivity.
  bool checkSessionTimeout() {
    if (!isLoggedIn || _lastActivity == null) return false;
    return DateTime.now().difference(_lastActivity!) > _sessionTimeout;
  }

  /// Records user activity to reset the session timeout timer.
  void recordActivity() {
    if (isLoggedIn) {
      _lastActivity = DateTime.now();
    }
  }

  /// Log in with email and password. Returns a [LoginResult].
  Future<LoginResult> login(String email, String password) async {
    // Rate limit check.
    final lockoutMinutes = _checkRateLimit(email);
    if (lockoutMinutes > 0) {
      logWarn('FrameworkAuthService', '[SECURITY] login_rate_limited: $email');
      return LoginResult(
        success: false,
        error: 'Too many failed attempts. Try again in $lockoutMinutes minute${lockoutMinutes == 1 ? '' : 's'}.',
      );
    }

    final db = _db!;
    final rows = await db.query(
      '_ods_fw_users',
      where: 'email = ?',
      whereArgs: [email],
    );
    if (rows.isEmpty) {
      _recordFailedAttempt(email);
      logInfo('FrameworkAuthService', '[SECURITY] login_failed: $email (user not found)');
      return const LoginResult(success: false);
    }

    final user = rows.first;
    if (!PasswordHasher.verify(password, user['salt'] as String, user['password_hash'] as String)) {
      _recordFailedAttempt(email);
      logInfo('FrameworkAuthService', '[SECURITY] login_failed: $email (bad password)');
      return const LoginResult(success: false);
    }

    _clearFailedAttempts(email);
    final userId = user['_id'] as String;
    final roleRows = await db.query(
      '_ods_fw_user_roles',
      where: 'user_id = ?',
      whereArgs: [userId],
    );

    _currentUserId = userId;
    _currentUsername = user['username'] as String? ?? email;
    _currentEmail = user['email'] as String? ?? email;
    _currentDisplayName = user['display_name'] as String? ?? _currentUsername;
    _currentRoles = roleRows.map((r) => r['role'] as String).toList();
    _lastActivity = DateTime.now();
    logInfo('FrameworkAuthService', '[SECURITY] login_success: $email');
    notifyListeners();
    return const LoginResult(success: true);
  }

  /// Log out the current user.
  void logout() {
    logInfo('FrameworkAuthService', '[SECURITY] logout: ${_currentUsername ?? 'unknown'}');
    _currentUserId = null;
    _currentUsername = null;
    _currentEmail = null;
    _currentDisplayName = null;
    _currentRoles = [];
    _lastActivity = null;
    notifyListeners();
  }

  /// Register a new user.
  Future<String?> registerUser({
    required String email,
    required String password,
    required String role,
    String? username,
    String? displayName,
  }) async {
    final db = _db!;
    final salt = PasswordHasher.generateSalt();
    final hash = PasswordHasher.hash(password, salt);

    try {
      final id = _generateFwId();
      await db.insert('_ods_fw_users', {
        '_id': id,
        'email': email,
        'username': username ?? email,
        'password_hash': hash,
        'salt': salt,
        'display_name': (displayName != null && displayName.trim().isNotEmpty)
            ? displayName.trim()
            : (username?.trim().isNotEmpty == true ? username!.trim() : email.split('@').first),
        '_createdAt': DateTime.now().toIso8601String(),
      });
      await db.insert('_ods_fw_user_roles', {'_id': _generateFwId(), 'user_id': id, 'role': role});
      if (role != 'user' && role != 'guest') {
        await db.insert('_ods_fw_user_roles', {'_id': _generateFwId(), 'user_id': id, 'role': 'user'});
      }
      logInfo('FrameworkAuthService', '[SECURITY] user_created: $email role=$role (id=$id)');
      return id;
    } catch (e) {
      logError('FrameworkAuthService', '[SECURITY] user_creation_failed: $email', e);
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
        'email': user['email'],
        'username': user['username'] ?? user['email'],
        'display_name': user['display_name'] ?? user['username'] ?? user['email'],
        'roles': roles.map((r) => r['role'] as String).toList(),
      });
    }
    return result;
  }

  /// Delete a user by ID.
  Future<void> deleteUser(String userId) async {
    final db = _db!;
    await db.delete('_ods_fw_user_roles', where: 'user_id = ?', whereArgs: [userId]);
    await db.delete('_ods_fw_users', where: '_id = ?', whereArgs: [userId]);
  }

  /// Update a user's display name and/or roles.
  Future<bool> updateUser(String userId, {String? displayName, List<String>? roles}) async {
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
          await db.insert('_ods_fw_user_roles', {'_id': _generateFwId(), 'user_id': userId, 'role': role});
        }
        logInfo('FrameworkAuthService', '[SECURITY] roles_changed: user=$userId roles=$roles');
      }
      return true;
    } catch (e) {
      logError('FrameworkAuthService', 'updateUser failed', e);
      return false;
    }
  }

  /// Change a user's password.
  Future<bool> changePassword(String userId, String newPassword) async {
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

import 'package:flutter/foundation.dart';

import 'data_store.dart';
import 'password_hasher.dart';

/// Manages authentication state and role-based access control for ODS apps.
///
/// ODS Ethos: The framework handles all auth complexity. Builders just add
/// `"roles": ["admin"]` to their spec elements, and AuthService makes it work.
///
/// This service is owned by AppEngine (like DataStore) and provides:
///   - Login/logout session management
///   - Admin setup wizard state
///   - Role-based access checks (the core `hasAccess` method)
///   - User CRUD operations (delegated to DataStore)
class AuthService extends ChangeNotifier {
  final DataStore _dataStore;

  // Session state
  int? _currentUserId;
  String? _currentUsername;
  String? _currentDisplayName;
  List<String> _currentRoles = [];
  bool _isAdminSetUp = false;
  bool _isInitialized = false;

  AuthService(this._dataStore);

  // ---------------------------------------------------------------------------
  // Public getters
  // ---------------------------------------------------------------------------

  bool get isInitialized => _isInitialized;
  bool get isLoggedIn => _currentUserId != null;
  bool get isGuest => _currentUserId == null;
  bool get isAdmin => _currentRoles.contains('admin');
  bool get isAdminSetUp => _isAdminSetUp;

  int? get currentUserId => _currentUserId;
  String get currentUsername => _currentUsername ?? 'guest';
  String get currentDisplayName => _currentDisplayName ?? 'Guest';

  /// Returns the current user's roles. Guests get ['guest'].
  List<String> get currentRoles => isGuest ? const ['guest'] : _currentRoles;

  // ---------------------------------------------------------------------------
  // Core permission check
  // ---------------------------------------------------------------------------

  /// Checks whether the current user has access to an element with the given
  /// role restriction.
  ///
  /// Returns true when:
  ///   - [requiredRoles] is null or empty (no restriction)
  ///   - The current user is an admin (admin bypasses all restrictions)
  ///   - The current user has at least one matching role
  bool hasAccess(List<String>? requiredRoles) {
    if (requiredRoles == null || requiredRoles.isEmpty) return true;
    if (isAdmin) return true;
    return currentRoles.any((r) => requiredRoles.contains(r));
  }

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Initializes the auth service: creates auth tables and checks admin state.
  /// Called by AppEngine.loadSpec() when auth.multiUser is true.
  Future<void> initialize() async {
    await _dataStore.ensureAuthTables();
    _isAdminSetUp = await _dataStore.hasAdminUser();
    _isInitialized = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Authentication operations
  // ---------------------------------------------------------------------------

  /// Attempts to log in with the given credentials.
  /// Returns true on success, false on failure.
  Future<bool> login(String username, String password) async {
    final user = await _dataStore.getUserByUsername(username);
    if (user == null) return false;

    final storedHash = user['password_hash'] as String;
    final salt = user['salt'] as String;

    if (!PasswordHasher.verify(password, salt, storedHash)) return false;

    _currentUserId = user['_id'] as int;
    _currentUsername = user['username'] as String;
    _currentDisplayName = user['display_name'] as String?;
    _currentRoles = await _dataStore.getUserRoles(_currentUserId!);
    notifyListeners();
    return true;
  }

  /// Logs out the current user, reverting to guest state.
  void logout() {
    _currentUserId = null;
    _currentUsername = null;
    _currentDisplayName = null;
    _currentRoles = [];
    notifyListeners();
  }

  /// Creates the initial admin account. Called from the admin setup wizard.
  /// Returns true on success.
  Future<bool> setupAdmin(String username, String password) async {
    try {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hash(password, salt);

      final userId = await _dataStore.createUser(
        username: username,
        passwordHash: hash,
        salt: salt,
        displayName: username,
      );

      await _dataStore.assignRole(userId, 'admin');
      await _dataStore.assignRole(userId, 'user');

      _isAdminSetUp = true;

      // Auto-login as the new admin.
      _currentUserId = userId;
      _currentUsername = username;
      _currentDisplayName = username;
      _currentRoles = ['admin', 'user'];
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('ODS AuthService: Admin setup failed: $e');
      return false;
    }
  }

  /// Registers a new user with the given role.
  /// Returns the user ID on success, null on failure.
  Future<int?> registerUser({
    required String username,
    required String password,
    required String role,
    String? displayName,
  }) async {
    try {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hash(password, salt);

      final userId = await _dataStore.createUser(
        username: username,
        passwordHash: hash,
        salt: salt,
        displayName: displayName ?? username,
      );

      await _dataStore.assignRole(userId, role);
      // All non-guest users also get the 'user' base role.
      if (role != 'user' && role != 'guest') {
        await _dataStore.assignRole(userId, 'user');
      }

      notifyListeners();
      return userId;
    } catch (e) {
      debugPrint('ODS AuthService: Registration failed: $e');
      return null;
    }
  }

  /// Changes the password for a user.
  Future<bool> changePassword(int userId, String newPassword) async {
    try {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hash(newPassword, salt);
      await _dataStore.updateUserPassword(userId, hash, salt);
      return true;
    } catch (e) {
      debugPrint('ODS AuthService: Password change failed: $e');
      return false;
    }
  }

  /// Returns all users with their roles (admin-only operation).
  Future<List<Map<String, dynamic>>> listUsers() async {
    return _dataStore.listUsers();
  }

  /// Deletes a user by ID.
  Future<void> deleteUser(int userId) async {
    await _dataStore.deleteUser(userId);
    notifyListeners();
  }

  /// Assigns a role to a user.
  Future<void> assignRole(int userId, String role) async {
    await _dataStore.assignRole(userId, role);
    // Refresh current user's roles if they were affected.
    if (userId == _currentUserId) {
      _currentRoles = await _dataStore.getUserRoles(userId);
    }
    notifyListeners();
  }

  /// Removes a role from a user.
  Future<void> removeRole(int userId, String role) async {
    await _dataStore.removeRole(userId, role);
    if (userId == _currentUserId) {
      _currentRoles = await _dataStore.getUserRoles(userId);
    }
    notifyListeners();
  }

  /// Resets the auth service to its initial state. Called on app close.
  void reset() {
    _currentUserId = null;
    _currentUsername = null;
    _currentDisplayName = null;
    _currentRoles = [];
    _isAdminSetUp = false;
    _isInitialized = false;
  }
}

import 'package:flutter/foundation.dart';

import 'data_store.dart';
import 'log_service.dart';
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
  String? _currentUserId;
  String? _currentUsername;
  String? _currentEmail;
  String? _currentDisplayName;
  List<String> _currentRoles = [];
  bool _isAdminSetUp = false;
  bool _isInitialized = false;

  // Rate limiting: track failed login attempts per email.
  static const int _maxFailedAttempts = 5;
  static const Duration _lockoutWindow = Duration(minutes: 5);
  final Map<String, List<DateTime>> _failedAttempts = {};

  // Session timeout tracking.
  DateTime? _lastActivity;
  static const Duration _sessionTimeout = Duration(minutes: 30);

  AuthService(this._dataStore);

  /// Inject framework-level auth state so per-app auth checks (hasAccess,
  /// isAdmin, etc.) work without a separate per-app login.
  void injectFrameworkAuth({
    required String username,
    String email = '',
    required String displayName,
    required List<String> roles,
  }) {
    _currentUserId = 'framework'; // Sentinel: signals "logged in" without a real per-app user
    _currentUsername = username.isNotEmpty ? username : 'user';
    _currentEmail = email;
    _currentDisplayName = displayName.isNotEmpty ? displayName : username.isNotEmpty ? username : 'User';
    _currentRoles = roles.isNotEmpty ? roles : const ['user'];
    _isAdminSetUp = true;
    _isInitialized = true;
  }

  // ---------------------------------------------------------------------------
  // Public getters
  // ---------------------------------------------------------------------------

  bool get isInitialized => _isInitialized;
  bool get isLoggedIn => _currentUserId != null;
  bool get isGuest => _currentUserId == null;
  bool get isAdmin =>
      _currentRoles.any((r) => r.toLowerCase() == 'admin');
  bool get isAdminSetUp => _isAdminSetUp;

  String? get currentUserId => _currentUserId;
  String get currentUsername => _currentUsername ?? 'guest';
  String get currentEmail => _currentEmail ?? '';
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
    final normalized = requiredRoles.map((r) => r.toLowerCase()).toList();
    return currentRoles.any((r) => normalized.contains(r.toLowerCase()));
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

  /// Checks whether the given email is currently rate-limited.
  /// Returns the number of minutes remaining if locked out, or 0 if not.
  int _checkRateLimit(String email) {
    final key = email.toLowerCase();
    final attempts = _failedAttempts[key];
    if (attempts == null) return 0;

    // Remove attempts outside the lockout window.
    final cutoff = DateTime.now().subtract(_lockoutWindow);
    attempts.removeWhere((t) => t.isBefore(cutoff));

    if (attempts.length >= _maxFailedAttempts) {
      final oldestRelevant = attempts.first;
      final unlockTime = oldestRelevant.add(_lockoutWindow);
      final remaining = unlockTime.difference(DateTime.now()).inMinutes + 1;
      return remaining > 0 ? remaining : 0;
    }
    return 0;
  }

  /// Records a failed login attempt for rate limiting.
  void _recordFailedAttempt(String email) {
    final key = email.toLowerCase();
    _failedAttempts.putIfAbsent(key, () => []).add(DateTime.now());
  }

  /// Clears failed login attempts after a successful login.
  void _clearFailedAttempts(String email) {
    _failedAttempts.remove(email.toLowerCase());
  }

  /// Attempts to log in with the given credentials.
  /// Returns a [LoginResult] indicating success or the reason for failure.
  Future<LoginResult> login(String email, String password) async {
    // Rate limit check.
    final lockoutMinutes = _checkRateLimit(email);
    if (lockoutMinutes > 0) {
      logWarn('AuthService', '[SECURITY] login_rate_limited: $email');
      return LoginResult(
        success: false,
        error: 'Too many failed attempts. Try again in $lockoutMinutes minute${lockoutMinutes == 1 ? '' : 's'}.',
      );
    }

    final user = await _dataStore.getUserByEmail(email);
    if (user == null) {
      _recordFailedAttempt(email);
      logInfo('AuthService', '[SECURITY] login_failed: $email (user not found)');
      return const LoginResult(success: false);
    }

    final storedHash = user['password_hash'] as String;
    final salt = user['salt'] as String;

    if (!PasswordHasher.verify(password, salt, storedHash)) {
      _recordFailedAttempt(email);
      logInfo('AuthService', '[SECURITY] login_failed: $email (bad password)');
      return const LoginResult(success: false);
    }

    _clearFailedAttempts(email);
    _currentUserId = user['_id'] as String;
    _currentUsername = user['username'] as String? ?? email;
    _currentEmail = user['email'] as String? ?? email;
    _currentDisplayName = user['display_name'] as String?;
    _currentRoles = await _dataStore.getUserRoles(_currentUserId!);
    _lastActivity = DateTime.now();
    logInfo('AuthService', '[SECURITY] login_success: $email');
    notifyListeners();
    return const LoginResult(success: true);
  }

  /// Checks whether the current session has timed out due to inactivity.
  /// Returns true if the session has been idle for more than 30 minutes.
  bool checkSessionTimeout() {
    if (!isLoggedIn || _lastActivity == null) return false;
    return DateTime.now().difference(_lastActivity!) > _sessionTimeout;
  }

  /// Records user activity to reset the session timeout timer.
  /// Call this on meaningful user interactions (navigation, form submission, etc.).
  void recordActivity() {
    if (isLoggedIn) {
      _lastActivity = DateTime.now();
    }
  }

  /// Logs out the current user, reverting to guest state.
  void logout() {
    logInfo('AuthService', '[SECURITY] logout: ${_currentUsername ?? 'unknown'}');
    _currentUserId = null;
    _currentUsername = null;
    _currentEmail = null;
    _currentDisplayName = null;
    _currentRoles = [];
    _lastActivity = null;
    notifyListeners();
  }

  /// Creates the initial admin account. Called from the admin setup wizard.
  /// Returns true on success.
  ///
  /// Pass [displayName] to store a human-readable name separate from the
  /// login email. Defaults to the email's local part when omitted.
  Future<bool> setupAdmin(
    String email,
    String password, {
    String? displayName,
  }) async {
    try {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hash(password, salt);
      final resolvedName = (displayName != null && displayName.trim().isNotEmpty)
          ? displayName.trim()
          : email.split('@').first;

      final userId = await _dataStore.createUser(
        email: email,
        passwordHash: hash,
        salt: salt,
        displayName: resolvedName,
      );

      await _dataStore.assignRole(userId, 'admin');
      await _dataStore.assignRole(userId, 'user');

      _isAdminSetUp = true;

      // Auto-login as the new admin.
      _currentUserId = userId;
      _currentUsername = email;
      _currentEmail = email;
      _currentDisplayName = resolvedName;
      _currentRoles = ['admin', 'user'];
      _lastActivity = DateTime.now();
      logInfo('AuthService', '[SECURITY] admin_setup: $email (id=$userId)');
      notifyListeners();
      return true;
    } catch (e) {
      logError('AuthService', '[SECURITY] admin_setup_failed', e);
      return false;
    }
  }

  /// Registers a new user with the given role.
  /// Returns the user ID on success, null on failure.
  Future<String?> registerUser({
    required String email,
    required String password,
    required String role,
    String? username,
    String? displayName,
  }) async {
    try {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hash(password, salt);

      final userId = await _dataStore.createUser(
        email: email,
        passwordHash: hash,
        salt: salt,
        username: username,
        displayName: displayName ?? username ?? email,
      );

      await _dataStore.assignRole(userId, role);
      // All non-guest users also get the 'user' base role.
      if (role != 'user' && role != 'guest') {
        await _dataStore.assignRole(userId, 'user');
      }

      logInfo('AuthService', '[SECURITY] user_created: $email role=$role (id=$userId)');
      notifyListeners();
      return userId;
    } catch (e) {
      logError('AuthService', '[SECURITY] user_creation_failed: $email', e);
      return null;
    }
  }

  /// Changes the password for a user.
  Future<bool> changePassword(String userId, String newPassword) async {
    try {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hash(newPassword, salt);
      await _dataStore.updateUserPassword(userId, hash, salt);
      return true;
    } catch (e) {
      logError('AuthService', 'Password change failed', e);
      return false;
    }
  }

  /// Returns all users with their roles (admin-only operation).
  Future<List<Map<String, dynamic>>> listUsers() async {
    return _dataStore.listUsers();
  }

  /// Deletes a user by ID.
  Future<void> deleteUser(String userId) async {
    await _dataStore.deleteUser(userId);
    notifyListeners();
  }

  /// Assigns a role to a user.
  Future<void> assignRole(String userId, String role) async {
    await _dataStore.assignRole(userId, role);
    logInfo('AuthService', '[SECURITY] role_assigned: user=$userId role=$role');
    // Refresh current user's roles if they were affected.
    if (userId == _currentUserId) {
      _currentRoles = await _dataStore.getUserRoles(userId);
    }
    notifyListeners();
  }

  /// Removes a role from a user.
  Future<void> removeRole(String userId, String role) async {
    await _dataStore.removeRole(userId, role);
    logInfo('AuthService', '[SECURITY] role_removed: user=$userId role=$role');
    if (userId == _currentUserId) {
      _currentRoles = await _dataStore.getUserRoles(userId);
    }
    notifyListeners();
  }

  /// Resets the auth service to its initial state. Called on app close.
  void reset() {
    _currentUserId = null;
    _currentUsername = null;
    _currentEmail = null;
    _currentDisplayName = null;
    _currentRoles = [];
    _isAdminSetUp = false;
    _isInitialized = false;
    _lastActivity = null;
    _failedAttempts.clear();
  }
}

/// Result of a login attempt.
class LoginResult {
  final bool success;
  final String? error;

  const LoginResult({required this.success, this.error});
}

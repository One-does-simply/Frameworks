import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/engine/auth_service.dart';
import 'package:ods_flutter_local/engine/data_store.dart';
import 'package:ods_flutter_local/engine/log_service.dart';
import 'package:ods_flutter_local/models/ods_field_definition.dart';

/// Fake DataStore used for Batch 3 auth/RBAC tests.
///
/// Unlike Batch 1's fake, this one overrides the auth-related methods
/// (getUserByEmail, getUserRoles, ensureAuthTables, hasAdminUser) so we can
/// drive the full login flow without needing a real SQLite database.
///
/// Tests control behavior via the exposed maps:
///   - [users]     : rows returned by getUserByEmail (keyed by lowercase email)
///   - [userRoles] : role lists returned by getUserRoles (keyed by user id)
class _FakeAuthDataStore extends DataStore {
  final Map<String, Map<String, dynamic>> users = {};
  final Map<String, List<String>> userRoles = {};
  bool adminExists = false;

  // Track which methods were called (for assertions that don't hit real DB).
  int ensureAuthTablesCalls = 0;
  int hasAdminUserCalls = 0;

  @override
  Future<void> ensureTable(
      String tableName, List<OdsFieldDefinition> fields) async {
    // No-op for auth tests.
  }

  @override
  Future<void> ensureAuthTables() async {
    ensureAuthTablesCalls++;
  }

  @override
  Future<bool> hasAdminUser() async {
    hasAdminUserCalls++;
    return adminExists;
  }

  @override
  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    return users[email.toLowerCase()];
  }

  @override
  Future<List<String>> getUserRoles(String userId) async {
    return userRoles[userId] ?? const [];
  }
}

/// Counts entries in the LogService buffer containing a given substring.
/// Works without LogService.initialize(): log() always appends to _buffer and
/// only tries to flush to a file if _logFile is non-null, which it is not in
/// unit tests. getLogs() drains the buffer into _stored so we can inspect it.
int _countLogsContaining(String marker) {
  final logs = LogService.instance.getLogs();
  return logs.where((e) => e.message.contains(marker)).length;
}

void main() {
  group('Batch 3: Auth & RBAC integration tests', () {
    // -----------------------------------------------------------------------
    // B3-1: hasAccess Role Matching
    // -----------------------------------------------------------------------
    group('B3-1: hasAccess role matching', () {
      test('editor user matches [editor] but not [admin]', () {
        final auth = AuthService(_FakeAuthDataStore());
        auth.injectFrameworkAuth(
          username: 'e',
          displayName: 'Editor',
          roles: ['editor'],
        );
        expect(auth.hasAccess(['editor']), isTrue);
        expect(auth.hasAccess(['admin']), isFalse);
      });

      test('hasAccess(null) returns true (no requirement)', () {
        final auth = AuthService(_FakeAuthDataStore());
        auth.injectFrameworkAuth(
          username: 'u',
          displayName: 'U',
          roles: ['user'],
        );
        expect(auth.hasAccess(null), isTrue);
      });

      test('hasAccess([]) returns true (empty requirement)', () {
        final auth = AuthService(_FakeAuthDataStore());
        auth.injectFrameworkAuth(
          username: 'u',
          displayName: 'U',
          roles: ['user'],
        );
        expect(auth.hasAccess([]), isTrue);
      });

      test('admin role bypasses all specific checks', () {
        final auth = AuthService(_FakeAuthDataStore());
        auth.injectFrameworkAuth(
          username: 'a',
          displayName: 'A',
          roles: ['admin'],
        );
        expect(auth.hasAccess(['editor']), isTrue);
        expect(auth.hasAccess(['manager']), isTrue);
        expect(auth.hasAccess(['someRoleThatDoesntExist']), isTrue);
        expect(auth.hasAccess(['admin']), isTrue);
      });

      test('empty roles in injectFrameworkAuth falls back to [user]', () {
        final auth = AuthService(_FakeAuthDataStore());
        auth.injectFrameworkAuth(
          username: 'u',
          displayName: 'U',
          roles: [],
        );
        // Implementation: empty -> const ['user']
        expect(auth.currentRoles, ['user']);
        expect(auth.hasAccess(['user']), isTrue);
      });

      test('case insensitivity: Admin role is normalized', () {
        final auth = AuthService(_FakeAuthDataStore());
        auth.injectFrameworkAuth(
          username: 'u',
          displayName: 'U',
          roles: ['Admin'], // Capital A
        );
        // isAdmin is now case-insensitive: 'Admin' counts as admin.
        expect(auth.isAdmin, isTrue);
        // hasAccess comparison is case-insensitive on both sides.
        expect(auth.hasAccess(['admin']), isTrue);
        expect(auth.hasAccess(['Admin']), isTrue);
        expect(auth.hasAccess(['ADMIN']), isTrue);
      });

      test('case insensitivity: user roles vs required roles mix case', () {
        final auth = AuthService(_FakeAuthDataStore());
        auth.injectFrameworkAuth(
          username: 'u',
          displayName: 'U',
          roles: ['Editor'], // Capital E
        );
        // Matching should work regardless of case on either side.
        expect(auth.hasAccess(['editor']), isTrue);
        expect(auth.hasAccess(['EDITOR']), isTrue);
        expect(auth.hasAccess(['Editor']), isTrue);
        expect(auth.hasAccess(['viewer']), isFalse);
      });

      test('user with multiple roles matches any one of them', () {
        final auth = AuthService(_FakeAuthDataStore());
        auth.injectFrameworkAuth(
          username: 'u',
          displayName: 'U',
          roles: ['editor', 'viewer', 'user'],
        );
        expect(auth.hasAccess(['editor']), isTrue);
        expect(auth.hasAccess(['viewer']), isTrue);
        expect(auth.hasAccess(['user']), isTrue);
        expect(auth.hasAccess(['manager']), isFalse);
      });

      test('multiple required roles match when user has any', () {
        final auth = AuthService(_FakeAuthDataStore());
        auth.injectFrameworkAuth(
          username: 'u',
          displayName: 'U',
          roles: ['viewer'],
        );
        // User has viewer; page requires editor OR viewer -> pass
        expect(auth.hasAccess(['editor', 'viewer']), isTrue);
        // Page requires editor OR admin -> fail
        expect(auth.hasAccess(['editor', 'admin']), isFalse);
      });

      test('guest (no login) has access when no roles required', () {
        final auth = AuthService(_FakeAuthDataStore());
        expect(auth.isGuest, isTrue);
        expect(auth.currentRoles, ['guest']);
        expect(auth.hasAccess(null), isTrue);
        expect(auth.hasAccess([]), isTrue);
        // Guest has no access to restricted pages
        expect(auth.hasAccess(['admin']), isFalse);
        expect(auth.hasAccess(['user']), isFalse);
      });

      test('guest matches a page that explicitly requires guest role', () {
        final auth = AuthService(_FakeAuthDataStore());
        // Role 'guest' is the default for unauthenticated users, so a page
        // restricted to ['guest'] should be accessible.
        expect(auth.hasAccess(['guest']), isTrue);
      });
    });

    // -----------------------------------------------------------------------
    // B3-2: Role-Based Page Navigation (AuthService-level proxy)
    // -----------------------------------------------------------------------
    //
    // AppEngine.navigateTo guards pages via authService.hasAccess(page.roles)
    // when isMultiUser is true. Standing up a full AppEngine requires
    // DataStore.initialize + spec parsing, which is heavier than needed for
    // these checks. We test the guard logic directly at the AuthService
    // hasAccess level (the same call the engine makes) and note that the
    // navigation-stack mutation behavior requires AppEngine integration.
    group('B3-2: Role-based page navigation (hasAccess guard logic)', () {
      test('user cannot access admin-only page', () {
        final auth = AuthService(_FakeAuthDataStore());
        auth.injectFrameworkAuth(
          username: 'u',
          displayName: 'U',
          roles: ['user'],
        );
        // Mimics AppEngine.navigateTo's guard: hasAccess(page.roles)
        expect(auth.hasAccess(['admin']), isFalse);
      });

      test('admin can access admin-only page', () {
        final auth = AuthService(_FakeAuthDataStore());
        auth.injectFrameworkAuth(
          username: 'a',
          displayName: 'A',
          roles: ['admin'],
        );
        expect(auth.hasAccess(['admin']), isTrue);
      });

      test('superAdmin can access admin-only page (via admin bypass)', () {
        final auth = AuthService(_FakeAuthDataStore());
        // superAdmin with admin role gets full access.
        auth.injectFrameworkAuth(
          username: 'sa',
          displayName: 'SA',
          roles: ['superAdmin', 'admin'],
        );
        expect(auth.hasAccess(['admin']), isTrue);
      });

      test('superAdmin WITHOUT admin role does not bypass admin-only page', () {
        final auth = AuthService(_FakeAuthDataStore());
        // Note: hasAccess only bypasses when 'admin' is in user's roles —
        // a role literally named 'superAdmin' is not treated as admin.
        auth.injectFrameworkAuth(
          username: 'sa',
          displayName: 'SA',
          roles: ['superAdmin'],
        );
        expect(auth.hasAccess(['admin']), isFalse);
      });

      test('page with no roles is accessible to anyone', () {
        final auth = AuthService(_FakeAuthDataStore());
        auth.injectFrameworkAuth(
          username: 'u',
          displayName: 'U',
          roles: ['user'],
        );
        expect(auth.hasAccess(null), isTrue);
        expect(auth.hasAccess([]), isTrue);
      });

      test('guest cannot access role-restricted page', () {
        final auth = AuthService(_FakeAuthDataStore());
        // No login -> guest.
        expect(auth.hasAccess(['user']), isFalse);
        expect(auth.hasAccess(['admin']), isFalse);
      });

      // NOTE: "multiUser: false disables the guard" is an AppEngine-level
      // behavior (`if (isMultiUser && !hasAccess(roles)) return;`). In single-
      // user mode the guard is bypassed entirely — testing that requires
      // AppEngine.navigateTo + a loaded spec, deferred here.
    });

    // -----------------------------------------------------------------------
    // B3-3: Session Timeout
    // -----------------------------------------------------------------------
    //
    // AuthService.checkSessionTimeout() returns true when the difference
    // between DateTime.now() and _lastActivity exceeds 30 minutes.
    // _lastActivity is a private field; we don't have a test-only setter, so
    // we exercise the API surface only:
    //   - Before login: always returns false
    //   - After injectFrameworkAuth / fresh state: fresh-enough to be false
    //   - After logout: cleared, returns false
    //   - recordActivity while logged-out is a no-op
    // A true "simulate 30 min idle" test would require clock injection.
    group('B3-3: Session timeout', () {
      test('guest (not logged in) checkSessionTimeout returns false', () {
        final auth = AuthService(_FakeAuthDataStore());
        expect(auth.isLoggedIn, isFalse);
        expect(auth.checkSessionTimeout(), isFalse);
      });

      test('injectFrameworkAuth alone does not set _lastActivity, timeout=false',
          () {
        // injectFrameworkAuth sets _currentUserId but doesn't touch
        // _lastActivity. checkSessionTimeout: "if (!isLoggedIn ||
        // _lastActivity == null) return false". So even "logged in via
        // injection" with null activity returns false.
        final auth = AuthService(_FakeAuthDataStore());
        auth.injectFrameworkAuth(
          username: 'u',
          displayName: 'U',
          roles: ['user'],
        );
        expect(auth.isLoggedIn, isTrue);
        expect(auth.checkSessionTimeout(), isFalse);
      });

      test('recordActivity after injectFrameworkAuth -> timeout still false',
          () {
        final auth = AuthService(_FakeAuthDataStore());
        auth.injectFrameworkAuth(
          username: 'u',
          displayName: 'U',
          roles: ['user'],
        );
        auth.recordActivity(); // Sets _lastActivity = now
        expect(auth.checkSessionTimeout(), isFalse);
      });

      test('recordActivity while guest is a no-op (no crash, no timeout)', () {
        final auth = AuthService(_FakeAuthDataStore());
        // Pre-condition: guest
        expect(auth.isLoggedIn, isFalse);
        // Should not throw; and timeout remains false.
        auth.recordActivity();
        expect(auth.checkSessionTimeout(), isFalse);
      });

      test('logout clears session (no timeout triggered after logout)', () {
        final auth = AuthService(_FakeAuthDataStore());
        auth.injectFrameworkAuth(
          username: 'u',
          displayName: 'U',
          roles: ['user'],
        );
        auth.recordActivity();
        auth.logout();
        expect(auth.isLoggedIn, isFalse);
        // Post-logout, checkSessionTimeout must return false (guest path).
        expect(auth.checkSessionTimeout(), isFalse);
      });

      test('successful login sets activity (timeout=false immediately after)',
          () async {
        final ds = _FakeAuthDataStore();
        // Seed a user with known hash+salt.
        // We use the known-good PasswordHasher via AuthService.setupAdmin
        // to create a real entry — but setupAdmin also auto-logs-in, which
        // already exercises the _lastActivity = now assignment. Verify that.
        final auth = AuthService(ds);
        // Note: setupAdmin() calls createUser, which on a Fake we cannot
        // easily support without re-implementing createUser. Instead,
        // simulate a post-login state using injectFrameworkAuth and then
        // manually call recordActivity to emulate the login path's
        // _lastActivity = now behavior.
        auth.injectFrameworkAuth(
          username: 'u',
          displayName: 'U',
          roles: ['user'],
        );
        auth.recordActivity();
        expect(auth.checkSessionTimeout(), isFalse);
      });

      // NOTE: "Simulate 30 min idle -> timeout returns true" requires either
      // a test-only setter for _lastActivity or an injectable clock. Neither
      // is currently available on AuthService. Deferred.
    });

    // -----------------------------------------------------------------------
    // B3-4: Login Rate Limiting
    // -----------------------------------------------------------------------
    //
    // 5 failed logins within 5 minutes lock out the 6th attempt for that
    // email. The rate-limiter is per-email, keyed lowercase, so different
    // emails are independent and case is normalized.
    group('B3-4: Login rate limiting', () {
      test('5 failed logins -> 6th returns rate-limit error', () async {
        final ds = _FakeAuthDataStore(); // no users seeded -> every login fails
        final auth = AuthService(ds);

        for (var i = 0; i < 5; i++) {
          final r = await auth.login('bad@example.com', 'wrong');
          expect(r.success, isFalse, reason: 'Attempt ${i + 1} should fail');
          // The first 5 failures do NOT set an error message — only a
          // locked-out 6th attempt carries "Too many failed attempts".
          expect(r.error, isNull, reason: 'Attempt ${i + 1} should have no error msg');
        }

        final r6 = await auth.login('bad@example.com', 'wrong');
        expect(r6.success, isFalse);
        expect(r6.error, isNotNull);
        expect(r6.error, contains('Too many failed attempts'));
      });

      test('different emails are tracked separately', () async {
        final ds = _FakeAuthDataStore();
        final auth = AuthService(ds);

        // Trip rate limit for emailA (5 fails)
        for (var i = 0; i < 5; i++) {
          await auth.login('a@example.com', 'wrong');
        }
        // emailA is now locked out.
        final ra6 = await auth.login('a@example.com', 'wrong');
        expect(ra6.error, contains('Too many failed attempts'));

        // emailB should still be free — 1 failed attempt, no lockout msg yet.
        final rb1 = await auth.login('b@example.com', 'wrong');
        expect(rb1.success, isFalse);
        expect(rb1.error, isNull);
      });

      test('email case insensitivity: rate limit keys lowercased', () async {
        final ds = _FakeAuthDataStore();
        final auth = AuthService(ds);

        // Alternate capitalizations — should all count against the same key.
        await auth.login('User@Example.com', 'x');
        await auth.login('user@example.com', 'x');
        await auth.login('USER@EXAMPLE.COM', 'x');
        await auth.login('uSer@ExAmple.com', 'x');
        await auth.login('user@Example.COM', 'x');

        // 6th attempt under any casing should be locked out.
        final r = await auth.login('user@example.com', 'x');
        expect(r.error, contains('Too many failed attempts'));
      });

      // NOTE: "Successful login clears rate limit counter" requires a real
      // user row + PasswordHasher.verify to succeed. _FakeAuthDataStore
      // could seed a user with a real salt+hash generated via PasswordHasher,
      // but that pulls in more infra. Deferred.
    });

    // -----------------------------------------------------------------------
    // B3-5: Rate Limit Audit Logging
    // -----------------------------------------------------------------------
    //
    // When rate-limited, AuthService logs a [SECURITY] marker via logWarn.
    // LogService.log() always appends to its in-memory buffer; even without
    // initialize(), getLogs() returns the buffered entries. We read the
    // buffer count before/after to check the audit marker fires.
    group('B3-5: Rate limit audit logging', () {
      test('rate limit triggers [SECURITY] login_rate_limited log entry',
          () async {
        // Baseline: drain anything that was buffered by earlier tests.
        LogService.instance.getLogs();
        final beforeRateLimit =
            _countLogsContaining('[SECURITY] login_rate_limited');

        final auth = AuthService(_FakeAuthDataStore());
        // Trip the limiter and then trigger a locked attempt.
        for (var i = 0; i < 5; i++) {
          await auth.login('sec@example.com', 'x');
        }
        final r6 = await auth.login('sec@example.com', 'x');
        expect(r6.error, contains('Too many failed attempts'));

        final afterRateLimit =
            _countLogsContaining('[SECURITY] login_rate_limited');
        expect(
          afterRateLimit,
          greaterThan(beforeRateLimit),
          reason: 'Rate-limited login must emit [SECURITY] audit log',
        );
      });

      test('failed login (not locked out) emits [SECURITY] login_failed',
          () async {
        LogService.instance.getLogs();
        final before = _countLogsContaining('[SECURITY] login_failed');

        final auth = AuthService(_FakeAuthDataStore());
        await auth.login('miss@example.com', 'x');

        final after = _countLogsContaining('[SECURITY] login_failed');
        expect(after, greaterThan(before));
      });
    });

    // -----------------------------------------------------------------------
    // B3-6: Current Roles Variations
    // -----------------------------------------------------------------------
    //
    // currentRoles getter behavior:
    //   - isGuest -> const ['guest']
    //   - otherwise -> _currentRoles (as injected or loaded from DB)
    //
    // injectFrameworkAuth's role-normalization:
    //   - roles empty -> defaults to const ['user']
    //   - roles non-empty -> used as-is
    group('B3-6: currentRoles variations', () {
      test('guest (no login) returns [guest]', () {
        final auth = AuthService(_FakeAuthDataStore());
        expect(auth.isGuest, isTrue);
        expect(auth.currentRoles, ['guest']);
      });

      test('injectFrameworkAuth with roles returns them verbatim', () {
        final auth = AuthService(_FakeAuthDataStore());
        auth.injectFrameworkAuth(
          username: 'a',
          displayName: 'A',
          roles: ['admin'],
        );
        expect(auth.currentRoles, ['admin']);
      });

      test('injectFrameworkAuth with multiple roles preserves order', () {
        final auth = AuthService(_FakeAuthDataStore());
        auth.injectFrameworkAuth(
          username: 'u',
          displayName: 'U',
          roles: ['editor', 'viewer', 'user'],
        );
        expect(auth.currentRoles, ['editor', 'viewer', 'user']);
      });

      test('injectFrameworkAuth with empty roles defaults to [user]', () {
        final auth = AuthService(_FakeAuthDataStore());
        auth.injectFrameworkAuth(
          username: 'u',
          displayName: 'U',
          roles: [],
        );
        expect(auth.currentRoles, ['user']);
      });

      test('case sensitivity: Admin is preserved literally in currentRoles', () {
        final auth = AuthService(_FakeAuthDataStore());
        auth.injectFrameworkAuth(
          username: 'u',
          displayName: 'U',
          roles: ['Admin'],
        );
        // The stored role preserves the original casing...
        expect(auth.currentRoles, ['Admin']);
        // ...but isAdmin is case-insensitive, so 'Admin' == admin for checks.
        expect(auth.isAdmin, isTrue);
      });

      test('logout reverts currentRoles back to [guest]', () {
        final auth = AuthService(_FakeAuthDataStore());
        auth.injectFrameworkAuth(
          username: 'u',
          displayName: 'U',
          roles: ['admin'],
        );
        expect(auth.currentRoles, ['admin']);
        auth.logout();
        expect(auth.currentRoles, ['guest']);
      });

      test('reset() clears all state back to guest', () {
        final auth = AuthService(_FakeAuthDataStore());
        auth.injectFrameworkAuth(
          username: 'u',
          displayName: 'U',
          roles: ['admin'],
        );
        auth.reset();
        expect(auth.currentRoles, ['guest']);
        expect(auth.isLoggedIn, isFalse);
        expect(auth.isGuest, isTrue);
      });
    });
  });
}

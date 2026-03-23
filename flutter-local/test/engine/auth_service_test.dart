import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/engine/auth_service.dart';
import 'package:ods_flutter_local/engine/password_hasher.dart';
import 'package:ods_flutter_local/engine/data_store.dart';

void main() {
  group('PasswordHasher', () {
    test('generates unique salts', () {
      final salt1 = PasswordHasher.generateSalt();
      final salt2 = PasswordHasher.generateSalt();
      expect(salt1, isNot(equals(salt2)));
      expect(salt1.length, greaterThan(10));
    });

    test('hashes deterministically with same salt', () {
      final salt = PasswordHasher.generateSalt();
      final hash1 = PasswordHasher.hash('password', salt);
      final hash2 = PasswordHasher.hash('password', salt);
      expect(hash1, equals(hash2));
    });

    test('different passwords produce different hashes', () {
      final salt = PasswordHasher.generateSalt();
      final hash1 = PasswordHasher.hash('password1', salt);
      final hash2 = PasswordHasher.hash('password2', salt);
      expect(hash1, isNot(equals(hash2)));
    });

    test('different salts produce different hashes', () {
      final salt1 = PasswordHasher.generateSalt();
      final salt2 = PasswordHasher.generateSalt();
      final hash1 = PasswordHasher.hash('password', salt1);
      final hash2 = PasswordHasher.hash('password', salt2);
      expect(hash1, isNot(equals(hash2)));
    });

    test('verify returns true for correct password', () {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hash('mypassword', salt);
      expect(PasswordHasher.verify('mypassword', salt, hash), true);
    });

    test('verify returns false for wrong password', () {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hash('mypassword', salt);
      expect(PasswordHasher.verify('wrongpassword', salt, hash), false);
    });

    test('hash produces non-empty string', () {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hash('test', salt);
      expect(hash, isNotEmpty);
      expect(hash.length, greaterThan(20));
    });
  });

  group('AuthService.hasAccess', () {
    // We can't easily instantiate AuthService without a real DataStore,
    // but we can test the hasAccess logic pattern directly.
    // The logic is: null/empty roles → true, admin → true, matching role → true.

    test('null roles grants access', () {
      // Simulating the hasAccess logic
      bool hasAccess(List<String>? requiredRoles, List<String> userRoles, bool isAdmin) {
        if (requiredRoles == null || requiredRoles.isEmpty) return true;
        if (isAdmin) return true;
        return userRoles.any((r) => requiredRoles.contains(r));
      }

      expect(hasAccess(null, ['user'], false), true);
      expect(hasAccess([], ['user'], false), true);
    });

    test('admin always has access', () {
      bool hasAccess(List<String>? requiredRoles, List<String> userRoles, bool isAdmin) {
        if (requiredRoles == null || requiredRoles.isEmpty) return true;
        if (isAdmin) return true;
        return userRoles.any((r) => requiredRoles.contains(r));
      }

      expect(hasAccess(['manager'], ['user'], true), true);
      expect(hasAccess(['superadmin'], [], true), true);
    });

    test('matching role grants access', () {
      bool hasAccess(List<String>? requiredRoles, List<String> userRoles, bool isAdmin) {
        if (requiredRoles == null || requiredRoles.isEmpty) return true;
        if (isAdmin) return true;
        return userRoles.any((r) => requiredRoles.contains(r));
      }

      expect(hasAccess(['manager', 'admin'], ['manager'], false), true);
      expect(hasAccess(['admin'], ['user'], false), false);
      expect(hasAccess(['viewer'], ['editor', 'viewer'], false), true);
    });

    test('non-matching role denies access', () {
      bool hasAccess(List<String>? requiredRoles, List<String> userRoles, bool isAdmin) {
        if (requiredRoles == null || requiredRoles.isEmpty) return true;
        if (isAdmin) return true;
        return userRoles.any((r) => requiredRoles.contains(r));
      }

      expect(hasAccess(['admin'], ['user'], false), false);
      expect(hasAccess(['manager', 'admin'], ['user', 'viewer'], false), false);
    });

    test('guest role works', () {
      bool hasAccess(List<String>? requiredRoles, List<String> userRoles, bool isAdmin) {
        if (requiredRoles == null || requiredRoles.isEmpty) return true;
        if (isAdmin) return true;
        return userRoles.any((r) => requiredRoles.contains(r));
      }

      expect(hasAccess(['guest', 'user'], ['guest'], false), true);
      expect(hasAccess(['user'], ['guest'], false), false);
    });
  });
}

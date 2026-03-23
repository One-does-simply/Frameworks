import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/models/ods_app.dart';
import 'package:ods_flutter_local/parser/spec_validator.dart';

void main() {
  final validator = SpecValidator();

  OdsApp _app(Map<String, dynamic> json) => OdsApp.fromJson(json);

  Map<String, dynamic> _minimalApp({Map<String, dynamic>? auth}) => {
        'appName': 'Test',
        'startPage': 'home',
        if (auth != null) 'auth': auth,
        'pages': {
          'home': {'component': 'page', 'title': 'Home', 'content': []},
          'admin': {'component': 'page', 'title': 'Admin', 'content': []},
        },
      };

  group('Auth validation', () {
    test('no auth block produces no auth warnings', () {
      final app = _app(_minimalApp());
      final result = validator.validate(app);
      expect(result.hasErrors, false);
      // No auth-related warnings expected
      final authWarnings = result.warnings
          .where((w) => w.message.contains('auth') || w.message.contains('role') || w.message.contains('multiUser'));
      expect(authWarnings, isEmpty);
    });

    test('multiUserOnly without multiUser warns', () {
      final app = _app(_minimalApp(auth: {
        'multiUser': false,
        'multiUserOnly': true,
      }));
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('multiUserOnly')), true);
    });

    test('custom role duplicating built-in warns', () {
      final app = _app(_minimalApp(auth: {
        'multiUser': true,
        'roles': ['admin', 'custom'],
      }));
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('built-in role "admin"')), true);
    });

    test('unknown defaultRole warns', () {
      final app = _app(_minimalApp(auth: {
        'multiUser': true,
        'defaultRole': 'nonexistent',
      }));
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('defaultRole')), true);
    });

    test('valid custom role does not warn', () {
      final app = _app(_minimalApp(auth: {
        'multiUser': true,
        'roles': ['manager'],
        'defaultRole': 'user',
      }));
      final result = validator.validate(app);
      final roleWarnings = result.warnings
          .where((w) => w.message.contains('defaultRole') || w.message.contains('built-in'));
      expect(roleWarnings, isEmpty);
    });
  });

  group('Role reference validation', () {
    test('menu item with unknown role warns', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'home',
        'auth': {'multiUser': true},
        'menu': [
          {'label': 'Admin', 'mapsTo': 'admin', 'roles': ['superadmin']},
        ],
        'pages': {
          'home': {'component': 'page', 'title': 'Home', 'content': []},
          'admin': {'component': 'page', 'title': 'Admin', 'content': []},
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('superadmin')), true);
    });

    test('page with valid role does not warn', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'home',
        'auth': {'multiUser': true, 'roles': ['manager']},
        'pages': {
          'home': {'component': 'page', 'title': 'Home', 'content': []},
          'admin': {
            'component': 'page',
            'title': 'Admin',
            'roles': ['admin', 'manager'],
            'content': [],
          },
        },
      });
      final result = validator.validate(app);
      final roleWarnings = result.warnings
          .where((w) => w.message.contains('not defined'));
      expect(roleWarnings, isEmpty);
    });

    test('component with unknown role warns', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'home',
        'auth': {'multiUser': true},
        'pages': {
          'home': {
            'component': 'page',
            'title': 'Home',
            'content': [
              {
                'component': 'text',
                'content': 'Secret',
                'roles': ['nonexistent'],
              },
            ],
          },
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('nonexistent')), true);
    });
  });

  group('Ownership validation', () {
    test('ownership without multiUser warns', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'home',
        'pages': {
          'home': {'component': 'page', 'title': 'Home', 'content': []},
        },
        'dataSources': {
          'reader': {
            'url': 'local://items',
            'method': 'GET',
            'ownership': {'enabled': true},
          },
        },
      });
      final result = validator.validate(app);
      expect(
        result.warnings.any((w) => w.message.contains('ownership') && w.message.contains('multiUser')),
        true,
      );
    });

    test('ownership with multiUser does not warn', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'home',
        'auth': {'multiUser': true},
        'pages': {
          'home': {'component': 'page', 'title': 'Home', 'content': []},
        },
        'dataSources': {
          'reader': {
            'url': 'local://items',
            'method': 'GET',
            'ownership': {'enabled': true},
          },
        },
      });
      final result = validator.validate(app);
      final ownershipWarnings = result.warnings
          .where((w) => w.message.contains('ownership'));
      expect(ownershipWarnings, isEmpty);
    });
  });
}

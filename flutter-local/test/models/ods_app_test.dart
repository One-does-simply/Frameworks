import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/models/ods_app.dart';

void main() {
  // =========================================================================
  // Minimal valid app
  // =========================================================================

  group('OdsApp.fromJson minimal', () {
    test('parses appName, startPage string, and pages', () {
      final app = OdsApp.fromJson({
        'appName': 'Test App',
        'startPage': 'home',
        'pages': {
          'home': {
            'title': 'Home',
            'content': [],
          },
        },
      });
      expect(app.appName, 'Test App');
      expect(app.startPage, 'home');
      expect(app.pages.containsKey('home'), true);
      expect(app.pages['home']!.title, 'Home');
    });

    test('startPageByRole is empty for string startPage', () {
      final app = OdsApp.fromJson({
        'appName': 'App',
        'startPage': 'home',
        'pages': {
          'home': {'title': 'Home', 'content': []},
        },
      });
      expect(app.startPageByRole, isEmpty);
    });
  });

  // =========================================================================
  // Role-based startPage
  // =========================================================================

  group('OdsApp.fromJson role-based startPage', () {
    test('resolves startPage to default from object', () {
      final app = OdsApp.fromJson({
        'appName': 'App',
        'startPage': {
          'default': 'page1',
          'admin': 'page2',
        },
        'pages': {
          'page1': {'title': 'Page 1', 'content': []},
          'page2': {'title': 'Page 2', 'content': []},
        },
      });
      expect(app.startPage, 'page1');
    });

    test('startPageByRole has role entries (without default)', () {
      final app = OdsApp.fromJson({
        'appName': 'App',
        'startPage': {
          'default': 'page1',
          'admin': 'page2',
        },
        'pages': {
          'page1': {'title': 'Page 1', 'content': []},
          'page2': {'title': 'Page 2', 'content': []},
        },
      });
      expect(app.startPageByRole['admin'], 'page2');
      expect(app.startPageByRole.containsKey('default'), false);
    });
  });

  // =========================================================================
  // Missing optional fields default to empty
  // =========================================================================

  group('OdsApp.fromJson optional fields', () {
    test('menu defaults to empty list', () {
      final app = OdsApp.fromJson({
        'appName': 'App',
        'startPage': 'home',
        'pages': {
          'home': {'title': 'Home', 'content': []},
        },
      });
      expect(app.menu, isEmpty);
    });

    test('dataSources defaults to empty map', () {
      final app = OdsApp.fromJson({
        'appName': 'App',
        'startPage': 'home',
        'pages': {
          'home': {'title': 'Home', 'content': []},
        },
      });
      expect(app.dataSources, isEmpty);
    });

    test('settings defaults to empty map', () {
      final app = OdsApp.fromJson({
        'appName': 'App',
        'startPage': 'home',
        'pages': {
          'home': {'title': 'Home', 'content': []},
        },
      });
      expect(app.settings, isEmpty);
    });

    test('tour defaults to empty list', () {
      final app = OdsApp.fromJson({
        'appName': 'App',
        'startPage': 'home',
        'pages': {
          'home': {'title': 'Home', 'content': []},
        },
      });
      expect(app.tour, isEmpty);
    });

    test('help defaults to null', () {
      final app = OdsApp.fromJson({
        'appName': 'App',
        'startPage': 'home',
        'pages': {
          'home': {'title': 'Home', 'content': []},
        },
      });
      expect(app.help, isNull);
    });
  });

  // =========================================================================
  // Full spec with all fields
  // =========================================================================

  group('OdsApp.fromJson full spec', () {
    test('parses all top-level fields', () {
      final app = OdsApp.fromJson({
        'appName': 'Full App',
        'startPage': 'dashboard',
        'menu': [
          {'label': 'Dashboard', 'mapsTo': 'dashboard'},
          {'label': 'Settings', 'mapsTo': 'settings'},
        ],
        'pages': {
          'dashboard': {
            'title': 'Dashboard',
            'content': [
              {'component': 'text', 'content': 'Welcome'},
            ],
          },
          'settings': {
            'title': 'Settings',
            'content': [],
          },
        },
        'dataSources': {
          'tasks': {
            'method': 'GET',
            'url': 'local://tasks',
          },
        },
        'help': {
          'overview': 'This is a test app.',
          'pages': {'dashboard': 'Dashboard help text'},
        },
        'tour': [
          {'title': 'Welcome', 'content': 'Start here', 'page': 'dashboard'},
        ],
        'settings': {
          'currency': {
            'label': 'Currency',
            'type': 'select',
            'default': 'USD',
            'options': ['USD', 'EUR'],
          },
        },
      });
      expect(app.appName, 'Full App');
      expect(app.startPage, 'dashboard');
      expect(app.menu.length, 2);
      expect(app.menu[0].label, 'Dashboard');
      expect(app.pages.length, 2);
      expect(app.help, isNotNull);
      expect(app.help!.overview, 'This is a test app.');
      expect(app.help!.pages['dashboard'], 'Dashboard help text');
      expect(app.tour.length, 1);
      expect(app.tour[0].title, 'Welcome');
      expect(app.settings.containsKey('currency'), true);
    });
  });

  // =========================================================================
  // startPageForRoles()
  // =========================================================================

  group('startPageForRoles', () {
    late OdsApp app;

    setUp(() {
      app = OdsApp.fromJson({
        'appName': 'App',
        'startPage': {
          'default': 'home',
          'admin': 'adminDash',
          'editor': 'editorDash',
        },
        'pages': {
          'home': {'title': 'Home', 'content': []},
          'adminDash': {'title': 'Admin', 'content': []},
          'editorDash': {'title': 'Editor', 'content': []},
        },
      });
    });

    test('resolves admin role to admin page', () {
      expect(app.startPageForRoles(['admin']), 'adminDash');
    });

    test('resolves editor role to editor page', () {
      expect(app.startPageForRoles(['editor']), 'editorDash');
    });

    test('falls back to default when no role matches', () {
      expect(app.startPageForRoles(['viewer']), 'home');
    });

    test('falls back to default for empty roles list', () {
      expect(app.startPageForRoles([]), 'home');
    });

    test('returns first matching role when user has multiple roles', () {
      expect(app.startPageForRoles(['editor', 'admin']), 'editorDash');
    });
  });

  // =========================================================================
  // startPageByRole edge case
  // =========================================================================

  group('startPageByRole', () {
    test('returns empty map for string startPage', () {
      final app = OdsApp.fromJson({
        'appName': 'App',
        'startPage': 'home',
        'pages': {
          'home': {'title': 'Home', 'content': []},
        },
      });
      expect(app.startPageByRole, isEmpty);
    });
  });
}

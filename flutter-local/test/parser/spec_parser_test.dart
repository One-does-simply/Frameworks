import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/parser/spec_parser.dart';

void main() {
  final parser = SpecParser();

  group('Invalid JSON', () {
    test('returns parse error for malformed JSON', () {
      final result = parser.parse('not json at all');
      expect(result.isOk, false);
      expect(result.parseError, isNotNull);
    });

    test('returns parse error for JSON array', () {
      final result = parser.parse('[1, 2, 3]');
      expect(result.isOk, false);
    });
  });

  group('Missing required fields', () {
    test('missing appName', () {
      final result = parser.parse(jsonEncode({
        'startPage': 'home',
        'pages': {
          'home': {
            'component': 'page',
            'title': 'Home',
            'content': [],
          }
        }
      }));
      expect(result.isOk, false);
      expect(result.validation.errors.any((e) => e.message.contains('appName')), true);
    });

    test('missing startPage', () {
      final result = parser.parse(jsonEncode({
        'appName': 'Test',
        'pages': {
          'home': {
            'component': 'page',
            'title': 'Home',
            'content': [],
          }
        }
      }));
      expect(result.isOk, false);
      expect(result.validation.errors.any((e) => e.message.contains('startPage')), true);
    });

    test('missing pages', () {
      final result = parser.parse(jsonEncode({
        'appName': 'Test',
        'startPage': 'home',
      }));
      expect(result.isOk, false);
      expect(result.validation.errors.any((e) => e.message.contains('pages')), true);
    });
  });

  group('Valid minimal spec', () {
    test('parses successfully', () {
      final result = parser.parse(jsonEncode({
        'appName': 'Test App',
        'startPage': 'home',
        'pages': {
          'home': {
            'component': 'page',
            'title': 'Home',
            'content': [
              {'component': 'text', 'content': 'Hello'},
            ],
          }
        }
      }));
      expect(result.isOk, true);
      expect(result.app, isNotNull);
      expect(result.app!.appName, 'Test App');
      expect(result.app!.startPage, 'home');
      expect(result.app!.pages.length, 1);
    });
  });

  group('Component parsing', () {
    ParseResult _parseSpec(Map<String, dynamic> spec) {
      return parser.parse(jsonEncode(spec));
    }

    test('text component', () {
      final result = _parseSpec({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {'component': 'text', 'content': 'Hello world'},
            ],
          }
        }
      });
      expect(result.isOk, true);
      expect(result.app!.pages['p']!.content.length, 1);
    });

    test('form with fields', () {
      final result = _parseSpec({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'form',
                'id': 'myForm',
                'fields': [
                  {'name': 'email', 'type': 'email', 'required': true},
                  {
                    'name': 'status',
                    'type': 'select',
                    'options': ['Open', 'Closed']
                  },
                ],
              }
            ],
          }
        }
      });
      expect(result.isOk, true);
    });

    test('button with onClick actions', () {
      final result = _parseSpec({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'button',
                'label': 'Go',
                'onClick': [
                  {'action': 'navigate', 'target': 'p'},
                ],
              }
            ],
          }
        }
      });
      expect(result.isOk, true);
    });

    test('list component with columns', () {
      final result = _parseSpec({
        'appName': 'Test',
        'startPage': 'p',
        'dataSources': {
          'reader': {'url': 'local://items', 'method': 'GET'},
        },
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'list',
                'dataSource': 'reader',
                'columns': [
                  {'header': 'Name', 'field': 'name'},
                ],
              }
            ],
          }
        }
      });
      expect(result.isOk, true);
    });
  });

  group('Data sources', () {
    test('local data source parsed', () {
      final result = parser.parse(jsonEncode({
        'appName': 'Test',
        'startPage': 'p',
        'dataSources': {
          'store': {'url': 'local://items', 'method': 'POST'},
          'reader': {'url': 'local://items', 'method': 'GET'},
        },
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [],
          }
        }
      }));
      expect(result.isOk, true);
      expect(result.app!.dataSources.length, 2);
      expect(result.app!.dataSources['store']!.method, 'POST');
      expect(result.app!.dataSources['reader']!.isLocal, true);
    });
  });

  group('Optional features', () {
    test('help parsed', () {
      final result = parser.parse(jsonEncode({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [],
          }
        },
        'help': {
          'overview': 'This is a test app.',
          'pages': {'p': 'This is page P.'},
        }
      }));
      expect(result.isOk, true);
      expect(result.app!.help, isNotNull);
      expect(result.app!.help!.overview, 'This is a test app.');
    });

    test('tour parsed', () {
      final result = parser.parse(jsonEncode({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [],
          }
        },
        'tour': [
          {'title': 'Welcome', 'content': 'Hello!'},
          {'title': 'Step 2', 'content': 'Do this.', 'page': 'p'},
        ]
      }));
      expect(result.isOk, true);
      expect(result.app!.tour, isNotNull);
      expect(result.app!.tour!.length, 2);
    });

    test('settings parsed', () {
      final result = parser.parse(jsonEncode({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [],
          }
        },
        'settings': {
          'theme': {
            'label': 'Theme',
            'type': 'select',
            'default': 'light',
            'options': ['light', 'dark'],
          }
        }
      }));
      expect(result.isOk, true);
      expect(result.app!.settings, isNotNull);
      expect(result.app!.settings!.containsKey('theme'), true);
    });

    test('menu parsed', () {
      final result = parser.parse(jsonEncode({
        'appName': 'Test',
        'startPage': 'p',
        'menu': [
          {'label': 'Home', 'mapsTo': 'p'},
        ],
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [],
          }
        }
      }));
      expect(result.isOk, true);
      expect(result.app!.menu.length, 1);
      expect(result.app!.menu.first.label, 'Home');
    });
  });
}

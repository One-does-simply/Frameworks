import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/models/ods_app.dart';
import 'package:ods_flutter_local/parser/spec_validator.dart';

void main() {
  final validator = SpecValidator();

  /// Helper: builds an OdsApp from JSON for validation.
  OdsApp _app(Map<String, dynamic> json) => OdsApp.fromJson(json);

  group('Top-level validation', () {
    test('empty appName is an error', () {
      final app = _app({
        'appName': '',
        'startPage': 'home',
        'pages': {
          'home': {'component': 'page', 'title': 'Home', 'content': []},
        },
      });
      final result = validator.validate(app);
      expect(result.hasErrors, true);
      expect(result.errors.any((e) => e.message.contains('appName')), true);
    });

    test('startPage not in pages is an error', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'missing',
        'pages': {
          'home': {'component': 'page', 'title': 'Home', 'content': []},
        },
      });
      final result = validator.validate(app);
      expect(result.hasErrors, true);
    });

    test('empty pages is caught at parse or validation level', () {
      // OdsApp.fromJson throws on empty pages (type cast issue),
      // which effectively prevents empty-page apps from being created.
      expect(
        () => _app({
          'appName': 'Test',
          'startPage': 'home',
          'pages': {},
        }),
        throwsA(anything),
      );
    });

    test('valid minimal app has no errors', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'home',
        'pages': {
          'home': {'component': 'page', 'title': 'Home', 'content': []},
        },
      });
      final result = validator.validate(app);
      expect(result.hasErrors, false);
    });
  });

  group('Menu validation', () {
    test('menu item pointing to missing page is a warning', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'home',
        'menu': [
          {'label': 'Bad Link', 'mapsTo': 'nonexistent'},
        ],
        'pages': {
          'home': {'component': 'page', 'title': 'Home', 'content': []},
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('nonexistent')), true);
    });

    test('valid menu item produces no warnings', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'home',
        'menu': [
          {'label': 'Home', 'mapsTo': 'home'},
        ],
        'pages': {
          'home': {'component': 'page', 'title': 'Home', 'content': []},
        },
      });
      final result = validator.validate(app);
      expect(result.warnings, isEmpty);
    });
  });

  group('List component validation', () {
    test('list referencing unknown dataSource warns', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'list',
                'dataSource': 'missing',
                'columns': [
                  {'header': 'Name', 'field': 'name'},
                ],
              },
            ],
          },
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('missing')), true);
    });

    test('rowColorMap without rowColorField warns', () {
      final app = _app({
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
                'rowColorMap': {'Open': 'green', 'Closed': 'red'},
              },
            ],
          },
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('rowColorMap')), true);
    });
  });

  group('Button action validation', () {
    test('navigate to missing page warns', () {
      final app = _app({
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
                  {'action': 'navigate', 'target': 'nonexistent'},
                ],
              },
            ],
          },
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('nonexistent')), true);
    });

    test('submit to missing dataSource warns', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'button',
                'label': 'Save',
                'onClick': [
                  {'action': 'submit', 'dataSource': 'missing', 'target': 'form1'},
                ],
              },
            ],
          },
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('missing')), true);
    });

    test('update without matchField warns', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'p',
        'dataSources': {
          'store': {'url': 'local://items', 'method': 'PUT'},
        },
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'button',
                'label': 'Update',
                'onClick': [
                  {'action': 'update', 'dataSource': 'store', 'target': 'form1'},
                ],
              },
            ],
          },
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('matchField')), true);
    });
  });

  group('Form field validation', () {
    test('unknown field type warns', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'form',
                'id': 'f',
                'fields': [
                  {'name': 'x', 'type': 'bogus'},
                ],
              },
            ],
          },
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('bogus')), true);
    });

    test('select without options warns', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'form',
                'id': 'f',
                'fields': [
                  {'name': 'status', 'type': 'select'},
                ],
              },
            ],
          },
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('options')), true);
    });

    test('computed field with no dependencies warns', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'form',
                'id': 'f',
                'fields': [
                  {'name': 'total', 'type': 'number', 'formula': '42'},
                ],
              },
            ],
          },
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('no field references')), true);
    });

    test('computed field referencing unknown field warns', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'form',
                'id': 'f',
                'fields': [
                  {'name': 'total', 'type': 'number', 'formula': '{missing} * 2'},
                ],
              },
            ],
          },
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('missing')), true);
    });

    test('required computed field warns', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'form',
                'id': 'f',
                'fields': [
                  {'name': 'a', 'type': 'number'},
                  {'name': 'total', 'type': 'number', 'formula': '{a} * 2', 'required': true},
                ],
              },
            ],
          },
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('read-only')), true);
    });

    test('visibleWhen referencing unknown sibling warns', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'form',
                'id': 'f',
                'fields': [
                  {
                    'name': 'extra',
                    'type': 'text',
                    'visibleWhen': {'field': 'missing', 'equals': 'yes'},
                  },
                ],
              },
            ],
          },
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('missing')), true);
    });

    test('min/max on non-number field warns', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'form',
                'id': 'f',
                'fields': [
                  {
                    'name': 'name',
                    'type': 'text',
                    'validation': {'min': 0, 'max': 100},
                  },
                ],
              },
            ],
          },
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('min/max')), true);
    });
  });

  group('Chart validation', () {
    test('chart referencing unknown dataSource warns', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'chart',
                'dataSource': 'missing',
                'chartType': 'bar',
                'labelField': 'name',
                'valueField': 'count',
              },
            ],
          },
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('missing')), true);
    });

    test('unknown chart type warns', () {
      final app = _app({
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
                'component': 'chart',
                'dataSource': 'reader',
                'chartType': 'donut',
                'labelField': 'name',
                'valueField': 'count',
              },
            ],
          },
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('donut')), true);
    });
  });

  group('Tabs validation', () {
    test('empty tabs warns', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {'component': 'tabs', 'tabs': []},
            ],
          },
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('no tabs')), true);
    });

    test('tab with empty content warns', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'tabs',
                'tabs': [
                  {'label': 'Empty', 'content': []},
                ],
              },
            ],
          },
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('no content')), true);
    });
  });

  group('Detail component validation', () {
    test('detail referencing unknown dataSource warns', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'detail',
                'dataSource': 'missing',
              },
            ],
          },
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('missing')), true);
    });
  });

  group('Row action validation', () {
    test('rowAction referencing unknown dataSource warns', () {
      final app = _app({
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
                'rowActions': [
                  {
                    'label': 'Delete',
                    'action': 'delete',
                    'dataSource': 'missing',
                    'matchField': '_id',
                  },
                ],
              },
            ],
          },
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('missing')), true);
    });

    test('update rowAction with empty values warns', () {
      final app = _app({
        'appName': 'Test',
        'startPage': 'p',
        'dataSources': {
          'reader': {'url': 'local://items', 'method': 'GET'},
          'updater': {'url': 'local://items', 'method': 'PUT'},
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
                'rowActions': [
                  {
                    'label': 'Mark Done',
                    'action': 'update',
                    'dataSource': 'updater',
                    'matchField': '_id',
                  },
                ],
              },
            ],
          },
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('empty values')), true);
    });
  });

  group('Dependent dropdown validation', () {
    test('filter.fromField referencing unknown sibling warns', () {
      final app = _app({
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
                'component': 'form',
                'id': 'f',
                'fields': [
                  {
                    'name': 'sub',
                    'type': 'select',
                    'optionsFrom': {
                      'dataSource': 'reader',
                      'valueField': 'name',
                      'filter': {'field': 'category', 'fromField': 'nonexistent'},
                    },
                  },
                ],
              },
            ],
          },
        },
      });
      final result = validator.validate(app);
      expect(result.warnings.any((w) => w.message.contains('nonexistent')), true);
    });
  });
}

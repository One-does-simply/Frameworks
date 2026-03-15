import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/models/ods_component.dart';
import 'package:ods_flutter_local/parser/spec_parser.dart';

/// Edge case tests for SpecParser, complementing the main parser test file.
void main() {
  final parser = SpecParser();

  ParseResult _parse(Map<String, dynamic> spec) =>
      parser.parse(jsonEncode(spec));

  group('Unknown component types', () {
    test('unknown component type parses as OdsUnknownComponent', () {
      final result = _parse({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {'component': 'wizardWidget', 'data': 'anything'},
            ],
          },
        },
      });
      expect(result.isOk, true);
      expect(result.app!.pages['p']!.content.first, isA<OdsUnknownComponent>());
    });
  });

  group('Empty content', () {
    test('page with empty content array parses', () {
      final result = _parse({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {'component': 'page', 'title': 'P', 'content': []},
        },
      });
      expect(result.isOk, true);
      expect(result.app!.pages['p']!.content, isEmpty);
    });
  });

  group('Multiple pages', () {
    test('multiple pages parsed correctly', () {
      final result = _parse({
        'appName': 'Test',
        'startPage': 'home',
        'pages': {
          'home': {'component': 'page', 'title': 'Home', 'content': []},
          'add': {'component': 'page', 'title': 'Add', 'content': []},
          'edit': {'component': 'page', 'title': 'Edit', 'content': []},
        },
      });
      expect(result.isOk, true);
      expect(result.app!.pages.length, 3);
    });
  });

  group('All component types', () {
    test('text component', () {
      final result = _parse({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {'component': 'text', 'content': 'Hello'},
            ],
          },
        },
      });
      expect(result.app!.pages['p']!.content.first, isA<OdsTextComponent>());
    });

    test('summary component', () {
      final result = _parse({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {'component': 'summary', 'label': 'Total', 'value': '42'},
            ],
          },
        },
      });
      expect(result.app!.pages['p']!.content.first, isA<OdsSummaryComponent>());
    });

    test('tabs component', () {
      final result = _parse({
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
                  {
                    'label': 'Tab1',
                    'content': [
                      {'component': 'text', 'content': 'Inside tab'},
                    ],
                  },
                ],
              },
            ],
          },
        },
      });
      expect(result.app!.pages['p']!.content.first, isA<OdsTabsComponent>());
    });

    test('detail component', () {
      final result = _parse({
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
              {'component': 'detail', 'dataSource': 'reader'},
            ],
          },
        },
      });
      expect(result.app!.pages['p']!.content.first, isA<OdsDetailComponent>());
    });

    test('chart component', () {
      final result = _parse({
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
                'chartType': 'bar',
                'labelField': 'name',
                'valueField': 'count',
              },
            ],
          },
        },
      });
      expect(result.app!.pages['p']!.content.first, isA<OdsChartComponent>());
    });
  });

  group('Field types', () {
    test('all field types parse', () {
      final types = ['text', 'email', 'number', 'date', 'datetime', 'multiline', 'select', 'checkbox', 'hidden'];
      for (final type in types) {
        final fields = <Map<String, dynamic>>[
          {
            'name': 'f',
            'type': type,
            if (type == 'select') 'options': ['A', 'B'],
          },
        ];
        final result = _parse({
          'appName': 'Test',
          'startPage': 'p',
          'pages': {
            'p': {
              'component': 'page',
              'title': 'P',
              'content': [
                {'component': 'form', 'id': 'form1', 'fields': fields},
              ],
            },
          },
        });
        expect(result.isOk, true, reason: 'Type "$type" should parse');
      }
    });
  });

  group('DataSource features', () {
    test('explicit fields on dataSource parsed', () {
      final result = _parse({
        'appName': 'Test',
        'startPage': 'p',
        'dataSources': {
          'reader': {
            'url': 'local://items',
            'method': 'GET',
            'fields': [
              {'name': 'name', 'type': 'text'},
              {'name': 'age', 'type': 'number'},
            ],
          },
        },
        'pages': {
          'p': {'component': 'page', 'title': 'P', 'content': []},
        },
      });
      expect(result.app!.dataSources['reader']!.fields, isNotNull);
      expect(result.app!.dataSources['reader']!.fields!.length, 2);
    });

    test('seedData on dataSource parsed', () {
      final result = _parse({
        'appName': 'Test',
        'startPage': 'p',
        'dataSources': {
          'store': {
            'url': 'local://items',
            'method': 'GET',
            'seedData': [
              {'name': 'Alice', 'age': '30'},
              {'name': 'Bob', 'age': '25'},
            ],
          },
        },
        'pages': {
          'p': {'component': 'page', 'title': 'P', 'content': []},
        },
      });
      expect(result.app!.dataSources['store']!.seedData, isNotNull);
      expect(result.app!.dataSources['store']!.seedData!.length, 2);
    });

    test('isLocal detection', () {
      final result = _parse({
        'appName': 'Test',
        'startPage': 'p',
        'dataSources': {
          'local': {'url': 'local://items', 'method': 'GET'},
          'remote': {'url': 'https://api.example.com/items', 'method': 'GET'},
        },
        'pages': {
          'p': {'component': 'page', 'title': 'P', 'content': []},
        },
      });
      expect(result.app!.dataSources['local']!.isLocal, true);
      expect(result.app!.dataSources['remote']!.isLocal, false);
    });

    test('tableName extraction', () {
      final result = _parse({
        'appName': 'Test',
        'startPage': 'p',
        'dataSources': {
          'store': {'url': 'local://my_table', 'method': 'POST'},
        },
        'pages': {
          'p': {'component': 'page', 'title': 'P', 'content': []},
        },
      });
      expect(result.app!.dataSources['store']!.tableName, 'my_table');
    });
  });

  group('Action parsing', () {
    test('computedFields on submit action parsed', () {
      final result = _parse({
        'appName': 'Test',
        'startPage': 'p',
        'dataSources': {
          'store': {'url': 'local://items', 'method': 'POST'},
        },
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'button',
                'label': 'Save',
                'onClick': [
                  {
                    'action': 'submit',
                    'target': 'form1',
                    'dataSource': 'store',
                    'computedFields': [
                      {'field': 'score', 'expression': "{answer} == {correct} ? '1' : '0'"},
                    ],
                  },
                ],
              },
            ],
          },
        },
      });
      expect(result.isOk, true);
      final btn = result.app!.pages['p']!.content.first as OdsButtonComponent;
      expect(btn.onClick.first.computedFields.length, 1);
      expect(btn.onClick.first.computedFields.first.field, 'score');
    });

    test('showMessage action parsed', () {
      final result = _parse({
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
                  {'action': 'showMessage', 'message': 'Saved!'},
                ],
              },
            ],
          },
        },
      });
      expect(result.isOk, true);
      final btn = result.app!.pages['p']!.content.first as OdsButtonComponent;
      expect(btn.onClick.first.message, 'Saved!');
    });

    test('record cursor actions parsed', () {
      final result = _parse({
        'appName': 'Test',
        'startPage': 'p',
        'pages': {
          'p': {
            'component': 'page',
            'title': 'P',
            'content': [
              {
                'component': 'button',
                'label': 'Next',
                'onClick': [
                  {
                    'action': 'nextRecord',
                    'target': 'quizForm',
                    'onEnd': {'action': 'navigate', 'target': 'results'},
                  },
                ],
              },
            ],
          },
        },
      });
      expect(result.isOk, true);
      final btn = result.app!.pages['p']!.content.first as OdsButtonComponent;
      expect(btn.onClick.first.isRecordAction, true);
      expect(btn.onClick.first.onEnd, isNotNull);
      expect(btn.onClick.first.onEnd!.target, 'results');
    });
  });

  group('List features', () {
    test('defaultSort parsed', () {
      final result = _parse({
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
                  {'header': 'Date', 'field': 'date', 'sortable': true},
                ],
                'defaultSort': {'field': 'date', 'direction': 'desc'},
              },
            ],
          },
        },
      });
      expect(result.isOk, true);
      final list = result.app!.pages['p']!.content.first as OdsListComponent;
      expect(list.defaultSort, isNotNull);
      expect(list.defaultSort!.field, 'date');
      expect(list.defaultSort!.isDescending, true);
    });

    test('card display mode parsed', () {
      final result = _parse({
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
                'displayAs': 'cards',
              },
            ],
          },
        },
      });
      expect(result.isOk, true);
      final list = result.app!.pages['p']!.content.first as OdsListComponent;
      expect(list.displayAs, 'cards');
    });

    test('row coloring parsed', () {
      final result = _parse({
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
                  {'header': 'Status', 'field': 'status'},
                ],
                'rowColorField': 'status',
                'rowColorMap': {'Open': 'green', 'Closed': 'red'},
              },
            ],
          },
        },
      });
      expect(result.isOk, true);
      final list = result.app!.pages['p']!.content.first as OdsListComponent;
      expect(list.rowColorField, 'status');
      expect(list.rowColorMap, isNotNull);
      expect(list.rowColorMap!['Open'], 'green');
    });
  });
}

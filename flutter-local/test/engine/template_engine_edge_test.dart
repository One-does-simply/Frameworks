import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/engine/template_engine.dart';

/// Edge case tests for TemplateEngine, complementing the main test file.
void main() {
  group('Nested \$map', () {
    test('\$map inside \$map', () {
      final template = {
        '\$map': 'groups',
        'each(group)': {
          'name': r'${group.name}',
          'items': {
            '\$map': 'group.items',
            'each(item)': r'${item}',
          },
        },
      };
      final context = {
        'groups': [
          {
            'name': 'A',
            'items': ['a1', 'a2'],
          },
          {
            'name': 'B',
            'items': ['b1'],
          },
        ],
      };
      final result = TemplateEngine.render(template, context) as List;
      expect(result.length, 2);
      expect(result[0]['name'], 'A');
      expect(result[0]['items'], ['a1', 'a2']);
      expect(result[1]['items'], ['b1']);
    });

    test('\$map inside \$map with index', () {
      final template = {
        '\$map': 'outer',
        'each(row, rowIdx)': {
          'row': '\${rowIdx}',
          'cells': {
            '\$map': 'row.cells',
            'each(cell, colIdx)': {
              'r': '\${rowIdx}',
              'c': '\${colIdx}',
              'v': '\${cell}',
            },
          },
        },
      };
      final context = {
        'outer': [
          {
            'cells': ['x', 'y'],
          },
        ],
      };
      final result = TemplateEngine.render(template, context) as List;
      expect(result[0]['row'], 0);
      expect(result[0]['cells'], [
        {'r': 0, 'c': 0, 'v': 'x'},
        {'r': 0, 'c': 1, 'v': 'y'},
      ]);
    });
  });

  group('Missing context variables', () {
    test('\$map with missing source returns empty', () {
      final result = TemplateEngine.render(
        {
          '\$map': 'nonexistent',
          'each(item)': r'${item}',
        },
        <String, dynamic>{},
      );
      expect(result, []);
    });

    test('\$if with missing variable is falsy', () {
      final result = TemplateEngine.render(
        {'\$if': 'missing', 'then': 'yes', 'else': 'no'},
        <String, dynamic>{},
      );
      expect(result, 'no');
    });

    test('\$eval of missing variable returns null', () {
      final result = TemplateEngine.render(
        {'\$eval': 'missing'},
        <String, dynamic>{},
      );
      expect(result, isNull);
    });

    test('interpolation with missing nested path', () {
      final result = TemplateEngine.render(
        r'${user.address.city}',
        {'user': <String, dynamic>{}},
      );
      // Missing nested path resolves to null
      expect(result, isNull);
    });
  });

  group('Deeply nested paths', () {
    test('three levels of dot access', () {
      final result = TemplateEngine.render(
        r'${a.b.c}',
        {
          'a': {
            'b': {'c': 'deep'}
          }
        },
      );
      expect(result, 'deep');
    });

    test('mixed index and dot', () {
      final result = TemplateEngine.render(
        r'${items[0].nested[1].value}',
        {
          'items': [
            {
              'nested': [
                {'value': 'skip'},
                {'value': 'found'},
              ]
            }
          ]
        },
      );
      expect(result, 'found');
    });

    test('null intermediate returns null', () {
      final result = TemplateEngine.render(
        r'${a.b.c}',
        {'a': null},
      );
      expect(result, isNull);
    });
  });

  group('\$if with \$map interaction', () {
    test('\$map produces items, \$if filters inside', () {
      final template = {
        '\$map': 'items',
        'each(item)': {
          '\$if': "item.active == 'true'",
          'then': {'name': r'${item.name}'},
        },
      };
      final context = {
        'items': [
          {'name': 'A', 'active': 'true'},
          {'name': 'B', 'active': 'false'},
          {'name': 'C', 'active': 'true'},
        ],
      };
      final result = TemplateEngine.render(template, context) as List;
      expect(result.length, 2);
      expect(result[0]['name'], 'A');
      expect(result[1]['name'], 'C');
    });
  });

  group('\$flatten edge cases', () {
    test('empty arrays produce empty result', () {
      final result = TemplateEngine.render(
        {
          '\$flatten': [[], []]
        },
        <String, dynamic>{},
      );
      expect(result, []);
    });

    test('non-list value passes through', () {
      final result = TemplateEngine.render(
        {'\$flatten': 'not a list'},
        <String, dynamic>{},
      );
      expect(result, 'not a list');
    });
  });

  group('Complex equality conditions', () {
    test('string equality with spaces', () {
      final result = TemplateEngine.render(
        {'\$if': "name == 'John Doe'", 'then': 'found', 'else': 'nope'},
        {'name': 'John Doe'},
      );
      // Note: the evaluator splits on ==, and the right side is 'John Doe'.
      // But _evaluateExpression will try to resolve 'John Doe' as a path,
      // finding 'John Doe' between quotes → string literal.
      expect(result, 'found');
    });

    test('numeric equality', () {
      final result = TemplateEngine.render(
        {'\$if': 'count == 0', 'then': 'empty', 'else': 'has data'},
        {'count': 0},
      );
      expect(result, 'empty');
    });
  });

  group('List rendering', () {
    test('renders list of objects', () {
      final result = TemplateEngine.render(
        [
          {'key': r'${name}'},
          {'key': 'static'},
        ],
        {'name': 'test'},
      );
      expect(result, [
        {'key': 'test'},
        {'key': 'static'},
      ]);
    });

    test('removed items filtered from lists', () {
      final result = TemplateEngine.render(
        [
          'always',
          {'\$if': 'show', 'then': 'conditional'},
          'also always',
        ],
        {'show': false},
      );
      expect(result, ['always', 'also always']);
    });
  });

  group('\$eval edge cases', () {
    test('eval dotted path', () {
      final result = TemplateEngine.render(
        {'\$eval': 'field.options'},
        {
          'field': {
            'options': ['A', 'B']
          }
        },
      );
      expect(result, ['A', 'B']);
    });

    test('eval numeric string returns number', () {
      final result = TemplateEngine.render(
        {'\$eval': '42.5'},
        <String, dynamic>{},
      );
      expect(result, 42.5);
    });
  });
}

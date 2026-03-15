import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/engine/template_engine.dart';

void main() {
  group('String interpolation', () {
    test('replaces simple variable', () {
      final result = TemplateEngine.render(
        r'Hello ${name}',
        {'name': 'World'},
      );
      expect(result, 'Hello World');
    });

    test('replaces multiple variables', () {
      final result = TemplateEngine.render(
        r'${greeting} ${name}!',
        {'greeting': 'Hi', 'name': 'Alice'},
      );
      expect(result, 'Hi Alice!');
    });

    test('whole-string expression preserves type (list)', () {
      final result = TemplateEngine.render(
        r'${items}',
        {'items': [1, 2, 3]},
      );
      expect(result, [1, 2, 3]);
    });

    test('whole-string expression preserves type (number)', () {
      final result = TemplateEngine.render(r'${count}', {'count': 42});
      expect(result, 42);
    });

    test('whole-string expression preserves type (bool)', () {
      final result = TemplateEngine.render(r'${flag}', {'flag': true});
      expect(result, true);
    });

    test('missing variable renders empty', () {
      final result = TemplateEngine.render(
        r'Hello ${missing}',
        <String, dynamic>{},
      );
      expect(result, 'Hello ');
    });
  });

  group('Path resolution', () {
    test('dotted path', () {
      final result = TemplateEngine.render(
        r'${user.name}',
        {
          'user': {'name': 'Alice'}
        },
      );
      expect(result, 'Alice');
    });

    test('indexed access', () {
      final result = TemplateEngine.render(
        r'${items[0]}',
        {
          'items': ['first', 'second']
        },
      );
      expect(result, 'first');
    });

    test('combined index and dot', () {
      final result = TemplateEngine.render(
        r'${fields[1].name}',
        {
          'fields': [
            {'name': 'a'},
            {'name': 'b'}
          ]
        },
      );
      expect(result, 'b');
    });

    test('out of bounds returns null', () {
      final result = TemplateEngine.render(
        r'${items[99]}',
        {
          'items': ['only']
        },
      );
      expect(result, isNull);
    });
  });

  group('\$if / then / else', () {
    test('truthy condition returns then branch', () {
      final result = TemplateEngine.render(
        {'\$if': 'flag', 'then': 'yes', 'else': 'no'},
        {'flag': true},
      );
      expect(result, 'yes');
    });

    test('falsy condition returns else branch', () {
      final result = TemplateEngine.render(
        {'\$if': 'flag', 'then': 'yes', 'else': 'no'},
        {'flag': false},
      );
      expect(result, 'no');
    });

    test('equality condition', () {
      final result = TemplateEngine.render(
        {'\$if': "type == 'select'", 'then': 'dropdown', 'else': 'input'},
        {'type': 'select'},
      );
      expect(result, 'dropdown');
    });

    test('inequality condition', () {
      final result = TemplateEngine.render(
        {'\$if': "type != 'select'", 'then': 'input', 'else': 'dropdown'},
        {'type': 'text'},
      );
      expect(result, 'input');
    });

    test('negation', () {
      final result = TemplateEngine.render(
        {'\$if': '!flag', 'then': 'hidden', 'else': 'visible'},
        {'flag': false},
      );
      expect(result, 'hidden');
    });

    test('missing else with false condition removes element', () {
      final result = TemplateEngine.render(
        [
          'keep',
          {'\$if': 'flag', 'then': 'conditional'},
        ],
        {'flag': false},
      );
      expect(result, ['keep']);
    });

    test('null variable is falsy', () {
      final result = TemplateEngine.render(
        {'\$if': 'missing', 'then': 'yes', 'else': 'no'},
        <String, dynamic>{},
      );
      expect(result, 'no');
    });

    test('empty string is falsy', () {
      final result = TemplateEngine.render(
        {'\$if': 'name', 'then': 'yes', 'else': 'no'},
        {'name': ''},
      );
      expect(result, 'no');
    });

    test('non-empty string is truthy', () {
      final result = TemplateEngine.render(
        {'\$if': 'name', 'then': 'yes', 'else': 'no'},
        {'name': 'Alice'},
      );
      expect(result, 'yes');
    });

    test('empty list is falsy', () {
      final result = TemplateEngine.render(
        {'\$if': 'items', 'then': 'yes', 'else': 'no'},
        {'items': []},
      );
      expect(result, 'no');
    });

    test('zero is falsy', () {
      final result = TemplateEngine.render(
        {'\$if': 'count', 'then': 'yes', 'else': 'no'},
        {'count': 0},
      );
      expect(result, 'no');
    });
  });

  group('\$map', () {
    test('maps over array', () {
      final result = TemplateEngine.render(
        {
          '\$map': 'items',
          'each(item)': r'${item.name}',
        },
        {
          'items': [
            {'name': 'Alice'},
            {'name': 'Bob'},
          ]
        },
      );
      expect(result, ['Alice', 'Bob']);
    });

    test('maps to objects', () {
      final result = TemplateEngine.render(
        {
          '\$map': 'fields',
          'each(f)': {
            'header': r'${f.label}',
            'field': r'${f.name}',
          },
        },
        {
          'fields': [
            {'name': 'age', 'label': 'Age'},
            {'name': 'email', 'label': 'Email'},
          ]
        },
      );
      expect(result, [
        {'header': 'Age', 'field': 'age'},
        {'header': 'Email', 'field': 'email'},
      ]);
    });

    test('provides index variable', () {
      final result = TemplateEngine.render(
        {
          '\$map': 'items',
          'each(item)': r'${itemIndex}',
        },
        {
          'items': ['a', 'b', 'c']
        },
      );
      expect(result, [0, 1, 2]);
    });

    test('empty source returns empty list', () {
      final result = TemplateEngine.render(
        {
          '\$map': 'items',
          'each(item)': r'${item}',
        },
        {'items': []},
      );
      expect(result, []);
    });

    test('non-list source returns empty list', () {
      final result = TemplateEngine.render(
        {
          '\$map': 'items',
          'each(item)': r'${item}',
        },
        {'items': 'not a list'},
      );
      expect(result, []);
    });

    test('map with conditional inside', () {
      final result = TemplateEngine.render(
        {
          '\$map': 'fields',
          'each(f)': {
            '\$if': "f.type == 'select'",
            'then': {
              'name': r'${f.name}',
              'type': 'select',
              'options': {'\$eval': 'f.options'}
            },
            'else': {'name': r'${f.name}', 'type': r'${f.type}'},
          },
        },
        {
          'fields': [
            {'name': 'title', 'type': 'text'},
            {
              'name': 'status',
              'type': 'select',
              'options': ['Open', 'Closed']
            },
          ]
        },
      );
      expect(result, [
        {'name': 'title', 'type': 'text'},
        {
          'name': 'status',
          'type': 'select',
          'options': ['Open', 'Closed']
        },
      ]);
    });
  });

  group('\$eval', () {
    test('evaluates variable reference', () {
      final result = TemplateEngine.render(
        {'\$eval': 'items'},
        {
          'items': [1, 2, 3]
        },
      );
      expect(result, [1, 2, 3]);
    });

    test('evaluates string literal', () {
      final result = TemplateEngine.render(
        {'\$eval': "'hello'"},
        <String, dynamic>{},
      );
      expect(result, 'hello');
    });

    test('evaluates boolean', () {
      final result = TemplateEngine.render(
        {'\$eval': 'true'},
        <String, dynamic>{},
      );
      expect(result, true);
    });

    test('evaluates number', () {
      final result = TemplateEngine.render(
        {'\$eval': '42'},
        <String, dynamic>{},
      );
      expect(result, 42);
    });
  });

  group('\$flatten', () {
    test('flattens nested arrays one level', () {
      final result = TemplateEngine.render(
        {
          '\$flatten': [
            [1, 2],
            [3, 4],
          ]
        },
        <String, dynamic>{},
      );
      expect(result, [1, 2, 3, 4]);
    });

    test('mixes arrays and single items', () {
      final result = TemplateEngine.render(
        {
          '\$flatten': [
            [1, 2],
            3,
            [4, 5],
          ]
        },
        <String, dynamic>{},
      );
      expect(result, [1, 2, 3, 4, 5]);
    });

    test('with conditional branches', () {
      final result = TemplateEngine.render(
        {
          '\$flatten': [
            ['always'],
            {
              '\$if': 'include',
              'then': ['conditional'],
              'else': [],
            },
          ]
        },
        {'include': true},
      );
      expect(result, ['always', 'conditional']);
    });

    test('conditional false produces clean array', () {
      final result = TemplateEngine.render(
        {
          '\$flatten': [
            ['always'],
            {
              '\$if': 'include',
              'then': ['conditional'],
              'else': [],
            },
          ]
        },
        {'include': false},
      );
      expect(result, ['always']);
    });
  });

  group('Plain object recursion', () {
    test('recursively renders nested objects', () {
      final result = TemplateEngine.render(
        {
          'name': r'${appName}',
          'nested': {
            'title': r'${title}',
          },
        },
        {'appName': 'MyApp', 'title': 'Home'},
      );
      expect(result, {
        'name': 'MyApp',
        'nested': {'title': 'Home'},
      });
    });

    test('primitives pass through', () {
      final result = TemplateEngine.render(
        {'count': 42, 'active': true, 'nothing': null},
        <String, dynamic>{},
      );
      expect(result, {'count': 42, 'active': true, 'nothing': null});
    });
  });
}

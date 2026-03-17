import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/engine/template_engine.dart';
import 'package:ods_flutter_local/models/ods_component.dart';
import 'package:ods_flutter_local/parser/spec_parser.dart';

/// Regression test: every template in the Specification repo must render
/// into a valid ODS spec that parses without errors.
void main() {
  final parser = SpecParser();
  final templatesDir = Directory('../../Specification/Templates');

  if (!templatesDir.existsSync()) {
    test('SKIP: Specification/Templates not found', () {});
    return;
  }

  final templateFiles = templatesDir
      .listSync()
      .whereType<File>()
      .where(
          (f) => f.path.endsWith('.json') && !f.path.endsWith('catalog.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  // Test data for each template — provides realistic answers for all questions.
  final testContexts = <String, Map<String, dynamic>>{
    'simple-tracker.json': {
      'appName': 'Test Tracker',
      'itemName': 'Items',
      'fields': [
        {'name': 'title', 'label': 'Title', 'type': 'text'},
        {
          'name': 'status',
          'label': 'Status',
          'type': 'select',
          'options': ['Open', 'Done']
        },
        {'name': 'notes', 'label': 'Notes', 'type': 'multiline'},
      ],
      'wantChart': false,
      'chartLabelField': 'status',
      'chartValueField': 'status',
    },
    'simple-tracker.json+chart': {
      'appName': 'Tracker With Chart',
      'itemName': 'Tasks',
      'fields': [
        {'name': 'name', 'label': 'Name', 'type': 'text'},
        {
          'name': 'category',
          'label': 'Category',
          'type': 'select',
          'options': ['A', 'B']
        },
      ],
      'wantChart': true,
      'chartLabelField': 'category',
      'chartValueField': 'category',
    },
    'survey.json': {
      'appName': 'Test Survey',
      'surveyTopic': 'Satisfaction',
      'fields': [
        {'name': 'name', 'label': 'Name', 'type': 'text'},
        {
          'name': 'rating',
          'label': 'Rating',
          'type': 'select',
          'options': ['1', '2', '3', '4', '5']
        },
        {'name': 'comments', 'label': 'Comments', 'type': 'multiline'},
      ],
      'chartField': 'rating',
    },
    'daily-log.json': {
      'appName': 'Test Journal',
      'entryName': 'Entry',
      'fields': [
        {'name': 'title', 'label': 'Title', 'type': 'text'},
        {'name': 'date', 'label': 'Date', 'type': 'date'},
        {
          'name': 'mood',
          'label': 'Mood',
          'type': 'select',
          'options': ['Great', 'OK', 'Bad']
        },
        {'name': 'content', 'label': 'Content', 'type': 'multiline'},
      ],
    },
    'scoreboard.json': {
      'appName': 'Test Scoreboard',
      'playerName': 'Player',
      'scoreName': 'Points',
      'wantCategories': true,
    },
    'scoreboard.json+nocat': {
      'appName': 'Simple Scoreboard',
      'playerName': 'Team',
      'scoreName': 'Wins',
      'wantCategories': false,
    },
    'quiz.json': {
      'appName': 'Test Quiz',
      'topic': 'Science',
      'wantProgress': true,
    },
    'quiz.json+noprogress': {
      'appName': 'Quick Quiz',
      'topic': 'Math',
      'wantProgress': false,
    },
    'inventory.json': {
      'appName': 'Test Inventory',
      'itemName': 'Supplies',
      'fields': [
        {'name': 'name', 'label': 'Name', 'type': 'text'},
        {'name': 'quantity', 'label': 'Quantity', 'type': 'number'},
        {'name': 'category', 'label': 'Category', 'type': 'select', 'options': ['Tools', 'Parts']},
        {'name': 'location', 'label': 'Location', 'type': 'text'},
      ],
      'wantChart': false,
      'chartField': 'category',
    },
    'approval.json': {
      'appName': 'Test Approvals',
      'requestName': 'Leave',
      'fields': [
        {'name': 'title', 'label': 'Title', 'type': 'text'},
        {'name': 'requestedBy', 'label': 'Requested By', 'type': 'text'},
        {'name': 'date', 'label': 'Date', 'type': 'date'},
        {'name': 'description', 'label': 'Description', 'type': 'multiline'},
      ],
      'wantChart': false,
    },
    'directory.json': {
      'appName': 'Test Directory',
      'entryName': 'Contact',
      'fields': [
        {'name': 'name', 'label': 'Name', 'type': 'text'},
        {'name': 'email', 'label': 'Email', 'type': 'email'},
        {'name': 'phone', 'label': 'Phone', 'type': 'text'},
        {'name': 'role', 'label': 'Role', 'type': 'text'},
      ],
    },
    'checklist.json': {
      'appName': 'Test Checklist',
      'checklistName': 'Safety Items',
      'fields': [
        {'name': 'itemName', 'label': 'Item Name', 'type': 'text'},
        {'name': 'result', 'label': 'Result', 'type': 'select', 'options': ['Pass', 'Fail', 'N/A']},
        {'name': 'inspector', 'label': 'Inspector', 'type': 'text'},
        {'name': 'date', 'label': 'Date', 'type': 'date'},
      ],
    },
    'master-detail.json': {
      'appName': 'Test Projects',
      'parentName': 'Project',
      'parentFields': [
        {'name': 'name', 'label': 'Name', 'type': 'text'},
        {'name': 'status', 'label': 'Status', 'type': 'select', 'options': ['Active', 'Complete']},
      ],
      'childName': 'Task',
      'childFields': [
        {'name': 'name', 'label': 'Name', 'type': 'text'},
        {'name': 'status', 'label': 'Status', 'type': 'select', 'options': ['To Do', 'Done']},
        {'name': 'dueDate', 'label': 'Due Date', 'type': 'date'},
      ],
    },
    'booking.json': {
      'appName': 'Test Bookings',
      'bookingName': 'Room',
      'fields': [
        {'name': 'name', 'label': 'Name', 'type': 'text'},
        {'name': 'date', 'label': 'Date', 'type': 'date'},
        {'name': 'time', 'label': 'Time', 'type': 'text'},
        {'name': 'attendees', 'label': 'Attendees', 'type': 'number'},
      ],
      'wantChart': false,
      'chartField': 'name',
    },
    'simple-checklist.json': {
      'appName': 'Grocery Lists',
      'listName': 'List',
      'itemName': 'Item',
      'fields': [
        {'name': 'category', 'label': 'Category', 'type': 'select', 'options': ['Produce', 'Dairy']},
        {'name': 'quantity', 'label': 'Quantity', 'type': 'number'},
      ],
    },
  };

  group('Template rendering produces valid ODS specs', () {
    for (final entry in testContexts.entries) {
      final fileName = entry.key.split('+').first; // Strip variant suffix
      final variantName = entry.key;
      final context = entry.value;

      final file = templateFiles
          .where((f) => f.uri.pathSegments.last == fileName)
          .firstOrNull;

      if (file == null) {
        test('SKIP: $fileName not found', () {});
        continue;
      }

      test('$variantName renders and parses', () {
        final templateJson =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final templateBody = templateJson['template'];

        // Render the template.
        final rendered = TemplateEngine.render(templateBody, context);
        expect(rendered, isA<Map<String, dynamic>>(),
            reason: '$variantName: render did not produce a Map');

        final specJson = jsonEncode(rendered);

        // Parse the rendered spec.
        final result = parser.parse(specJson);
        expect(result.parseError, isNull,
            reason:
                '$variantName parse error: ${result.parseError}');
        expect(result.validation.hasErrors, false,
            reason:
                '$variantName validation errors: ${result.validation.errors}');
        expect(result.app, isNotNull,
            reason: '$variantName produced null app');

        // Basic structure checks.
        final app = result.app!;
        expect(app.appName, context['appName']);
        expect(app.pages, isNotEmpty,
            reason: '$variantName has no pages');
        expect(app.pages.containsKey(app.startPage), true,
            reason:
                '$variantName: startPage "${app.startPage}" not in pages');

        // Every page must have a content list.
        for (final pageEntry in app.pages.entries) {
          expect(pageEntry.value.content, isA<List>(),
              reason:
                  '$variantName: ${pageEntry.key}.content is not a List');
        }
      });
    }
  });

  // ---------------------------------------------------------------------------
  // Structural validation: forms have fields, lists have columns, etc.
  // These tests would have caught the "empty addForm fields" bug.
  // ---------------------------------------------------------------------------

  group('Rendered templates have valid component structure', () {
    for (final entry in testContexts.entries) {
      final fileName = entry.key.split('+').first;
      final variantName = entry.key;
      final context = entry.value;

      final file = templateFiles
          .where((f) => f.uri.pathSegments.last == fileName)
          .firstOrNull;
      if (file == null) continue;

      test('$variantName: every form has non-empty fields', () {
        final templateJson =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final rendered = TemplateEngine.render(templateJson['template'], context)
            as Map<String, dynamic>;
        final result = parser.parse(jsonEncode(rendered));
        final app = result.app!;

        for (final pageEntry in app.pages.entries) {
          for (final comp in pageEntry.value.content) {
            if (comp is OdsFormComponent) {
              expect(comp.fields, isNotEmpty,
                  reason:
                      '$variantName: form "${comp.id}" on page "${pageEntry.key}" has empty fields');
            }
          }
        }
      });

      test('$variantName: every list has non-empty columns', () {
        final templateJson =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final rendered = TemplateEngine.render(templateJson['template'], context)
            as Map<String, dynamic>;
        final result = parser.parse(jsonEncode(rendered));
        final app = result.app!;

        for (final pageEntry in app.pages.entries) {
          _checkListColumns(pageEntry.value.content, variantName, pageEntry.key);
        }
      });

      test('$variantName: every dataSource reference resolves', () {
        final templateJson =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final rendered = TemplateEngine.render(templateJson['template'], context)
            as Map<String, dynamic>;
        final result = parser.parse(jsonEncode(rendered));
        final app = result.app!;
        final dsKeys = app.dataSources.keys.toSet();

        for (final pageEntry in app.pages.entries) {
          _checkDataSourceRefs(
              pageEntry.value.content, dsKeys, variantName, pageEntry.key);
        }
      });
    }
  });

  // ---------------------------------------------------------------------------
  // Template engine unit tests for $map with index and && conditions
  // ---------------------------------------------------------------------------

  group('TemplateEngine \$map with index variable', () {
    test('each(item, index) exposes named index variable', () {
      final template = {
        '\$map': 'items',
        'each(item, idx)': {
          'name': '\${item.name}',
          'position': '\${idx}',
        },
      };
      final context = {
        'items': [
          {'name': 'A'},
          {'name': 'B'},
        ],
      };
      final result = TemplateEngine.render(template, context) as List;
      expect(result.length, 2);
      expect(result[0]['position'], 0);
      expect(result[1]['position'], 1);
    });

    test('each(item, index) works in \$if conditions', () {
      final template = {
        '\$map': 'items',
        'each(item, index)': {
          '\$if': 'index == 0',
          'then': {'name': '\${item.name}', 'first': true},
          'else': {'name': '\${item.name}', 'first': false},
        },
      };
      final context = {
        'items': [
          {'name': 'A'},
          {'name': 'B'},
        ],
      };
      final result = TemplateEngine.render(template, context) as List;
      expect(result[0]['first'], true);
      expect(result[1]['first'], false);
    });
  });

  group('TemplateEngine && and || conditions', () {
    test('&& evaluates both sides', () {
      final template = {
        '\$if': "a == 'x' && b == 'y'",
        'then': 'yes',
        'else': 'no',
      };
      expect(TemplateEngine.render(template, {'a': 'x', 'b': 'y'}), 'yes');
      expect(TemplateEngine.render(template, {'a': 'x', 'b': 'z'}), 'no');
      expect(TemplateEngine.render(template, {'a': 'z', 'b': 'y'}), 'no');
    });

    test('|| evaluates either side', () {
      final template = {
        '\$if': "a == 'x' || b == 'y'",
        'then': 'yes',
        'else': 'no',
      };
      expect(TemplateEngine.render(template, {'a': 'x', 'b': 'z'}), 'yes');
      expect(TemplateEngine.render(template, {'a': 'z', 'b': 'y'}), 'yes');
      expect(TemplateEngine.render(template, {'a': 'z', 'b': 'z'}), 'no');
    });

    test('&& with type check and index (real template pattern)', () {
      final template = {
        '\$map': 'fields',
        'each(field, index)': {
          '\$if': "field.type == 'select' && index == 0",
          'then': {
            'header': '\${field.label}',
            'field': '\${field.name}',
            'filterable': true,
          },
          'else': {
            'header': '\${field.label}',
            'field': '\${field.name}',
          },
        },
      };
      final context = {
        'fields': [
          {'name': 'status', 'label': 'Status', 'type': 'select', 'options': ['A', 'B']},
          {'name': 'notes', 'label': 'Notes', 'type': 'text'},
        ],
      };
      final result = TemplateEngine.render(template, context) as List;
      expect(result[0]['filterable'], true,
          reason: 'First select field should be filterable');
      expect(result[1].containsKey('filterable'), false,
          reason: 'Second field should not be filterable');
    });
  });
}

/// Recursively checks that every OdsListComponent has non-empty columns.
void _checkListColumns(
    List<OdsComponent> components, String variant, String pageId) {
  for (final comp in components) {
    if (comp is OdsListComponent) {
      expect(comp.columns, isNotEmpty,
          reason: '$variant: list on page "$pageId" has empty columns');
    }
    if (comp is OdsTabsComponent) {
      for (final tab in comp.tabs) {
        _checkListColumns(tab.content, variant, '$pageId/${tab.label}');
      }
    }
  }
}

/// Recursively checks that every component referencing a dataSource uses a
/// valid key.
void _checkDataSourceRefs(List<OdsComponent> components, Set<String> dsKeys,
    String variant, String pageId) {
  for (final comp in components) {
    if (comp is OdsListComponent) {
      expect(dsKeys, contains(comp.dataSource),
          reason:
              '$variant: list on page "$pageId" references unknown dataSource "${comp.dataSource}"');
    }
    // Summary components reference dataSources indirectly via aggregate
    // expressions in the value string — no direct field to check here.
    if (comp is OdsTabsComponent) {
      for (final tab in comp.tabs) {
        _checkDataSourceRefs(tab.content, dsKeys, variant, '$pageId/${tab.label}');
      }
    }
  }
}

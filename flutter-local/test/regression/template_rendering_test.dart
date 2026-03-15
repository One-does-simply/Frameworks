import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/engine/template_engine.dart';
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
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/models/ods_help.dart';

void main() {
  // =========================================================================
  // OdsHelp.fromJson
  // =========================================================================

  group('OdsHelp.fromJson', () {
    test('valid help with overview and pages', () {
      final help = OdsHelp.fromJson({
        'overview': 'Welcome to the app.',
        'pages': {
          'home': 'This is the home page.',
          'settings': 'Configure your preferences here.',
        },
      });
      expect(help.overview, 'Welcome to the app.');
      expect(help.pages, hasLength(2));
      expect(help.pages['home'], 'This is the home page.');
      expect(help.pages['settings'], 'Configure your preferences here.');
    });

    test('missing pages defaults to empty map', () {
      final help = OdsHelp.fromJson({
        'overview': 'An app with no page help.',
      });
      expect(help.pages, isEmpty);
    });
  });

  // =========================================================================
  // OdsTourStep.fromJson
  // =========================================================================

  group('OdsTourStep.fromJson', () {
    test('all fields including page', () {
      final step = OdsTourStep.fromJson({
        'title': 'Getting Started',
        'content': 'Here is how you begin.',
        'page': 'page_intro',
      });
      expect(step.title, 'Getting Started');
      expect(step.content, 'Here is how you begin.');
      expect(step.page, 'page_intro');
    });

    test('missing page is null', () {
      final step = OdsTourStep.fromJson({
        'title': 'Final Notes',
        'content': 'That is everything you need to know.',
      });
      expect(step.title, 'Final Notes');
      expect(step.content, 'That is everything you need to know.');
      expect(step.page, isNull);
    });
  });
}

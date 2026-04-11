import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/models/ods_visible_when.dart';

void main() {
  // =========================================================================
  // fromJson
  // =========================================================================

  group('OdsComponentVisibleWhen.fromJson', () {
    test('parses field-based condition with equals', () {
      final vw = OdsComponentVisibleWhen.fromJson({
        'field': 'type',
        'form': 'myForm',
        'equals': 'Other',
      });
      expect(vw.field, 'type');
      expect(vw.form, 'myForm');
      expect(vw.equals, 'Other');
      expect(vw.notEquals, isNull);
      expect(vw.source, isNull);
    });

    test('parses field-based condition with notEquals', () {
      final vw = OdsComponentVisibleWhen.fromJson({
        'field': 'status',
        'form': 'taskForm',
        'notEquals': 'completed',
      });
      expect(vw.field, 'status');
      expect(vw.form, 'taskForm');
      expect(vw.notEquals, 'completed');
      expect(vw.equals, isNull);
    });

    test('parses data-based condition', () {
      final vw = OdsComponentVisibleWhen.fromJson({
        'source': 'quiz_answers',
        'countEquals': 10,
        'countMin': 5,
        'countMax': 20,
      });
      expect(vw.source, 'quiz_answers');
      expect(vw.countEquals, 10);
      expect(vw.countMin, 5);
      expect(vw.countMax, 20);
      expect(vw.field, isNull);
      expect(vw.form, isNull);
    });

    test('all fields null by default', () {
      final vw = OdsComponentVisibleWhen.fromJson({});
      expect(vw.field, isNull);
      expect(vw.form, isNull);
      expect(vw.equals, isNull);
      expect(vw.notEquals, isNull);
      expect(vw.source, isNull);
      expect(vw.countEquals, isNull);
      expect(vw.countMin, isNull);
      expect(vw.countMax, isNull);
    });
  });

  // =========================================================================
  // isFieldBased
  // =========================================================================

  group('isFieldBased', () {
    test('returns true when field AND form are set', () {
      final vw = OdsComponentVisibleWhen.fromJson({
        'field': 'category',
        'form': 'mainForm',
        'equals': 'premium',
      });
      expect(vw.isFieldBased, isTrue);
    });

    test('returns false when only field is set', () {
      final vw = OdsComponentVisibleWhen.fromJson({
        'field': 'category',
      });
      expect(vw.isFieldBased, isFalse);
    });

    test('returns false when only form is set', () {
      final vw = OdsComponentVisibleWhen.fromJson({
        'form': 'mainForm',
      });
      expect(vw.isFieldBased, isFalse);
    });
  });

  // =========================================================================
  // isDataBased
  // =========================================================================

  group('isDataBased', () {
    test('returns true when source is set', () {
      final vw = OdsComponentVisibleWhen.fromJson({
        'source': 'answers',
        'countMin': 1,
      });
      expect(vw.isDataBased, isTrue);
    });

    test('returns false when source is null', () {
      final vw = OdsComponentVisibleWhen.fromJson({
        'field': 'type',
        'form': 'myForm',
      });
      expect(vw.isDataBased, isFalse);
    });
  });
}

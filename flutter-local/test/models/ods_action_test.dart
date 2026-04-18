import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/models/ods_action.dart';

void main() {
  // =========================================================================
  // OdsAction.fromJson
  // =========================================================================

  group('OdsAction.fromJson', () {
    test('minimal action with just action type', () {
      final a = OdsAction.fromJson({'action': 'navigate'});
      expect(a.action, 'navigate');
      expect(a.target, isNull);
      expect(a.dataSource, isNull);
      expect(a.matchField, isNull);
      expect(a.populateForm, isNull);
      expect(a.withData, isNull);
      expect(a.confirm, isNull);
      expect(a.message, isNull);
      expect(a.filter, isNull);
      expect(a.onEnd, isNull);
      expect(a.cascade, isNull);
      expect(a.computedFields, isEmpty);
      expect(a.preserveFields, isEmpty);
    });

    test('full action with all fields', () {
      final a = OdsAction.fromJson({
        'action': 'submit',
        'target': 'myForm',
        'dataSource': 'postItems',
        'matchField': 'id',
        'populateForm': 'editForm',
        'withData': {'name': '{itemName}'},
        'confirm': 'Are you sure?',
        'message': 'Saved successfully',
      });
      expect(a.action, 'submit');
      expect(a.target, 'myForm');
      expect(a.dataSource, 'postItems');
      expect(a.matchField, 'id');
      expect(a.populateForm, 'editForm');
      expect(a.withData, {'name': '{itemName}'});
      expect(a.confirm, 'Are you sure?');
      expect(a.message, 'Saved successfully');
    });

    test('action with computedFields list', () {
      final a = OdsAction.fromJson({
        'action': 'submit',
        'computedFields': [
          {'field': 'score', 'expression': '{answer} == {correct} ? \'1\' : \'0\''},
          {'field': 'timestamp', 'expression': 'NOW'},
        ],
      });
      expect(a.computedFields, hasLength(2));
      expect(a.computedFields[0].field, 'score');
      expect(a.computedFields[0].expression, '{answer} == {correct} ? \'1\' : \'0\'');
      expect(a.computedFields[1].field, 'timestamp');
      expect(a.computedFields[1].expression, 'NOW');
    });

    test('action with nested onEnd action (recursive)', () {
      final a = OdsAction.fromJson({
        'action': 'nextRecord',
        'target': 'quizForm',
        'onEnd': {
          'action': 'navigate',
          'target': 'resultsPage',
        },
      });
      expect(a.action, 'nextRecord');
      expect(a.onEnd, isNotNull);
      expect(a.onEnd!.action, 'navigate');
      expect(a.onEnd!.target, 'resultsPage');
    });

    test('action with filter and cascade maps (legacy flat-key converted)',
        () {
      // Legacy flat-key cascade form is converted to the React-aligned
      // nested form {childDsId: fieldName} for forward compatibility.
      final a = OdsAction.fromJson({
        'action': 'firstRecord',
        'target': 'quizForm',
        'filter': {'listId': '{selectedList}'},
        'cascade': {
          'childDataSource': 'childItems',
          'childLinkField': 'parentName',
        },
      });
      expect(a.filter, {'listId': '{selectedList}'});
      expect(a.cascade, {'childItems': 'parentName'});
    });

    test('action with React-style nested cascade map', () {
      final a = OdsAction.fromJson({
        'action': 'update',
        'target': 'c1',
        'cascade': {
          'tasks': 'category',
          'notes': 'cat',
        },
      });
      expect(a.cascade, {'tasks': 'category', 'notes': 'cat'});
    });

    test('action with preserveFields', () {
      final a = OdsAction.fromJson({
        'action': 'submit',
        'target': 'addItemForm',
        'preserveFields': ['listName', 'category'],
      });
      expect(a.preserveFields, ['listName', 'category']);
    });
  });

  // =========================================================================
  // Type guards
  // =========================================================================

  group('type guards', () {
    test('isNavigate', () {
      final a = OdsAction.fromJson({'action': 'navigate'});
      expect(a.isNavigate, isTrue);
      expect(a.isSubmit, isFalse);
      expect(a.isUpdate, isFalse);
      expect(a.isShowMessage, isFalse);
      expect(a.isRecordAction, isFalse);
    });

    test('isSubmit', () {
      final a = OdsAction.fromJson({'action': 'submit'});
      expect(a.isSubmit, isTrue);
      expect(a.isNavigate, isFalse);
    });

    test('isUpdate', () {
      final a = OdsAction.fromJson({'action': 'update'});
      expect(a.isUpdate, isTrue);
      expect(a.isNavigate, isFalse);
    });

    test('isShowMessage', () {
      final a = OdsAction.fromJson({'action': 'showMessage'});
      expect(a.isShowMessage, isTrue);
      expect(a.isNavigate, isFalse);
    });

    test('isRecordAction for firstRecord', () {
      final a = OdsAction.fromJson({'action': 'firstRecord'});
      expect(a.isRecordAction, isTrue);
    });

    test('isRecordAction for nextRecord', () {
      final a = OdsAction.fromJson({'action': 'nextRecord'});
      expect(a.isRecordAction, isTrue);
    });

    test('isRecordAction for previousRecord', () {
      final a = OdsAction.fromJson({'action': 'previousRecord'});
      expect(a.isRecordAction, isTrue);
    });

    test('isRecordAction for lastRecord', () {
      final a = OdsAction.fromJson({'action': 'lastRecord'});
      expect(a.isRecordAction, isTrue);
    });
  });

  // =========================================================================
  // OdsComputedField.fromJson
  // =========================================================================

  group('OdsComputedField.fromJson', () {
    test('parses field and expression', () {
      final cf = OdsComputedField.fromJson({
        'field': 'total',
        'expression': '{quantity} * {unitPrice}',
      });
      expect(cf.field, 'total');
      expect(cf.expression, '{quantity} * {unitPrice}');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/models/ods_data_source.dart';

void main() {
  // =========================================================================
  // fromJson
  // =========================================================================

  group('OdsDataSource.fromJson', () {
    test('parses local:// URL and method', () {
      final ds = OdsDataSource.fromJson({
        'url': 'local://tasks',
        'method': 'GET',
      });
      expect(ds.url, 'local://tasks');
      expect(ds.method, 'GET');
    });

    test('parses external http URL', () {
      final ds = OdsDataSource.fromJson({
        'url': 'https://api.example.com/items',
        'method': 'POST',
      });
      expect(ds.url, 'https://api.example.com/items');
      expect(ds.method, 'POST');
    });

    test('parses with fields array', () {
      final ds = OdsDataSource.fromJson({
        'url': 'local://products',
        'method': 'POST',
        'fields': [
          {'name': 'title', 'type': 'text'},
          {'name': 'price', 'type': 'number'},
        ],
      });
      expect(ds.fields, isNotNull);
      expect(ds.fields, hasLength(2));
      expect(ds.fields![0].name, 'title');
      expect(ds.fields![1].name, 'price');
    });

    test('parses with seedData', () {
      final ds = OdsDataSource.fromJson({
        'url': 'local://categories',
        'method': 'GET',
        'seedData': [
          {'name': 'Work', 'color': 'blue'},
          {'name': 'Personal', 'color': 'green'},
        ],
      });
      expect(ds.seedData, isNotNull);
      expect(ds.seedData, hasLength(2));
      expect(ds.seedData![0]['name'], 'Work');
      expect(ds.seedData![1]['color'], 'green');
    });

    test('parses with ownership config', () {
      final ds = OdsDataSource.fromJson({
        'url': 'local://notes',
        'method': 'GET',
        'ownership': {
          'enabled': true,
          'ownerField': 'createdBy',
          'adminOverride': false,
        },
      });
      expect(ds.ownership.enabled, isTrue);
      expect(ds.ownership.ownerField, 'createdBy');
      expect(ds.ownership.adminOverride, isFalse);
    });

    test('default ownership when not provided', () {
      final ds = OdsDataSource.fromJson({
        'url': 'local://items',
        'method': 'GET',
      });
      expect(ds.ownership.enabled, isFalse);
      expect(ds.ownership.ownerField, '_owner');
      expect(ds.ownership.adminOverride, isTrue);
    });
  });

  // =========================================================================
  // isLocal
  // =========================================================================

  group('isLocal', () {
    test('returns true for local:// URL', () {
      final ds = OdsDataSource.fromJson({
        'url': 'local://myTable',
        'method': 'GET',
      });
      expect(ds.isLocal, isTrue);
    });

    test('returns false for http:// URL', () {
      final ds = OdsDataSource.fromJson({
        'url': 'https://api.example.com/data',
        'method': 'GET',
      });
      expect(ds.isLocal, isFalse);
    });
  });

  // =========================================================================
  // tableName
  // =========================================================================

  group('tableName', () {
    test('extracts name from local://tableName', () {
      final ds = OdsDataSource.fromJson({
        'url': 'local://quizAnswers',
        'method': 'POST',
      });
      expect(ds.tableName, 'quizAnswers');
    });

    test('returns empty string for non-local sources', () {
      final ds = OdsDataSource.fromJson({
        'url': 'https://api.example.com/data',
        'method': 'GET',
      });
      expect(ds.tableName, '');
    });
  });
}

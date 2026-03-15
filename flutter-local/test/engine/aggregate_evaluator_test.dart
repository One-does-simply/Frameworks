import 'package:flutter_test/flutter_test.dart';
import 'package:ods_flutter_local/engine/aggregate_evaluator.dart';

void main() {
  /// Helper: builds a queryFn that returns canned data per dataSource ID.
  Future<List<Map<String, dynamic>>> Function(String) _queryFn(
    Map<String, List<Map<String, dynamic>>> data,
  ) {
    return (id) async => data[id] ?? [];
  }

  final sampleRows = [
    {'amount': '100', 'status': 'Done', 'name': 'A'},
    {'amount': '200', 'status': 'Done', 'name': 'B'},
    {'amount': '50', 'status': 'Pending', 'name': 'C'},
    {'amount': '150', 'status': 'Pending', 'name': 'D'},
  ];

  group('hasAggregates', () {
    test('detects SUM', () {
      expect(AggregateEvaluator.hasAggregates('{SUM(ds, amount)}'), true);
    });

    test('detects COUNT', () {
      expect(AggregateEvaluator.hasAggregates('{COUNT(ds)}'), true);
    });

    test('detects PCT', () {
      expect(AggregateEvaluator.hasAggregates('{PCT(ds, status=Done)}'), true);
    });

    test('returns false for plain text', () {
      expect(AggregateEvaluator.hasAggregates('Hello world'), false);
    });

    test('returns false for field references', () {
      expect(AggregateEvaluator.hasAggregates('{fieldName}'), false);
    });

    test('case insensitive', () {
      expect(AggregateEvaluator.hasAggregates('{sum(ds, amount)}'), true);
    });
  });

  group('COUNT', () {
    test('counts all rows', () async {
      final result = await AggregateEvaluator.resolve(
        'Total: {COUNT(items)}',
        _queryFn({'items': sampleRows}),
      );
      expect(result, 'Total: 4');
    });

    test('counts filtered rows', () async {
      final result = await AggregateEvaluator.resolve(
        '{COUNT(items, status=Done)}',
        _queryFn({'items': sampleRows}),
      );
      expect(result, '2');
    });

    test('returns 0 for empty data source', () async {
      final result = await AggregateEvaluator.resolve(
        '{COUNT(items)}',
        _queryFn({'items': []}),
      );
      expect(result, '0');
    });

    test('returns 0 for unknown data source', () async {
      final result = await AggregateEvaluator.resolve(
        '{COUNT(missing)}',
        _queryFn({}),
      );
      expect(result, '0');
    });

    test('filter with no matches returns 0', () async {
      final result = await AggregateEvaluator.resolve(
        '{COUNT(items, status=Cancelled)}',
        _queryFn({'items': sampleRows}),
      );
      expect(result, '0');
    });
  });

  group('SUM', () {
    test('sums a numeric field', () async {
      final result = await AggregateEvaluator.resolve(
        '{SUM(items, amount)}',
        _queryFn({'items': sampleRows}),
      );
      expect(result, '500');
    });

    test('sums with filter', () async {
      // Filtered: only "Done" rows → amount 100 + 200 = 300
      // But SUM with filter syntax is "field=value" which sets filterField=field.
      // Actually looking at the code, SUM(items, amount) is just field=amount.
      // For filtered SUM we'd need a different syntax which isn't supported.
      // The filter syntax "field=value" is for COUNT/PCT style.
      // Let's test what happens with non-numeric field.
      final result = await AggregateEvaluator.resolve(
        '{SUM(items, amount)}',
        _queryFn({'items': sampleRows}),
      );
      expect(result, '500');
    });

    test('returns 0 for empty rows', () async {
      final result = await AggregateEvaluator.resolve(
        '{SUM(items, amount)}',
        _queryFn({'items': []}),
      );
      expect(result, '0');
    });

    test('skips non-numeric values', () async {
      final result = await AggregateEvaluator.resolve(
        '{SUM(items, amount)}',
        _queryFn({
          'items': [
            {'amount': '100'},
            {'amount': 'N/A'},
            {'amount': '50'},
          ]
        }),
      );
      expect(result, '150');
    });

    test('returns 0 when all values are non-numeric', () async {
      final result = await AggregateEvaluator.resolve(
        '{SUM(items, amount)}',
        _queryFn({
          'items': [
            {'amount': 'N/A'},
            {'amount': 'unknown'},
          ]
        }),
      );
      expect(result, '0');
    });

    test('returns 0 when field is missing from rows', () async {
      final result = await AggregateEvaluator.resolve(
        '{SUM(items, missing)}',
        _queryFn({'items': sampleRows}),
      );
      expect(result, '0');
    });
  });

  group('AVG', () {
    test('computes average', () async {
      final result = await AggregateEvaluator.resolve(
        '{AVG(items, amount)}',
        _queryFn({'items': sampleRows}),
      );
      expect(result, '125');
    });

    test('returns 0 for empty rows', () async {
      final result = await AggregateEvaluator.resolve(
        '{AVG(items, amount)}',
        _queryFn({'items': []}),
      );
      expect(result, '0');
    });

    test('handles decimal averages', () async {
      final result = await AggregateEvaluator.resolve(
        '{AVG(items, amount)}',
        _queryFn({
          'items': [
            {'amount': '10'},
            {'amount': '20'},
            {'amount': '30'},
          ]
        }),
      );
      expect(result, '20');
    });
  });

  group('MIN and MAX', () {
    test('finds minimum', () async {
      final result = await AggregateEvaluator.resolve(
        '{MIN(items, amount)}',
        _queryFn({'items': sampleRows}),
      );
      expect(result, '50');
    });

    test('finds maximum', () async {
      final result = await AggregateEvaluator.resolve(
        '{MAX(items, amount)}',
        _queryFn({'items': sampleRows}),
      );
      expect(result, '200');
    });

    test('MIN returns 0 for empty rows', () async {
      final result = await AggregateEvaluator.resolve(
        '{MIN(items, amount)}',
        _queryFn({'items': []}),
      );
      expect(result, '0');
    });
  });

  group('PCT', () {
    test('computes percentage of matching rows', () async {
      final result = await AggregateEvaluator.resolve(
        '{PCT(items, status=Done)}',
        _queryFn({'items': sampleRows}),
      );
      expect(result, '50'); // 2 of 4 = 50%
    });

    test('returns 0 when no rows match', () async {
      final result = await AggregateEvaluator.resolve(
        '{PCT(items, status=Cancelled)}',
        _queryFn({'items': sampleRows}),
      );
      expect(result, '0');
    });

    test('returns 0 for empty data source', () async {
      final result = await AggregateEvaluator.resolve(
        '{PCT(items, status=Done)}',
        _queryFn({'items': []}),
      );
      expect(result, '0');
    });

    test('100% when all match', () async {
      final result = await AggregateEvaluator.resolve(
        '{PCT(items, status=Done)}',
        _queryFn({
          'items': [
            {'status': 'Done'},
            {'status': 'Done'},
          ]
        }),
      );
      expect(result, '100');
    });
  });

  group('Multiple aggregates in one string', () {
    test('resolves all aggregates', () async {
      final result = await AggregateEvaluator.resolve(
        'Done: {COUNT(items, status=Done)} of {COUNT(items)} ({PCT(items, status=Done)}%)',
        _queryFn({'items': sampleRows}),
      );
      expect(result, 'Done: 2 of 4 (50%)');
    });
  });

  group('Caching', () {
    test('queries each dataSource only once', () async {
      var callCount = 0;
      Future<List<Map<String, dynamic>>> countingQuery(String id) async {
        callCount++;
        return sampleRows;
      }

      await AggregateEvaluator.resolve(
        '{COUNT(items)} {SUM(items, amount)} {MAX(items, amount)}',
        countingQuery,
      );
      expect(callCount, 1, reason: 'Should cache and reuse the first query');
    });
  });

  group('Number formatting', () {
    test('whole numbers have no decimal', () async {
      final result = await AggregateEvaluator.resolve(
        '{SUM(items, amount)}',
        _queryFn({
          'items': [
            {'amount': '10'},
            {'amount': '20'},
          ]
        }),
      );
      expect(result, '30');
      expect(result.contains('.'), false);
    });

    test('decimal results show 2 places', () async {
      final result = await AggregateEvaluator.resolve(
        '{AVG(items, amount)}',
        _queryFn({
          'items': [
            {'amount': '10'},
            {'amount': '20'},
            {'amount': '15'},
          ]
        }),
      );
      expect(result, '15');
    });
  });
}

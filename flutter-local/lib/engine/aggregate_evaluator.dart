/// Evaluates aggregate expressions in text content strings.
///
/// ODS Spec: Text components can include aggregate references like
/// `{SUM(expenses, amount)}` or `{COUNT(quiz_answers, correct=1)}`.
/// These are resolved at runtime by querying the data source and
/// computing the aggregate value.
///
/// Supported functions: SUM, COUNT, AVG, MIN, MAX, PCT
/// Syntax variants:
///   - `{FUNC(dataSourceId, field)}` — aggregate a field across all rows
///   - `{FUNC(dataSourceId)}` — COUNT all rows (no field needed)
///   - `{FUNC(dataSourceId, field=value)}` — filtered aggregate
///   - `{PCT(dataSourceId, field=value)}` — percentage of rows matching filter
class AggregateEvaluator {
  /// Matches aggregate function calls in text content.
  /// Groups: 1=function, 2=dataSourceId, 3=optional remainder (field or field=value)
  static final _aggregatePattern = RegExp(
    r'\{(SUM|COUNT|AVG|MIN|MAX|PCT)\((\w+)(?:,\s*(.+?))?\)\}',
    caseSensitive: false,
  );

  /// Returns true if the content contains any aggregate references.
  static bool hasAggregates(String content) {
    return _aggregatePattern.hasMatch(content);
  }

  /// Resolves all aggregate references in [content] using [queryFn] to
  /// fetch rows from data sources.
  ///
  /// Returns the content string with all `{FUNC(...)}` replaced by
  /// computed values.
  static Future<String> resolve(
    String content,
    Future<List<Map<String, dynamic>>> Function(String dataSourceId) queryFn,
  ) async {
    // Collect all matches and their replacements.
    final matches = _aggregatePattern.allMatches(content).toList();
    if (matches.isEmpty) return content;

    // Cache data source queries to avoid duplicate fetches.
    final cache = <String, List<Map<String, dynamic>>>{};

    var result = content;
    // Process matches in reverse order to preserve string indices.
    for (final match in matches.reversed) {
      final func = match.group(1)!.toUpperCase();
      final dataSourceId = match.group(2)!;
      final remainder = match.group(3)?.trim();

      // Parse remainder: could be "field", "field=value", or null.
      String? field;
      String? filterField;
      String? filterValue;

      if (remainder != null) {
        final eqIndex = remainder.indexOf('=');
        if (eqIndex > 0) {
          filterField = remainder.substring(0, eqIndex).trim();
          filterValue = remainder.substring(eqIndex + 1).trim();
          // For filtered COUNT, the filter field is also the field.
          field = filterField;
        } else {
          field = remainder;
        }
      }

      // Fetch rows (with caching).
      cache[dataSourceId] ??= await queryFn(dataSourceId);
      var rows = cache[dataSourceId]!;

      // Apply filter if specified.
      if (filterField != null && filterValue != null) {
        rows = rows.where((row) {
          final val = row[filterField]?.toString() ?? '';
          return val == filterValue;
        }).toList();
      }

      // Compute aggregate.
      String value;
      if (func == 'PCT') {
        // PCT needs the total (unfiltered) row count.
        final allRows = cache[dataSourceId]!;
        if (allRows.isEmpty) {
          value = '0';
        } else {
          value = _formatNumber((rows.length / allRows.length) * 100);
        }
      } else {
        value = _compute(func, rows, field);
      }
      result = result.replaceRange(match.start, match.end, value);
    }

    return result;
  }

  /// Computes a single aggregate function over a list of [rows].
  ///
  /// For COUNT, returns the row count (ignores [field]).
  /// For SUM/AVG/MIN/MAX, extracts numeric values from [field] in each row,
  /// skipping non-numeric values. Returns '0' if no numeric values are found.
  static String _compute(
    String func,
    List<Map<String, dynamic>> rows,
    String? field,
  ) {
    if (func == 'COUNT') {
      return rows.length.toString();
    }

    if (field == null || rows.isEmpty) return '0';

    // Extract numeric values for the field.
    final values = <double>[];
    for (final row in rows) {
      final raw = row[field]?.toString() ?? '';
      final num = double.tryParse(raw);
      if (num != null) values.add(num);
    }

    if (values.isEmpty) return '0';

    switch (func) {
      case 'SUM':
        final sum = values.fold(0.0, (a, b) => a + b);
        return _formatNumber(sum);
      case 'AVG':
        final avg = values.fold(0.0, (a, b) => a + b) / values.length;
        return _formatNumber(avg);
      case 'MIN':
        final min = values.reduce((a, b) => a < b ? a : b);
        return _formatNumber(min);
      case 'MAX':
        final max = values.reduce((a, b) => a > b ? a : b);
        return _formatNumber(max);
      default:
        return '0';
    }
  }

  /// Formats a number: drop trailing decimals if it's a whole number.
  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }
}

/**
 * Evaluates aggregate expressions in text content strings.
 *
 * ODS Spec: Text components can include aggregate references like
 * `{SUM(expenses, amount)}` or `{COUNT(quiz_answers, correct=1)}`.
 * These are resolved at runtime by querying the data source and
 * computing the aggregate value.
 *
 * Supported functions: SUM, COUNT, AVG, MIN, MAX, PCT
 * Syntax variants:
 *   - `{FUNC(dataSourceId, field)}` -- aggregate a field across all rows
 *   - `{FUNC(dataSourceId)}` -- COUNT all rows (no field needed)
 *   - `{FUNC(dataSourceId, field=value)}` -- filtered aggregate
 *   - `{PCT(dataSourceId, field=value)}` -- percentage of rows matching filter
 */

/** Matches aggregate function calls in text content. */
const AGGREGATE_PATTERN =
  /\{(SUM|COUNT|AVG|MIN|MAX|PCT)\((\w+)(?:,\s*(.+?))?\)\}/gi;

/** Type for the query function that fetches rows from a data source. */
export type QueryFn = (
  dataSourceId: string,
) => Promise<Record<string, unknown>[]>;

/** Returns true if the content contains any aggregate references. */
export function hasAggregates(content: string): boolean {
  return new RegExp(AGGREGATE_PATTERN.source, 'gi').test(content);
}

/**
 * Resolves all aggregate references in content using queryFn to
 * fetch rows from data sources.
 *
 * Returns the content string with all `{FUNC(...)}` replaced by
 * computed values.
 */
export async function resolveAggregates(
  content: string,
  queryFn: QueryFn,
): Promise<string> {
  // Collect all matches and their positions.
  const re = new RegExp(AGGREGATE_PATTERN.source, 'gi');
  const matches: { start: number; end: number; func: string; dsId: string; remainder: string | undefined }[] = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(content)) !== null) {
    matches.push({
      start: m.index,
      end: m.index + m[0].length,
      func: m[1].toUpperCase(),
      dsId: m[2],
      remainder: m[3]?.trim(),
    });
  }

  if (matches.length === 0) return content;

  // Cache data source queries to avoid duplicate fetches.
  const cache: Record<string, Record<string, unknown>[]> = {};

  let result = content;
  // Process matches in reverse order to preserve string indices.
  for (let i = matches.length - 1; i >= 0; i--) {
    const { start, end, func, dsId, remainder } = matches[i];

    // Parse remainder: could be "field", "field=value", or undefined.
    let field: string | undefined;
    let filterField: string | undefined;
    let filterValue: string | undefined;

    if (remainder !== undefined) {
      const eqIndex = remainder.indexOf('=');
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
    if (!(dsId in cache)) {
      cache[dsId] = await queryFn(dsId);
    }
    let rows = cache[dsId];

    // Apply filter if specified.
    if (filterField !== undefined && filterValue !== undefined) {
      rows = rows.filter((row) => {
        const val = row[filterField!] != null ? String(row[filterField!]) : '';
        return val === filterValue;
      });
    }

    // Compute aggregate.
    let value: string;
    if (func === 'PCT') {
      // PCT needs the total (unfiltered) row count.
      const allRows = cache[dsId];
      if (allRows.length === 0) {
        value = '0';
      } else {
        value = formatNumber((rows.length / allRows.length) * 100);
      }
    } else {
      value = compute(func, rows, field);
    }
    result = result.substring(0, start) + value + result.substring(end);
  }

  return result;
}

/**
 * Computes a single aggregate function over a list of rows.
 *
 * For COUNT, returns the row count (ignores field).
 * For SUM/AVG/MIN/MAX, extracts numeric values from field in each row,
 * skipping non-numeric values. Returns '0' if no numeric values are found.
 */
function compute(
  func: string,
  rows: Record<string, unknown>[],
  field: string | undefined,
): string {
  if (func === 'COUNT') {
    return rows.length.toString();
  }

  if (field === undefined || rows.length === 0) return '0';

  // Extract numeric values for the field.
  const values: number[] = [];
  for (const row of rows) {
    const raw = row[field] != null ? String(row[field]) : '';
    const num = Number(raw);
    if (raw !== '' && !isNaN(num)) {
      values.push(num);
    }
  }

  if (values.length === 0) return '0';

  switch (func) {
    case 'SUM': {
      const sum = values.reduce((a, b) => a + b, 0);
      return formatNumber(sum);
    }
    case 'AVG': {
      const avg = values.reduce((a, b) => a + b, 0) / values.length;
      return formatNumber(avg);
    }
    case 'MIN': {
      const min = values.reduce((a, b) => (a < b ? a : b));
      return formatNumber(min);
    }
    case 'MAX': {
      const max = values.reduce((a, b) => (a > b ? a : b));
      return formatNumber(max);
    }
    default:
      return '0';
  }
}

/** Formats a number: drop trailing decimals if it's a whole number. */
function formatNumber(value: number): string {
  if (value === Math.round(value)) {
    return Math.round(value).toString();
  }
  return value.toFixed(2);
}

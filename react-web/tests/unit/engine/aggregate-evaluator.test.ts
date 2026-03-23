import { describe, it, expect } from 'vitest';
import { hasAggregates, resolveAggregates, type QueryFn } from '../../../src/engine/aggregate-evaluator.ts';

/** Helper: builds a queryFn that returns canned data per dataSource ID. */
function makeQueryFn(
  data: Record<string, Record<string, unknown>[]>,
): QueryFn {
  return async (id: string) => data[id] ?? [];
}

const sampleRows: Record<string, unknown>[] = [
  { amount: '100', status: 'Done', name: 'A' },
  { amount: '200', status: 'Done', name: 'B' },
  { amount: '50', status: 'Pending', name: 'C' },
  { amount: '150', status: 'Pending', name: 'D' },
];

describe('hasAggregates', () => {
  it('detects SUM', () => {
    expect(hasAggregates('{SUM(ds, amount)}')).toBe(true);
  });

  it('detects COUNT', () => {
    expect(hasAggregates('{COUNT(ds)}')).toBe(true);
  });

  it('detects PCT', () => {
    expect(hasAggregates('{PCT(ds, status=Done)}')).toBe(true);
  });

  it('returns false for plain text', () => {
    expect(hasAggregates('Hello world')).toBe(false);
  });

  it('returns false for field references', () => {
    expect(hasAggregates('{fieldName}')).toBe(false);
  });

  it('case insensitive', () => {
    expect(hasAggregates('{sum(ds, amount)}')).toBe(true);
  });
});

describe('COUNT', () => {
  it('counts all rows', async () => {
    const result = await resolveAggregates(
      'Total: {COUNT(items)}',
      makeQueryFn({ items: sampleRows }),
    );
    expect(result).toBe('Total: 4');
  });

  it('counts filtered rows', async () => {
    const result = await resolveAggregates(
      '{COUNT(items, status=Done)}',
      makeQueryFn({ items: sampleRows }),
    );
    expect(result).toBe('2');
  });

  it('returns 0 for empty data source', async () => {
    const result = await resolveAggregates(
      '{COUNT(items)}',
      makeQueryFn({ items: [] }),
    );
    expect(result).toBe('0');
  });

  it('returns 0 for unknown data source', async () => {
    const result = await resolveAggregates(
      '{COUNT(missing)}',
      makeQueryFn({}),
    );
    expect(result).toBe('0');
  });

  it('filter with no matches returns 0', async () => {
    const result = await resolveAggregates(
      '{COUNT(items, status=Cancelled)}',
      makeQueryFn({ items: sampleRows }),
    );
    expect(result).toBe('0');
  });
});

describe('SUM', () => {
  it('sums a numeric field', async () => {
    const result = await resolveAggregates(
      '{SUM(items, amount)}',
      makeQueryFn({ items: sampleRows }),
    );
    expect(result).toBe('500');
  });

  it('sums with filter (all rows)', async () => {
    const result = await resolveAggregates(
      '{SUM(items, amount)}',
      makeQueryFn({ items: sampleRows }),
    );
    expect(result).toBe('500');
  });

  it('returns 0 for empty rows', async () => {
    const result = await resolveAggregates(
      '{SUM(items, amount)}',
      makeQueryFn({ items: [] }),
    );
    expect(result).toBe('0');
  });

  it('skips non-numeric values', async () => {
    const result = await resolveAggregates(
      '{SUM(items, amount)}',
      makeQueryFn({
        items: [
          { amount: '100' },
          { amount: 'N/A' },
          { amount: '50' },
        ],
      }),
    );
    expect(result).toBe('150');
  });

  it('returns 0 when all values are non-numeric', async () => {
    const result = await resolveAggregates(
      '{SUM(items, amount)}',
      makeQueryFn({
        items: [
          { amount: 'N/A' },
          { amount: 'unknown' },
        ],
      }),
    );
    expect(result).toBe('0');
  });

  it('returns 0 when field is missing from rows', async () => {
    const result = await resolveAggregates(
      '{SUM(items, missing)}',
      makeQueryFn({ items: sampleRows }),
    );
    expect(result).toBe('0');
  });
});

describe('AVG', () => {
  it('computes average', async () => {
    const result = await resolveAggregates(
      '{AVG(items, amount)}',
      makeQueryFn({ items: sampleRows }),
    );
    expect(result).toBe('125');
  });

  it('returns 0 for empty rows', async () => {
    const result = await resolveAggregates(
      '{AVG(items, amount)}',
      makeQueryFn({ items: [] }),
    );
    expect(result).toBe('0');
  });

  it('handles decimal averages', async () => {
    const result = await resolveAggregates(
      '{AVG(items, amount)}',
      makeQueryFn({
        items: [
          { amount: '10' },
          { amount: '20' },
          { amount: '30' },
        ],
      }),
    );
    expect(result).toBe('20');
  });
});

describe('MIN and MAX', () => {
  it('finds minimum', async () => {
    const result = await resolveAggregates(
      '{MIN(items, amount)}',
      makeQueryFn({ items: sampleRows }),
    );
    expect(result).toBe('50');
  });

  it('finds maximum', async () => {
    const result = await resolveAggregates(
      '{MAX(items, amount)}',
      makeQueryFn({ items: sampleRows }),
    );
    expect(result).toBe('200');
  });

  it('MIN returns 0 for empty rows', async () => {
    const result = await resolveAggregates(
      '{MIN(items, amount)}',
      makeQueryFn({ items: [] }),
    );
    expect(result).toBe('0');
  });
});

describe('PCT', () => {
  it('computes percentage of matching rows', async () => {
    const result = await resolveAggregates(
      '{PCT(items, status=Done)}',
      makeQueryFn({ items: sampleRows }),
    );
    expect(result).toBe('50'); // 2 of 4 = 50%
  });

  it('returns 0 when no rows match', async () => {
    const result = await resolveAggregates(
      '{PCT(items, status=Cancelled)}',
      makeQueryFn({ items: sampleRows }),
    );
    expect(result).toBe('0');
  });

  it('returns 0 for empty data source', async () => {
    const result = await resolveAggregates(
      '{PCT(items, status=Done)}',
      makeQueryFn({ items: [] }),
    );
    expect(result).toBe('0');
  });

  it('100% when all match', async () => {
    const result = await resolveAggregates(
      '{PCT(items, status=Done)}',
      makeQueryFn({
        items: [
          { status: 'Done' },
          { status: 'Done' },
        ],
      }),
    );
    expect(result).toBe('100');
  });
});

describe('Multiple aggregates in one string', () => {
  it('resolves all aggregates', async () => {
    const result = await resolveAggregates(
      'Done: {COUNT(items, status=Done)} of {COUNT(items)} ({PCT(items, status=Done)}%)',
      makeQueryFn({ items: sampleRows }),
    );
    expect(result).toBe('Done: 2 of 4 (50%)');
  });
});

describe('Caching', () => {
  it('queries each dataSource only once', async () => {
    let callCount = 0;
    const countingQuery: QueryFn = async (_id: string) => {
      callCount++;
      return sampleRows;
    };

    await resolveAggregates(
      '{COUNT(items)} {SUM(items, amount)} {MAX(items, amount)}',
      countingQuery,
    );
    expect(callCount).toBe(1);
  });
});

describe('Number formatting', () => {
  it('whole numbers have no decimal', async () => {
    const result = await resolveAggregates(
      '{SUM(items, amount)}',
      makeQueryFn({
        items: [
          { amount: '10' },
          { amount: '20' },
        ],
      }),
    );
    expect(result).toBe('30');
    expect(result.includes('.')).toBe(false);
  });

  it('decimal results show 2 places', async () => {
    const result = await resolveAggregates(
      '{AVG(items, amount)}',
      makeQueryFn({
        items: [
          { amount: '10' },
          { amount: '20' },
          { amount: '15' },
        ],
      }),
    );
    expect(result).toBe('15');
  });
});

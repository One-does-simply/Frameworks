import { describe, it, expect } from 'vitest'
import { render, evaluateCondition, evaluateExpression } from '../../../src/engine/template-engine.ts'

// ---------------------------------------------------------------------------
// String interpolation
// ---------------------------------------------------------------------------

describe('TemplateEngine — string interpolation', () => {
  it('replaces a simple variable', () => {
    expect(render('Hello ${name}!', { name: 'World' })).toBe('Hello World!')
  })

  it('replaces multiple variables', () => {
    expect(render('${a} and ${b}', { a: 'X', b: 'Y' })).toBe('X and Y')
  })

  it('preserves raw type for whole-string expression', () => {
    expect(render('${items}', { items: [1, 2, 3] })).toEqual([1, 2, 3])
  })

  it('returns number for whole-string numeric expression', () => {
    expect(render('${count}', { count: 42 })).toBe(42)
  })

  it('returns empty string for missing variable in partial interpolation', () => {
    expect(render('Hello ${missing}!', {})).toBe('Hello !')
  })

  it('returns undefined for missing whole-string variable', () => {
    expect(render('${missing}', {})).toBeUndefined()
  })
})

// ---------------------------------------------------------------------------
// Path resolution
// ---------------------------------------------------------------------------

describe('TemplateEngine — path resolution', () => {
  it('resolves dotted paths', () => {
    expect(render('${a.b}', { a: { b: 'value' } })).toBe('value')
  })

  it('resolves indexed access', () => {
    expect(render('${items[0]}', { items: ['first', 'second'] })).toBe('first')
  })

  it('resolves combined dot and index', () => {
    expect(render('${fields[1].name}', { fields: [{ name: 'a' }, { name: 'b' }] })).toBe('b')
  })

  it('returns null for deeply nested missing path', () => {
    expect(render('${a.b.c}', { a: { b: null } })).toBeNull()
  })

  it('returns null for index out of range', () => {
    expect(render('${items[99]}', { items: ['x'] })).toBeNull()
  })
})

// ---------------------------------------------------------------------------
// $if / then / else
// ---------------------------------------------------------------------------

describe('TemplateEngine — $if', () => {
  it('renders then branch on truthy variable', () => {
    expect(render({ $if: 'flag', then: 'yes' }, { flag: true })).toBe('yes')
  })

  it('renders else branch on falsy variable', () => {
    expect(render({ $if: 'flag', then: 'yes', else: 'no' }, { flag: false })).toBe('no')
  })

  it('removes element when condition is false and no else', () => {
    const result = render([{ $if: 'flag', then: 'kept' }, 'always'], { flag: false })
    expect(result).toEqual(['always'])
  })

  it('supports equality comparison', () => {
    expect(render({ $if: "type == 'select'", then: 'dropdown' }, { type: 'select' })).toBe('dropdown')
  })

  it('supports inequality comparison', () => {
    expect(render({ $if: "type != 'text'", then: 'not text' }, { type: 'select' })).toBe('not text')
  })

  it('supports negation', () => {
    expect(render({ $if: '!flag', then: 'negated' }, { flag: false })).toBe('negated')
  })

  it('supports logical AND', () => {
    expect(render({ $if: 'a && b', then: 'both' }, { a: true, b: true })).toBe('both')
    const result = render({ $if: 'a && b', then: 'both', else: 'no' }, { a: true, b: false })
    expect(result).toBe('no')
  })

  it('supports logical OR', () => {
    expect(render({ $if: 'a || b', then: 'either' }, { a: false, b: true })).toBe('either')
  })

  it('empty string is falsy', () => {
    expect(render({ $if: 'name', then: 'yes', else: 'no' }, { name: '' })).toBe('no')
  })

  it('non-empty string is truthy', () => {
    expect(render({ $if: 'name', then: 'yes', else: 'no' }, { name: 'hello' })).toBe('yes')
  })

  it('empty array is falsy', () => {
    expect(render({ $if: 'items', then: 'yes', else: 'no' }, { items: [] })).toBe('no')
  })

  it('zero is falsy', () => {
    expect(render({ $if: 'count', then: 'yes', else: 'no' }, { count: 0 })).toBe('no')
  })

  it('missing variable is falsy', () => {
    expect(render({ $if: 'missing', then: 'yes', else: 'no' }, {})).toBe('no')
  })
})

// ---------------------------------------------------------------------------
// $map / each()
// ---------------------------------------------------------------------------

describe('TemplateEngine — $map', () => {
  it('maps over a simple array', () => {
    const result = render(
      { $map: 'items', 'each(item)': '${item}' },
      { items: ['a', 'b', 'c'] },
    )
    expect(result).toEqual(['a', 'b', 'c'])
  })

  it('maps over objects', () => {
    const result = render(
      { $map: 'fields', 'each(f)': { name: '${f.name}', type: '${f.type}' } },
      { fields: [{ name: 'email', type: 'email' }, { name: 'age', type: 'number' }] },
    )
    expect(result).toEqual([
      { name: 'email', type: 'email' },
      { name: 'age', type: 'number' },
    ])
  })

  it('exposes implicit index variable', () => {
    const result = render(
      { $map: 'items', 'each(item)': '${itemIndex}' },
      { items: ['a', 'b'] },
    )
    expect(result).toEqual([0, 1])
  })

  it('supports explicit index name', () => {
    const result = render(
      { $map: 'items', 'each(item, idx)': '${idx}' },
      { items: ['a', 'b'] },
    )
    expect(result).toEqual([0, 1])
  })

  it('removes elements from $map via inner $if', () => {
    const result = render(
      {
        $map: 'items',
        'each(item)': {
          $if: "item.type == 'select'",
          then: { name: '${item.name}' },
        },
      },
      { items: [{ name: 'a', type: 'text' }, { name: 'b', type: 'select' }] },
    )
    expect(result).toEqual([{ name: 'b' }])
  })

  it('returns empty array for missing source', () => {
    expect(render({ $map: 'missing', 'each(item)': '${item}' }, {})).toEqual([])
  })

  it('returns empty array for non-array source', () => {
    expect(render({ $map: 'val', 'each(item)': '${item}' }, { val: 'string' })).toEqual([])
  })
})

// ---------------------------------------------------------------------------
// $eval
// ---------------------------------------------------------------------------

describe('TemplateEngine — $eval', () => {
  it('evaluates a variable reference', () => {
    expect(render({ $eval: 'items' }, { items: [1, 2] })).toEqual([1, 2])
  })

  it('preserves type (not stringified)', () => {
    expect(render({ $eval: 'count' }, { count: 42 })).toBe(42)
  })

  it('evaluates string literal', () => {
    expect(render({ $eval: "'hello'" }, {})).toBe('hello')
  })

  it('evaluates boolean literal', () => {
    expect(render({ $eval: 'true' }, {})).toBe(true)
  })
})

// ---------------------------------------------------------------------------
// $flatten
// ---------------------------------------------------------------------------

describe('TemplateEngine — $flatten', () => {
  it('flattens nested arrays one level', () => {
    expect(render({ $flatten: [[1, 2], [3, 4]] }, {})).toEqual([1, 2, 3, 4])
  })

  it('passes through non-array items', () => {
    expect(render({ $flatten: [[1], 2, [3]] }, {})).toEqual([1, 2, 3])
  })

  it('removes removed sentinels during flattening', () => {
    const result = render(
      {
        $flatten: [
          ['always'],
          { $if: 'flag', then: ['conditional'] },
        ],
      },
      { flag: false },
    )
    expect(result).toEqual(['always'])
  })

  it('handles empty arrays', () => {
    expect(render({ $flatten: [[], [], []] }, {})).toEqual([])
  })
})

// ---------------------------------------------------------------------------
// Plain object recursion
// ---------------------------------------------------------------------------

describe('TemplateEngine — plain objects', () => {
  it('renders values recursively', () => {
    const result = render(
      { name: '${appName}', nested: { value: '${count}' } },
      { appName: 'Test', count: 5 },
    )
    expect(result).toEqual({ name: 'Test', nested: { value: 5 } })
  })

  it('removes keys with removed values', () => {
    const result = render(
      { keep: 'yes', remove: { $if: 'flag', then: 'value' } },
      { flag: false },
    )
    expect(result).toEqual({ keep: 'yes' })
  })
})

// ---------------------------------------------------------------------------
// evaluateExpression
// ---------------------------------------------------------------------------

describe('evaluateExpression', () => {
  it('parses numeric literals', () => {
    expect(evaluateExpression('42', {})).toBe(42)
    expect(evaluateExpression('3.14', {})).toBe(3.14)
  })

  it('parses string literals', () => {
    expect(evaluateExpression("'hello'", {})).toBe('hello')
    expect(evaluateExpression('"world"', {})).toBe('world')
  })

  it('parses boolean literals', () => {
    expect(evaluateExpression('true', {})).toBe(true)
    expect(evaluateExpression('false', {})).toBe(false)
  })
})

// ---------------------------------------------------------------------------
// evaluateCondition
// ---------------------------------------------------------------------------

describe('evaluateCondition', () => {
  it('handles truthy values', () => {
    expect(evaluateCondition('name', { name: 'hello' })).toBe(true)
  })

  it('handles falsy null', () => {
    expect(evaluateCondition('missing', {})).toBe(false)
  })

  it('handles equality with string literal', () => {
    expect(evaluateCondition("type == 'select'", { type: 'select' })).toBe(true)
    expect(evaluateCondition("type == 'select'", { type: 'text' })).toBe(false)
  })

  it('handles AND with OR precedence', () => {
    // OR has lower precedence, so: (a && b) || c
    expect(evaluateCondition('a && b || c', { a: false, b: true, c: true })).toBe(true)
    expect(evaluateCondition('a && b || c', { a: false, b: true, c: false })).toBe(false)
  })

  it('ignores operators inside string literals', () => {
    expect(evaluateCondition("val == '&&'", { val: '&&' })).toBe(true)
  })
})

// ---------------------------------------------------------------------------
// Complex / integration patterns
// ---------------------------------------------------------------------------

describe('TemplateEngine — complex patterns', () => {
  it('$map with conditional inside (real template pattern)', () => {
    const template = {
      columns: {
        $flatten: [
          [{ name: 'name', label: 'Name' }],
          {
            $if: 'fields',
            then: {
              $map: 'fields',
              'each(field)': {
                $if: "field.type == 'select'",
                then: { name: '${field.name}', label: '${field.label}', filterable: true },
                else: { name: '${field.name}', label: '${field.label}' },
              },
            },
            else: [],
          },
        ],
      },
    }

    const result = render(template, {
      fields: [
        { name: 'priority', label: 'Priority', type: 'select' },
        { name: 'notes', label: 'Notes', type: 'text' },
      ],
    }) as Record<string, unknown>

    expect(result.columns).toEqual([
      { name: 'name', label: 'Name' },
      { name: 'priority', label: 'Priority', filterable: true },
      { name: 'notes', label: 'Notes' },
    ])
  })

  it('nested $map with index', () => {
    const template = {
      $map: 'groups',
      'each(group)': {
        title: '${group.name}',
        items: {
          $map: 'group.items',
          'each(item, i)': { label: '${item}', position: '${i}' },
        },
      },
    }

    const result = render(template, {
      groups: [
        { name: 'A', items: ['x', 'y'] },
        { name: 'B', items: ['z'] },
      ],
    })

    expect(result).toEqual([
      {
        title: 'A',
        items: [
          { label: 'x', position: 0 },
          { label: 'y', position: 1 },
        ],
      },
      {
        title: 'B',
        items: [{ label: 'z', position: 0 }],
      },
    ])
  })

  it('preserves primitives through rendering', () => {
    const result = render(
      { number: 42, bool: true, nil: null, str: 'hello' },
      {},
    )
    expect(result).toEqual({ number: 42, bool: true, nil: null, str: 'hello' })
  })
})

/**
 * Batch 9: Performance baselines.
 *
 * These tests characterize behavior under load. They are NOT hunting for
 * bugs — they establish soft timing bounds so that a pathological regression
 * (10x slowdown, algorithmic blow-up, accidental O(n^2)) is caught by CI.
 *
 * Guiding principles:
 *   - Generous bounds. We want to catch pathological regressions, not tight timing.
 *   - All bounds include comfortable slack for slow CI machines.
 *   - Baseline timings are recorded in comments. Machine note:
 *     the baselines below were measured on a Windows 11 laptop
 *     (11th Gen Intel i7, Node 22 via Vitest 4.1, jsdom env).
 *   - DO NOT fix anything here. If a test is way off expectation,
 *     flag it in the PR description so an engineer can investigate.
 *
 * Perf-test philosophy: each `it` block runs ONE scenario and measures it with
 * performance.now(). The measurement is logged so CI output shows baselines.
 */

import { describe, it, expect, beforeEach } from 'vitest'
import fs from 'fs'
import path from 'path'
import { useAppStore } from '../../src/engine/app-store.ts'
import { AuthService } from '../../src/engine/auth-service.ts'
import { parseApp } from '../../src/models/ods-app.ts'
import { FakeDataService } from '../helpers/fake-data-service.ts'
import { parseSpec } from '../../src/parser/spec-parser.ts'
import { evaluateFormula } from '../../src/engine/formula-evaluator.ts'
import { evaluateExpression } from '../../src/engine/expression-evaluator.ts'
import { resolveAggregates } from '../../src/engine/aggregate-evaluator.ts'

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

function mockPb() {
  return {
    authStore: { isValid: false, record: null },
    collection: () => ({
      listAuthMethods: async () => ({ oauth2: { providers: [] } }),
    }),
  } as any
}

function resetStore(ds: FakeDataService, authService: AuthService) {
  useAppStore.setState({
    app: null,
    currentPageId: null,
    navigationStack: [],
    formStates: {},
    recordCursors: {},
    recordGeneration: 0,
    validation: null,
    loadError: null,
    debugMode: false,
    isLoading: false,
    lastActionError: null,
    lastMessage: null,
    appSettings: {},
    dataService: ds as any,
    authService,
    currentSlug: null,
    isMultiUser: false,
    needsAdminSetup: false,
    needsLogin: false,
    isMultiUserOnly: false,
  })
}

/** Times a synchronous block and logs the result. Returns elapsed ms. */
function measure(label: string, fn: () => void): number {
  const start = performance.now()
  fn()
  const elapsed = performance.now() - start
  // eslint-disable-next-line no-console
  console.log(`[perf] ${label}: ${elapsed.toFixed(1)}ms`)
  return elapsed
}

/** Times an async block. Returns elapsed ms. */
async function measureAsync(label: string, fn: () => Promise<void>): Promise<number> {
  const start = performance.now()
  await fn()
  const elapsed = performance.now() - start
  // eslint-disable-next-line no-console
  console.log(`[perf] ${label}: ${elapsed.toFixed(1)}ms`)
  return elapsed
}

// ---------------------------------------------------------------------------
// P1: Spec parsing at scale
// ---------------------------------------------------------------------------

/** Generate a spec JSON string with the given number of pages. */
function generateLargeSpec(pageCount: number): string {
  const pages: Record<string, unknown> = {}
  for (let i = 0; i < pageCount; i++) {
    pages[`page${i}`] = {
      component: 'page',
      title: `Page ${i}`,
      content: [
        {
          component: 'text',
          content: `This is page ${i}.`,
        },
        {
          component: 'button',
          label: 'Next',
          actions: [
            { action: 'navigate', target: `page${(i + 1) % pageCount}` },
          ],
        },
      ],
    }
  }
  const spec = {
    appName: 'BigApp',
    startPage: 'page0',
    pages,
    dataSources: {
      items: {
        url: 'local://items',
        method: 'POST',
        fields: [{ name: 'name', type: 'text' }],
      },
    },
  }
  return JSON.stringify(spec)
}

/** Generate a spec with one form containing `fieldCount` fields. */
function generateLargeFormSpec(fieldCount: number): string {
  const fields: unknown[] = []
  for (let i = 0; i < fieldCount; i++) {
    fields.push({
      name: `f${i}`,
      type: i % 3 === 0 ? 'text' : i % 3 === 1 ? 'number' : 'select',
      label: `Field ${i}`,
      ...(i % 3 === 2 ? { options: ['a', 'b', 'c'] } : {}),
    })
  }
  const spec = {
    appName: 'BigFormApp',
    startPage: 'home',
    pages: {
      home: {
        component: 'page',
        title: 'Home',
        content: [
          { component: 'form', id: 'bigForm', fields },
        ],
      },
    },
    dataSources: {
      items: {
        url: 'local://items',
        method: 'POST',
        fields: fields.map(f => ({ name: (f as any).name, type: 'text' })),
      },
    },
  }
  return JSON.stringify(spec)
}

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

describe('Batch 9: Performance baselines', () => {
  let ds: FakeDataService
  let authService: AuthService

  beforeEach(() => {
    ds = new FakeDataService()
    ds.initialize('test')
    authService = new AuthService(mockPb())
    resetStore(ds, authService)
  })

  // -------------------------------------------------------------------------
  // P1: Spec parsing
  // -------------------------------------------------------------------------

  describe('P1: Spec parsing at scale', () => {
    it('parses a 500-page spec under 1s', () => {
      const json = generateLargeSpec(500)
      const elapsed = measure('P1 500-page spec', () => {
        const result = parseSpec(json)
        expect(result.parseError).toBeNull()
        expect(Object.keys(result.app!.pages).length).toBe(500)
      })
      // Baseline: ~3.5ms on Win11 i7 laptop (500-page synthetic spec).
      expect(elapsed).toBeLessThan(1000)
    })

    it('parses all Specification/Examples under 2s total', () => {
      const examplesDir = path.resolve(__dirname, '../../../../Specification/Examples')
      if (!fs.existsSync(examplesDir)) {
        // Gracefully skip if the Specification repo isn't available (CI).
        console.log('[perf] P1 examples: SKIPPED (Specification/Examples not found)')
        return
      }
      const files = fs
        .readdirSync(examplesDir)
        .filter(f => f.endsWith('.json') && f !== 'catalog.json')

      const elapsed = measure(`P1 examples (n=${files.length})`, () => {
        for (const f of files) {
          const json = fs.readFileSync(path.join(examplesDir, f), 'utf-8')
          const result = parseSpec(json)
          expect(result.parseError, `Parse error in ${f}`).toBeNull()
        }
      })
      // Baseline: ~9ms for 15 example specs on Win11 i7 laptop.
      expect(elapsed).toBeLessThan(2000)
    })

    it('parses a form with 1000 fields under 500ms', () => {
      const json = generateLargeFormSpec(1000)
      const elapsed = measure('P1 1000-field form', () => {
        const result = parseSpec(json)
        expect(result.parseError).toBeNull()
      })
      // Baseline: ~1.5ms on Win11 i7 laptop.
      expect(elapsed).toBeLessThan(500)
    })
  })

  // -------------------------------------------------------------------------
  // P2: Data service throughput
  // -------------------------------------------------------------------------

  describe('P2: Data service throughput', () => {
    it('inserts 10,000 rows sequentially under 5s', async () => {
      const elapsed = await measureAsync('P2 insert 10k sequential', async () => {
        for (let i = 0; i < 10000; i++) {
          await ds.insert('tasks', { title: `Task ${i}`, status: 'todo' })
        }
      })
      // Baseline: ~8ms on Win11 i7 laptop (fake is in-memory).
      expect(elapsed).toBeLessThan(5000)
      const count = await ds.getRowCount('tasks')
      expect(count).toBe(10000)
    })

    it('inserts 10,000 rows via Promise.all under 2s', async () => {
      const elapsed = await measureAsync('P2 insert 10k concurrent', async () => {
        const promises: Promise<string>[] = []
        for (let i = 0; i < 10000; i++) {
          promises.push(ds.insert('tasks', { title: `Task ${i}`, status: 'todo' }))
        }
        await Promise.all(promises)
      })
      // Baseline: ~8ms on Win11 i7 laptop.
      // NOTE: FakeDataService is synchronous; real PocketBase would be much slower.
      expect(elapsed).toBeLessThan(2000)
    })

    it('queries 10,000 rows under 1s', async () => {
      // Seed
      for (let i = 0; i < 10000; i++) {
        await ds.insert('tasks', { title: `Task ${i}`, status: 'todo' })
      }
      const elapsed = await measureAsync('P2 query 10k', async () => {
        const rows = await ds.query('tasks')
        expect(rows.length).toBe(10000)
      })
      // Baseline: ~0.2ms on Win11 i7 laptop (in-memory array clone + reverse).
      expect(elapsed).toBeLessThan(1000)
    })

    it('filters 10,000 rows → ~10 matches under 500ms', async () => {
      // Seed with a sparse matching status.
      for (let i = 0; i < 10000; i++) {
        await ds.insert('tasks', {
          title: `Task ${i}`,
          status: i % 1000 === 0 ? 'done' : 'todo',
        })
      }
      const elapsed = await measureAsync('P2 filter 10k → ~10', async () => {
        const rows = await ds.queryWithFilter('tasks', { status: 'done' })
        expect(rows.length).toBe(10)
      })
      // Baseline: ~1.5ms on Win11 i7 laptop (linear scan).
      expect(elapsed).toBeLessThan(500)
    })
  })

  // -------------------------------------------------------------------------
  // P3: Expression / formula / template evaluation
  // -------------------------------------------------------------------------

  describe('P3: Expression/formula evaluation', () => {
    it('evaluates 10,000 math formulas under 1s', () => {
      const values = { a: '5', b: '10', c: '2' }
      const elapsed = measure('P3 10k formulas', () => {
        for (let i = 0; i < 10000; i++) {
          const out = evaluateFormula('{a} + {b} * {c}', 'number', values)
          // 5 + 10*2 = 25
          if (out !== '25') throw new Error(`Unexpected: ${out}`)
        }
      })
      // Baseline: ~13ms on Win11 i7 laptop (10k formula evals).
      expect(elapsed).toBeLessThan(1000)
    })

    it('evaluates 1,000 ternary expressions under 500ms', () => {
      const values = { status: 'active' }
      const elapsed = measure('P3 1k ternaries', () => {
        for (let i = 0; i < 1000; i++) {
          const out = evaluateExpression("{status} == 'active' ? 'yes' : 'no'", values)
          if (out !== 'yes') throw new Error(`Unexpected: ${out}`)
        }
      })
      // Baseline: ~2ms on Win11 i7 laptop (1k ternary evals).
      expect(elapsed).toBeLessThan(500)
    })

    it('resolves a template with 100 aggregate refs under 1s', async () => {
      // Seed data for COUNT aggregation.
      for (let i = 0; i < 50; i++) {
        await ds.insert('tasks', { status: i % 2 === 0 ? 'todo' : 'done' })
      }
      // Build content string with 100 aggregate references.
      const parts: string[] = []
      for (let i = 0; i < 100; i++) {
        parts.push(`{COUNT(tasks)}`)
      }
      const content = parts.join(' / ')
      const queryFn = async (dsId: string) => ds.query(dsId)

      const elapsed = await measureAsync('P3 100 aggregate refs', async () => {
        const result = await resolveAggregates(content, queryFn)
        // Each aggregate should resolve to "50".
        expect(result.startsWith('50')).toBe(true)
      })
      // Baseline: ~0.5ms on Win11 i7 laptop (single cached query → 100 substitutions).
      expect(elapsed).toBeLessThan(1000)
    })
  })

  // -------------------------------------------------------------------------
  // P4: Action chains
  // -------------------------------------------------------------------------

  describe('P4: Action chains', () => {
    function makeTasksApp() {
      return parseApp({
        appName: 'Perf',
        startPage: 'home',
        pages: {
          home: {
            title: 'Home',
            content: [
              {
                component: 'form',
                id: 'addForm',
                fields: [
                  { name: 'title', type: 'text' },
                  { name: 'status', type: 'text' },
                ],
              },
            ],
          },
        },
        dataSources: {
          tasks: {
            url: 'local://tasks',
            method: 'POST',
            fields: [
              { name: 'title', type: 'text' },
              { name: 'status', type: 'text' },
            ],
          },
        },
      })
    }

    it('executes 100 sequential submits under 5s', async () => {
      const app = makeTasksApp()
      useAppStore.setState({
        app,
        currentPageId: 'home',
      })

      const elapsed = await measureAsync('P4 100 submits', async () => {
        for (let i = 0; i < 100; i++) {
          useAppStore.setState({
            formStates: { addForm: { title: `Task ${i}`, status: 'todo' } },
          })
          await useAppStore.getState().executeActions([
            {
              action: 'submit',
              target: 'addForm',
              dataSource: 'tasks',
              computedFields: [],
              preserveFields: [],
            },
          ])
        }
      })
      const rows = await ds.query('tasks')
      expect(rows.length).toBe(100)
      // Baseline: ~5ms on Win11 i7 laptop (100 submits through app store).
      expect(elapsed).toBeLessThan(5000)
    })

    // P4 1000-step cascade: intentionally NOT tested.
    // Cascade rename is bounded by parent-data-source row count, not action
    // chain depth, and a 1000-step cascade would indicate a spec bug
    // (circular ref). Document as limitation instead.
    it.skip('1000-step cascade — intentional limitation, not measured', () => {
      // Left as documentation: ODS cascade rename is designed to fan out
      // once per parent rename, not chain through 1000 steps. A 1000-step
      // cascade would point to a spec bug, not a perf concern.
    })

    it('executes submit with 100 computedFields under 100ms', async () => {
      const app = makeTasksApp()
      useAppStore.setState({
        app,
        currentPageId: 'home',
        formStates: { addForm: { title: 'Compute', status: 'todo' } },
      })
      const computedFields = []
      for (let i = 0; i < 100; i++) {
        computedFields.push({ field: `c${i}`, expression: `prefix_{title}_${i}` })
      }
      const elapsed = await measureAsync('P4 100 computedFields', async () => {
        await useAppStore.getState().executeActions([
          {
            action: 'submit',
            target: 'addForm',
            dataSource: 'tasks',
            computedFields,
            preserveFields: [],
          },
        ])
      })
      const rows = await ds.query('tasks')
      expect(rows.length).toBe(1)
      expect(rows[0].c0).toBe('prefix_Compute_0')
      expect(rows[0].c99).toBe('prefix_Compute_99')
      // Baseline: ~0.5ms on Win11 i7 laptop (100 computedFields on one submit).
      expect(elapsed).toBeLessThan(100)
    })
  })

  // -------------------------------------------------------------------------
  // P5: Store reactivity
  // -------------------------------------------------------------------------

  describe('P5: Store reactivity', () => {
    it('fires 1,000 form field updates under 500ms', () => {
      const elapsed = measure('P5 1k field updates', () => {
        for (let i = 0; i < 1000; i++) {
          useAppStore.getState().updateFormField('myForm', `field${i % 50}`, `v${i}`)
        }
      })
      const state = useAppStore.getState().formStates['myForm']
      expect(state).toBeDefined()
      // We wrote 50 distinct field names (last value wins per field).
      expect(Object.keys(state).length).toBe(50)
      // Baseline: ~11ms on Win11 i7 laptop (zustand shallow-merge per update).
      expect(elapsed).toBeLessThan(500)
    })

    it('100 rapid recordGeneration bumps under 100ms', () => {
      const elapsed = measure('P5 100 recordGeneration bumps', () => {
        for (let i = 0; i < 100; i++) {
          const cur = useAppStore.getState().recordGeneration
          useAppStore.setState({ recordGeneration: cur + 1 })
        }
      })
      expect(useAppStore.getState().recordGeneration).toBe(100)
      // Baseline: ~0.7ms on Win11 i7 laptop (100 setState bumps).
      expect(elapsed).toBeLessThan(100)
    })
  })
})

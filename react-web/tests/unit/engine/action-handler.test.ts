import { describe, it, expect, beforeEach } from 'vitest';
import { executeAction } from '../../../src/engine/action-handler.ts';
import type { ActionResult } from '../../../src/engine/action-handler.ts';
import type { OdsAction } from '../../../src/models/ods-action.ts';
import type { OdsApp } from '../../../src/models/ods-app.ts';
import { parseApp } from '../../../src/models/ods-app.ts';
import { FakeDataService } from '../../helpers/fake-data-service.ts';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function buildApp(overrides?: {
  fields?: unknown[];
  dataSources?: Record<string, unknown>;
}): OdsApp {
  return parseApp({
    appName: 'Test',
    startPage: 'p',
    dataSources: {
      store: { url: 'local://items', method: 'POST' },
      updater: { url: 'local://items', method: 'PUT' },
      ...overrides?.dataSources,
    },
    pages: {
      p: {
        component: 'page',
        title: 'P',
        content: [
          {
            component: 'form',
            id: 'myForm',
            fields: overrides?.fields ?? [
              { name: 'name', type: 'text', required: true },
              { name: 'email', type: 'email' },
              { name: 'age', type: 'number' },
            ],
          },
        ],
      },
    },
  });
}

function action(overrides: Partial<OdsAction> & { action: string }): OdsAction {
  return {
    computedFields: [],
    preserveFields: [],
    ...overrides,
  } as OdsAction;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('ActionHandler', () => {
  let fake: FakeDataService;

  beforeEach(() => {
    fake = new FakeDataService();
    fake.initialize('test');
  });

  // -------------------------------------------------------------------------
  // Navigate action
  // -------------------------------------------------------------------------

  describe('Navigate action', () => {
    it('returns target page', async () => {
      const result = await executeAction({
        action: action({ action: 'navigate', target: 'other' }),
        app: buildApp(),
        formStates: {},
        dataService: fake,
      });
      expect(result.navigateTo).toBe('other');
      expect(result.error).toBeUndefined();
    });
  });

  // -------------------------------------------------------------------------
  // ShowMessage action
  // -------------------------------------------------------------------------

  describe('ShowMessage action', () => {
    it('returns message', async () => {
      const result = await executeAction({
        action: action({ action: 'showMessage', message: 'Done!' }),
        app: buildApp(),
        formStates: {},
        dataService: fake,
      });
      expect(result.message).toBe('Done!');
    });
  });

  // -------------------------------------------------------------------------
  // Submit action
  // -------------------------------------------------------------------------

  describe('Submit action', () => {
    it('missing target returns error', async () => {
      const result = await executeAction({
        action: action({ action: 'submit', dataSource: 'store' }),
        app: buildApp(),
        formStates: { myForm: { name: 'test' } },
        dataService: fake,
      });
      expect(result.error).toBeDefined();
    });

    it('missing dataSource returns error', async () => {
      const result = await executeAction({
        action: action({ action: 'submit', target: 'myForm' }),
        app: buildApp(),
        formStates: { myForm: { name: 'test' } },
        dataService: fake,
      });
      expect(result.error).toBeDefined();
    });

    it('empty form data returns error', async () => {
      const result = await executeAction({
        action: action({ action: 'submit', target: 'myForm', dataSource: 'store' }),
        app: buildApp(),
        formStates: {},
        dataService: fake,
      });
      expect(result.error).toBeDefined();
    });

    it('missing required field returns validation error', async () => {
      const result = await executeAction({
        action: action({ action: 'submit', target: 'myForm', dataSource: 'store' }),
        app: buildApp(),
        formStates: { myForm: { name: '', email: 'a@b.com' } },
        dataService: fake,
      });
      expect(result.error).toBeDefined();
      expect(result.error).toContain('Required');
    });

    it('valid submit succeeds', async () => {
      const result = await executeAction({
        action: action({ action: 'submit', target: 'myForm', dataSource: 'store' }),
        app: buildApp(),
        formStates: { myForm: { name: 'Alice', email: 'a@b.com', age: '25' } },
        dataService: fake,
      });
      expect(result.submitted).toBe(true);
      expect(result.error).toBeUndefined();
      expect(fake.insertedData.length).toBeGreaterThan(0);
    });

    it('invalid email returns validation error', async () => {
      const result = await executeAction({
        action: action({ action: 'submit', target: 'myForm', dataSource: 'store' }),
        app: buildApp(),
        formStates: { myForm: { name: 'Alice', email: 'not-an-email' } },
        dataService: fake,
      });
      expect(result.error).toBeDefined();
      expect(result.error).toContain('email');
    });

    it('unknown dataSource returns error', async () => {
      const result = await executeAction({
        action: action({ action: 'submit', target: 'myForm', dataSource: 'nonexistent' }),
        app: buildApp(),
        formStates: { myForm: { name: 'Alice' } },
        dataService: fake,
      });
      expect(result.error).toBeDefined();
    });
  });

  // -------------------------------------------------------------------------
  // Update action
  // -------------------------------------------------------------------------

  describe('Update action', () => {
    it('missing matchField returns error', async () => {
      const result = await executeAction({
        action: action({ action: 'update', target: 'myForm', dataSource: 'updater' }),
        app: buildApp(),
        formStates: { myForm: { name: 'Alice' } },
        dataService: fake,
      });
      expect(result.error).toBeDefined();
    });

    it('empty match field value returns error', async () => {
      const result = await executeAction({
        action: action({ action: 'update', target: 'myForm', dataSource: 'updater', matchField: '_id' }),
        app: buildApp(),
        formStates: { myForm: { name: 'Alice', _id: '' } },
        dataService: fake,
      });
      expect(result.error).toBeDefined();
      expect(result.error).toContain('empty');
    });

    it('valid update succeeds', async () => {
      // Seed a row so the update matches on the name field
      fake.seed('items', [{ name: 'Alice', email: 'a@b.com' }]);
      const result = await executeAction({
        action: action({ action: 'update', target: 'myForm', dataSource: 'updater', matchField: 'name' }),
        app: buildApp(),
        formStates: { myForm: { name: 'Alice', email: 'updated@b.com' } },
        dataService: fake,
      });
      expect(result.submitted).toBe(true);
      expect(result.error).toBeUndefined();
    });

    it('no matching row returns error', async () => {
      // No rows seeded — update returns 0
      const result = await executeAction({
        action: action({ action: 'update', target: 'myForm', dataSource: 'updater', matchField: '_id' }),
        app: buildApp(),
        formStates: { myForm: { name: 'Alice', _id: '999' } },
        dataService: fake,
      });
      expect(result.error).toBeDefined();
      expect(result.error).toContain('Record not found');
    });
  });

  // -------------------------------------------------------------------------
  // Computed fields
  // -------------------------------------------------------------------------

  describe('Computed fields', () => {
    it('computed fields are evaluated on submit', async () => {
      const result = await executeAction({
        action: action({
          action: 'submit',
          target: 'myForm',
          dataSource: 'store',
          computedFields: [{ field: 'greeting', expression: '{name} says hi' }],
        }),
        app: buildApp(),
        formStates: { myForm: { name: 'Alice' } },
        dataService: fake,
      });
      expect(result.submitted).toBe(true);
      const lastInserted = fake.insertedData[fake.insertedData.length - 1];
      expect(lastInserted['greeting']).toBe('Alice says hi');
    });
  });

  // -------------------------------------------------------------------------
  // Hidden fields
  // -------------------------------------------------------------------------

  describe('Hidden fields', () => {
    it('hidden fields by visibleWhen are excluded from storage', async () => {
      const app = parseApp({
        appName: 'Test',
        startPage: 'p',
        dataSources: { store: { url: 'local://items', method: 'POST' } },
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'form',
                id: 'myForm',
                fields: [
                  { name: 'type', type: 'select', options: ['A', 'B'] },
                  {
                    name: 'extra',
                    type: 'text',
                    visibleWhen: { field: 'type', equals: 'B' },
                  },
                ],
              },
            ],
          },
        },
      });

      const result = await executeAction({
        action: action({ action: 'submit', target: 'myForm', dataSource: 'store' }),
        app,
        formStates: { myForm: { type: 'A', extra: 'should be hidden' } },
        dataService: fake,
      });
      expect(result.submitted).toBe(true);
      const lastInserted = fake.insertedData[fake.insertedData.length - 1];
      expect(lastInserted).not.toHaveProperty('extra');
    });

    it('hidden required fields do NOT block validation', async () => {
      const app = parseApp({
        appName: 'Test',
        startPage: 'p',
        dataSources: { store: { url: 'local://items', method: 'POST' } },
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'form',
                id: 'myForm',
                fields: [
                  { name: 'type', type: 'select', options: ['A', 'B'] },
                  {
                    name: 'extra',
                    type: 'text',
                    required: true,
                    visibleWhen: { field: 'type', equals: 'B' },
                  },
                ],
              },
            ],
          },
        },
      });

      const result = await executeAction({
        action: action({ action: 'submit', target: 'myForm', dataSource: 'store' }),
        app,
        formStates: { myForm: { type: 'A', extra: '' } },
        dataService: fake,
      });
      expect(result.error).toBeUndefined();
      expect(result.submitted).toBe(true);
    });
  });

  // -------------------------------------------------------------------------
  // Computed field exclusion (formula fields)
  // -------------------------------------------------------------------------

  describe('Computed field exclusion', () => {
    it('formula fields are not stored in database', async () => {
      const app = parseApp({
        appName: 'Test',
        startPage: 'p',
        dataSources: { store: { url: 'local://items', method: 'POST' } },
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'form',
                id: 'myForm',
                fields: [
                  { name: 'qty', type: 'number', required: true },
                  { name: 'price', type: 'number', required: true },
                  { name: 'total', type: 'number', formula: '{qty} * {price}' },
                ],
              },
            ],
          },
        },
      });

      const result = await executeAction({
        action: action({ action: 'submit', target: 'myForm', dataSource: 'store' }),
        app,
        formStates: { myForm: { qty: '5', price: '10', total: '50' } },
        dataService: fake,
      });
      expect(result.submitted).toBe(true);
      const lastInserted = fake.insertedData[fake.insertedData.length - 1];
      expect(lastInserted).not.toHaveProperty('total');
    });
  });

  // -------------------------------------------------------------------------
  // Unknown action
  // -------------------------------------------------------------------------

  describe('Unknown action', () => {
    it('unknown action type does not crash', async () => {
      const result = await executeAction({
        action: action({ action: 'teleport' }),
        app: buildApp(),
        formStates: {},
        dataService: fake,
      });
      expect(result.error).toBeUndefined();
      expect(result.submitted).toBe(false);
    });
  });

  // -------------------------------------------------------------------------
  // Error formatting
  // -------------------------------------------------------------------------

  describe('Error formatting', () => {
    it('multiple validation errors are comma-separated', async () => {
      const app = parseApp({
        appName: 'Test',
        startPage: 'p',
        dataSources: { store: { url: 'local://items', method: 'POST' } },
        pages: {
          p: {
            component: 'page',
            title: 'P',
            content: [
              {
                component: 'form',
                id: 'myForm',
                fields: [
                  { name: 'a', type: 'text', required: true, label: 'Field A' },
                  { name: 'b', type: 'text', required: true, label: 'Field B' },
                  { name: 'c', type: 'text', required: true, label: 'Field C' },
                ],
              },
            ],
          },
        },
      });

      const result = await executeAction({
        action: action({ action: 'submit', target: 'myForm', dataSource: 'store' }),
        app,
        formStates: { myForm: { a: '', b: '', c: '' } },
        dataService: fake,
      });
      expect(result.error).toContain('Field A');
      expect(result.error).toContain('Field B');
      expect(result.error).toContain('Field C');
    });
  });
});

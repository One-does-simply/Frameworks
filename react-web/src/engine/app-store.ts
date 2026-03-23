import { create } from 'zustand'
import type { OdsAction } from '../models/ods-action.ts'
import { isRecordAction } from '../models/ods-action.ts'
import type { OdsApp } from '../models/ods-app.ts'
import type { OdsFormComponent } from '../models/ods-component.ts'
import { isLocal, tableName } from '../models/ods-data-source.ts'
import { parseSpec, isOk } from '../parser/spec-parser.ts'
import type { ValidationResult } from '../parser/spec-validator.ts'
import { executeAction, type ActionResult } from './action-handler.ts'
import type { AuthService } from './auth-service.ts'
import type { DataService } from './data-service.ts'

// ---------------------------------------------------------------------------
// Record cursor — step-through navigation for forms with recordSource
// ---------------------------------------------------------------------------

export class RecordCursor {
  rows: Record<string, unknown>[]
  private _currentIndex: number

  constructor(rows: Record<string, unknown>[], currentIndex = 0) {
    this.rows = rows
    this._currentIndex = currentIndex
  }

  get currentIndex(): number { return this._currentIndex }
  set currentIndex(value: number) { this._currentIndex = value }

  get currentRecord(): Record<string, unknown> | undefined {
    if (this._currentIndex < 0 || this._currentIndex >= this.rows.length) return undefined
    return this.rows[this._currentIndex]
  }

  get hasNext(): boolean { return this._currentIndex < this.rows.length - 1 }
  get hasPrevious(): boolean { return this._currentIndex > 0 }
  get isEmpty(): boolean { return this.rows.length === 0 }
  get count(): number { return this.rows.length }
  get position(): string { return `${this._currentIndex + 1} of ${this.rows.length}` }
}

// ---------------------------------------------------------------------------
// App state interface
// ---------------------------------------------------------------------------

export interface AppState {
  // State fields
  app: OdsApp | null
  currentPageId: string | null
  navigationStack: string[]
  formStates: Record<string, Record<string, string>>
  recordCursors: Record<string, RecordCursor>
  recordGeneration: number
  validation: ValidationResult | null
  loadError: string | null
  debugMode: boolean
  isLoading: boolean
  lastActionError: string | null
  lastMessage: string | null
  appSettings: Record<string, string>

  // Services (not serializable, stored as refs)
  dataService: DataService | null
  authService: AuthService | null

  // Computed getters
  isMultiUser: boolean
  needsAdminSetup: boolean
  needsLogin: boolean
  isMultiUserOnly: boolean

  // Actions
  loadSpec: (jsonString: string, dataService: DataService, authService: AuthService) => Promise<boolean>
  navigateTo: (pageId: string) => void
  goBack: () => void
  canGoBack: () => boolean
  updateFormField: (formId: string, fieldName: string, value: string) => void
  clearForm: (formId: string, preserveFields?: string[]) => void
  getFormState: (formId: string) => Record<string, string>
  populateFormAndNavigate: (formId: string, pageId: string, rowData: Record<string, unknown>) => void
  executeActions: (actions: OdsAction[], confirmFn?: (message: string) => Promise<boolean>) => Promise<void>
  queryDataSource: (dataSourceId: string) => Promise<Record<string, unknown>[]>
  reset: () => void
  toggleDebugMode: () => void
}

// ---------------------------------------------------------------------------
// Initial state
// ---------------------------------------------------------------------------

const initialState = {
  app: null,
  currentPageId: null,
  navigationStack: [] as string[],
  formStates: {} as Record<string, Record<string, string>>,
  recordCursors: {} as Record<string, RecordCursor>,
  recordGeneration: 0,
  validation: null,
  loadError: null,
  debugMode: false,
  isLoading: false,
  lastActionError: null,
  lastMessage: null,
  appSettings: {} as Record<string, string>,
  dataService: null,
  authService: null,
  isMultiUser: false,
  needsAdminSetup: false,
  needsLogin: false,
  isMultiUserOnly: false,
}

// ---------------------------------------------------------------------------
// Store creation
// ---------------------------------------------------------------------------

export const useAppStore = create<AppState>()((set, get) => ({
  ...initialState,

  // -------------------------------------------------------------------------
  // Spec loading
  // -------------------------------------------------------------------------

  loadSpec: async (jsonString: string, dataService: DataService, authService: AuthService): Promise<boolean> => {
    set({ isLoading: true, loadError: null })

    // Parse and validate.
    const result = parseSpec(jsonString)

    set({ validation: result.validation })

    if (result.parseError) {
      set({ loadError: result.parseError, isLoading: false })
      return false
    }

    if (!isOk(result)) {
      const errorMsg = result.validation.messages
        .filter(m => m.level === 'error')
        .map(m => m.message)
        .join('\n')
      set({ loadError: errorMsg, isLoading: false })
      return false
    }

    const app = result.app!

    // Initialize data service and set up data sources.
    try {
      dataService.initialize(app.appName)
      await dataService.setupDataSources(app.dataSources)

      // Load app settings from the database, falling back to spec defaults.
      const appSettings: Record<string, string> = {}
      for (const [key, setting] of Object.entries(app.settings)) {
        appSettings[key] = setting.defaultValue
      }
      const savedSettings = await dataService.getAllAppSettings()
      Object.assign(appSettings, savedSettings)

      // Initialize auth if multi-user mode is enabled.
      if (app.auth.multiUser) {
        await authService.initialize()
      }

      set({
        app,
        dataService,
        authService,
        appSettings,
        currentPageId: app.startPage,
        navigationStack: [],
        formStates: {},
        recordCursors: {},
        isLoading: false,
        isMultiUser: app.auth.multiUser,
        isMultiUserOnly: app.auth.multiUserOnly ?? false,
        needsAdminSetup: app.auth.multiUser && !authService.isAdminSetUp,
        needsLogin: app.auth.multiUser && authService.isAdminSetUp && !authService.isLoggedIn,
      })

      return true
    } catch (e) {
      set({ loadError: `Database initialization failed: ${e}`, isLoading: false })
      return false
    }
  },

  // -------------------------------------------------------------------------
  // Navigation
  // -------------------------------------------------------------------------

  navigateTo: (pageId: string) => {
    const { app, currentPageId, navigationStack, authService } = get()
    if (!app || !app.pages[pageId]) return

    // Role-based navigation guard.
    const targetPage = app.pages[pageId]
    const isMultiUser = app.auth.multiUser
    if (isMultiUser && authService && !authService.hasAccess(targetPage.roles)) {
      console.warn(`ODS: Navigation blocked — user lacks role for page "${pageId}"`)
      return
    }

    const newStack = currentPageId
      ? [...navigationStack, currentPageId]
      : [...navigationStack]

    set({
      currentPageId: pageId,
      navigationStack: newStack,
    })
  },

  goBack: () => {
    const { navigationStack } = get()
    if (navigationStack.length === 0) return

    const newStack = [...navigationStack]
    const previousPage = newStack.pop()!

    set({
      currentPageId: previousPage,
      navigationStack: newStack,
    })
  },

  canGoBack: () => {
    return get().navigationStack.length > 0
  },

  // -------------------------------------------------------------------------
  // Form state
  // -------------------------------------------------------------------------

  updateFormField: (formId: string, fieldName: string, value: string) => {
    const { formStates } = get()
    const state = formStates[formId] ?? {}
    // Shallow merge — no set() notification for per-keystroke performance.
    // Components should use getFormState() to read, and only clearForm
    // triggers a full re-render.
    set({
      formStates: {
        ...formStates,
        [formId]: { ...state, [fieldName]: value },
      },
    })
  },

  clearForm: (formId: string, preserveFields?: string[]) => {
    const { formStates } = get()

    let preserved: Record<string, string> | undefined
    if (preserveFields && preserveFields.length > 0) {
      const oldState = formStates[formId]
      if (oldState) {
        preserved = {}
        for (const field of preserveFields) {
          if (field in oldState) {
            preserved[field] = oldState[field]
          }
        }
      }
    }

    const newFormStates = { ...formStates }
    delete newFormStates[formId]

    if (preserved && Object.keys(preserved).length > 0) {
      newFormStates[formId] = preserved
    }

    set({ formStates: newFormStates })
  },

  getFormState: (formId: string) => {
    const { formStates } = get()
    if (!formStates[formId]) {
      // Create and store an empty form state on first access.
      const newState: Record<string, string> = {}
      set({ formStates: { ...formStates, [formId]: newState } })
      return newState
    }
    return formStates[formId]
  },

  populateFormAndNavigate: (formId: string, pageId: string, rowData: Record<string, unknown>) => {
    const { formStates } = get()
    const state: Record<string, string> = {}
    for (const [key, value] of Object.entries(rowData)) {
      state[key] = value != null ? String(value) : ''
    }
    set({ formStates: { ...formStates, [formId]: state } })
    get().navigateTo(pageId)
  },

  // -------------------------------------------------------------------------
  // Action execution
  // -------------------------------------------------------------------------

  executeActions: async (
    actions: OdsAction[],
    confirmFn?: (message: string) => Promise<boolean>,
  ) => {
    const state = get()
    const { app, dataService, authService } = state
    if (!app || !dataService) return

    set({ lastActionError: null, lastMessage: null })

    // Snapshot form state so later actions can still read values after
    // submit clears the original form.
    const formSnapshot: Record<string, Record<string, string>> = {}
    for (const [k, v] of Object.entries(state.formStates)) {
      formSnapshot[k] = { ...v }
    }

    for (const action of actions) {
      // Per-action confirmation.
      if (action.confirm && confirmFn) {
        const proceed = await confirmFn(action.confirm)
        if (!proceed) return
      }

      // Record cursor actions are handled directly by the store.
      if (isRecordAction(action)) {
        const onEndAction = await handleRecordAction(get, set, action, formSnapshot)
        if (onEndAction) {
          // The cursor hit the end — execute the onEnd action and stop this chain.
          await get().executeActions([onEndAction])
          return
        }
        continue
      }

      const ownerId = app.auth.multiUser && authService
        ? authService.currentUserId
        : undefined

      const result = await executeAction({
        action,
        app,
        formStates: formSnapshot,
        dataService,
        ownerId,
      })

      if (result.error) {
        console.warn('ODS Action Error:', result.error)
        set({ lastActionError: result.error })
        return // Stop executing further actions in the chain.
      }

      if (result.message) {
        set({ lastMessage: result.message })
      }

      // Clear the form after a successful submit so fields reset.
      if (result.submitted && action.target) {
        get().clearForm(action.target, action.preserveFields)
      }

      // Handle cascade rename.
      if (result.cascade) {
        await handleCascade(get, result, action, formSnapshot)
      }

      if (result.navigateTo) {
        get().navigateTo(result.navigateTo)
      }

      // Pre-fill a form with data after navigation.
      if (result.populateForm && result.populateData) {
        const currentFormStates = get().formStates
        const formState = currentFormStates[result.populateForm] ?? {}
        const newFormState = { ...formState }
        for (const [key, rawValue] of Object.entries(result.populateData)) {
          let value = rawValue != null ? String(rawValue) : ''
          // Resolve {fieldName} references from form state snapshot.
          value = value.replace(/\{(\w+)\}/g, (fullMatch, ref: string) => {
            for (const fs of Object.values(formSnapshot)) {
              if (ref in fs) return fs[ref]
            }
            return fullMatch // Leave unreplaced if not found.
          })
          newFormState[key] = value
        }
        set({
          formStates: {
            ...get().formStates,
            [result.populateForm]: newFormState,
          },
        })
      }
    }
  },

  // -------------------------------------------------------------------------
  // Data querying
  // -------------------------------------------------------------------------

  queryDataSource: async (dataSourceId: string): Promise<Record<string, unknown>[]> => {
    const { app, dataService, authService } = get()
    if (!app || !dataService) return []

    const ds = app.dataSources[dataSourceId]
    if (!ds || !isLocal(ds)) return []

    const table = tableName(ds)

    // Apply ownership filtering when applicable.
    if (ds.ownership.enabled && app.auth.multiUser && authService) {
      return dataService.queryWithOwnership(
        table,
        ds.ownership.ownerField,
        authService.currentUserId,
        authService.isAdmin,
        ds.ownership.adminOverride,
      )
    }

    return dataService.query(table)
  },

  // -------------------------------------------------------------------------
  // Reset & debug
  // -------------------------------------------------------------------------

  reset: () => {
    set({ ...initialState })
  },

  toggleDebugMode: () => {
    set({ debugMode: !get().debugMode })
  },
}))

// ---------------------------------------------------------------------------
// Record cursor helpers (internal)
// ---------------------------------------------------------------------------

type GetState = () => AppState
type SetState = (partial: Partial<AppState>) => void

async function handleRecordAction(
  get: GetState,
  set: SetState,
  action: OdsAction,
  formSnapshot: Record<string, Record<string, string>>,
): Promise<OdsAction | undefined> {
  const formId = action.target
  const { app } = get()
  if (!formId || !app) return undefined

  switch (action.action) {
    case 'firstRecord':
      return await handleFirstRecord(get, set, formId, action, formSnapshot)
    case 'nextRecord':
      return handleNextRecord(get, set, formId, action)
    case 'previousRecord':
      return handlePreviousRecord(get, set, formId, action)
    case 'lastRecord':
      return await handleLastRecord(get, set, formId, action, formSnapshot)
    default:
      return undefined
  }
}

async function handleFirstRecord(
  get: GetState,
  set: SetState,
  formId: string,
  action: OdsAction,
  formSnapshot: Record<string, Record<string, string>>,
): Promise<OdsAction | undefined> {
  const { app, dataService, formStates } = get()
  if (!app || !dataService) return action.onEnd

  // Find the form component to get its recordSource.
  const form = findFormComponent(formId, app)
  if (!form || !form.recordSource) {
    console.warn(`ODS: firstRecord — form "${formId}" has no recordSource`)
    return undefined
  }

  const ds = app.dataSources[form.recordSource]
  if (!ds || !isLocal(ds)) return action.onEnd

  // Resolve {field} references in the filter from current form state.
  const resolvedFilter = resolveFilter(action.filter, formSnapshot, formStates)

  let rows: Record<string, unknown>[]
  try {
    if (resolvedFilter && Object.keys(resolvedFilter).length > 0) {
      rows = await dataService.queryWithFilter(tableName(ds), resolvedFilter)
    } else {
      rows = await dataService.query(tableName(ds))
    }
  } catch (e) {
    console.warn('ODS: firstRecord query failed:', e)
    return action.onEnd
  }

  if (rows.length === 0) {
    return action.onEnd
  }

  // Create cursor and populate form.
  const cursor = new RecordCursor(rows, 0)
  const newCursors = { ...get().recordCursors, [formId]: cursor }
  set({ recordCursors: newCursors })
  populateFormFromCursor(get, set, formId)
  return undefined
}

function handleNextRecord(
  get: GetState,
  set: SetState,
  formId: string,
  action: OdsAction,
): OdsAction | undefined {
  const cursor = get().recordCursors[formId]
  if (!cursor || !cursor.hasNext) {
    return action.onEnd
  }

  cursor.currentIndex++
  populateFormFromCursor(get, set, formId)
  return undefined
}

function handlePreviousRecord(
  get: GetState,
  set: SetState,
  formId: string,
  action: OdsAction,
): OdsAction | undefined {
  const cursor = get().recordCursors[formId]
  if (!cursor || !cursor.hasPrevious) {
    return action.onEnd
  }

  cursor.currentIndex--
  populateFormFromCursor(get, set, formId)
  return undefined
}

async function handleLastRecord(
  get: GetState,
  set: SetState,
  formId: string,
  action: OdsAction,
  formSnapshot: Record<string, Record<string, string>>,
): Promise<OdsAction | undefined> {
  // Reuse firstRecord logic to load data, then jump to end.
  const result = await handleFirstRecord(get, set, formId, action, formSnapshot)
  if (result) return result // onEnd (empty)

  const cursor = get().recordCursors[formId]
  if (cursor && !cursor.isEmpty) {
    cursor.currentIndex = cursor.count - 1
    populateFormFromCursor(get, set, formId)
  }
  return undefined
}

function populateFormFromCursor(get: GetState, set: SetState, formId: string): void {
  const cursor = get().recordCursors[formId]
  const record = cursor?.currentRecord
  if (!record) return

  const state: Record<string, string> = {}
  for (const [key, value] of Object.entries(record)) {
    state[key] = value != null ? String(value) : ''
  }

  set({
    formStates: { ...get().formStates, [formId]: state },
    recordGeneration: get().recordGeneration + 1,
  })
}

function resolveFilter(
  filter: Record<string, string> | undefined,
  formSnapshot: Record<string, Record<string, string>>,
  formStates: Record<string, Record<string, string>>,
): Record<string, string> | undefined {
  if (!filter || Object.keys(filter).length === 0) return undefined

  // Build a flat map of all form values for reference resolution.
  const allValues: Record<string, string> = {}
  for (const fs of Object.values(formSnapshot)) {
    Object.assign(allValues, fs)
  }
  for (const fs of Object.values(formStates)) {
    Object.assign(allValues, fs)
  }

  const fieldPattern = /\{(\w+)\}/g
  const resolved: Record<string, string> = {}
  for (const [key, value] of Object.entries(filter)) {
    resolved[key] = value.replace(fieldPattern, (_, ref: string) => allValues[ref] ?? '')
  }
  return resolved
}

function findFormComponent(formId: string, app: OdsApp): OdsFormComponent | undefined {
  for (const page of Object.values(app.pages)) {
    for (const component of page.content) {
      if (component.component === 'form' && (component as OdsFormComponent).id === formId) {
        return component as OdsFormComponent
      }
    }
  }
  return undefined
}

// ---------------------------------------------------------------------------
// Cascade rename helper
// ---------------------------------------------------------------------------

async function handleCascade(
  get: GetState,
  result: ActionResult,
  action: OdsAction,
  formSnapshot: Record<string, Record<string, string>>,
): Promise<void> {
  const { dataService, app } = get()
  if (!dataService || !app || !result.cascade) return

  const childDsId = result.cascade['childDataSource']
  const childField = result.cascade['childLinkField']
  const parentField = result.cascade['parentField']
  const newValue = formSnapshot[action.target!]?.[parentField!]

  if (!childDsId || !childField || !parentField || !newValue) return

  // Find the old value from other form states.
  let oldValue: string | undefined
  for (const [key, fs] of Object.entries(formSnapshot)) {
    if (key === action.target) continue
    const v = fs[parentField]
    if (v && v !== newValue) {
      oldValue = v
      break
    }
  }

  if (!oldValue || oldValue === newValue) return

  // Perform cascade rename on the child data source.
  const childDs = app.dataSources[childDsId]
  if (!childDs || !isLocal(childDs)) return

  const childTable = tableName(childDs)

  try {
    // Query children matching the old value and update them.
    const children = await dataService.queryWithFilter(childTable, { [childField]: oldValue })
    for (const child of children) {
      const updateData: Record<string, unknown> = { [childField]: newValue }
      const matchId = child['_id'] as string
      if (matchId) {
        await dataService.update(childTable, updateData, '_id', matchId)
      }
    }
  } catch (e) {
    console.warn('ODS: Cascade rename failed:', e)
  }
}

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
import { runAutoBackup } from './backup-service.ts'
import { applyBranding, resetBranding } from './branding-service.ts'
import { logWarn, logError } from './log-service.ts'

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

  // Multi-app routing
  currentSlug: string | null

  // Computed getters
  isMultiUser: boolean
  needsAdminSetup: boolean
  needsLogin: boolean
  isMultiUserOnly: boolean

  // Actions
  loadSpec: (jsonString: string, dataService: DataService, authService: AuthService, slug?: string) => Promise<boolean>
  navigateTo: (pageId: string) => void
  goBack: () => void
  canGoBack: () => boolean
  updateFormField: (formId: string, fieldName: string, value: string) => void
  clearForm: (formId: string, preserveFields?: string[]) => void
  getFormState: (formId: string) => Record<string, string>
  populateFormAndNavigate: (formId: string, pageId: string, rowData: Record<string, unknown>) => void
  executeActions: (actions: OdsAction[], confirmFn?: (message: string) => Promise<boolean>) => Promise<void>
  executeDeleteRowAction: (dataSourceId: string, matchField: string, matchValue: string) => Promise<void>
  executeCopyRowsAction: (params: {
    row: Record<string, unknown>
    sourceDataSourceId: string
    targetDataSourceId: string
    parentDataSourceId: string
    linkField: string
    nameField: string
    resetValues: Record<string, string>
  }) => Promise<void>
  executeToggle: (params: {
    dataSourceId: string
    matchField: string
    matchValue: string
    toggleField: string
    currentValue: string
    autoComplete?: {
      groupField: string
      groupValue: string
      parentDataSource: string
      parentMatchField: string
      parentValues: Record<string, string>
    }
  }) => Promise<void>
  queryDataSource: (dataSourceId: string) => Promise<Record<string, unknown>[]>
  cascadeRename: (params: {
    parentDataSourceId: string
    parentMatchField: string
    oldValue: string
    newValue: string
    childDataSourceId: string
    childLinkField: string
  }) => Promise<void>
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
  currentSlug: null as string | null,
  isMultiUser: false,
  needsAdminSetup: false,
  needsLogin: false,
  isMultiUserOnly: false,
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Check startPageByRole for the first matching role, fall back to app.startPage. */
export function startPageForRoles(roles: string[], app: OdsApp): string {
  for (const role of roles) {
    const page = app.startPageByRole[role]
    if (page) return page
  }
  return app.startPage
}

// ---------------------------------------------------------------------------
// Store creation
// ---------------------------------------------------------------------------

export const useAppStore = create<AppState>()((set, get) => ({
  ...initialState,

  // -------------------------------------------------------------------------
  // Spec loading
  // -------------------------------------------------------------------------

  loadSpec: async (jsonString: string, dataService: DataService, authService: AuthService, slug?: string): Promise<boolean> => {
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

      // PocketBase superadmin is available — mark auth service accordingly
      // so role checks and menu filtering work immediately.
      const pbSuperAdminAvailable = dataService.isAdminAuthenticated
      if (pbSuperAdminAvailable) {
        authService.setSuperAdmin(true)
      }

      // Resolve role-based start page from startPageByRole.
      const startPageId = pbSuperAdminAvailable
        ? startPageForRoles(['admin'], app)
        : authService.isLoggedIn
          ? startPageForRoles(authService.currentRoles, app)
          : app.startPage

      set({
        app,
        dataService,
        authService,
        appSettings,
        currentPageId: startPageId,
        navigationStack: [],
        formStates: {},
        recordCursors: {},
        isLoading: false,
        currentSlug: slug ?? null,
        isMultiUser: app.auth.multiUser,
        isMultiUserOnly: app.auth.multiUserOnly ?? false,
        needsAdminSetup: app.auth.multiUser && !pbSuperAdminAvailable && !authService.isAdminSetUp,
        needsLogin: app.auth.multiUser && !pbSuperAdminAvailable && !authService.isLoggedIn,
      })

      // Apply branding — merge spec defaults with any saved user overrides
      const brandingKey = `ods_branding_${app.appName.replace(/[^\w]/g, '_').toLowerCase()}`
      let effectiveBranding = app.branding
      try {
        const saved = JSON.parse(localStorage.getItem(brandingKey) ?? '{}')
        if (saved.theme || saved.mode) {
          effectiveBranding = { ...app.branding, ...saved }
        }
      } catch { /* ignore */ }
      applyBranding(effectiveBranding).catch(() => {})

      // Run auto-backup in background (best-effort, non-blocking)
      runAutoBackup(app, dataService).catch(() => {})

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
    if (!app) return
    if (!app.pages[pageId]) {
      logWarn('AppStore', `Navigate to unknown page "${pageId}"`)
      return
    }

    // Role-based navigation guard.
    const targetPage = app.pages[pageId]
    const isMultiUser = app.auth.multiUser
    if (isMultiUser && authService && !authService.hasAccess(targetPage.roles)) {
      logWarn('AppStore', `Navigation blocked — user lacks role for page "${pageId}"`)
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

    // Use a mutable queue so onEnd can be prepended after successful actions
    // without recursing into executeActions (which would reset lastMessage).
    const queue: OdsAction[] = [...actions]

    while (queue.length > 0) {
      const action = queue.shift()!

      // Per-action confirmation.
      if (action.confirm && confirmFn) {
        const proceed = await confirmFn(action.confirm)
        if (!proceed) return
      }

      // Record cursor actions are handled directly by the store.
      if (isRecordAction(action)) {
        const onEndAction = await handleRecordAction(get, set, action, formSnapshot)
        if (onEndAction) {
          // The cursor hit the end — run the onEnd action next (and stop
          // after it completes; record-action onEnd replaces the rest of
          // the chain, preserving existing semantics).
          queue.length = 0
          queue.push(onEndAction)
        }
        continue
      }

      const ownerId = app.auth.multiUser && authService
        ? authService.currentUserId
        : undefined

      // If this is an update with cascade, query the target row BEFORE the
      // update to capture the current value of the parent cascade field.
      // This is more reliable than scanning other form states for the old
      // value (which breaks for direct withData updates).
      let cascadeOldValueFromRow: string | undefined
      if (action.action === 'update' && action.cascade && action.dataSource && action.matchField) {
        const parentField = action.cascade['parentField']
        const ds = app.dataSources[action.dataSource]
        if (parentField && ds && isLocal(ds)) {
          // Resolve the matchValue: for withData form-less updates it is
          // action.target; otherwise it is the form's matchField value.
          let matchValue: string | undefined
          if (action.withData && action.target) {
            matchValue = action.target
          } else if (action.target) {
            matchValue = formSnapshot[action.target]?.[action.matchField]
          }
          if (matchValue) {
            try {
              const rows = await dataService.queryWithFilter(tableName(ds), {
                [action.matchField]: matchValue,
              })
              if (rows.length > 0) {
                const v = rows[0][parentField]
                if (v != null) cascadeOldValueFromRow = String(v)
              }
            } catch (e) {
              logWarn('AppStore', 'Cascade pre-query failed', e)
            }
          }
        }
      }

      let result: ActionResult
      try {
        result = await executeAction({
          action,
          app,
          formStates: formSnapshot,
          dataService,
          ownerId,
        })
      } catch (e) {
        logError('ActionHandler', 'Action exception', e)
        set({ lastActionError: `Action failed: ${e instanceof Error ? e.message : String(e)}` })
        return
      }

      if (result.error) {
        logWarn('ActionHandler', 'Action error', result.error)
        set({ lastActionError: result.error })
        return // Stop executing further actions in the chain.
      }

      if (result.message) {
        set({ lastMessage: result.message })
      } else if (action.action === 'showMessage') {
        // showMessage explicitly invoked — always set lastMessage (even empty string)
        // so consumers can detect the action fired. Default to '' when the result
        // carries no message.
        set({ lastMessage: result.message ?? '' })
      }

      // Bump record generation so data-bound components re-fetch.
      if (result.submitted) {
        set({ recordGeneration: get().recordGeneration + 1 })
      }

      // Clear the form after a successful submit so fields reset.
      if (result.submitted && action.target) {
        get().clearForm(action.target, action.preserveFields)
      }

      // Handle cascade rename.
      if (result.cascade) {
        await handleCascade(get, result, action, formSnapshot, cascadeOldValueFromRow)
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

      // Universal onEnd: fire onEnd after any successful non-record action.
      // Record actions have their own onEnd semantics handled above (fired
      // when the cursor hits the end). For all other action types, onEnd
      // runs as a follow-up chained action on success. Prepend to the queue
      // so it runs next, before any remaining queued actions.
      if (action.onEnd) {
        queue.unshift(action.onEnd)
      }
    }
  },

  // -------------------------------------------------------------------------
  // Delete row action
  // -------------------------------------------------------------------------

  executeDeleteRowAction: async (dataSourceId: string, matchField: string, matchValue: string) => {
    const { app, dataService } = get()
    if (!app || !dataService) return

    const ds = app.dataSources[dataSourceId]
    if (!ds || !isLocal(ds)) return

    try {
      await dataService.delete(tableName(ds), matchField, matchValue)
      set({ recordGeneration: get().recordGeneration + 1, lastMessage: `Deleted record` })
    } catch (e) {
      logWarn('AppStore', 'Delete row action error', e)
      set({ lastActionError: `Delete failed: ${e}` })
    }
  },

  // -------------------------------------------------------------------------
  // Copy rows action
  // -------------------------------------------------------------------------

  executeCopyRowsAction: async (params: {
    row: Record<string, unknown>
    sourceDataSourceId: string
    targetDataSourceId: string
    parentDataSourceId: string
    linkField: string
    nameField: string
    resetValues: Record<string, string>
  }) => {
    const { app, dataService } = get()
    if (!app || !dataService) return

    const { row, sourceDataSourceId, targetDataSourceId, parentDataSourceId, linkField, nameField, resetValues } = params

    const sourceDsConfig = app.dataSources[sourceDataSourceId]
    const targetDsConfig = app.dataSources[targetDataSourceId]
    const parentDsConfig = app.dataSources[parentDataSourceId]
    if (!sourceDsConfig || !targetDsConfig || !parentDsConfig) return

    try {
      // 1. Generate a copy name from the parent row.
      const originalName = String(row[nameField] ?? 'Untitled')
      const copyName = `${originalName} (copy)`

      // 2. Create the parent copy: duplicate key fields, override values.
      const parentRow: Record<string, unknown> = { ...row }
      delete parentRow['_id']
      parentRow[nameField] = copyName
      // Apply any reset values to the parent.
      for (const [key, value] of Object.entries(resetValues)) {
        if (key in parentRow) {
          parentRow[key] = value
        }
      }
      // Auto-set date fields to today.
      const today = new Date().toISOString().split('T')[0]
      for (const key of Object.keys(parentRow)) {
        if (key.toLowerCase().includes('date') && parentRow[key] != null) {
          parentRow[key] = today
        }
      }
      await dataService.insert(tableName(parentDsConfig), parentRow)

      // 3. Query children linked to the original parent.
      const originalLinkValue = String(row[nameField] ?? '')
      const children = await dataService.query(tableName(sourceDsConfig))
      const matchingChildren = children.filter(
        (child) => String(child[linkField] ?? '') === originalLinkValue,
      )

      // 4. Copy each child with the new link value and reset fields.
      for (const child of matchingChildren) {
        const childCopy: Record<string, unknown> = { ...child }
        delete childCopy['_id']
        childCopy[linkField] = copyName
        for (const [key, value] of Object.entries(resetValues)) {
          childCopy[key] = value
        }
        await dataService.insert(tableName(targetDsConfig), childCopy)
      }

      set({
        recordGeneration: get().recordGeneration + 1,
        lastMessage: `Copied "${originalName}" → "${copyName}" with ${matchingChildren.length} items`,
      })
    } catch (e) {
      logWarn('AppStore', 'CopyRows error', e)
      set({ lastActionError: `Copy failed: ${e}` })
    }
  },

  // -------------------------------------------------------------------------
  // Toggle + autoComplete
  // -------------------------------------------------------------------------

  executeToggle: async (params: {
    dataSourceId: string
    matchField: string
    matchValue: string
    toggleField: string
    currentValue: string
    autoComplete?: {
      groupField: string
      groupValue: string
      parentDataSource: string
      parentMatchField: string
      parentValues: Record<string, string>
    }
  }) => {
    const { app, dataService } = get()
    if (!app || !dataService) return

    const { dataSourceId, matchField, matchValue, toggleField, currentValue, autoComplete } = params

    const ds = app.dataSources[dataSourceId]
    if (!ds || !isLocal(ds)) return

    const newValue = currentValue === 'true' ? 'false' : 'true'

    try {
      await dataService.update(tableName(ds), { [toggleField]: newValue }, matchField, matchValue)

      // Check autoComplete after toggling.
      if (autoComplete && newValue === 'true') {
        const parentDs = app.dataSources[autoComplete.parentDataSource]
        if (parentDs && isLocal(parentDs)) {
          const allRows = await dataService.query(tableName(ds))
          const groupRows = allRows.filter(
            (r) => String(r[autoComplete.groupField] ?? '') === autoComplete.groupValue,
          )

          if (groupRows.length > 0) {
            const allDone = groupRows.every((r) => String(r[toggleField] ?? '') === 'true')
            if (allDone) {
              await dataService.update(
                tableName(parentDs),
                autoComplete.parentValues,
                autoComplete.parentMatchField,
                autoComplete.groupValue,
              )
              set({ lastMessage: 'All items complete — list marked as done!' })
            }
          }
        }
      }

      set({ recordGeneration: get().recordGeneration + 1 })
    } catch (e) {
      logWarn('AppStore', 'Toggle error', e)
      set({ lastActionError: `Toggle failed: ${e}` })
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
  // Cascade rename
  // -------------------------------------------------------------------------

  cascadeRename: async (params: {
    parentDataSourceId: string
    parentMatchField: string
    oldValue: string
    newValue: string
    childDataSourceId: string
    childLinkField: string
  }) => {
    const { app, dataService } = get()
    if (!app || !dataService) return

    const { parentDataSourceId, parentMatchField, oldValue, newValue, childDataSourceId, childLinkField } = params
    if (oldValue === newValue) return

    const parentDs = app.dataSources[parentDataSourceId]
    const childDs = app.dataSources[childDataSourceId]
    if (!parentDs || !childDs || !isLocal(parentDs) || !isLocal(childDs)) return

    try {
      // Update parent row.
      await dataService.update(tableName(parentDs), { [parentMatchField]: newValue }, parentMatchField, oldValue)

      // Update all child rows where the link field matches the old value.
      const children = await dataService.query(tableName(childDs))
      for (const child of children) {
        if (String(child[childLinkField] ?? '') === oldValue) {
          const id = String(child['_id'] ?? '')
          if (id) {
            await dataService.update(tableName(childDs), { [childLinkField]: newValue }, '_id', id)
          }
        }
      }

      set({ recordGeneration: get().recordGeneration + 1 })
    } catch (e) {
      logWarn('AppStore', 'Cascade rename error', e)
      set({ lastActionError: `Cascade rename failed: ${e}` })
    }
  },

  // -------------------------------------------------------------------------
  // Reset & debug
  // -------------------------------------------------------------------------

  reset: () => {
    resetBranding()
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
    logWarn('AppStore', `firstRecord — form "${formId}" has no recordSource`)
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
    logWarn('AppStore', 'firstRecord query failed', e)
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
  preQueriedOldValue?: string,
): Promise<void> {
  const { dataService, app } = get()
  if (!dataService || !app || !result.cascade) return

  const childDsId = result.cascade['childDataSource']
  const childField = result.cascade['childLinkField']
  const parentField = result.cascade['parentField']

  if (!childDsId || !childField || !parentField) return

  // Resolve the new value: prefer form state (for form-based updates);
  // fall back to action.withData (for form-less direct updates).
  let newValue: string | undefined = formSnapshot[action.target!]?.[parentField]
  if (!newValue && action.withData && parentField in action.withData) {
    const v = (action.withData as Record<string, unknown>)[parentField]
    if (v != null) newValue = String(v)
  }

  if (!newValue) return

  // Prefer the pre-queried old value (read from the row before update).
  // Fall back to the legacy form-scan approach for backwards compat when
  // the caller didn't supply it.
  let oldValue: string | undefined = preQueriedOldValue
  if (!oldValue) {
    for (const [key, fs] of Object.entries(formSnapshot)) {
      if (key === action.target) continue
      const v = fs[parentField]
      if (v && v !== newValue) {
        oldValue = v
        break
      }
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
    logWarn('AppStore', 'Cascade rename failed', e)
  }
}

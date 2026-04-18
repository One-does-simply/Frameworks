import { logWarn } from './log-service.ts'
import type { OdsAction, OdsComputedField } from '../models/ods-action.ts'
import type { OdsApp } from '../models/ods-app.ts'
import type { OdsFieldDefinition, OdsValidation } from '../models/ods-field.ts'
import type { OdsFormComponent } from '../models/ods-component.ts'
import { isLocal, tableName } from '../models/ods-data-source.ts'
import { isComputed } from '../models/ods-field.ts'
import { validateField } from '../models/ods-field.ts'
import { evaluateExpression } from './expression-evaluator.ts'
// DataService and FakeDataService both implement DataServiceLike (below)

// ---------------------------------------------------------------------------
// Action result
// ---------------------------------------------------------------------------

/** The outcome of executing a single action. */
export interface ActionResult {
  /** Page ID to navigate to (from a "navigate" action). */
  navigateTo?: string
  /** Whether a "submit" or "update" action completed successfully. */
  submitted: boolean
  /** Human-readable error message if the action failed. */
  error?: string
  /** Informational message to display as a toast (from "showMessage" action). */
  message?: string
  /** Form ID to populate after navigation. */
  populateForm?: string
  /** Data to populate in the form (values may contain {formField} references). */
  populateData?: Record<string, unknown>
  /** Cascade rename config from an update action. */
  cascade?: Record<string, string>
  /** The match field for cascade rename resolution. */
  cascadeMatchField?: string
  /** The old value for cascade rename resolution. */
  cascadeOldValue?: string
}

// ---------------------------------------------------------------------------
// Duck-type interface for data service (DataService or FakeDataService)
// ---------------------------------------------------------------------------

/** Minimal interface shared by DataService and FakeDataService. */
interface DataServiceLike {
  ensureCollection(table: string, fields: OdsFieldDefinition[]): Promise<void>
  insert(table: string, data: Record<string, unknown>): Promise<string>
  update(table: string, data: Record<string, unknown>, matchField: string, matchValue: string): Promise<number>
}

// ---------------------------------------------------------------------------
// Main execute function
// ---------------------------------------------------------------------------

/**
 * Executes a single ODS action and returns the result.
 *
 * ODS Spec alignment: Implements the action types defined in the spec:
 *   - "navigate" -> returns a page ID for the store to navigate to
 *   - "submit" -> collects form data, ensures collection, inserts a row
 *   - "update" -> collects form data, finds matching row, updates it
 *   - "showMessage" -> returns a message string for UI toast display
 *
 * Record cursor actions (firstRecord, nextRecord, etc.) are handled
 * directly by the app store since they manage UI state (form cursors).
 */
export async function executeAction(params: {
  action: OdsAction
  app: OdsApp
  formStates: Record<string, Record<string, string>>
  dataService: DataServiceLike
  ownerId?: string
}): Promise<ActionResult> {
  const { action, app, formStates, dataService, ownerId } = params

  switch (action.action) {
    case 'navigate':
      return {
        submitted: false,
        navigateTo: action.target,
        populateForm: action.populateForm,
        populateData: action.withData,
      }

    case 'submit':
      return await handleSubmit(action, app, formStates, dataService, ownerId)

    case 'update':
      return await handleUpdate(action, app, formStates, dataService)

    case 'showMessage':
      return { submitted: false, message: action.message ?? '' }

    default:
      // Graceful degradation: unknown action types are logged, not crashed.
      logWarn('ActionHandler', `Unknown action type "${action.action}"`)
      return { submitted: false }
  }
}

// ---------------------------------------------------------------------------
// Submit handler
// ---------------------------------------------------------------------------

async function handleSubmit(
  action: OdsAction,
  app: OdsApp,
  formStates: Record<string, Record<string, string>>,
  dataService: DataServiceLike,
  ownerId?: string,
): Promise<ActionResult> {
  const formId = action.target
  const dataSourceId = action.dataSource

  if (!formId || !dataSourceId) {
    return { submitted: false, error: 'Submit action missing target or dataSource' }
  }

  const formData = formStates[formId]
  if (!formData || Object.keys(formData).length === 0) {
    return { submitted: false, error: 'No form data found' }
  }

  // Validate required fields and validation rules before persisting.
  const formFields = findFormFields(formId, app)
  const errors = validateFields(formFields, formData)
  if (errors.length > 0) {
    return { submitted: false, error: formatErrors(errors) }
  }

  const ds = app.dataSources[dataSourceId]
  if (!ds) {
    return { submitted: false, error: 'Unknown dataSource' }
  }

  if (!isLocal(ds)) {
    return { submitted: false, error: 'External dataSources not supported in local mode' }
  }

  // Strip computed, hidden, and framework-injected fields — they are not stored.
  const excludeNames = fieldsToExclude(formFields, formData)
  const storedFields = formFields.filter(f => !isComputed(f) && !excludeNames.has(f.name))
  const declaredNames = new Set(formFields.map(f => f.name))
  const storedData: Record<string, unknown> = {}
  for (const [key, value] of Object.entries(formData)) {
    if (!excludeNames.has(key) && declaredNames.has(key)) {
      storedData[key] = value
    }
  }

  // Evaluate computed fields and merge into stored data.
  applyComputedFields(action.computedFields, storedData, storedFields)

  // "Form is the schema": use the field definitions to create or update the collection.
  if (storedFields.length > 0) {
    await dataService.ensureCollection(tableName(ds), storedFields)
  }

  // Auto-inject ownership field when row-level security is enabled.
  if (ds.ownership.enabled && ownerId) {
    storedData[ds.ownership.ownerField] = ownerId
  }

  await dataService.insert(tableName(ds), storedData)
  return { submitted: true }
}

// ---------------------------------------------------------------------------
// Update handler
// ---------------------------------------------------------------------------

async function handleUpdate(
  action: OdsAction,
  app: OdsApp,
  formStates: Record<string, Record<string, string>>,
  dataService: DataServiceLike,
): Promise<ActionResult> {
  const dataSourceId = action.dataSource
  const matchField = action.matchField

  // Direct update via withData (e.g., kanban drag-drop) — no form needed.
  if (action.withData && dataSourceId && matchField && action.target) {
    const ds = app.dataSources[dataSourceId]
    if (!ds) return { submitted: false, error: 'Unknown dataSource' }
    if (!isLocal(ds)) return { submitted: false, error: 'External dataSources not supported in local mode' }

    // Strip framework-managed and match fields so a crafted spec can't rewrite them.
    const safeData = { ...(action.withData as Record<string, unknown>) }
    delete safeData[matchField]
    delete safeData['_id']
    delete safeData['_createdAt']

    const rowsAffected = await dataService.update(
      tableName(ds),
      safeData,
      matchField,
      action.target,
    )
    if (rowsAffected === 0) {
      console.warn('ActionHandler: No matching record found for', matchField, '=', action.target)
      return { submitted: false, error: 'Record not found' }
    }
    return {
      submitted: true,
      cascade: action.cascade,
      cascadeMatchField: matchField,
      cascadeOldValue: action.target,
    }
  }

  const formId = action.target

  if (!formId || !dataSourceId || !matchField) {
    return { submitted: false, error: 'Update action missing target, dataSource, or matchField' }
  }

  const formData = formStates[formId]
  if (!formData || Object.keys(formData).length === 0) {
    return { submitted: false, error: 'No form data found' }
  }

  const matchValue = (formData[matchField] ?? '').trim()
  if (matchValue === '') {
    return { submitted: false, error: `Match field "${matchField}" is empty` }
  }

  // Validate required fields and validation rules before persisting.
  const formFields = findFormFields(formId, app)
  const errors = validateFields(formFields, formData)
  if (errors.length > 0) {
    return { submitted: false, error: formatErrors(errors) }
  }

  const ds = app.dataSources[dataSourceId]
  if (!ds) {
    return { submitted: false, error: 'Unknown dataSource' }
  }

  if (!isLocal(ds)) {
    return { submitted: false, error: 'External dataSources not supported in local mode' }
  }

  // Strip computed, hidden, and framework-injected fields — they are not stored.
  const excludeNames = fieldsToExclude(formFields, formData)
  const storedFields = formFields.filter(f => !isComputed(f) && !excludeNames.has(f.name))
  const declaredNames = new Set(formFields.map(f => f.name))
  const storedData: Record<string, unknown> = {}
  for (const [key, value] of Object.entries(formData)) {
    if (!excludeNames.has(key) && declaredNames.has(key)) {
      storedData[key] = value
    }
  }

  // Evaluate computed fields and merge into stored data.
  applyComputedFields(action.computedFields, storedData, storedFields)

  // Ensure collection schema is up to date.
  if (storedFields.length > 0) {
    await dataService.ensureCollection(tableName(ds), storedFields)
  }

  const rowsAffected = await dataService.update(
    tableName(ds),
    storedData,
    matchField,
    matchValue,
  )

  if (rowsAffected === 0) {
    console.warn('ActionHandler: No matching record found for', matchField, '=', matchValue)
    return { submitted: false, error: 'Record not found' }
  }

  return {
    submitted: true,
    cascade: action.cascade,
    cascadeMatchField: matchField,
    cascadeOldValue: matchValue,
  }
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/**
 * Validates all visible, non-computed fields. Returns a list of error strings.
 */
function validateFields(
  fields: OdsFieldDefinition[],
  formData: Record<string, string>,
): string[] {
  const errors: string[] = []

  for (const field of fields) {
    if (isComputed(field)) continue
    if (field.readOnly) continue
    if (isFieldHidden(field, formData)) continue

    const value = (formData[field.name] ?? '').trim()

    // Check required.
    if (field.required && value === '') {
      errors.push(`Required: ${field.label ?? field.name}`)
      continue
    }

    // Type-level guards (apply to any non-empty value regardless of validation rules).
    // Required-empty is already handled above; skip type guards for empty values
    // so users can leave optional fields blank.
    if (value !== '') {
      // Number type: must parse to a finite number.
      if (field.type === 'number') {
        const parsed = parseFloat(value)
        if (isNaN(parsed) || !isFinite(parsed)) {
          errors.push(`${field.label ?? field.name}: Must be a number`)
          continue
        }
      }
      // Select type: value must be one of the options (when options is a non-empty list).
      if (field.type === 'select' && Array.isArray(field.options) && field.options.length > 0) {
        if (!field.options.includes(value)) {
          errors.push(`${field.label ?? field.name}: Value must be one of: ${field.options.join(', ')}`)
          continue
        }
      }
    }

    // Check validation rules.
    if (field.validation && value !== '') {
      const error = validateField(field.validation, value, field.type)
      if (error) {
        errors.push(`${field.label ?? field.name}: ${error}`)
      }
    } else if (field.type === 'email' && value !== '') {
      // Always validate email format even without an explicit validation block.
      const defaultValidation: OdsValidation = {}
      const error = validateField(defaultValidation, value, 'email')
      if (error) {
        errors.push(`${field.label ?? field.name}: ${error}`)
      }
    }
  }

  return errors
}

/**
 * Formats a list of validation errors into a user-friendly string.
 * Caps at 5 errors to keep toast messages readable.
 */
function formatErrors(errors: string[]): string {
  if (errors.length <= 5) return errors.join(', ')
  const shown = errors.slice(0, 5).join(', ')
  return `${shown}, and ${errors.length - 5} more`
}

// ---------------------------------------------------------------------------
// Computed fields
// ---------------------------------------------------------------------------

/**
 * Evaluates computed fields from an action and merges them into the data map.
 * Also adds field definitions for computed columns so the collection schema
 * includes them.
 */
function applyComputedFields(
  computedFields: OdsComputedField[],
  data: Record<string, unknown>,
  fields: OdsFieldDefinition[],
): void {
  if (computedFields.length === 0) return

  const formValues: Record<string, string> = {}
  for (const [k, v] of Object.entries(data)) {
    formValues[k] = String(v)
  }

  const existingFieldNames = new Set(fields.map(f => f.name))

  for (const cf of computedFields) {
    const value = evaluateExpression(cf.expression, formValues)
    data[cf.field] = value
    // Ensure the computed column exists in the schema.
    if (!existingFieldNames.has(cf.field)) {
      fields.push({
        name: cf.field,
        type: 'text',
        required: false,
        currency: false,
        readOnly: false,
      })
      existingFieldNames.add(cf.field)
    }
  }
}

// ---------------------------------------------------------------------------
// Field visibility helpers
// ---------------------------------------------------------------------------

/** Checks whether a field is currently hidden by a visibleWhen condition. */
function isFieldHidden(field: OdsFieldDefinition, formData: Record<string, string>): boolean {
  const condition = field.visibleWhen
  if (!condition) return false
  const watchedValue = formData[condition.field] ?? ''
  return watchedValue !== condition.equals
}

/**
 * Returns the set of field names that should be excluded from storage
 * (computed fields + conditionally hidden fields).
 */
function fieldsToExclude(
  fields: OdsFieldDefinition[],
  formData: Record<string, string>,
): Set<string> {
  const exclude = new Set<string>()
  for (const field of fields) {
    if (isComputed(field)) exclude.add(field.name)
    if (isFieldHidden(field, formData)) exclude.add(field.name)
  }
  return exclude
}

// ---------------------------------------------------------------------------
// Form field lookup
// ---------------------------------------------------------------------------

/**
 * Searches all pages for a form component with the given ID and returns
 * its field definitions. Used to auto-create collection schemas.
 */
function findFormFields(formId: string, app: OdsApp): OdsFieldDefinition[] {
  for (const page of Object.values(app.pages)) {
    for (const component of page.content) {
      if (component.component === 'form' && (component as OdsFormComponent).id === formId) {
        return (component as OdsFormComponent).fields
      }
    }
  }
  return []
}

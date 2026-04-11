import type { OdsApp } from '../models/ods-app.ts'
import type { OdsPage } from '../models/ods-page.ts'
import type { OdsComponent } from '../models/ods-component.ts'
import { isComputed } from '../models/ods-field.ts'

// ---------------------------------------------------------------------------
// Validation result types
// ---------------------------------------------------------------------------

export interface ValidationMessage {
  level: 'error' | 'warning' | 'info'
  message: string
  context?: string
}

export class ValidationResult {
  messages: ValidationMessage[] = []

  error(message: string, context?: string) {
    this.messages.push({ level: 'error', message, context })
  }

  warning(message: string, context?: string) {
    this.messages.push({ level: 'warning', message, context })
  }

  info(message: string, context?: string) {
    this.messages.push({ level: 'info', message, context })
  }

  get hasErrors(): boolean {
    return this.messages.some(m => m.level === 'error')
  }

  get errors(): ValidationMessage[] {
    return this.messages.filter(m => m.level === 'error')
  }

  get warnings(): ValidationMessage[] {
    return this.messages.filter(m => m.level === 'warning')
  }
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const VALID_FIELD_TYPES = new Set([
  'text', 'email', 'number', 'date', 'datetime', 'multiline', 'select', 'checkbox', 'hidden', 'user',
])

const VALID_SUMMARY_FUNCTIONS = new Set(['sum', 'avg', 'count', 'min', 'max'])

// ---------------------------------------------------------------------------
// Main validator
// ---------------------------------------------------------------------------

/** Validates an OdsApp for structural integrity and cross-reference correctness. */
export function validate(app: OdsApp): ValidationResult {
  const result = new ValidationResult()

  if (!app.appName) {
    result.error('appName is empty')
  }

  if (!app.pages[app.startPage]) {
    result.error(`startPage "${app.startPage}" does not match any defined page`)
  }
  for (const [role, pageId] of Object.entries(app.startPageByRole)) {
    if (!app.pages[pageId]) {
      result.error(`startPage for role "${role}" references unknown page "${pageId}"`)
    }
  }

  if (Object.keys(app.pages).length === 0) {
    result.error('No pages defined')
  }

  // Menu items point to real pages.
  for (const entry of app.menu) {
    if (!app.pages[entry.mapsTo]) {
      result.warning(`Menu item "${entry.label}" maps to unknown page "${entry.mapsTo}"`)
    }
  }

  // Auth validation.
  validateAuth(app, result)

  // Page component validation.
  for (const [pageId, page] of Object.entries(app.pages)) {
    validatePage(pageId, page, app, result)
  }

  return result
}

// ---------------------------------------------------------------------------
// Page validation
// ---------------------------------------------------------------------------

function validatePage(pageId: string, page: OdsPage, app: OdsApp, result: ValidationResult) {
  for (const component of page.content) {
    validateComponent(component, pageId, app, result)
  }
}

function validateComponent(component: OdsComponent, pageId: string, app: OdsApp, result: ValidationResult) {
  switch (component.component) {
    case 'list': {
      if (!app.dataSources[component.dataSource]) {
        result.warning(
          `List component references unknown dataSource "${component.dataSource}"`,
          `page: ${pageId}`,
        )
      }
      if (component.rowColorMap && !component.rowColorField) {
        result.warning(
          'List has rowColorMap but no rowColorField — colors will not be applied',
          `page: ${pageId}`,
        )
      }
      // Summary rules.
      const columnFields = new Set(component.columns.map(c => c.field))
      for (const rule of component.summary) {
        if (!columnFields.has(rule.column)) {
          result.warning(`Summary rule references unknown column "${rule.column}"`, `page: ${pageId}`)
        }
        if (!VALID_SUMMARY_FUNCTIONS.has(rule.function)) {
          result.warning(`Summary rule has unknown function "${rule.function}"`, `page: ${pageId}`)
        }
      }
      // Row actions.
      for (const ra of component.rowActions) {
        if (!app.dataSources[ra.dataSource]) {
          result.warning(
            `Row action "${ra.label}" references unknown dataSource "${ra.dataSource}"`,
            `page: ${pageId}`,
          )
        }
        if (ra.action === 'update' && Object.keys(ra.values).length === 0) {
          result.warning(`Row action "${ra.label}" has empty values map`, `page: ${pageId}`)
        }
        if (ra.action !== 'update' && ra.action !== 'delete' && ra.action !== 'copyRows') {
          result.warning(
            `Row action "${ra.label}" has unknown action type "${ra.action}"`,
            `page: ${pageId}`,
          )
        }
      }
      break
    }

    case 'button': {
      for (const action of component.onClick) {
        if (action.action === 'navigate' && action.target) {
          if (!app.pages[action.target]) {
            result.warning(
              `Navigate action targets unknown page "${action.target}"`,
              `page: ${pageId}, button: "${component.label}"`,
            )
          }
        }
        if (action.action === 'submit' && action.dataSource) {
          if (!app.dataSources[action.dataSource]) {
            result.warning(
              `Submit action references unknown dataSource "${action.dataSource}"`,
              `page: ${pageId}, button: "${component.label}"`,
            )
          }
        }
        if (action.action === 'update') {
          if (action.dataSource && !app.dataSources[action.dataSource]) {
            result.warning(
              `Update action references unknown dataSource "${action.dataSource}"`,
              `page: ${pageId}, button: "${component.label}"`,
            )
          }
          if (!action.matchField) {
            result.warning(
              'Update action is missing matchField',
              `page: ${pageId}, button: "${component.label}"`,
            )
          }
        }
      }
      break
    }

    case 'form': {
      const fieldNames = new Set(component.fields.map(f => f.name))
      for (const field of component.fields) {
        if (!VALID_FIELD_TYPES.has(field.type)) {
          result.warning(
            `Field "${field.name}" has unknown type "${field.type}"`,
            `page: ${pageId}, form: "${component.id}"`,
          )
        }
        // Computed field validation.
        if (isComputed(field)) {
          // Extract {fieldName} references from formula.
          const deps = (field.formula!.match(/\{(\w+)\}/g) ?? []).map(m => m.slice(1, -1))
          if (deps.length === 0) {
            result.warning(
              `Computed field "${field.name}" formula has no field references`,
              `page: ${pageId}, form: "${component.id}"`,
            )
          }
          for (const dep of deps) {
            if (!fieldNames.has(dep)) {
              result.warning(
                `Computed field "${field.name}" references unknown field "{${dep}}"`,
                `page: ${pageId}, form: "${component.id}"`,
              )
            }
          }
          if (field.required) {
            result.warning(
              `Computed field "${field.name}" is marked required but computed fields are read-only`,
              `page: ${pageId}, form: "${component.id}"`,
            )
          }
        }
        // visibleWhen references.
        if (field.visibleWhen) {
          if (!fieldNames.has(field.visibleWhen.field)) {
            result.warning(
              `Field "${field.name}" visibleWhen references unknown field "${field.visibleWhen.field}"`,
              `page: ${pageId}, form: "${component.id}"`,
            )
          }
        }
        // Validation rules vs field type.
        if (field.validation) {
          if ((field.validation.min != null || field.validation.max != null) && field.type !== 'number') {
            result.warning(
              `Field "${field.name}" has min/max validation but type is "${field.type}" (not number)`,
              `page: ${pageId}, form: "${component.id}"`,
            )
          }
        }
        // Select fields need options.
        if (field.type === 'select') {
          const hasStatic = field.options && field.options.length > 0
          const hasDynamic = field.optionsFrom != null
          if (!hasStatic && !hasDynamic) {
            result.warning(
              `Select field "${field.name}" is missing both options array and optionsFrom`,
              `page: ${pageId}, form: "${component.id}"`,
            )
          }
          if (hasDynamic && !app.dataSources[field.optionsFrom!.dataSource]) {
            result.warning(
              `Select field "${field.name}" optionsFrom references unknown dataSource "${field.optionsFrom!.dataSource}"`,
              `page: ${pageId}, form: "${component.id}"`,
            )
          }
        }
        // Dependent dropdown filter refs.
        if (field.optionsFrom?.filter) {
          if (!fieldNames.has(field.optionsFrom.filter.fromField)) {
            result.warning(
              `Field "${field.name}" optionsFrom.filter.fromField references unknown sibling field "${field.optionsFrom.filter.fromField}"`,
              `page: ${pageId}, form: "${component.id}"`,
            )
          }
        }
      }
      break
    }

    case 'chart': {
      if (!app.dataSources[component.dataSource]) {
        result.warning(`Chart component references unknown dataSource "${component.dataSource}"`, `page: ${pageId}`)
      }
      if (!['bar', 'line', 'pie'].includes(component.chartType)) {
        result.warning(`Chart component has unknown chartType "${component.chartType}"`, `page: ${pageId}`)
      }
      break
    }

    case 'tabs': {
      if (component.tabs.length === 0) {
        result.warning('Tabs component has no tabs defined', `page: ${pageId}`)
      }
      for (const tab of component.tabs) {
        if (tab.content.length === 0) {
          result.warning(`Tab "${tab.label}" has no content`, `page: ${pageId}`)
        }
        for (const nested of tab.content) {
          if (nested.component === 'list' && !app.dataSources[nested.dataSource]) {
            result.warning(
              `List in tab "${tab.label}" references unknown dataSource "${nested.dataSource}"`,
              `page: ${pageId}`,
            )
          }
        }
      }
      break
    }

    case 'kanban': {
      if (!app.dataSources[component.dataSource]) {
        result.warning(
          `Kanban component references unknown dataSource "${component.dataSource}"`,
          `page: ${pageId}`,
        )
      }
      if (!component.statusField) {
        result.warning(
          'Kanban component has empty statusField — board columns cannot be determined',
          `page: ${pageId}`,
        )
      }
      for (const ra of component.rowActions) {
        if (!app.dataSources[ra.dataSource]) {
          result.warning(
            `Row action "${ra.label}" references unknown dataSource "${ra.dataSource}"`,
            `page: ${pageId}`,
          )
        }
        if (ra.action === 'update' && Object.keys(ra.values).length === 0) {
          result.warning(`Row action "${ra.label}" has empty values map`, `page: ${pageId}`)
        }
        if (ra.action !== 'update' && ra.action !== 'delete' && ra.action !== 'copyRows') {
          result.warning(
            `Row action "${ra.label}" has unknown action type "${ra.action}"`,
            `page: ${pageId}`,
          )
        }
      }
      break
    }

    case 'detail': {
      if (!app.dataSources[component.dataSource]) {
        result.warning(`Detail component references unknown dataSource "${component.dataSource}"`, `page: ${pageId}`)
      }
      break
    }

    case 'unknown': {
      result.warning(`Unknown component type "${component.originalType}" will be skipped`, `page: ${pageId}`)
      break
    }
  }
}

// ---------------------------------------------------------------------------
// Auth validation
// ---------------------------------------------------------------------------

function validateAuth(app: OdsApp, result: ValidationResult) {
  const auth = app.auth
  const builtInRoles = new Set(['guest', 'user', 'admin'])
  const allRolesSet = new Set([...builtInRoles, ...auth.customRoles])

  if (auth.multiUserOnly && !auth.multiUser) {
    result.warning('auth.multiUserOnly is true but auth.multiUser is false')
  }

  for (const role of auth.customRoles) {
    if (builtInRoles.has(role)) {
      result.warning(`auth.roles contains built-in role "${role}" — it is always present implicitly`)
    }
  }

  if (!allRolesSet.has(auth.defaultRole)) {
    result.warning(`auth.defaultRole "${auth.defaultRole}" is not a recognized role`)
  }

  function checkRoles(roles: string[] | undefined, context: string) {
    if (!roles) return
    for (const role of roles) {
      if (!allRolesSet.has(role)) {
        result.warning(`Role "${role}" is not defined in auth.roles or built-in defaults`, context)
      }
    }
  }

  for (const item of app.menu) {
    checkRoles(item.roles, `menu: ${item.label}`)
  }

  for (const [pageId, page] of Object.entries(app.pages)) {
    checkRoles(page.roles, `page: ${pageId}`)
    for (const component of page.content) {
      checkRoles(component.roles, `page: ${pageId}`)
      if (component.component === 'list') {
        for (const col of component.columns) {
          checkRoles(col.roles, `page: ${pageId}, column: ${col.field}`)
        }
        for (const action of component.rowActions) {
          checkRoles(action.roles, `page: ${pageId}, rowAction: ${action.label}`)
        }
      }
      if (component.component === 'kanban') {
        for (const action of component.rowActions) {
          checkRoles(action.roles, `page: ${pageId}, rowAction: ${action.label}`)
        }
      }
      if (component.component === 'form') {
        for (const field of component.fields) {
          checkRoles(field.roles, `page: ${pageId}, field: ${field.name}`)
        }
      }
    }
  }

  for (const [dsId, ds] of Object.entries(app.dataSources)) {
    if (ds.ownership.enabled && !auth.multiUser) {
      result.warning(
        `DataSource "${dsId}" has ownership enabled but auth.multiUser is false`,
        `dataSource: ${dsId}`,
      )
    }
  }
}

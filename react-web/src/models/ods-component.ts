import { parseAction, type OdsAction } from './ods-action.ts'
import { parseFieldDefinition, type OdsFieldDefinition } from './ods-field.ts'
import { parseStyleHint, type OdsStyleHint } from './ods-style-hint.ts'
import { parseComponentVisibleWhen, type OdsComponentVisibleWhen } from './ods-visible-when.ts'

// ---------------------------------------------------------------------------
// Shared base fields (every component has these)
// ---------------------------------------------------------------------------

interface OdsComponentBase {
  styleHint: OdsStyleHint
  visibleWhen?: OdsComponentVisibleWhen
  visible?: string
  roles?: string[]
}

function parseBase(j: Record<string, unknown>): OdsComponentBase {
  return {
    styleHint: parseStyleHint(j['styleHint']),
    visibleWhen: parseComponentVisibleWhen(j['visibleWhen']),
    visible: j['visible'] as string | undefined,
    roles: j['roles'] as string[] | undefined,
  }
}

// ---------------------------------------------------------------------------
// List helpers
// ---------------------------------------------------------------------------

export interface OdsToggle {
  dataSource: string
  matchField: string
  autoComplete?: OdsAutoComplete
}

export interface OdsAutoComplete {
  groupField: string
  parentDataSource: string
  parentMatchField: string
  parentValues: Record<string, string>
}

export interface OdsListColumn {
  header: string
  field: string
  sortable: boolean
  filterable: boolean
  currency: boolean
  colorMap?: Record<string, string>
  displayMap?: Record<string, string>
  toggle?: OdsToggle
  roles?: string[]
}

function parseListColumn(json: unknown): OdsListColumn {
  const j = json as Record<string, unknown>
  return {
    header: j['header'] as string,
    field: j['field'] as string,
    sortable: (j['sortable'] as boolean) ?? false,
    filterable: (j['filterable'] as boolean) ?? false,
    currency: (j['currency'] as boolean) ?? false,
    colorMap: j['colorMap'] as Record<string, string> | undefined,
    displayMap: j['displayMap'] as Record<string, string> | undefined,
    toggle: parseToggle(j['toggle']),
    roles: j['roles'] as string[] | undefined,
  }
}

function parseToggle(json: unknown): OdsToggle | undefined {
  if (json == null || typeof json !== 'object') return undefined
  const j = json as Record<string, unknown>
  return {
    dataSource: j['dataSource'] as string,
    matchField: (j['matchField'] as string) ?? '_id',
    autoComplete: parseAutoComplete(j['autoComplete']),
  }
}

function parseAutoComplete(json: unknown): OdsAutoComplete | undefined {
  if (json == null || typeof json !== 'object') return undefined
  const j = json as Record<string, unknown>
  return {
    groupField: j['groupField'] as string,
    parentDataSource: j['parentDataSource'] as string,
    parentMatchField: (j['parentMatchField'] as string) ?? 'name',
    parentValues: (j['parentValues'] as Record<string, string>) ?? {},
  }
}

export interface OdsRowActionHideWhen {
  field: string
  equals?: string
  notEquals?: string
}

/** Returns true if the action should be hidden for this row. */
export function hideWhenMatches(hw: OdsRowActionHideWhen, row: Record<string, unknown>): boolean {
  const rowValue = String(row[hw.field] ?? '')
  if (hw.equals != null && rowValue === hw.equals) return true
  if (hw.notEquals != null && rowValue !== hw.notEquals) return true
  return false
}

export interface OdsRowAction {
  label: string
  action: string
  dataSource: string
  matchField: string
  values: Record<string, string>
  confirm?: string
  hideWhen?: OdsRowActionHideWhen
  sourceDataSource?: string
  targetDataSource?: string
  parentDataSource?: string
  linkField?: string
  nameField?: string
  resetValues: Record<string, string>
  roles?: string[]
}

function parseRowAction(json: unknown): OdsRowAction {
  const j = json as Record<string, unknown>
  const hideWhenRaw = j['hideWhen'] as Record<string, unknown> | undefined
  return {
    label: j['label'] as string,
    action: j['action'] as string,
    dataSource: (j['dataSource'] as string) ?? '',
    matchField: (j['matchField'] as string) ?? '_id',
    values: (j['values'] as Record<string, string>) ?? {},
    confirm: j['confirm'] as string | undefined,
    hideWhen: hideWhenRaw ? {
      field: hideWhenRaw['field'] as string,
      equals: hideWhenRaw['equals'] as string | undefined,
      notEquals: hideWhenRaw['notEquals'] as string | undefined,
    } : undefined,
    sourceDataSource: j['sourceDataSource'] as string | undefined,
    targetDataSource: j['targetDataSource'] as string | undefined,
    parentDataSource: j['parentDataSource'] as string | undefined,
    linkField: j['linkField'] as string | undefined,
    nameField: j['nameField'] as string | undefined,
    resetValues: (j['resetValues'] as Record<string, string>) ?? {},
    roles: j['roles'] as string[] | undefined,
  }
}

export interface OdsSummaryRule {
  column: string
  function: string
  label?: string
}

export interface OdsDefaultSort {
  field: string
  direction: string
}

export interface OdsRowTap {
  target: string
  populateForm?: string
}

export interface OdsTabDefinition {
  label: string
  content: OdsComponent[]
}

// ---------------------------------------------------------------------------
// Component types (discriminated union)
// ---------------------------------------------------------------------------

export interface OdsTextComponent extends OdsComponentBase {
  component: 'text'
  content: string
  format: string
}

export interface OdsListComponent extends OdsComponentBase {
  component: 'list'
  dataSource: string
  columns: OdsListColumn[]
  rowActions: OdsRowAction[]
  summary: OdsSummaryRule[]
  onRowTap?: OdsRowTap
  searchable: boolean
  displayAs: string
  rowColorField?: string
  rowColorMap?: Record<string, string>
  defaultSort?: OdsDefaultSort
}

export interface OdsFormComponent extends OdsComponentBase {
  component: 'form'
  id: string
  fields: OdsFieldDefinition[]
  recordSource?: string
}

export interface OdsButtonComponent extends OdsComponentBase {
  component: 'button'
  label: string
  onClick: OdsAction[]
}

export interface OdsChartComponent extends OdsComponentBase {
  component: 'chart'
  dataSource: string
  chartType: string
  labelField: string
  valueField: string
  title?: string
  aggregate: string
}

export interface OdsSummaryComponent extends OdsComponentBase {
  component: 'summary'
  label: string
  value: string
  icon?: string
}

export interface OdsTabsComponent extends OdsComponentBase {
  component: 'tabs'
  tabs: OdsTabDefinition[]
}

export interface OdsDetailComponent extends OdsComponentBase {
  component: 'detail'
  dataSource: string
  fields?: string[]
  labels?: Record<string, string>
  fromForm?: string
}

export interface OdsKanbanComponent extends OdsComponentBase {
  component: 'kanban'
  dataSource: string
  statusField: string
  titleField?: string
  cardFields: string[]
  rowActions: OdsRowAction[]
  defaultSort?: OdsDefaultSort
  searchable: boolean
}

export interface OdsUnknownComponent extends OdsComponentBase {
  component: 'unknown'
  originalType: string
  rawJson: Record<string, unknown>
}

/** Discriminated union of all ODS component types. */
export type OdsComponent =
  | OdsTextComponent
  | OdsListComponent
  | OdsFormComponent
  | OdsButtonComponent
  | OdsChartComponent
  | OdsSummaryComponent
  | OdsTabsComponent
  | OdsDetailComponent
  | OdsKanbanComponent
  | OdsUnknownComponent

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

function normalizeAggregate(raw: string | undefined): string | undefined {
  if (!raw) return undefined
  switch (raw.toLowerCase()) {
    case 'count': return 'count'
    case 'average': case 'avg': return 'avg'
    case 'sum': return 'sum'
    default: return raw.toLowerCase()
  }
}

export function parseComponent(json: unknown): OdsComponent {
  const j = json as Record<string, unknown>
  const type = j['component'] as string
  const base = parseBase(j)

  switch (type) {
    case 'text':
      return {
        ...base,
        component: 'text',
        content: j['content'] as string,
        format: (j['format'] as string) ?? 'plain',
      }

    case 'list': {
      return {
        ...base,
        component: 'list',
        dataSource: j['dataSource'] as string,
        columns: Array.isArray(j['columns'])
          ? (j['columns'] as unknown[]).map(parseListColumn) : [],
        rowActions: Array.isArray(j['rowActions'])
          ? (j['rowActions'] as unknown[]).map(parseRowAction) : [],
        summary: Array.isArray(j['summary'])
          ? (j['summary'] as unknown[]).map(s => {
              const sr = s as Record<string, unknown>
              return { column: sr['column'] as string, function: sr['function'] as string, label: sr['label'] as string | undefined }
            }) : [],
        onRowTap: j['onRowTap'] ? (() => {
          const rt = j['onRowTap'] as Record<string, unknown>
          return { target: rt['target'] as string, populateForm: rt['populateForm'] as string | undefined }
        })() : undefined,
        searchable: (j['searchable'] as boolean) ?? false,
        displayAs: (j['displayAs'] as string) ?? 'table',
        rowColorField: j['rowColorField'] as string | undefined,
        rowColorMap: j['rowColorMap'] as Record<string, string> | undefined,
        defaultSort: j['defaultSort'] ? (() => {
          const ds = j['defaultSort'] as Record<string, unknown>
          return { field: ds['field'] as string, direction: (ds['direction'] as string) ?? 'asc' }
        })() : undefined,
      }
    }

    case 'form':
      return {
        ...base,
        component: 'form',
        id: j['id'] as string,
        fields: Array.isArray(j['fields'])
          ? (j['fields'] as unknown[]).map(parseFieldDefinition) : [],
        recordSource: j['recordSource'] as string | undefined,
      }

    case 'button':
      return {
        ...base,
        component: 'button',
        label: j['label'] as string,
        onClick: Array.isArray(j['onClick'])
          ? (j['onClick'] as unknown[]).map(parseAction) : [],
      }

    case 'chart': {
      const labelField = j['labelField'] as string
      const valueField = j['valueField'] as string
      const defaultAggregate = labelField === valueField ? 'count' : 'sum'
      return {
        ...base,
        component: 'chart',
        dataSource: j['dataSource'] as string,
        chartType: (j['chartType'] as string) ?? 'bar',
        labelField,
        valueField,
        title: j['title'] as string | undefined,
        aggregate: normalizeAggregate(j['aggregate'] as string | undefined) ?? defaultAggregate,
      }
    }

    case 'summary':
      return {
        ...base,
        component: 'summary',
        label: j['label'] as string,
        value: j['value'] as string,
        icon: j['icon'] as string | undefined,
      }

    case 'tabs':
      return {
        ...base,
        component: 'tabs',
        tabs: Array.isArray(j['tabs'])
          ? (j['tabs'] as unknown[]).map(t => {
              const tab = t as Record<string, unknown>
              return {
                label: tab['label'] as string,
                content: Array.isArray(tab['content'])
                  ? (tab['content'] as unknown[]).map(parseComponent) : [],
              }
            }) : [],
      }

    case 'kanban': {
      return {
        ...base,
        component: 'kanban',
        dataSource: j['dataSource'] as string,
        statusField: (j['statusField'] as string) ?? '',
        titleField: j['titleField'] as string | undefined,
        cardFields: Array.isArray(j['cardFields'])
          ? (j['cardFields'] as string[]) : [],
        rowActions: Array.isArray(j['rowActions'])
          ? (j['rowActions'] as unknown[]).map(parseRowAction) : [],
        defaultSort: j['defaultSort'] ? (() => {
          const ds = j['defaultSort'] as Record<string, unknown>
          return { field: ds['field'] as string, direction: (ds['direction'] as string) ?? 'asc' }
        })() : undefined,
        searchable: (j['searchable'] as boolean) ?? false,
      }
    }

    case 'detail':
      return {
        ...base,
        component: 'detail',
        dataSource: (j['dataSource'] as string) ?? '',
        fields: j['fields'] as string[] | undefined,
        labels: j['labels'] as Record<string, string> | undefined,
        fromForm: j['fromForm'] as string | undefined,
      }

    default:
      return {
        ...base,
        component: 'unknown' as const,
        originalType: type ?? 'unknown',
        rawJson: j as Record<string, unknown>,
      }
  }
}

import { useState, useEffect, useMemo, useCallback } from 'react'
import { useAppStore } from '@/engine/app-store'
import { evaluateFormula } from '@/engine/formula-evaluator'
import { isComputed, type OdsFieldDefinition } from '@/models/ods-field'
import {
  hideWhenMatches,
  type OdsListComponent,
  type OdsListColumn,
  type OdsRowAction,
  type OdsSummaryRule,
} from '@/models/ods-component'

import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Checkbox } from '@/components/ui/checkbox'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type Row = Record<string, unknown>

interface PendingConfirm {
  action: OdsRowAction
  row: Row
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Resolve computed field definitions from the data source. */
function getComputedFields(
  dataSourceId: string,
): Map<string, OdsFieldDefinition> {
  const app = useAppStore.getState().app
  if (!app) return new Map()
  const ds = app.dataSources[dataSourceId]
  if (!ds?.fields) return new Map()
  const map = new Map<string, OdsFieldDefinition>()
  for (const f of ds.fields) {
    if (isComputed(f)) map.set(f.name, f)
  }
  return map
}

/** Get cell value, evaluating computed fields from row data. */
function getCellValue(
  row: Row,
  field: string,
  computedFields: Map<string, OdsFieldDefinition>,
): string {
  const computed = computedFields.get(field)
  if (computed && computed.formula) {
    const values: Record<string, string | null | undefined> = {}
    for (const [k, v] of Object.entries(row)) {
      values[k] = v != null ? String(v) : undefined
    }
    return evaluateFormula(computed.formula, computed.type, values)
  }
  const raw = row[field]
  return raw != null ? String(raw) : ''
}

/** Sort rows in-memory. */
function sortRows(
  rows: Row[],
  sortField: string | null,
  sortAscending: boolean,
): Row[] {
  if (!sortField) return rows
  const sorted = [...rows]
  sorted.sort((a, b) => {
    const aVal = String(a[sortField] ?? '')
    const bVal = String(b[sortField] ?? '')
    const aNum = Number(aVal)
    const bNum = Number(bVal)
    let cmp: number
    if (!isNaN(aNum) && !isNaN(bNum) && aVal !== '' && bVal !== '') {
      cmp = aNum - bNum
    } else {
      cmp = aVal.localeCompare(bVal)
    }
    return sortAscending ? cmp : -cmp
  })
  return sorted
}

/** Filter rows by column filter dropdowns. */
function filterRows(
  rows: Row[],
  filters: Record<string, string | null>,
): Row[] {
  const active = Object.entries(filters).filter(
    ([, v]) => v != null && v !== '',
  )
  if (active.length === 0) return rows
  return rows.filter((row) =>
    active.every(([field, val]) => String(row[field] ?? '') === val),
  )
}

/** Filter rows by search query across visible columns. */
function searchRows(
  rows: Row[],
  query: string,
  columns: OdsListColumn[],
  computedFields: Map<string, OdsFieldDefinition>,
): Row[] {
  if (!query.trim()) return rows
  const lower = query.toLowerCase()
  return rows.filter((row) =>
    columns.some((col) => {
      const value = getCellValue(row, col.field, computedFields)
      return value.toLowerCase().includes(lower)
    }),
  )
}

/** Compute summary value for a column. */
function computeSummary(
  rows: Row[],
  rule: OdsSummaryRule,
  computedFields: Map<string, OdsFieldDefinition>,
): string {
  const fn = rule.function.toLowerCase()

  if (fn === 'count') return rows.length.toString()

  const nums = rows
    .map((r) => {
      const val = getCellValue(r, rule.column, computedFields)
      return Number(val)
    })
    .filter((n) => !isNaN(n))

  if (nums.length === 0) return '0'

  switch (fn) {
    case 'sum':
      return formatNumber(nums.reduce((a, b) => a + b, 0))
    case 'avg':
    case 'average':
      return formatNumber(nums.reduce((a, b) => a + b, 0) / nums.length)
    case 'min':
      return formatNumber(Math.min(...nums))
    case 'max':
      return formatNumber(Math.max(...nums))
    default:
      return ''
  }
}

function formatNumber(n: number): string {
  if (n === Math.round(n)) return Math.round(n).toString()
  return n.toFixed(2)
}

/** Map ODS color names to Tailwind background classes. */
function rowColorClass(colorName: string): string {
  const map: Record<string, string> = {
    red: 'bg-red-50 dark:bg-red-950/30',
    green: 'bg-green-50 dark:bg-green-950/30',
    blue: 'bg-blue-50 dark:bg-blue-950/30',
    yellow: 'bg-yellow-50 dark:bg-yellow-950/30',
    orange: 'bg-orange-50 dark:bg-orange-950/30',
    purple: 'bg-purple-50 dark:bg-purple-950/30',
    gray: 'bg-gray-100 dark:bg-gray-800/30',
    grey: 'bg-gray-100 dark:bg-gray-800/30',
  }
  return map[colorName.toLowerCase()] ?? ''
}

/** Map ODS color names to Tailwind text classes. */
function textColorClass(colorName: string): string {
  const map: Record<string, string> = {
    red: 'text-red-600 dark:text-red-400 font-semibold',
    green: 'text-green-600 dark:text-green-400 font-semibold',
    blue: 'text-blue-600 dark:text-blue-400 font-semibold',
    yellow: 'text-yellow-600 dark:text-yellow-400 font-semibold',
    orange: 'text-orange-600 dark:text-orange-400 font-semibold',
    purple: 'text-purple-600 dark:text-purple-400 font-semibold',
    gray: 'text-gray-500 dark:text-gray-400',
    grey: 'text-gray-500 dark:text-gray-400',
  }
  return map[colorName.toLowerCase()] ?? ''
}

// ---------------------------------------------------------------------------
// Main ListComponent
// ---------------------------------------------------------------------------

interface ListComponentProps {
  model: OdsListComponent
}

export function ListComponent({ model }: ListComponentProps) {
  const queryDataSource = useAppStore((s) => s.queryDataSource)
  const executeActions = useAppStore((s) => s.executeActions)
  const populateFormAndNavigate = useAppStore((s) => s.populateFormAndNavigate)
  const navigateTo = useAppStore((s) => s.navigateTo)
  const authService = useAppStore((s) => s.authService)
  const isMultiUser = useAppStore((s) => s.isMultiUser)
  const lastMessage = useAppStore((s) => s.lastMessage)

  // Data
  const [rows, setRows] = useState<Row[]>([])
  const [loading, setLoading] = useState(true)

  // Sorting
  const [sortField, setSortField] = useState<string | null>(
    model.defaultSort?.field ?? null,
  )
  const [sortAscending, setSortAscending] = useState(
    model.defaultSort ? model.defaultSort.direction !== 'desc' : true,
  )

  // Filters and search
  const [columnFilters, setColumnFilters] = useState<Record<string, string | null>>({})
  const [searchQuery, setSearchQuery] = useState('')

  // Confirm dialog
  const [pendingConfirm, setPendingConfirm] = useState<PendingConfirm | null>(null)

  // Computed fields from data source definition.
  const computedFields = useMemo(
    () => getComputedFields(model.dataSource),
    [model.dataSource],
  )

  // Visible columns (role-filtered).
  const visibleColumns = useMemo(() => {
    if (!isMultiUser || !authService) return model.columns
    return model.columns.filter((col) => authService.hasAccess(col.roles))
  }, [model.columns, isMultiUser, authService])

  // Visible row actions (role-filtered).
  const visibleRowActions = useMemo(() => {
    if (!isMultiUser || !authService) return model.rowActions
    return model.rowActions.filter((action) => authService.hasAccess(action.roles))
  }, [model.rowActions, isMultiUser, authService])

  const hasRowActions = visibleRowActions.length > 0

  // Load data on mount and whenever lastMessage changes (indicating a data mutation).
  useEffect(() => {
    let cancelled = false
    const load = async () => {
      setLoading(true)
      const data = await queryDataSource(model.dataSource)
      if (!cancelled) {
        setRows(data)
        setLoading(false)
      }
    }
    load()
    return () => { cancelled = true }
  }, [model.dataSource, queryDataSource, lastMessage])

  // Process rows: filter -> search -> sort.
  const processedRows = useMemo(() => {
    let result = filterRows(rows, columnFilters)
    result = searchRows(result, searchQuery, visibleColumns, computedFields)
    result = sortRows(result, sortField, sortAscending)
    return result
  }, [rows, columnFilters, searchQuery, visibleColumns, computedFields, sortField, sortAscending])

  // Pre-filter rows (before sort) for summary calculation.
  const summaryRows = useMemo(() => {
    let result = filterRows(rows, columnFilters)
    result = searchRows(result, searchQuery, visibleColumns, computedFields)
    return result
  }, [rows, columnFilters, searchQuery, visibleColumns, computedFields])

  // ---------------------------------------------------------------------------
  // Column header sort handler
  // ---------------------------------------------------------------------------

  const handleSort = useCallback(
    (field: string) => {
      if (sortField === field) {
        setSortAscending((prev) => !prev)
      } else {
        setSortField(field)
        setSortAscending(true)
      }
    },
    [sortField],
  )

  // ---------------------------------------------------------------------------
  // Row tap handler
  // ---------------------------------------------------------------------------

  const handleRowTap = useCallback(
    (row: Row) => {
      if (!model.onRowTap) return
      if (model.onRowTap.populateForm) {
        populateFormAndNavigate(model.onRowTap.populateForm, model.onRowTap.target, row)
      } else {
        navigateTo(model.onRowTap.target)
      }
    },
    [model.onRowTap, populateFormAndNavigate, navigateTo],
  )

  // ---------------------------------------------------------------------------
  // Row action execution
  // ---------------------------------------------------------------------------

  const executeRowAction = useCallback(
    async (action: OdsRowAction, row: Row) => {
      const rowId = String(row[action.matchField] ?? row['_id'] ?? '')
      if (!rowId) return

      if (action.action === 'delete') {
        // Build a delete action.
        await executeActions([
          {
            action: 'delete',
            dataSource: action.dataSource,
            matchField: action.matchField,
            target: rowId,
            computedFields: [],
            preserveFields: [],
          },
        ])
      } else if (action.action === 'update') {
        await executeActions([
          {
            action: 'update',
            dataSource: action.dataSource,
            matchField: action.matchField,
            target: rowId,
            withData: action.values as Record<string, unknown>,
            computedFields: [],
            preserveFields: [],
          },
        ])
      } else if (action.action === 'copyRows') {
        await executeActions([
          {
            action: 'copyRows',
            dataSource: action.sourceDataSource ?? action.dataSource,
            target: action.targetDataSource ?? action.dataSource,
            matchField: action.matchField,
            withData: { [action.matchField]: rowId },
            computedFields: [],
            preserveFields: [],
          },
        ])
      }
    },
    [executeActions],
  )

  const handleRowAction = useCallback(
    (action: OdsRowAction, row: Row) => {
      const needsConfirm = action.confirm != null || action.action === 'delete'
      if (needsConfirm) {
        setPendingConfirm({ action, row })
      } else {
        executeRowAction(action, row)
      }
    },
    [executeRowAction],
  )

  const handleConfirm = useCallback(() => {
    if (pendingConfirm) {
      executeRowAction(pendingConfirm.action, pendingConfirm.row)
      setPendingConfirm(null)
    }
  }, [pendingConfirm, executeRowAction])

  // ---------------------------------------------------------------------------
  // Toggle handler
  // ---------------------------------------------------------------------------

  const handleToggle = useCallback(
    async (col: OdsListColumn, row: Row, currentChecked: boolean) => {
      if (!col.toggle) return
      const rowId = String(row[col.toggle.matchField] ?? row['_id'] ?? '')
      if (!rowId) return

      await executeActions([
        {
          action: 'update',
          dataSource: col.toggle.dataSource,
          matchField: col.toggle.matchField,
          target: rowId,
          withData: { [col.field]: currentChecked ? 'false' : 'true' },
          computedFields: [],
          preserveFields: [],
        },
      ])
    },
    [executeActions],
  )

  // ---------------------------------------------------------------------------
  // Filter dropdown values
  // ---------------------------------------------------------------------------

  const filterableColumns = useMemo(
    () => visibleColumns.filter((col) => col.filterable),
    [visibleColumns],
  )

  const filterOptions = useMemo(() => {
    const opts: Record<string, string[]> = {}
    for (const col of filterableColumns) {
      const unique = new Set<string>()
      for (const row of rows) {
        const val = getCellValue(row, col.field, computedFields)
        if (val) unique.add(val)
      }
      opts[col.field] = Array.from(unique).sort()
    }
    return opts
  }, [filterableColumns, rows, computedFields])

  // ---------------------------------------------------------------------------
  // Resolve row color
  // ---------------------------------------------------------------------------

  const resolveRowColor = useCallback(
    (row: Row): string => {
      if (!model.rowColorField || !model.rowColorMap) return ''
      const val = String(row[model.rowColorField] ?? '')
      const color = model.rowColorMap[val]
      return color ? rowColorClass(color) : ''
    },
    [model.rowColorField, model.rowColorMap],
  )

  // ---------------------------------------------------------------------------
  // Render: Loading
  // ---------------------------------------------------------------------------

  if (loading) {
    return (
      <div className="flex items-center justify-center py-8 text-muted-foreground">
        Loading...
      </div>
    )
  }

  // ---------------------------------------------------------------------------
  // Render: Empty state
  // ---------------------------------------------------------------------------

  if (rows.length === 0) {
    return (
      <Card>
        <CardContent className="py-6">
          <p className="text-muted-foreground text-center">No data yet.</p>
        </CardContent>
      </Card>
    )
  }

  // ---------------------------------------------------------------------------
  // Render: Main content
  // ---------------------------------------------------------------------------

  const isFiltered =
    Object.values(columnFilters).some((v) => v != null && v !== '') ||
    searchQuery.trim() !== ''

  return (
    <div className="space-y-3 py-2">
      {/* Search bar */}
      {model.searchable && (
        <Input
          type="search"
          placeholder="Search..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="max-w-sm"
        />
      )}

      {/* Filter dropdowns */}
      {filterableColumns.length > 0 && (
        <div className="flex flex-wrap gap-3">
          {filterableColumns.map((col) => (
            <div key={col.field} className="flex items-center gap-2">
              <span className="text-sm text-muted-foreground">{col.header}:</span>
              <Select
                value={columnFilters[col.field] ?? '__all__'}
                onValueChange={(val) =>
                  setColumnFilters((prev) => ({
                    ...prev,
                    [col.field]: val === '__all__' ? null : val,
                  }))
                }
              >
                <SelectTrigger className="h-8 w-[150px]">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="__all__">All</SelectItem>
                  {(filterOptions[col.field] ?? []).map((opt) => (
                    <SelectItem key={opt} value={opt}>
                      {opt}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          ))}
        </div>
      )}

      {/* Data display */}
      {model.displayAs === 'cards' ? (
        <CardDisplay
          rows={processedRows}
          columns={visibleColumns}
          computedFields={computedFields}
          rowActions={visibleRowActions}
          onRowTap={model.onRowTap ? handleRowTap : undefined}
          onRowAction={handleRowAction}
          resolveRowColor={resolveRowColor}
        />
      ) : (
        <TableDisplay
          rows={processedRows}
          columns={visibleColumns}
          computedFields={computedFields}
          sortField={sortField}
          sortAscending={sortAscending}
          onSort={handleSort}
          hasRowActions={hasRowActions}
          rowActions={visibleRowActions}
          onRowTap={model.onRowTap ? handleRowTap : undefined}
          onRowAction={handleRowAction}
          onToggle={handleToggle}
          resolveRowColor={resolveRowColor}
        />
      )}

      {/* Tap hint */}
      {model.onRowTap && processedRows.length > 0 && (
        <p className="text-xs text-muted-foreground text-center">
          Click a row to edit
        </p>
      )}

      {/* Summary row */}
      {model.summary.length > 0 && (
        <SummaryRow
          rules={model.summary}
          rows={summaryRows}
          columns={visibleColumns}
          computedFields={computedFields}
        />
      )}

      {/* Filtered count */}
      {isFiltered && (
        <p className="text-xs text-muted-foreground">
          Showing {processedRows.length} of {rows.length} records
        </p>
      )}

      {/* Confirm dialog */}
      <AlertDialog
        open={pendingConfirm != null}
        onOpenChange={(open) => {
          if (!open) setPendingConfirm(null)
        }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Confirm Action</AlertDialogTitle>
            <AlertDialogDescription>
              {pendingConfirm?.action.confirm ??
                (pendingConfirm?.action.action === 'delete'
                  ? 'Are you sure you want to delete this record?'
                  : 'Are you sure?')}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={handleConfirm}>
              Continue
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Table display sub-component
// ---------------------------------------------------------------------------

interface TableDisplayProps {
  rows: Row[]
  columns: OdsListColumn[]
  computedFields: Map<string, OdsFieldDefinition>
  sortField: string | null
  sortAscending: boolean
  onSort: (field: string) => void
  hasRowActions: boolean
  rowActions: OdsRowAction[]
  onRowTap?: (row: Row) => void
  onRowAction: (action: OdsRowAction, row: Row) => void
  onToggle: (col: OdsListColumn, row: Row, checked: boolean) => void
  resolveRowColor: (row: Row) => string
}

function TableDisplay({
  rows,
  columns,
  computedFields,
  sortField,
  sortAscending,
  onSort,
  hasRowActions,
  rowActions,
  onRowTap,
  onRowAction,
  onToggle,
  resolveRowColor,
}: TableDisplayProps) {
  return (
    <div className="overflow-x-auto rounded-md border">
      <Table>
        <TableHeader>
          <TableRow>
            {columns.map((col) => (
              <TableHead
                key={col.field}
                className={col.sortable ? 'cursor-pointer select-none' : ''}
                onClick={col.sortable ? () => onSort(col.field) : undefined}
              >
                <span className="inline-flex items-center gap-1">
                  {col.header}
                  {col.sortable && sortField === col.field && (
                    <span className="text-xs">
                      {sortAscending ? '\u2191' : '\u2193'}
                    </span>
                  )}
                </span>
              </TableHead>
            ))}
            {hasRowActions && <TableHead>Actions</TableHead>}
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((row, idx) => {
            const rowKey = String(row['_id'] ?? idx)
            const colorCls = resolveRowColor(row)
            return (
              <TableRow
                key={rowKey}
                className={`${colorCls} ${onRowTap ? 'cursor-pointer hover:bg-accent/50' : ''}`}
                onClick={onRowTap ? () => onRowTap(row) : undefined}
              >
                {columns.map((col) => (
                  <TableCell key={col.field}>
                    <CellContent
                      col={col}
                      row={row}
                      computedFields={computedFields}
                      onToggle={onToggle}
                    />
                  </TableCell>
                ))}
                {hasRowActions && (
                  <TableCell>
                    <div
                      className="flex gap-1"
                      onClick={(e) => e.stopPropagation()}
                    >
                      {rowActions
                        .filter(
                          (action) =>
                            !action.hideWhen ||
                            !hideWhenMatches(action.hideWhen, row),
                        )
                        .map((action, i) => (
                          <Button
                            key={i}
                            variant={
                              action.action === 'delete'
                                ? 'destructive'
                                : 'outline'
                            }
                            size="sm"
                            onClick={() => onRowAction(action, row)}
                          >
                            {action.label}
                          </Button>
                        ))}
                    </div>
                  </TableCell>
                )}
              </TableRow>
            )
          })}
        </TableBody>
      </Table>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Cell content renderer
// ---------------------------------------------------------------------------

interface CellContentProps {
  col: OdsListColumn
  row: Row
  computedFields: Map<string, OdsFieldDefinition>
  onToggle: (col: OdsListColumn, row: Row, checked: boolean) => void
}

function CellContent({ col, row, computedFields, onToggle }: CellContentProps) {
  // Toggle column: render as checkbox.
  if (col.toggle) {
    const checked = getCellValue(row, col.field, computedFields) === 'true'
    return (
      <Checkbox
        checked={checked}
        onCheckedChange={() => onToggle(col, row, checked)}
        onClick={(e) => e.stopPropagation()}
      />
    )
  }

  const value = getCellValue(row, col.field, computedFields)

  // Apply displayMap.
  let display = value
  if (col.displayMap && col.displayMap[value]) {
    display = col.displayMap[value]
  }

  // Apply colorMap.
  let colorCls = ''
  if (col.colorMap) {
    const colorName = col.colorMap[value]
    if (colorName) {
      colorCls = textColorClass(colorName)
    }
  }

  return <span className={colorCls}>{display}</span>
}

// ---------------------------------------------------------------------------
// Card display sub-component
// ---------------------------------------------------------------------------

interface CardDisplayProps {
  rows: Row[]
  columns: OdsListColumn[]
  computedFields: Map<string, OdsFieldDefinition>
  rowActions: OdsRowAction[]
  onRowTap?: (row: Row) => void
  onRowAction: (action: OdsRowAction, row: Row) => void
  resolveRowColor: (row: Row) => string
}

function CardDisplay({
  rows,
  columns,
  computedFields,
  rowActions,
  onRowTap,
  onRowAction,
  resolveRowColor,
}: CardDisplayProps) {
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
      {rows.map((row, idx) => {
        const rowKey = String(row['_id'] ?? idx)
        const colorCls = resolveRowColor(row)
        return (
          <Card
            key={rowKey}
            className={`${colorCls} ${onRowTap ? 'cursor-pointer hover:shadow-md transition-shadow' : ''}`}
            onClick={onRowTap ? () => onRowTap(row) : undefined}
          >
            <CardHeader className="pb-2">
              <CardTitle className="text-base">
                {getCellValue(row, columns[0]?.field ?? '', computedFields)}
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-1">
              {columns.slice(1).map((col) => {
                const value = getCellValue(row, col.field, computedFields)
                let display = value
                if (col.displayMap && col.displayMap[value]) {
                  display = col.displayMap[value]
                }
                return (
                  <div key={col.field} className="flex justify-between text-sm">
                    <span className="text-muted-foreground">{col.header}</span>
                    <span>{display}</span>
                  </div>
                )
              })}

              {/* Row actions in card mode */}
              {rowActions.length > 0 && (
                <div
                  className="flex gap-1 pt-2"
                  onClick={(e) => e.stopPropagation()}
                >
                  {rowActions
                    .filter(
                      (action) =>
                        !action.hideWhen ||
                        !hideWhenMatches(action.hideWhen, row),
                    )
                    .map((action, i) => (
                      <Button
                        key={i}
                        variant={
                          action.action === 'delete' ? 'destructive' : 'outline'
                        }
                        size="sm"
                        onClick={() => onRowAction(action, row)}
                      >
                        {action.label}
                      </Button>
                    ))}
                </div>
              )}
            </CardContent>
          </Card>
        )
      })}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Summary row sub-component
// ---------------------------------------------------------------------------

interface SummaryRowProps {
  rules: OdsSummaryRule[]
  rows: Row[]
  columns: OdsListColumn[]
  computedFields: Map<string, OdsFieldDefinition>
}

function SummaryRow({ rules, rows, columns, computedFields }: SummaryRowProps) {
  // Build a map of column field -> summary text.
  const summaryMap = new Map<string, string>()
  for (const rule of rules) {
    const label = rule.label ?? rule.function.toUpperCase()
    const value = computeSummary(rows, rule, computedFields)
    summaryMap.set(rule.column, `${label}: ${value}`)
  }

  return (
    <div className="overflow-x-auto rounded-md border bg-muted/50">
      <Table>
        <TableBody>
          <TableRow className="font-semibold">
            {columns.map((col) => (
              <TableCell key={col.field}>
                {summaryMap.get(col.field) ?? ''}
              </TableCell>
            ))}
          </TableRow>
        </TableBody>
      </Table>
    </div>
  )
}

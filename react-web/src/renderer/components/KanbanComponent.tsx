import { useState, useEffect, useMemo, useCallback, useRef } from 'react'
import { useAppStore } from '@/engine/app-store'
import {
  hideWhenMatches,
  type OdsKanbanComponent,
  type OdsRowAction,
} from '@/models/ods-component'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import { Badge } from '@/components/ui/badge'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { isLocal, tableName } from '@/models/ods-data-source'
import type { OdsFieldDefinition } from '@/models/ods-field'
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

/** Deterministic "random" rotation for sticky-note feel, based on row id. */
function cardRotation(id: string): string {
  let hash = 0
  for (let i = 0; i < id.length; i++) {
    hash = ((hash << 5) - hash + id.charCodeAt(i)) | 0
  }
  const deg = ((hash % 5) - 2) * 0.6 // range roughly -1.2 to 1.2 degrees
  return `rotate(${deg}deg)`
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

/** Search rows across card fields. */
function searchRows(
  rows: Row[],
  query: string,
  cardFields: string[],
): Row[] {
  if (!query.trim()) return rows
  const lower = query.toLowerCase()
  return rows.filter((row) =>
    cardFields.some((field) => {
      const val = row[field]
      return val != null && String(val).toLowerCase().includes(lower)
    }),
  )
}

/**
 * Resolve the status field options from the app's data sources or form fields.
 * Looks for a select field matching the statusField name.
 */
function resolveStatusOptions(dataSourceId: string, statusField: string): string[] {
  const app = useAppStore.getState().app
  if (!app) return []

  // First: check the dataSource's own field definitions.
  const ds = app.dataSources[dataSourceId]
  if (ds?.fields) {
    const field = ds.fields.find((f) => f.name === statusField)
    if (field?.options && field.options.length > 0) return field.options
  }

  // Second: search all form components across all pages for a matching select field.
  for (const page of Object.values(app.pages)) {
    for (const component of page.content) {
      if (component.component === 'form') {
        const field = component.fields.find(
          (f) => f.name === statusField && f.type === 'select',
        )
        if (field?.options && field.options.length > 0) return field.options
      }
      // Also check tabs content.
      if (component.component === 'tabs') {
        for (const tab of component.tabs) {
          for (const nested of tab.content) {
            if (nested.component === 'form') {
              const field = nested.fields.find(
                (f) => f.name === statusField && f.type === 'select',
              )
              if (field?.options && field.options.length > 0) return field.options
            }
          }
        }
      }
    }
  }

  return []
}

/**
 * Find a PUT dataSource that points to the same local:// table as the given GET dataSource.
 * Returns the dataSource id if found.
 */
function findPutDataSource(getDataSourceId: string): string | null {
  const app = useAppStore.getState().app
  if (!app) return null

  const getDsUrl = app.dataSources[getDataSourceId]?.url
  if (!getDsUrl) return null

  for (const [id, ds] of Object.entries(app.dataSources)) {
    if (ds.method === 'PUT' && ds.url === getDsUrl) return id
  }
  return null
}

/**
 * Find a POST dataSource that points to the same local:// table as the given GET dataSource.
 * Returns the dataSource id if found.
 */
function findPostDataSource(getDataSourceId: string): string | null {
  const app = useAppStore.getState().app
  if (!app) return null

  const getDsUrl = app.dataSources[getDataSourceId]?.url
  if (!getDsUrl) return null

  for (const [id, ds] of Object.entries(app.dataSources)) {
    if (ds.method === 'POST' && ds.url === getDsUrl) return id
  }
  return null
}

/**
 * Resolve field definitions for the card fields by inspecting dataSource fields and form fields.
 * Returns a map from field name to its definition.
 */
function resolveFieldDefinitions(
  dataSourceId: string,
  fieldNames: string[],
): Map<string, OdsFieldDefinition> {
  const app = useAppStore.getState().app
  if (!app) return new Map()

  const result = new Map<string, OdsFieldDefinition>()

  // Check dataSource fields first.
  const ds = app.dataSources[dataSourceId]
  if (ds?.fields) {
    for (const f of ds.fields) {
      if (fieldNames.includes(f.name)) result.set(f.name, f)
    }
  }

  // Fill in any missing from form fields across pages.
  const missing = fieldNames.filter((n) => !result.has(n))
  if (missing.length > 0) {
    for (const page of Object.values(app.pages)) {
      for (const component of page.content) {
        if (component.component === 'form') {
          for (const f of component.fields) {
            if (missing.includes(f.name) && !result.has(f.name)) {
              result.set(f.name, f)
            }
          }
        }
        if (component.component === 'tabs') {
          for (const tab of component.tabs) {
            for (const nested of tab.content) {
              if (nested.component === 'form') {
                for (const f of nested.fields) {
                  if (missing.includes(f.name) && !result.has(f.name)) {
                    result.set(f.name, f)
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  return result
}

/** Get field label from dataSource fields or form fields. */
function getFieldLabel(dataSourceId: string, fieldName: string): string {
  const app = useAppStore.getState().app
  if (!app) return fieldName

  // Check dataSource fields.
  const ds = app.dataSources[dataSourceId]
  if (ds?.fields) {
    const field = ds.fields.find((f) => f.name === fieldName)
    if (field?.label) return field.label
  }

  // Check form fields.
  for (const page of Object.values(app.pages)) {
    for (const component of page.content) {
      if (component.component === 'form') {
        const field = component.fields.find((f) => f.name === fieldName)
        if (field?.label) return field.label
      }
    }
  }

  // Fallback: capitalize the field name.
  return fieldName.charAt(0).toUpperCase() + fieldName.slice(1)
}

// ---------------------------------------------------------------------------
// Column tint colors (cycles through subtle background tints)
// ---------------------------------------------------------------------------

const COLUMN_TINTS = [
  'bg-slate-50/80 dark:bg-slate-900/40',
  'bg-blue-50/60 dark:bg-blue-950/30',
  'bg-amber-50/60 dark:bg-amber-950/30',
  'bg-emerald-50/60 dark:bg-emerald-950/30',
  'bg-violet-50/60 dark:bg-violet-950/30',
  'bg-rose-50/60 dark:bg-rose-950/30',
  'bg-cyan-50/60 dark:bg-cyan-950/30',
  'bg-orange-50/60 dark:bg-orange-950/30',
]

// ---------------------------------------------------------------------------
// Main KanbanComponent
// ---------------------------------------------------------------------------

interface KanbanComponentProps {
  model: OdsKanbanComponent
}

export function KanbanComponent({ model }: KanbanComponentProps) {
  const queryDataSource = useAppStore((s) => s.queryDataSource)
  const executeActions = useAppStore((s) => s.executeActions)
  const executeDeleteRowAction = useAppStore((s) => s.executeDeleteRowAction)
  const authService = useAppStore((s) => s.authService)
  const isMultiUser = useAppStore((s) => s.isMultiUser)
  const lastMessage = useAppStore((s) => s.lastMessage)
  const recordGeneration = useAppStore((s) => s.recordGeneration)
  const currentPageId = useAppStore((s) => s.currentPageId)

  // Data
  const [rows, setRows] = useState<Row[]>([])
  const [loading, setLoading] = useState(true)

  // Search
  const [searchQuery, setSearchQuery] = useState('')

  // Detail dialog
  const [detailRow, setDetailRow] = useState<Row | null>(null)

  // Confirm dialog
  const [pendingConfirm, setPendingConfirm] = useState<PendingConfirm | null>(null)

  // Drag state
  const [dragOverColumn, setDragOverColumn] = useState<string | null>(null)
  const dragStartedRef = useRef(false)

  // Status options (columns).
  const statusOptions = useMemo(
    () => resolveStatusOptions(model.dataSource, model.statusField),
    [model.dataSource, model.statusField],
  )

  // PUT dataSource for drag-and-drop updates.
  const putDataSourceId = useMemo(
    () => findPutDataSource(model.dataSource),
    [model.dataSource],
  )

  // POST dataSource for adding new cards.
  const postDataSourceId = useMemo(
    () => findPostDataSource(model.dataSource),
    [model.dataSource],
  )

  // Field definitions for card fields (used by quick-add dialog).
  const fieldDefs = useMemo(
    () => resolveFieldDefinitions(model.dataSource, model.cardFields),
    [model.dataSource, model.cardFields],
  )

  // Quick-add state.
  const [addingToColumn, setAddingToColumn] = useState<string | null>(null)
  const [addFormValues, setAddFormValues] = useState<Record<string, string>>({})
  const [addSubmitting, setAddSubmitting] = useState(false)

  // Title field: explicit or first cardFields entry.
  const titleField = model.titleField ?? model.cardFields[0] ?? ''

  // Visible row actions (role-filtered).
  const visibleRowActions = useMemo(() => {
    if (!isMultiUser || !authService) return model.rowActions
    return model.rowActions.filter((action) => authService.hasAccess(action.roles))
  }, [model.rowActions, isMultiUser, authService])

  // Re-fetch data.
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
  }, [model.dataSource, queryDataSource, lastMessage, recordGeneration, currentPageId])

  // Process rows: search -> sort.
  const processedRows = useMemo(() => {
    let result = searchRows(rows, searchQuery, model.cardFields)
    if (model.defaultSort) {
      result = sortRows(
        result,
        model.defaultSort.field,
        model.defaultSort.direction !== 'desc',
      )
    }
    return result
  }, [rows, searchQuery, model.cardFields, model.defaultSort])

  // Group rows by status column value.
  const columnData = useMemo(() => {
    const groups: Record<string, Row[]> = {}
    for (const opt of statusOptions) {
      groups[opt] = []
    }
    for (const row of processedRows) {
      const status = String(row[model.statusField] ?? '')
      if (groups[status]) {
        groups[status].push(row)
      } else {
        // If the row's status doesn't match any option, put it in the first column.
        if (statusOptions.length > 0) {
          groups[statusOptions[0]].push(row)
        }
      }
    }
    return groups
  }, [processedRows, statusOptions, model.statusField])

  // ---------------------------------------------------------------------------
  // Drag and drop handlers
  // ---------------------------------------------------------------------------

  const handleDragStart = useCallback((e: React.DragEvent, rowId: string) => {
    e.dataTransfer.setData('text/plain', rowId)
    e.dataTransfer.effectAllowed = 'move'
    dragStartedRef.current = true
  }, [])

  const handleDragOver = useCallback((e: React.DragEvent, columnValue: string) => {
    e.preventDefault()
    e.dataTransfer.dropEffect = 'move'
    setDragOverColumn(columnValue)
  }, [])

  const handleDragLeave = useCallback(() => {
    setDragOverColumn(null)
  }, [])

  const handleDrop = useCallback(
    async (e: React.DragEvent, columnValue: string) => {
      e.preventDefault()
      setDragOverColumn(null)
      const rowId = e.dataTransfer.getData('text/plain')
      if (!rowId || !putDataSourceId) return

      // Find the row to check if it's already in this column.
      const row = rows.find((r) => String(r['_id'] ?? '') === rowId)
      if (!row) return
      if (String(row[model.statusField] ?? '') === columnValue) return

      // Execute update via the PUT dataSource.
      await executeActions([
        {
          action: 'update',
          dataSource: putDataSourceId,
          matchField: '_id',
          target: rowId,
          withData: { [model.statusField]: columnValue },
          computedFields: [],
          preserveFields: [],
        },
      ])
    },
    [putDataSourceId, rows, model.statusField, executeActions],
  )

  // ---------------------------------------------------------------------------
  // Card click (open detail) — only if not a drag
  // ---------------------------------------------------------------------------

  const handleCardClick = useCallback((row: Row) => {
    if (dragStartedRef.current) {
      dragStartedRef.current = false
      return
    }
    setDetailRow(row)
  }, [])

  const handleDragEnd = useCallback(() => {
    // Reset drag state after a short delay to allow click handler to check it.
    setTimeout(() => { dragStartedRef.current = false }, 50)
  }, [])

  // ---------------------------------------------------------------------------
  // Row action execution (same pattern as ListComponent)
  // ---------------------------------------------------------------------------

  const executeRowAction = useCallback(
    async (action: OdsRowAction, row: Row) => {
      const rowId = String(row[action.matchField] ?? row['_id'] ?? '')
      if (!rowId) return

      if (action.action === 'delete') {
        await executeDeleteRowAction(action.dataSource, action.matchField, rowId)
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
      }
    },
    [executeActions, executeDeleteRowAction],
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
  // Quick-add handlers
  // ---------------------------------------------------------------------------

  const openQuickAdd = useCallback((columnStatus: string) => {
    setAddFormValues({})
    setAddingToColumn(columnStatus)
  }, [])

  const closeQuickAdd = useCallback(() => {
    setAddingToColumn(null)
    setAddFormValues({})
    setAddSubmitting(false)
  }, [])

  const handleAddFieldChange = useCallback((fieldName: string, value: string) => {
    setAddFormValues((prev) => ({ ...prev, [fieldName]: value }))
  }, [])

  const handleQuickAddSubmit = useCallback(async () => {
    if (!postDataSourceId || addingToColumn == null) return

    const app = useAppStore.getState().app
    const dataService = useAppStore.getState().dataService
    if (!app || !dataService) return

    const ds = app.dataSources[postDataSourceId]
    if (!ds || !isLocal(ds)) return

    setAddSubmitting(true)
    try {
      // Build the record: merge form values + status field.
      const record: Record<string, unknown> = {
        ...addFormValues,
        [model.statusField]: addingToColumn,
      }

      // Inject owner if multi-user.
      if (isMultiUser && authService) {
        const ownership = ds.ownership
        if (ownership?.enabled && ownership.ownerField) {
          record[ownership.ownerField] = authService.currentUserId ?? ''
        }
      }

      // Ensure the collection exists (use field defs from POST dataSource or GET).
      const postDs = app.dataSources[postDataSourceId]
      const getDs = app.dataSources[model.dataSource]
      const fields = postDs?.fields ?? getDs?.fields
      if (fields && fields.length > 0) {
        await dataService.ensureCollection(tableName(ds), fields)
      }

      await dataService.insert(tableName(ds), record)

      // Bump record generation to trigger re-fetch.
      useAppStore.setState((s) => ({ recordGeneration: s.recordGeneration + 1 }))

      closeQuickAdd()
    } catch (err) {
      console.error('ODS: Quick-add failed', err)
    } finally {
      setAddSubmitting(false)
    }
  }, [postDataSourceId, addingToColumn, addFormValues, model.statusField, model.dataSource, isMultiUser, authService, closeQuickAdd])

  // ---------------------------------------------------------------------------
  // Render: Loading
  // ---------------------------------------------------------------------------

  if (loading) {
    return (
      <div className="flex items-center justify-center gap-2 py-12 text-muted-foreground">
        <div className="size-4 animate-spin rounded-full border-2 border-primary border-t-transparent" />
        <span className="text-sm">Loading...</span>
      </div>
    )
  }

  // ---------------------------------------------------------------------------
  // Render: No status options
  // ---------------------------------------------------------------------------

  if (statusOptions.length === 0) {
    return (
      <div className="rounded-lg border border-orange-300 bg-orange-50 p-4 text-sm text-orange-800 dark:border-orange-700 dark:bg-orange-950 dark:text-orange-300">
        Kanban board cannot render: no options found for status field &ldquo;{model.statusField}&rdquo;.
        Define options on the select field or in the dataSource field definitions.
      </div>
    )
  }

  // ---------------------------------------------------------------------------
  // Render: Main board
  // ---------------------------------------------------------------------------

  const isFiltered = searchQuery.trim() !== ''

  return (
    <div className="space-y-3 py-2">
      {/* Search bar */}
      {model.searchable && (
        <Input
          type="search"
          placeholder="Search cards..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="max-w-sm"
        />
      )}

      {/* Board */}
      <div className="flex gap-4 overflow-x-auto pb-4">
        {statusOptions.map((status, colIdx) => {
          const cards = columnData[status] ?? []
          const tint = COLUMN_TINTS[colIdx % COLUMN_TINTS.length]
          const isDropTarget = dragOverColumn === status

          return (
            <div
              key={status}
              className={`flex min-w-[280px] max-w-[320px] flex-shrink-0 flex-col rounded-xl border ${tint} ${
                isDropTarget ? 'ring-2 ring-primary/50' : ''
              }`}
              onDragOver={(e) => handleDragOver(e, status)}
              onDragLeave={handleDragLeave}
              onDrop={(e) => handleDrop(e, status)}
            >
              {/* Column header */}
              <div className="flex items-center justify-between px-3 py-2.5 border-b">
                <span className="text-sm font-semibold text-foreground">{status}</span>
                <Badge variant="secondary" className="text-xs">
                  {cards.length}
                </Badge>
              </div>

              {/* Cards container */}
              <div className="flex flex-1 flex-col gap-2.5 overflow-y-auto p-2.5" style={{ maxHeight: '70vh' }}>
                {cards.length === 0 && (
                  <div className="flex items-center justify-center py-8 text-xs text-muted-foreground/60">
                    No cards
                  </div>
                )}
                {cards.map((row) => {
                  const rowId = String(row['_id'] ?? '')
                  return (
                    <KanbanCard
                      key={rowId}
                      row={row}
                      rowId={rowId}
                      titleField={titleField}
                      cardFields={model.cardFields}
                      dataSourceId={model.dataSource}
                      rowActions={visibleRowActions}
                      onDragStart={handleDragStart}
                      onDragEnd={handleDragEnd}
                      onClick={handleCardClick}
                      onRowAction={handleRowAction}
                    />
                  )
                })}
              </div>

              {/* Quick-add button */}
              {postDataSourceId && (
                <div className="border-t px-2.5 py-2">
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-7 w-full justify-start text-xs text-muted-foreground hover:text-foreground"
                    onClick={() => openQuickAdd(status)}
                  >
                    + Add
                  </Button>
                </div>
              )}
            </div>
          )
        })}
      </div>

      {/* Filtered count */}
      {isFiltered && (
        <p className="text-xs text-muted-foreground">
          Showing {processedRows.length} of {rows.length} cards
        </p>
      )}

      {/* Quick-add dialog */}
      <Dialog open={addingToColumn != null} onOpenChange={(open) => { if (!open) closeQuickAdd() }}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle className="text-base">Add to {addingToColumn}</DialogTitle>
          </DialogHeader>
          <div className="space-y-3 pt-1">
            {/* Status field shown as read-only badge */}
            <div className="flex items-center gap-2">
              <Label className="text-xs text-muted-foreground">{getFieldLabel(model.dataSource, model.statusField)}</Label>
              <Badge variant="secondary" className="text-xs">{addingToColumn}</Badge>
            </div>

            {/* Card fields */}
            {model.cardFields
              .filter((f) => f !== model.statusField)
              .map((fieldName, idx) => {
                const def = fieldDefs.get(fieldName)
                const label = def?.label ?? getFieldLabel(model.dataSource, fieldName)
                const fieldType = def?.type ?? 'text'
                const isRequired = idx === 0 || fieldName === titleField
                const value = addFormValues[fieldName] ?? ''

                return (
                  <div key={fieldName} className="space-y-1">
                    <Label className="text-xs">
                      {label}
                      {isRequired && <span className="text-destructive ml-0.5">*</span>}
                    </Label>
                    <QuickAddField
                      fieldName={fieldName}
                      fieldType={fieldType}
                      value={value}
                      options={def?.options}
                      placeholder={def?.placeholder}
                      onChange={handleAddFieldChange}
                    />
                  </div>
                )
              })}

            {/* Actions */}
            <div className="flex justify-end gap-2 pt-1">
              <Button variant="outline" size="sm" onClick={closeQuickAdd}>
                Cancel
              </Button>
              <Button
                size="sm"
                disabled={addSubmitting || !(addFormValues[titleField] ?? '').trim()}
                onClick={handleQuickAddSubmit}
              >
                {addSubmitting ? 'Adding...' : 'Add'}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Detail dialog */}
      <Dialog open={detailRow != null} onOpenChange={(open) => { if (!open) setDetailRow(null) }}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>
              {detailRow ? String(detailRow[titleField] ?? 'Card Details') : 'Card Details'}
            </DialogTitle>
          </DialogHeader>
          {detailRow && (
            <div className="space-y-3 pt-2">
              {model.cardFields.map((field) => {
                const val = detailRow[field]
                if (val == null || String(val) === '') return null
                return (
                  <div key={field} className="flex flex-col gap-0.5">
                    <span className="text-xs font-medium text-muted-foreground">
                      {getFieldLabel(model.dataSource, field)}
                    </span>
                    <span className="text-sm">{String(val)}</span>
                  </div>
                )
              })}
              {/* Status field in detail */}
              <div className="flex flex-col gap-0.5">
                <span className="text-xs font-medium text-muted-foreground">
                  {getFieldLabel(model.dataSource, model.statusField)}
                </span>
                <span className="text-sm">{String(detailRow[model.statusField] ?? '')}</span>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

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
// KanbanCard sub-component
// ---------------------------------------------------------------------------

interface KanbanCardProps {
  row: Row
  rowId: string
  titleField: string
  cardFields: string[]
  dataSourceId: string
  rowActions: OdsRowAction[]
  onDragStart: (e: React.DragEvent, rowId: string) => void
  onDragEnd: () => void
  onClick: (row: Row) => void
  onRowAction: (action: OdsRowAction, row: Row) => void
}

function KanbanCard({
  row,
  rowId,
  titleField,
  cardFields,
  dataSourceId,
  rowActions,
  onDragStart,
  onDragEnd,
  onClick,
  onRowAction,
}: KanbanCardProps) {
  const rotation = useMemo(() => cardRotation(rowId), [rowId])

  // Secondary fields: cardFields minus the title field.
  const secondaryFields = useMemo(
    () => cardFields.filter((f) => f !== titleField),
    [cardFields, titleField],
  )

  const visibleActions = useMemo(
    () => rowActions.filter((a) => !a.hideWhen || !hideWhenMatches(a.hideWhen, row)),
    [rowActions, row],
  )

  return (
    <div
      draggable
      onDragStart={(e) => onDragStart(e, rowId)}
      onDragEnd={onDragEnd}
      onClick={() => onClick(row)}
      className="cursor-grab rounded-lg border bg-card p-3 shadow-sm transition-shadow hover:shadow-md active:cursor-grabbing"
      style={{ transform: rotation }}
    >
      {/* Title */}
      <p className="text-sm font-semibold leading-snug text-card-foreground">
        {String(row[titleField] ?? '')}
      </p>

      {/* Secondary fields */}
      {secondaryFields.length > 0 && (
        <div className="mt-1.5 space-y-0.5">
          {secondaryFields.map((field) => {
            const val = row[field]
            if (val == null || String(val) === '') return null
            return (
              <div key={field} className="flex items-baseline justify-between text-xs text-muted-foreground">
                <span>{getFieldLabel(dataSourceId, field)}</span>
                <span className="ml-2 text-foreground/80 truncate max-w-[140px]">
                  {String(val)}
                </span>
              </div>
            )
          })}
        </div>
      )}

      {/* Row actions */}
      {visibleActions.length > 0 && (
        <div
          className="mt-2 flex flex-wrap gap-1 border-t pt-2"
          onClick={(e) => e.stopPropagation()}
        >
          {visibleActions.map((action, i) => (
            <Button
              key={i}
              variant={action.action === 'delete' ? 'destructive' : 'outline'}
              size="sm"
              className="h-6 text-xs px-2"
              onClick={() => onRowAction(action, row)}
            >
              {action.label}
            </Button>
          ))}
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// QuickAddField sub-component — renders the appropriate input for a field type
// ---------------------------------------------------------------------------

interface QuickAddFieldProps {
  fieldName: string
  fieldType: string
  value: string
  options?: string[]
  placeholder?: string
  onChange: (fieldName: string, value: string) => void
}

function QuickAddField({
  fieldName,
  fieldType,
  value,
  options,
  placeholder,
  onChange,
}: QuickAddFieldProps) {
  switch (fieldType) {
    case 'select':
      return (
        <Select value={value} onValueChange={(v) => onChange(fieldName, v)}>
          <SelectTrigger className="h-8 text-sm">
            <SelectValue placeholder={placeholder ?? 'Select...'} />
          </SelectTrigger>
          <SelectContent>
            {(options ?? []).map((opt) => (
              <SelectItem key={opt} value={opt}>
                {opt}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      )

    case 'multiline':
      return (
        <Textarea
          value={value}
          onChange={(e) => onChange(fieldName, e.target.value)}
          placeholder={placeholder}
          rows={2}
          className="text-sm"
        />
      )

    case 'number':
      return (
        <Input
          type="number"
          value={value}
          onChange={(e) => onChange(fieldName, e.target.value)}
          placeholder={placeholder}
          className="h-8 text-sm"
        />
      )

    case 'date':
      return (
        <Input
          type="date"
          value={value}
          onChange={(e) => onChange(fieldName, e.target.value)}
          className="h-8 text-sm"
        />
      )

    case 'datetime':
      return (
        <Input
          type="datetime-local"
          value={value}
          onChange={(e) => onChange(fieldName, e.target.value)}
          className="h-8 text-sm"
        />
      )

    case 'checkbox':
      return (
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={value === 'true'}
            onChange={(e) => onChange(fieldName, e.target.checked ? 'true' : 'false')}
            className="size-4 rounded border"
          />
          <span className="text-muted-foreground">Yes</span>
        </label>
      )

    case 'email':
      return (
        <Input
          type="email"
          value={value}
          onChange={(e) => onChange(fieldName, e.target.value)}
          placeholder={placeholder}
          className="h-8 text-sm"
        />
      )

    default:
      // text and any unknown type
      return (
        <Input
          type="text"
          value={value}
          onChange={(e) => onChange(fieldName, e.target.value)}
          placeholder={placeholder}
          className="h-8 text-sm"
        />
      )
  }
}

import { useCallback, useEffect, useState } from 'react'
import { useAppStore } from '@/engine/app-store.ts'
import { tableName, isLocal } from '@/models/ods-data-source.ts'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'
import { Badge } from '@/components/ui/badge'
import {
  Table,
  TableHeader,
  TableBody,
  TableHead,
  TableRow,
  TableCell,
} from '@/components/ui/table'
import { Button } from '@/components/ui/button'
import { RefreshCw, ChevronDown, ChevronUp, Download } from 'lucide-react'
import {
  getLogs,
  downloadLogs,
  type LogEntry,
  type LogLevel,
  LEVEL_ORDER,
} from '@/engine/log-service.ts'

// ---------------------------------------------------------------------------
// DebugPanel — collapsible panel at the bottom of the app
// ---------------------------------------------------------------------------
//
// ODS Spec: Debug mode is a framework feature, not a spec feature. The spec
// says nothing about debugging — that's intentional. Debugging is a framework
// concern, and each framework can implement it differently.
//
// ODS Ethos: "Citizen developers need guardrails, not guesswork." When
// something isn't working, the debug panel gives immediate visibility into
// validation issues, navigation state, and stored data — all in context,
// without leaving the app.
//
// Tabs:
//   1. Validation — spec validation messages (errors, warnings, info).
//   2. Navigation — current page, navigation stack, and all page IDs.
//   3. Data — browse data source collections and their rows.
// ---------------------------------------------------------------------------

export function DebugPanel() {
  const [collapsed, setCollapsed] = useState(false)
  const authService = useAppStore((s) => s.authService)

  // In production, only show for admin users.
  if (!import.meta.env.DEV) {
    if (!authService?.isSuperAdmin && !authService?.isAdmin) return null
  }

  return (
    <div className="border-t bg-zinc-950 text-zinc-200">
      {/* Header bar — always visible */}
      <button
        onClick={() => setCollapsed(!collapsed)}
        className="flex w-full items-center justify-between px-4 py-1.5 text-xs font-semibold uppercase tracking-wider text-zinc-400 hover:text-zinc-200"
      >
        <span>Debug Panel</span>
        {collapsed ? (
          <ChevronUp className="size-4" />
        ) : (
          <ChevronDown className="size-4" />
        )}
      </button>

      {/* Panel body */}
      {!collapsed && (
        <div className="h-64">
          <Tabs defaultValue="validation" className="flex h-full flex-col">
            <TabsList className="mx-4 shrink-0">
              <TabsTrigger value="validation">Validation</TabsTrigger>
              <TabsTrigger value="navigation">Navigation</TabsTrigger>
              <TabsTrigger value="data">Data</TabsTrigger>
              <TabsTrigger value="logs">Logs</TabsTrigger>
            </TabsList>

            <TabsContent value="validation" className="min-h-0 flex-1 overflow-y-auto px-4 pb-2">
              <ValidationTab />
            </TabsContent>

            <TabsContent value="navigation" className="min-h-0 flex-1 overflow-y-auto px-4 pb-2">
              <NavigationTab />
            </TabsContent>

            <TabsContent value="data" className="min-h-0 flex-1 overflow-y-auto px-4 pb-2">
              <DataTab />
            </TabsContent>

            <TabsContent value="logs" className="min-h-0 flex-1 overflow-y-auto px-4 pb-2">
              <LogsTab />
            </TabsContent>
          </Tabs>
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Validation Tab
// ---------------------------------------------------------------------------

function ValidationTab() {
  const validation = useAppStore((s) => s.validation)

  if (!validation) {
    return <p className="py-4 text-center text-sm text-zinc-500">No spec loaded</p>
  }

  const messages = validation.messages
  if (messages.length === 0) {
    return <p className="py-4 text-center text-sm text-green-400">No issues found</p>
  }

  return (
    <ul className="space-y-1 py-2">
      {messages.map((msg, i) => {
        const colorClass =
          msg.level === 'error'
            ? 'text-red-400'
            : msg.level === 'warning'
              ? 'text-yellow-400'
              : 'text-blue-400'

        const badgeVariant =
          msg.level === 'error'
            ? 'destructive' as const
            : msg.level === 'warning'
              ? 'secondary' as const
              : 'outline' as const

        return (
          <li key={i} className="flex items-start gap-2 text-xs">
            <Badge variant={badgeVariant} className="mt-0.5 shrink-0 text-[10px] uppercase">
              {msg.level}
            </Badge>
            <div className="min-w-0">
              <span className={colorClass}>{msg.message}</span>
              {msg.context && (
                <span className="ml-2 text-zinc-500">{msg.context}</span>
              )}
            </div>
          </li>
        )
      })}
    </ul>
  )
}

// ---------------------------------------------------------------------------
// Navigation Tab
// ---------------------------------------------------------------------------

function NavigationTab() {
  const app = useAppStore((s) => s.app)
  const currentPageId = useAppStore((s) => s.currentPageId)
  const navigationStack = useAppStore((s) => s.navigationStack)
  const formStates = useAppStore((s) => s.formStates)

  if (!app) {
    return <p className="py-4 text-center text-sm text-zinc-500">No app loaded</p>
  }

  const pageIds = Object.keys(app.pages)

  // Summary of form states: count of fields per form.
  const formSummaries = Object.entries(formStates).map(([formId, fields]) => ({
    formId,
    fieldCount: Object.keys(fields).length,
    filledCount: Object.values(fields).filter((v) => v !== '').length,
  }))

  return (
    <div className="space-y-3 py-2 text-xs">
      {/* Current page */}
      <div>
        <span className="text-zinc-400">Current Page: </span>
        <span className="font-mono text-zinc-100">{currentPageId ?? 'none'}</span>
      </div>

      {/* Navigation stack */}
      <div>
        <span className="text-zinc-400">Stack: </span>
        <span className="font-mono text-zinc-300">
          {navigationStack.length > 0 ? navigationStack.join(' > ') : '(empty)'}
        </span>
      </div>

      {/* All pages */}
      <div>
        <span className="text-zinc-400">Pages:</span>
        <ul className="mt-1 space-y-0.5 pl-2">
          {pageIds.map((pageId) => {
            const isCurrent = pageId === currentPageId
            return (
              <li
                key={pageId}
                className={`font-mono ${isCurrent ? 'text-blue-400 font-semibold' : 'text-zinc-500'}`}
              >
                {isCurrent ? '>> ' : '   '}
                {pageId}
              </li>
            )
          })}
        </ul>
      </div>

      {/* Form states summary */}
      {formSummaries.length > 0 && (
        <div>
          <span className="text-zinc-400">Form States:</span>
          <ul className="mt-1 space-y-0.5 pl-2">
            {formSummaries.map(({ formId, fieldCount, filledCount }) => (
              <li key={formId} className="font-mono text-zinc-400">
                {formId}: {filledCount}/{fieldCount} fields filled
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Data Tab
// ---------------------------------------------------------------------------

interface CollectionInfo {
  dataSourceId: string
  table: string
  rowCount: number
}

function DataTab() {
  const app = useAppStore((s) => s.app)
  const dataService = useAppStore((s) => s.dataService)
  const recordGeneration = useAppStore((s) => s.recordGeneration)

  const [collections, setCollections] = useState<CollectionInfo[]>([])
  const [selectedTable, setSelectedTable] = useState<string | null>(null)
  const [rows, setRows] = useState<Record<string, unknown>[]>([])
  const [isLoading, setIsLoading] = useState(false)

  // Load collection list from data sources.
  const loadCollections = useCallback(async () => {
    if (!app || !dataService) return

    const infos: CollectionInfo[] = []
    for (const [dsId, ds] of Object.entries(app.dataSources)) {
      if (!isLocal(ds)) continue
      const table = tableName(ds)
      const count = await dataService.getRowCount(table)
      infos.push({ dataSourceId: dsId, table, rowCount: count })
    }
    setCollections(infos)
  }, [app, dataService])

  // Reload collections when record generation changes (inserts/deletes).
  useEffect(() => {
    loadCollections()
  }, [loadCollections, recordGeneration])

  // Load rows for a selected table.
  const loadRows = useCallback(
    async (table: string) => {
      if (!dataService) return
      setIsLoading(true)
      setSelectedTable(table)
      try {
        const data = await dataService.query(table)
        setRows(data)
      } catch {
        setRows([])
      } finally {
        setIsLoading(false)
      }
    },
    [dataService],
  )

  // Refresh selected table when generation changes.
  useEffect(() => {
    if (selectedTable) {
      loadRows(selectedTable)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [recordGeneration])

  if (!app || !dataService) {
    return <p className="py-4 text-center text-sm text-zinc-500">No data service</p>
  }

  // Derive column headers from the first row.
  const columns = rows.length > 0 ? Object.keys(rows[0]) : []

  return (
    <div className="flex h-full flex-col gap-2 py-2">
      {/* Collection selector */}
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-xs text-zinc-400">Tables:</span>
        {collections.map((col) => (
          <button
            key={col.table}
            onClick={() => loadRows(col.table)}
            className={`rounded px-2 py-0.5 text-xs transition-colors ${
              col.table === selectedTable
                ? 'bg-blue-600 text-white'
                : 'bg-zinc-800 text-zinc-300 hover:bg-zinc-700'
            }`}
          >
            {col.dataSourceId}{' '}
            <span className="text-zinc-400">({col.rowCount})</span>
          </button>
        ))}
        <Button
          variant="ghost"
          size="icon-sm"
          onClick={() => {
            loadCollections()
            if (selectedTable) loadRows(selectedTable)
          }}
          className="text-zinc-400 hover:text-zinc-200"
        >
          <RefreshCw className="size-3.5" />
        </Button>
      </div>

      {/* Table data */}
      <div className="min-h-0 flex-1 overflow-auto">
        {isLoading ? (
          <p className="py-4 text-center text-xs text-zinc-500">Loading...</p>
        ) : selectedTable === null ? (
          <p className="py-4 text-center text-xs text-zinc-500">Select a table</p>
        ) : rows.length === 0 ? (
          <p className="py-4 text-center text-xs text-zinc-500">No rows</p>
        ) : (
          <Table className="text-xs">
            <TableHeader>
              <TableRow className="border-zinc-700 hover:bg-zinc-900">
                {columns.map((col) => (
                  <TableHead key={col} className="h-7 text-zinc-400">
                    {col}
                  </TableHead>
                ))}
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((row, rowIdx) => (
                <TableRow key={rowIdx} className="border-zinc-800 hover:bg-zinc-900">
                  {columns.map((col) => (
                    <TableCell key={col} className="py-1 text-zinc-300">
                      {row[col] != null ? String(row[col]) : ''}
                    </TableCell>
                  ))}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Logs Tab
// ---------------------------------------------------------------------------

const LEVEL_COLORS: Record<LogLevel, string> = {
  error: 'text-red-400',
  warn: 'text-yellow-400',
  info: 'text-blue-400',
  debug: 'text-zinc-500',
}

const LEVEL_BADGE: Record<LogLevel, 'destructive' | 'secondary' | 'outline'> = {
  error: 'destructive',
  warn: 'secondary',
  info: 'outline',
  debug: 'outline',
}

function LogsTab() {
  const [entries, setEntries] = useState<LogEntry[]>([])
  const [filter, setFilter] = useState<LogLevel>('debug')

  const refresh = useCallback(() => {
    const all = getLogs() as LogEntry[]
    const minOrder = LEVEL_ORDER[filter]
    setEntries(
      all
        .filter(e => LEVEL_ORDER[e.level] >= minOrder)
        .reverse() // newest first
    )
  }, [filter])

  useEffect(() => { refresh() }, [refresh])

  return (
    <div className="flex h-full flex-col gap-2 py-2">
      {/* Controls */}
      <div className="flex items-center gap-2">
        <span className="text-xs text-zinc-400">Filter:</span>
        {(['debug', 'info', 'warn', 'error'] as const).map((lvl) => (
          <button
            key={lvl}
            onClick={() => setFilter(lvl)}
            className={`rounded px-2 py-0.5 text-xs transition-colors ${
              filter === lvl
                ? 'bg-blue-600 text-white'
                : 'bg-zinc-800 text-zinc-300 hover:bg-zinc-700'
            }`}
          >
            {lvl}
          </button>
        ))}
        <span className="text-xs text-zinc-500">({entries.length})</span>
        <div className="flex-1" />
        <Button
          variant="ghost"
          size="icon-sm"
          onClick={() => downloadLogs()}
          className="text-zinc-400 hover:text-zinc-200"
          title="Download logs"
        >
          <Download className="size-3.5" />
        </Button>
        <Button
          variant="ghost"
          size="icon-sm"
          onClick={refresh}
          className="text-zinc-400 hover:text-zinc-200"
          title="Refresh"
        >
          <RefreshCw className="size-3.5" />
        </Button>
      </div>

      {/* Log entries */}
      <div className="min-h-0 flex-1 overflow-auto">
        {entries.length === 0 ? (
          <p className="py-4 text-center text-xs text-zinc-500">No log entries</p>
        ) : (
          <ul className="space-y-0.5">
            {entries.map((entry, i) => (
              <li key={i} className="flex items-start gap-2 text-xs font-mono">
                <span className="shrink-0 text-zinc-600">
                  {entry.timestamp.slice(11, 23)}
                </span>
                <Badge
                  variant={LEVEL_BADGE[entry.level]}
                  className="mt-0.5 shrink-0 text-[9px] uppercase w-12 justify-center"
                >
                  {entry.level}
                </Badge>
                <span className="shrink-0 text-zinc-500">[{entry.category}]</span>
                <span className={LEVEL_COLORS[entry.level]}>{entry.message}</span>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  )
}

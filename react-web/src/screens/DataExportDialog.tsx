import { useState } from 'react'
import { useAppStore } from '@/engine/app-store.ts'
import { isLocal, tableName } from '@/models/ods-data-source.ts'
import type { OdsApp } from '@/models/ods-app.ts'
import type { DataService } from '@/engine/data-service.ts'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog'
import { Separator } from '@/components/ui/separator'
import { toast } from 'sonner'
import { logError } from '@/engine/log-service.ts'
import { FileJson, Table, Database } from 'lucide-react'

// ---------------------------------------------------------------------------
// DataExportDialog — export all app data as JSON, CSV, or SQL
//
// Can be used from either:
//   1. Inside an app (reads from store)  — pass no extra props
//   2. Admin dashboard (pass app + dataService props)
// ---------------------------------------------------------------------------

type ExportFormat = 'json' | 'csv' | 'sql'

interface DataExportDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  /** When provided, use this app instead of reading from store. */
  app?: OdsApp
  /** When provided, use this DataService instead of reading from store. */
  dataService?: DataService
}

export function DataExportDialog({ open, onOpenChange, app: appProp, dataService: dsProp }: DataExportDialogProps) {
  const storeApp = useAppStore((s) => s.app)
  const storeDs = useAppStore((s) => s.dataService)

  const app = appProp ?? storeApp!
  const dataService = dsProp ?? storeDs

  const [isExporting, setIsExporting] = useState(false)

  // Collect all local data source table names
  const localTables: { id: string; table: string }[] = []
  if (app) {
    for (const [dsId, ds] of Object.entries(app.dataSources)) {
      if (isLocal(ds)) {
        localTables.push({ id: dsId, table: tableName(ds) })
      }
    }
  }

  async function handleExport(format: ExportFormat) {
    if (!dataService) return

    setIsExporting(true)
    try {
      // Query all tables
      const exportData: Record<string, Record<string, unknown>[]> = {}
      for (const { table } of localTables) {
        exportData[table] = await dataService.query(table)
      }

      const safeName = app.appName.replace(/[^\w]/g, '_').toLowerCase()

      if (format === 'json') {
        downloadJson(safeName, exportData)
      } else if (format === 'csv') {
        downloadCsv(safeName, exportData)
      } else {
        downloadSql(safeName, exportData)
      }

      toast.success(`Data exported as ${format.toUpperCase()}.`)
      onOpenChange(false)
    } catch (err) {
      logError('DataExport', 'Export failed', err)
      toast.error('Export failed. Check the console for details.')
    } finally {
      setIsExporting(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-sm">
        <DialogHeader>
          <DialogTitle>Export Data</DialogTitle>
          <DialogDescription>
            Download all your app data in the format of your choice.
          </DialogDescription>
        </DialogHeader>

        {localTables.length === 0 ? (
          <p className="py-4 text-center text-sm text-muted-foreground">
            No local data sources to export.
          </p>
        ) : (
          <div className="space-y-1">
            <p className="text-xs text-muted-foreground">
              {localTables.length} table{localTables.length === 1 ? '' : 's'}: {localTables.map((t) => t.table).join(', ')}
            </p>
            <Separator className="my-3" />

            <button
              onClick={() => handleExport('json')}
              disabled={isExporting}
              className="flex w-full items-center gap-3 rounded-lg px-3 py-3 text-left text-sm transition-colors hover:bg-muted disabled:opacity-50"
            >
              <FileJson className="size-5 text-primary" />
              <div>
                <div className="font-medium">JSON</div>
                <div className="text-xs text-muted-foreground">
                  Standard JSON — works with any programming language
                </div>
              </div>
            </button>

            <button
              onClick={() => handleExport('csv')}
              disabled={isExporting}
              className="flex w-full items-center gap-3 rounded-lg px-3 py-3 text-left text-sm transition-colors hover:bg-muted disabled:opacity-50"
            >
              <Table className="size-5 text-primary" />
              <div>
                <div className="font-medium">CSV</div>
                <div className="text-xs text-muted-foreground">
                  Comma-separated values — opens in Excel, Sheets, etc.
                </div>
              </div>
            </button>

            <button
              onClick={() => handleExport('sql')}
              disabled={isExporting}
              className="flex w-full items-center gap-3 rounded-lg px-3 py-3 text-left text-sm transition-colors hover:bg-muted disabled:opacity-50"
            >
              <Database className="size-5 text-primary" />
              <div>
                <div className="font-medium">SQL</div>
                <div className="text-xs text-muted-foreground">
                  CREATE TABLE + INSERT statements for any SQL database
                </div>
              </div>
            </button>
          </div>
        )}

        {isExporting && (
          <p className="text-center text-sm text-muted-foreground">Exporting...</p>
        )}

        <DialogFooter showCloseButton />
      </DialogContent>
    </Dialog>
  )
}

// ---------------------------------------------------------------------------
// Download helpers — Blob + URL.createObjectURL
// ---------------------------------------------------------------------------

function triggerDownload(filename: string, content: string, mimeType: string) {
  const blob = new Blob([content], { type: mimeType })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
}

function downloadJson(
  safeName: string,
  tables: Record<string, Record<string, unknown>[]>,
) {
  const payload = {
    appName: safeName,
    exportedAt: new Date().toISOString(),
    tables,
  }
  const jsonStr = JSON.stringify(payload, null, 2)
  triggerDownload(`${safeName}_export.json`, jsonStr, 'application/json')
}

function downloadCsv(
  safeName: string,
  tables: Record<string, Record<string, unknown>[]>,
) {
  const tableNames = Object.keys(tables)

  for (const tableName of tableNames) {
    const rows = tables[tableName]
    if (!rows || rows.length === 0) continue

    // Collect all column names, excluding internal _id
    const columnSet = new Set<string>()
    for (const row of rows) {
      for (const key of Object.keys(row)) {
        if (key !== '_id' && key !== 'id' && key !== 'collectionId' && key !== 'collectionName') {
          columnSet.add(key)
        }
      }
    }
    const columns = Array.from(columnSet)

    // Build CSV
    const lines: string[] = []
    lines.push(columns.map(csvEscape).join(','))
    for (const row of rows) {
      lines.push(columns.map((col) => csvEscape(String(row[col] ?? ''))).join(','))
    }

    const filename = tableNames.length === 1
      ? `${safeName}_export.csv`
      : `${safeName}_${tableName}.csv`

    triggerDownload(filename, lines.join('\n'), 'text/csv')
  }
}

/** Escape a SQL identifier (table or column name) by doubling any internal double quotes. */
function sqlIdentifier(name: string): string {
  // Validate: only allow safe identifier characters.
  if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(name)) {
    // Fall back to escaping double quotes within the identifier.
    return `"${name.replace(/"/g, '""')}"`
  }
  return `"${name}"`
}

// NOTE: Exported SQL is for reference and data portability only — not for direct
// use in production databases without review. Always validate before executing.
function downloadSql(
  safeName: string,
  tables: Record<string, Record<string, unknown>[]>,
) {
  const lines: string[] = []
  lines.push(`-- ODS Data Export: ${safeName}`)
  lines.push(`-- Exported at: ${new Date().toISOString()}`)
  lines.push('-- WARNING: This SQL is for reference only. Review before executing in production.')
  lines.push('')

  for (const [tblName, rows] of Object.entries(tables)) {
    if (!rows || rows.length === 0) continue

    // Collect all column names, excluding internal fields
    const columnSet = new Set<string>()
    for (const row of rows) {
      for (const key of Object.keys(row)) {
        if (key !== '_id' && key !== 'id' && key !== 'collectionId' && key !== 'collectionName') {
          columnSet.add(key)
        }
      }
    }
    const columns = Array.from(columnSet)

    // CREATE TABLE — use escaped identifiers
    lines.push(`CREATE TABLE IF NOT EXISTS ${sqlIdentifier(tblName)} (`)
    lines.push(columns.map((col) => `  ${sqlIdentifier(col)} TEXT`).join(',\n'))
    lines.push(');')
    lines.push('')

    // INSERT statements — use escaped identifiers and properly escaped values
    for (const row of rows) {
      const values = columns.map((col) => {
        const val = row[col]
        if (val == null) return 'NULL'
        return `'${String(val).replace(/'/g, "''")}'`
      })
      lines.push(`INSERT INTO ${sqlIdentifier(tblName)} (${columns.map((c) => sqlIdentifier(c)).join(', ')}) VALUES (${values.join(', ')});`)
    }
    lines.push('')
  }

  triggerDownload(`${safeName}_export.sql`, lines.join('\n'), 'application/sql')
}

function csvEscape(value: string): string {
  if (value.includes(',') || value.includes('"') || value.includes('\n')) {
    return `"${value.replace(/"/g, '""')}"`
  }
  return value
}

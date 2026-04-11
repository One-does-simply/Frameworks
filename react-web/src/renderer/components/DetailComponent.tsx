import { useEffect, useState } from 'react'
import { logWarn } from '@/engine/log-service.ts'

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useAppStore } from '@/engine/app-store.ts'
import type { OdsDetailComponent } from '@/models/ods-component.ts'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Converts a camelCase or snake_case field name to a human-readable label. */
function humanize(name: string): string {
  // Insert spaces before uppercase letters (camelCase).
  const spaced = name.replace(/([a-z])([A-Z])/g, '$1 $2')
  // Replace underscores, trim, and capitalize first letter.
  const words = spaced.replace(/_/g, ' ').trim()
  if (words.length === 0) return name
  return words[0].toUpperCase() + words.slice(1)
}

// ---------------------------------------------------------------------------
// DetailComponent
// ---------------------------------------------------------------------------

/**
 * Renders an OdsDetailComponent as a read-only card showing field/value pairs.
 *
 * Data can come from either:
 * - A data source (queried via `queryDataSource`)
 * - A form state (read via `getFormState` when `fromForm` is specified)
 */
export function DetailComponent({ model }: { model: OdsDetailComponent }) {
  const queryDataSource = useAppStore((s) => s.queryDataSource)
  const getFormState = useAppStore((s) => s.getFormState)
  const formStates = useAppStore((s) => s.formStates)
  const recordGeneration = useAppStore((s) => s.recordGeneration)

  const [data, setData] = useState<Record<string, string> | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    // If fromForm is set, read from form state directly.
    if (model.fromForm) {
      const formState = getFormState(model.fromForm)
      setData(formState)
      setLoading(false)
      return
    }

    // Otherwise, query the data source.
    let cancelled = false

    async function load() {
      setLoading(true)
      try {
        const rows = await queryDataSource(model.dataSource)
        if (cancelled) return

        if (rows.length === 0) {
          setData(null)
        } else {
          // Show the first (most recent) record, converting values to strings.
          const row = rows[0]
          const stringified: Record<string, string> = {}
          for (const [k, v] of Object.entries(row)) {
            stringified[k] = v != null ? String(v) : ''
          }
          setData(stringified)
        }
      } catch (err) {
        logWarn('DetailComponent', 'Failed to load data', err)
        if (!cancelled) setData(null)
      } finally {
        if (!cancelled) setLoading(false)
      }
    }

    load()
    return () => { cancelled = true }
  }, [queryDataSource, getFormState, model.dataSource, model.fromForm, formStates, recordGeneration])

  if (loading) {
    return (
      <Card className="my-2">
        <CardContent className="py-4">
          <p className="text-muted-foreground">Loading...</p>
        </CardContent>
      </Card>
    )
  }

  if (!data || Object.keys(data).length === 0) {
    return (
      <Card className="my-2">
        <CardContent className="py-4">
          <p className="text-muted-foreground">No data available</p>
        </CardContent>
      </Card>
    )
  }

  // Determine which fields to show and in what order.
  let fieldNames: string[]
  if (model.fields && model.fields.length > 0) {
    fieldNames = model.fields
  } else {
    // Show all fields except internal ones (prefixed with _).
    fieldNames = Object.keys(data).filter((k) => !k.startsWith('_'))
  }

  return (
    <Card className="my-2">
      <CardHeader>
        <CardTitle className="sr-only">Detail</CardTitle>
      </CardHeader>
      <CardContent>
        <dl className="space-y-3">
          {fieldNames.map((field) => {
            const label = model.labels?.[field] ?? humanize(field)
            const value = data[field] ?? ''

            return (
              <div key={field} className="flex gap-3">
                <dt className="w-[120px] shrink-0 text-sm font-medium text-muted-foreground">
                  {label}
                </dt>
                <dd className="text-sm font-medium text-foreground">
                  {value || '\u2014'}
                </dd>
              </div>
            )
          })}
        </dl>
      </CardContent>
    </Card>
  )
}

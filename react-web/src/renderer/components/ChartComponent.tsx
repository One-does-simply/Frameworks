import { useEffect, useState } from 'react'
import {
  BarChart,
  Bar,
  LineChart,
  Line,
  PieChart,
  Pie,
  Cell,
  XAxis,
  YAxis,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts'

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useAppStore } from '@/engine/app-store.ts'
import type { OdsChartComponent } from '@/models/ods-component.ts'

// ---------------------------------------------------------------------------
// Color palette — Tailwind-compatible colors for chart segments
// ---------------------------------------------------------------------------

const CHART_COLORS = [
  '#6366f1', // indigo-500
  '#f43f5e', // rose-500
  '#10b981', // emerald-500
  '#f59e0b', // amber-500
  '#3b82f6', // blue-500
  '#8b5cf6', // violet-500
  '#ec4899', // pink-500
  '#14b8a6', // teal-500
  '#ef4444', // red-500
  '#84cc16', // lime-500
  '#06b6d4', // cyan-500
  '#f97316', // orange-500
]

function getColor(index: number): string {
  return CHART_COLORS[index % CHART_COLORS.length]
}

// ---------------------------------------------------------------------------
// Aggregation
// ---------------------------------------------------------------------------

interface AggregatedEntry {
  label: string
  value: number
}

function aggregateData(
  rows: Record<string, unknown>[],
  labelField: string,
  valueField: string,
  aggregate: string,
): AggregatedEntry[] {
  // Cap rows to prevent excessive memory use.
  const capped = rows.length > 10000 ? rows.slice(0, 10000) : rows

  const sums = new Map<string, number>()
  const counts = new Map<string, number>()

  for (const row of capped) {
    const label = String(row[labelField] ?? 'Unknown')
    const value = Number(row[valueField]) || 0
    sums.set(label, (sums.get(label) ?? 0) + value)
    counts.set(label, (counts.get(label) ?? 0) + 1)
  }

  const labels = [...sums.keys()]

  return labels.map((label) => {
    let value: number
    switch (aggregate) {
      case 'count':
        value = counts.get(label) ?? 0
        break
      case 'avg': {
        const count = counts.get(label) ?? 1
        value = count > 0 ? (sums.get(label) ?? 0) / count : 0
        break
      }
      case 'sum':
      default:
        value = sums.get(label) ?? 0
        break
    }
    return { label, value }
  })
}

// ---------------------------------------------------------------------------
// Chart sub-components
// ---------------------------------------------------------------------------

function OdsBarChart({ data }: { data: AggregatedEntry[] }) {
  return (
    <ResponsiveContainer width="100%" height={250}>
      <BarChart data={data}>
        <XAxis
          dataKey="label"
          tick={{ fontSize: 12 }}
          tickFormatter={(v: string) => (v.length > 12 ? v.slice(0, 12) + '\u2026' : v)}
        />
        <YAxis tick={{ fontSize: 12 }} />
        <Tooltip />
        <Bar dataKey="value" radius={[4, 4, 0, 0]}>
          {data.map((_, i) => (
            <Cell key={i} fill={getColor(i)} />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  )
}

function OdsLineChart({ data }: { data: AggregatedEntry[] }) {
  return (
    <ResponsiveContainer width="100%" height={250}>
      <LineChart data={data}>
        <XAxis
          dataKey="label"
          tick={{ fontSize: 12 }}
          tickFormatter={(v: string) => (v.length > 12 ? v.slice(0, 12) + '\u2026' : v)}
        />
        <YAxis tick={{ fontSize: 12 }} />
        <Tooltip />
        <Line
          type="monotone"
          dataKey="value"
          stroke="#6366f1"
          strokeWidth={2}
          dot={{ r: 4 }}
          activeDot={{ r: 6 }}
        />
      </LineChart>
    </ResponsiveContainer>
  )
}

function OdsPieChart({ data }: { data: AggregatedEntry[] }) {
  return (
    <ResponsiveContainer width="100%" height={250}>
      <PieChart>
        <Pie
          data={data}
          dataKey="value"
          nameKey="label"
          cx="50%"
          cy="50%"
          innerRadius={40}
          outerRadius={80}
          label={({ percent }: { percent?: number }) => `${((percent ?? 0) * 100).toFixed(0)}%`}
        >
          {data.map((_, i) => (
            <Cell key={i} fill={getColor(i)} />
          ))}
        </Pie>
        <Tooltip />
        <Legend />
      </PieChart>
    </ResponsiveContainer>
  )
}

// ---------------------------------------------------------------------------
// Main component
// ---------------------------------------------------------------------------

export function ChartComponent({ model }: { model: OdsChartComponent }) {
  const queryDataSource = useAppStore((s) => s.queryDataSource)
  const recordGeneration = useAppStore((s) => s.recordGeneration)
  const currentPageId = useAppStore((s) => s.currentPageId)
  const [data, setData] = useState<AggregatedEntry[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let cancelled = false

    async function load() {
      setLoading(true)
      try {
        const rows = await queryDataSource(model.dataSource)
        if (cancelled) return
        const aggregated = aggregateData(rows, model.labelField, model.valueField, model.aggregate)
        setData(aggregated)
      } catch (err) {
        console.warn('ODS ChartComponent: failed to load data', err)
        if (!cancelled) setData([])
      } finally {
        if (!cancelled) setLoading(false)
      }
    }

    load()
    return () => { cancelled = true }
  }, [queryDataSource, model.dataSource, model.labelField, model.valueField, model.aggregate, recordGeneration, currentPageId])

  if (loading) {
    return (
      <Card className="my-2">
        <CardContent className="flex items-center justify-center h-[250px]">
          <p className="text-muted-foreground">Loading chart...</p>
        </CardContent>
      </Card>
    )
  }

  if (data.length === 0) {
    return (
      <Card className="my-2">
        <CardContent className="py-4">
          <p className="text-muted-foreground">No data for chart.</p>
        </CardContent>
      </Card>
    )
  }

  function renderChart() {
    switch (model.chartType) {
      case 'line':
        return <OdsLineChart data={data} />
      case 'pie':
        return <OdsPieChart data={data} />
      case 'bar':
      default:
        return <OdsBarChart data={data} />
    }
  }

  return (
    <Card className="my-2">
      {model.title && (
        <CardHeader className="pb-0">
          <CardTitle className="text-center">{model.title}</CardTitle>
        </CardHeader>
      )}
      <CardContent>
        {renderChart()}
      </CardContent>
    </Card>
  )
}

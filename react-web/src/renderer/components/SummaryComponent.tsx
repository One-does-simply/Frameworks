import { useEffect, useState } from 'react'
import { useAppStore } from '@/engine/app-store.ts'
import { hasAggregates, resolveAggregates } from '@/engine/aggregate-evaluator.ts'
import type { OdsSummaryComponent } from '@/models/ods-component.ts'
import { hintColor, hintIcon, hintSize } from '@/models/ods-style-hint.ts'
import { Card, CardContent } from '@/components/ui/card.tsx'
import { resolveIcon } from './ButtonComponent.tsx'
import { cn } from '@/lib/utils.ts'

// ---------------------------------------------------------------------------
// Color mapping — ODS color names to Tailwind classes
// ---------------------------------------------------------------------------

const COLOR_MAP: Record<string, { bg: string; text: string; border: string }> = {
  primary:     { bg: 'bg-primary/10',     text: 'text-primary',                          border: 'border-l-primary' },
  blue:        { bg: 'bg-blue-50 dark:bg-blue-950',     text: 'text-blue-600 dark:text-blue-400',     border: 'border-l-blue-500' },
  green:       { bg: 'bg-green-50 dark:bg-green-950',    text: 'text-green-600 dark:text-green-400',   border: 'border-l-green-500' },
  red:         { bg: 'bg-red-50 dark:bg-red-950',       text: 'text-red-600 dark:text-red-400',       border: 'border-l-red-500' },
  orange:      { bg: 'bg-orange-50 dark:bg-orange-950',   text: 'text-orange-600 dark:text-orange-400', border: 'border-l-orange-500' },
  amber:       { bg: 'bg-amber-50 dark:bg-amber-950',    text: 'text-amber-600 dark:text-amber-400',   border: 'border-l-amber-500' },
  yellow:      { bg: 'bg-yellow-50 dark:bg-yellow-950',   text: 'text-yellow-600 dark:text-yellow-400', border: 'border-l-yellow-500' },
  teal:        { bg: 'bg-teal-50 dark:bg-teal-950',     text: 'text-teal-600 dark:text-teal-400',     border: 'border-l-teal-500' },
  indigo:      { bg: 'bg-indigo-50 dark:bg-indigo-950',   text: 'text-indigo-600 dark:text-indigo-400', border: 'border-l-indigo-500' },
  purple:      { bg: 'bg-purple-50 dark:bg-purple-950',   text: 'text-purple-600 dark:text-purple-400', border: 'border-l-purple-500' },
  pink:        { bg: 'bg-pink-50 dark:bg-pink-950',     text: 'text-pink-600 dark:text-pink-400',     border: 'border-l-pink-500' },
  success:     { bg: 'bg-green-50 dark:bg-green-950',    text: 'text-green-600 dark:text-green-400',   border: 'border-l-green-500' },
  warning:     { bg: 'bg-amber-50 dark:bg-amber-950',    text: 'text-amber-600 dark:text-amber-400',   border: 'border-l-amber-500' },
  info:        { bg: 'bg-blue-50 dark:bg-blue-950',     text: 'text-blue-600 dark:text-blue-400',     border: 'border-l-blue-500' },
  destructive: { bg: 'bg-red-50 dark:bg-red-950',       text: 'text-red-600 dark:text-red-400',       border: 'border-l-red-500' },
}

const DEFAULT_COLORS = {
  bg: 'bg-primary/5',
  text: 'text-primary',
  border: 'border-l-primary',
}

/**
 * Renders an OdsSummaryComponent as a styled KPI card.
 *
 * Shows a label, a large aggregate value, and an optional icon.
 * The value supports aggregate syntax like `{SUM(expenses, amount)}`.
 *
 * Style hints:
 *   - color: accent color for the card border stripe and icon
 *   - icon: overrides the model's icon property
 *   - size: "compact" or "large"
 */
export function SummaryComponent({ model }: { model: OdsSummaryComponent }) {
  const color = hintColor(model.styleHint)
  const iconName = hintIcon(model.styleHint) ?? model.icon
  const size = hintSize(model.styleHint)

  const colors = COLOR_MAP[color ?? ''] ?? DEFAULT_COLORS
  const Icon = resolveIcon(iconName)

  const isCompact = size === 'compact'
  const isLarge = size === 'large'

  const iconSize = isCompact ? 'size-7' : isLarge ? 'size-13' : 'size-10'
  const iconPad = isCompact ? 'p-1.5' : 'p-2.5'
  const valueText = isCompact
    ? 'text-xl font-bold'
    : isLarge
      ? 'text-4xl font-extrabold'
      : 'text-2xl font-bold'

  return (
    <div className="py-2">
      <Card className={cn('border-l-4 py-0', colors.border, colors.bg)}>
        <CardContent className="flex items-center gap-4 py-4">
          {Icon && (
            <div className={cn('rounded-xl', iconPad, `${colors.text} bg-white/60 dark:bg-white/10`)}>
              <Icon className={cn(iconSize, colors.text)} />
            </div>
          )}
          <div className="flex-1 min-w-0">
            <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              {model.label}
            </p>
            <div className="mt-1">
              <SummaryValue
                value={model.value}
                className={cn(valueText, colors.text)}
              />
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

// ---------------------------------------------------------------------------
// SummaryValue — resolves aggregates if present
// ---------------------------------------------------------------------------

function SummaryValue({
  value,
  className,
}: {
  value: string
  className: string
}) {
  if (!hasAggregates(value)) {
    return <p className={className}>{value}</p>
  }

  return <AggregateValue rawValue={value} className={className} />
}

function AggregateValue({
  rawValue,
  className,
}: {
  rawValue: string
  className: string
}) {
  const queryDataSource = useAppStore((s) => s.queryDataSource)
  const currentPageId = useAppStore((s) => s.currentPageId)
  const recordGeneration = useAppStore((s) => s.recordGeneration)
  const [resolved, setResolved] = useState('...')

  useEffect(() => {
    let cancelled = false
    resolveAggregates(rawValue, queryDataSource).then((text) => {
      if (!cancelled) setResolved(text)
    })
    return () => { cancelled = true }
  }, [rawValue, queryDataSource, currentPageId, recordGeneration])

  return <p className={className}>{resolved}</p>
}

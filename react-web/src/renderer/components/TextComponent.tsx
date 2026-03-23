import { useEffect, useState } from 'react'
import Markdown from 'react-markdown'
import { useAppStore } from '@/engine/app-store.ts'
import { hasAggregates, resolveAggregates } from '@/engine/aggregate-evaluator.ts'
import type { OdsTextComponent } from '@/models/ods-component.ts'
import { hintVariant, hintAlign, hintColor } from '@/models/ods-style-hint.ts'
import { cn } from '@/lib/utils.ts'

/**
 * Renders an OdsTextComponent as styled text or Markdown.
 *
 * styleHint mapping:
 *   - variant: heading -> h2, subheading -> h3, body -> p, caption -> small
 *   - align: left/center/right -> text-left/center/right
 *   - color: maps to Tailwind color classes
 *
 * If the content contains aggregate references like `{SUM(expenses, amount)}`,
 * the component resolves them at runtime via the data store.
 */
export function TextComponent({ model }: { model: OdsTextComponent }) {
  const variant = hintVariant(model.styleHint)
  const align = hintAlign(model.styleHint)
  const color = hintColor(model.styleHint)

  const alignClass = resolveAlign(align)
  const colorClass = resolveColor(color)

  // Fast path: no aggregates.
  if (!hasAggregates(model.content)) {
    return (
      <div className={cn('py-2', alignClass)}>
        <TextContent
          text={model.content}
          format={model.format}
          variant={variant}
          colorClass={colorClass}
        />
      </div>
    )
  }

  // Data-aware path: resolve aggregate references.
  return (
    <AggregateText
      content={model.content}
      format={model.format}
      variant={variant}
      alignClass={alignClass}
      colorClass={colorClass}
    />
  )
}

// ---------------------------------------------------------------------------
// Aggregate resolver wrapper
// ---------------------------------------------------------------------------

function AggregateText({
  content,
  format,
  variant,
  alignClass,
  colorClass,
}: {
  content: string
  format: string
  variant: string | undefined
  alignClass: string
  colorClass: string
}) {
  const queryDataSource = useAppStore((s) => s.queryDataSource)
  const currentPageId = useAppStore((s) => s.currentPageId)
  const recordGeneration = useAppStore((s) => s.recordGeneration)
  const [resolved, setResolved] = useState(content)

  useEffect(() => {
    let cancelled = false
    resolveAggregates(content, queryDataSource).then((text) => {
      if (!cancelled) setResolved(text)
    })
    return () => { cancelled = true }
  }, [content, queryDataSource, currentPageId, recordGeneration])

  return (
    <div className={cn('py-2', alignClass)}>
      <TextContent
        text={resolved}
        format={format}
        variant={variant}
        colorClass={colorClass}
      />
    </div>
  )
}

// ---------------------------------------------------------------------------
// Text content — plain text or Markdown
// ---------------------------------------------------------------------------

function TextContent({
  text,
  format,
  variant,
  colorClass,
}: {
  text: string
  format: string
  variant: string | undefined
  colorClass: string
}) {
  if (format === 'markdown') {
    return (
      <div className={cn('prose prose-sm dark:prose-invert max-w-none', colorClass)}>
        <Markdown>{text}</Markdown>
      </div>
    )
  }

  // Plain text — map variant to HTML element.
  const variantClass = resolveVariantClass(variant)

  switch (variant) {
    case 'heading':
      return <h2 className={cn(variantClass, colorClass)}>{text}</h2>
    case 'subheading':
      return <h3 className={cn(variantClass, colorClass)}>{text}</h3>
    case 'caption':
      return <small className={cn(variantClass, colorClass)}>{text}</small>
    case 'body':
    default:
      return <p className={cn(variantClass, colorClass)}>{text}</p>
  }
}

// ---------------------------------------------------------------------------
// Style resolution helpers
// ---------------------------------------------------------------------------

function resolveVariantClass(variant: string | undefined): string {
  switch (variant) {
    case 'heading':
      return 'text-2xl font-bold tracking-tight'
    case 'subheading':
      return 'text-lg font-semibold'
    case 'caption':
      return 'text-xs text-muted-foreground'
    case 'body':
    default:
      return 'text-sm'
  }
}

function resolveAlign(align: string | undefined): string {
  switch (align) {
    case 'center': return 'text-center'
    case 'right': return 'text-right'
    case 'left':
    default:
      return 'text-left'
  }
}

function resolveColor(color: string | undefined): string {
  if (!color) return ''

  const colorMap: Record<string, string> = {
    primary: 'text-primary',
    secondary: 'text-secondary-foreground',
    muted: 'text-muted-foreground',
    destructive: 'text-destructive',
    success: 'text-green-600 dark:text-green-400',
    warning: 'text-amber-600 dark:text-amber-400',
    info: 'text-blue-600 dark:text-blue-400',
    red: 'text-red-600 dark:text-red-400',
    orange: 'text-orange-600 dark:text-orange-400',
    amber: 'text-amber-600 dark:text-amber-400',
    yellow: 'text-yellow-600 dark:text-yellow-400',
    green: 'text-green-600 dark:text-green-400',
    teal: 'text-teal-600 dark:text-teal-400',
    blue: 'text-blue-600 dark:text-blue-400',
    indigo: 'text-indigo-600 dark:text-indigo-400',
    purple: 'text-purple-600 dark:text-purple-400',
    pink: 'text-pink-600 dark:text-pink-400',
  }

  return colorMap[color] ?? ''
}

import { useEffect, useState } from 'react'
import { useAppStore } from '@/engine/app-store.ts'
import { evaluateBool } from '@/engine/expression-evaluator.ts'
import {
  isFieldBased,
  isDataBased,
  type OdsComponentVisibleWhen,
} from '@/models/ods-visible-when.ts'
import type { OdsPage } from '@/models/ods-page.ts'
import type { OdsComponent } from '@/models/ods-component.ts'
import { RoleGuard } from './RoleGuard.tsx'
import { TextComponent } from './components/TextComponent.tsx'
import { ButtonComponent } from './components/ButtonComponent.tsx'
import { SummaryComponent } from './components/SummaryComponent.tsx'
import { FormComponent } from './components/FormComponent.tsx'
import { ListComponent } from './components/ListComponent.tsx'
import { ChartComponent } from './components/ChartComponent.tsx'
import { TabsComponent } from './components/TabsComponent.tsx'
import { DetailComponent } from './components/DetailComponent.tsx'
import { KanbanComponent } from './components/KanbanComponent.tsx'

// ---------------------------------------------------------------------------
// PageRenderer — maps an OdsPage to rendered components
// ---------------------------------------------------------------------------

export function PageRenderer({ page }: { page: OdsPage }) {
  return (
    <div className="mx-auto max-w-5xl space-y-3 px-4 py-5">
      {page.content.map((component, i) => (
        <ComponentRenderer key={i} component={component} />
      ))}
    </div>
  )
}

// ---------------------------------------------------------------------------
// ComponentRenderer — dispatches to the correct component widget
// ---------------------------------------------------------------------------

/** Renders a single ODS component. Exported for use by TabsComponent. */
export function renderComponent(component: OdsComponent, key?: number): React.ReactNode {
  return <ComponentRenderer key={key} component={component} />
}

function ComponentRenderer({ component }: { component: OdsComponent }) {
  let content: React.ReactNode

  switch (component.component) {
    case 'text':
      content = <TextComponent model={component} />
      break
    case 'button':
      content = <ButtonComponent model={component} />
      break
    case 'summary':
      content = <SummaryComponent model={component} />
      break
    case 'list':
      content = <ListComponent model={component} />
      break
    case 'form':
      content = <FormComponent model={component} />
      break
    case 'chart':
      content = <ChartComponent model={component} />
      break
    case 'tabs':
      content = <TabsComponent model={component} renderComponent={renderComponent} />
      break
    case 'detail':
      content = <DetailComponent model={component} />
      break
    case 'kanban':
      content = <KanbanComponent model={component} />
      break
    case 'unknown':
      content = <UnknownComponent originalType={component.originalType} />
      break
    default:
      content = null
  }

  // Wrap with expression-based visibility.
  if (component.visible != null) {
    content = (
      <ExpressionVisibility expression={component.visible}>
        {content}
      </ExpressionVisibility>
    )
  }

  // Wrap with structured visibleWhen condition.
  if (component.visibleWhen != null) {
    content = (
      <VisibilityWrapper condition={component.visibleWhen}>
        {content}
      </VisibilityWrapper>
    )
  }

  // Wrap with role guard.
  if (component.roles && component.roles.length > 0) {
    content = <RoleGuard roles={component.roles}>{content}</RoleGuard>
  }

  return <>{content}</>
}

// ---------------------------------------------------------------------------
// VisibilityWrapper — structured visibleWhen conditions
// ---------------------------------------------------------------------------

function VisibilityWrapper({
  condition,
  children,
}: {
  condition: OdsComponentVisibleWhen
  children: React.ReactNode
}) {
  if (isFieldBased(condition)) {
    return (
      <FieldVisibility condition={condition}>{children}</FieldVisibility>
    )
  }

  if (isDataBased(condition)) {
    return (
      <DataVisibility condition={condition}>{children}</DataVisibility>
    )
  }

  // Invalid condition — show by default.
  return <>{children}</>
}

function FieldVisibility({
  condition,
  children,
}: {
  condition: OdsComponentVisibleWhen
  children: React.ReactNode
}) {
  const formState = useAppStore((s) => s.formStates[condition.form!] ?? {})
  const fieldValue = formState[condition.field!] ?? ''

  let visible = true
  if (condition.equals != null) {
    visible = fieldValue === condition.equals
  } else if (condition.notEquals != null) {
    visible = fieldValue !== condition.notEquals
  }

  if (!visible) return null
  return <>{children}</>
}

function DataVisibility({
  condition,
  children,
}: {
  condition: OdsComponentVisibleWhen
  children: React.ReactNode
}) {
  const queryDataSource = useAppStore((s) => s.queryDataSource)
  const [visible, setVisible] = useState(false)
  const [loaded, setLoaded] = useState(false)

  useEffect(() => {
    let cancelled = false
    queryDataSource(condition.source!).then((rows) => {
      if (cancelled) return
      const count = rows.length
      let vis = true
      if (condition.countEquals != null) vis = count === condition.countEquals
      if (vis && condition.countMin != null) vis = count >= condition.countMin
      if (vis && condition.countMax != null) vis = count <= condition.countMax
      setVisible(vis)
      setLoaded(true)
    })
    return () => { cancelled = true }
  }, [queryDataSource, condition])

  if (!loaded || !visible) return null
  return <>{children}</>
}

// ---------------------------------------------------------------------------
// ExpressionVisibility — expression-based visible property
// ---------------------------------------------------------------------------

function ExpressionVisibility({
  expression,
  children,
}: {
  expression: string
  children: React.ReactNode
}) {
  const formStates = useAppStore((s) => s.formStates)

  // Collect all form state values into a flat map.
  const values: Record<string, string> = {}
  for (const formState of Object.values(formStates)) {
    Object.assign(values, formState)
  }

  const visible = evaluateBool(expression, values)
  if (!visible) return null
  return <>{children}</>
}

// ---------------------------------------------------------------------------
// Unknown component — only visible in debug mode
// ---------------------------------------------------------------------------

function UnknownComponent({ originalType }: { originalType: string }) {
  const debugMode = useAppStore((s) => s.debugMode)
  if (!debugMode) return null

  return (
    <div className="rounded-lg border border-orange-300 bg-orange-50 p-3 text-sm italic text-orange-800 dark:border-orange-700 dark:bg-orange-950 dark:text-orange-300">
      Unknown component: &ldquo;{originalType}&rdquo;
    </div>
  )
}

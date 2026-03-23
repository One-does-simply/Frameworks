import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import type { OdsComponent, OdsTabsComponent } from '@/models/ods-component.ts'

// ---------------------------------------------------------------------------
// Component renderer type — passed as a prop to avoid circular imports
// with PageRenderer.
// ---------------------------------------------------------------------------

export type RenderComponentFn = (component: OdsComponent, index: number) => React.ReactNode

// ---------------------------------------------------------------------------
// TabsComponent
// ---------------------------------------------------------------------------

/**
 * Renders an OdsTabsComponent as a shadcn Tabs layout.
 *
 * Each tab has a label and a content array of ODS components, rendered via
 * the provided `renderComponent` function (typically `ComponentRenderer`
 * from PageRenderer).
 */
export function TabsComponent({
  model,
  renderComponent,
}: {
  model: OdsTabsComponent
  renderComponent: RenderComponentFn
}) {
  if (model.tabs.length === 0) return null

  const defaultTab = `tab-0`

  return (
    <div className="my-2">
      <Tabs defaultValue={defaultTab}>
        <TabsList className={model.tabs.length > 4 ? 'w-full overflow-x-auto' : undefined}>
          {model.tabs.map((tab, i) => (
            <TabsTrigger key={i} value={`tab-${i}`}>
              {tab.label}
            </TabsTrigger>
          ))}
        </TabsList>

        {model.tabs.map((tab, i) => (
          <TabsContent key={i} value={`tab-${i}`}>
            <div className="pt-3 space-y-2">
              {tab.content.map((component, ci) => renderComponent(component, ci))}
            </div>
          </TabsContent>
        ))}
      </Tabs>
    </div>
  )
}

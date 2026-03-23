import { parseComponent, type OdsComponent } from './ods-component.ts'

/** A single page (screen) in an ODS application. */
export interface OdsPage {
  title: string
  content: OdsComponent[]
  roles?: string[]
}

export function parsePage(json: unknown): OdsPage {
  const j = json as Record<string, unknown>
  return {
    title: j['title'] as string,
    content: Array.isArray(j['content'])
      ? (j['content'] as unknown[]).map(parseComponent)
      : [],
    roles: j['roles'] as string[] | undefined,
  }
}

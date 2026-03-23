/** In-app help content defined by the spec author. */
export interface OdsHelp {
  overview: string
  pages: Record<string, string>
}

export function parseHelp(json: unknown): OdsHelp | undefined {
  if (json == null || typeof json !== 'object') return undefined
  const j = json as Record<string, unknown>
  return {
    overview: j['overview'] as string,
    pages: (j['pages'] as Record<string, string>) ?? {},
  }
}

/** A single step in the guided tour. */
export interface OdsTourStep {
  title: string
  content: string
  page?: string
}

export function parseTourStep(json: unknown): OdsTourStep {
  const j = json as Record<string, unknown>
  return {
    title: j['title'] as string,
    content: j['content'] as string,
    page: j['page'] as string | undefined,
  }
}

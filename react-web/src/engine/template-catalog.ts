/**
 * Fetches the ODS template catalog from the Specification repository.
 * Used by the Quick Build screen to list and load templates.
 */

const TEMPLATE_BASE_URL =
  'https://one-does-simply.github.io/Specification/Templates'

export interface TemplateCatalogEntry {
  id: string
  name: string
  description: string
  file: string // e.g. "simple-tracker.json"
}

interface CatalogResponse {
  templates: TemplateCatalogEntry[]
}

/** Fetch the template catalog index. Returns null on failure. */
export async function fetchTemplateCatalog(): Promise<TemplateCatalogEntry[] | null> {
  try {
    const resp = await fetch(`${TEMPLATE_BASE_URL}/catalog.json`, {
      signal: AbortSignal.timeout(10_000),
    })
    if (!resp.ok) return null
    const data: CatalogResponse = await resp.json()
    return data.templates ?? null
  } catch {
    return null
  }
}

/** Fetch a single template definition by its catalog file name. */
export async function fetchTemplate(fileName: string): Promise<Record<string, unknown> | null> {
  try {
    const resp = await fetch(`${TEMPLATE_BASE_URL}/${fileName}`, {
      signal: AbortSignal.timeout(10_000),
    })
    if (!resp.ok) return null
    return await resp.json()
  } catch {
    return null
  }
}

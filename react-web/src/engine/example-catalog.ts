/**
 * Fetches the ODS example catalog from the Specification repository.
 * Used for first-run onboarding and "Browse Examples" in the admin dashboard.
 */

const CATALOG_BASE_URL =
  'https://one-does-simply.github.io/Specification/Examples'

export interface CatalogEntry {
  id: string
  name: string
  description: string
  file: string // e.g. "expense-tracker.json"
}

export interface Catalog {
  examples: CatalogEntry[]
}

/** Fetch the example catalog index. Returns null on failure. */
export async function fetchCatalog(): Promise<CatalogEntry[] | null> {
  try {
    const resp = await fetch(`${CATALOG_BASE_URL}/catalog.json`, {
      signal: AbortSignal.timeout(10_000),
    })
    if (!resp.ok) return null
    const data: Catalog = await resp.json()
    return data.examples ?? null
  } catch {
    return null
  }
}

/** Fetch a single example spec by its catalog file name. */
export async function fetchExampleSpec(fileName: string): Promise<string | null> {
  try {
    const resp = await fetch(`${CATALOG_BASE_URL}/${fileName}`, {
      signal: AbortSignal.timeout(10_000),
    })
    if (!resp.ok) return null
    return await resp.text()
  } catch {
    return null
  }
}

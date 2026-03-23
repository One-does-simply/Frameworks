import { parseFieldDefinition, type OdsFieldDefinition } from './ods-field.ts'
import { parseOwnership, type OdsOwnership } from './ods-ownership.ts'

/** A data endpoint — local storage or external API. */
export interface OdsDataSource {
  url: string
  method: string
  fields?: OdsFieldDefinition[]
  seedData?: Record<string, unknown>[]
  ownership: OdsOwnership
}

/** Whether this source uses framework-managed local storage. */
export const isLocal = (ds: OdsDataSource) => ds.url.startsWith('local://')

/** Extracts the table name from a local:// URL. */
export const tableName = (ds: OdsDataSource) =>
  isLocal(ds) ? ds.url.substring('local://'.length) : ''

export function parseDataSource(json: unknown): OdsDataSource {
  const j = json as Record<string, unknown>
  return {
    url: j['url'] as string,
    method: j['method'] as string,
    fields: Array.isArray(j['fields'])
      ? (j['fields'] as unknown[]).map(parseFieldDefinition)
      : undefined,
    seedData: j['seedData'] as Record<string, unknown>[] | undefined,
    ownership: parseOwnership(j['ownership']),
  }
}

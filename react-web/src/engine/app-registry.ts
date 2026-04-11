import type PocketBase from 'pocketbase'
import { logInfo, logError } from './log-service.ts'

/**
 * Manages the `_ods_apps` PocketBase collection — the central registry
 * of all ODS apps loaded on this server.
 *
 * ODS Ethos: Apps persist across server restarts. Admin loads a spec once,
 * and it's live at its own URL forever (until archived or deleted).
 */

const COLLECTION_NAME = '_ods_apps'

export interface AppRecord {
  id: string
  name: string
  slug: string
  specJson: string
  status: 'active' | 'archived'
  description: string
  created: string
  updated: string
}

/** Generate a URL-safe slug from an app name. */
export function slugify(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^\w\s-]/g, '')
    .replace(/[\s_]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .substring(0, 64)
}

export class AppRegistry {
  private pb: PocketBase

  constructor(pb: PocketBase) {
    this.pb = pb
  }

  /** Ensure the _ods_apps collection exists. Called once during admin init. */
  async ensureCollection(): Promise<void> {
    try {
      await this.pb.collection(COLLECTION_NAME).getList(1, 1, { requestKey: null })
    } catch {
      // Collection doesn't exist — create it.
      try {
        await this.pb.collections.create({
          name: COLLECTION_NAME,
          type: 'base',
          fields: [
            { name: 'name', type: 'text', required: true },
            { name: 'slug', type: 'text', required: true },
            { name: 'specJson', type: 'json', required: true, maxSize: 5242880 },
            { name: 'status', type: 'text', required: false },
            { name: 'description', type: 'text', required: false },
          ],
          listRule: '',
          viewRule: '',
          createRule: '',
          updateRule: '',
          deleteRule: '',
        })
        logInfo('AppRegistry', 'Created _ods_apps collection')
      } catch (e) {
        logError('AppRegistry', 'Failed to create _ods_apps collection', e)
        // May already exist from a previous session — try to verify
        try {
          await this.pb.collection(COLLECTION_NAME).getList(1, 1, { requestKey: null })
          logInfo('AppRegistry', '_ods_apps collection already exists')
        } catch (e2) {
          logError('AppRegistry', '_ods_apps collection is unusable', e2)
        }
      }
    }
  }

  /** List all apps (active first, then archived). */
  async listApps(): Promise<AppRecord[]> {
    try {
      const result = await this.pb.collection(COLLECTION_NAME).getList(1, 200, {
        requestKey: null,
      })
      const records = result.items
      return (records ?? []).map(r => ({
        id: r.id,
        name: r['name'] as string,
        slug: r['slug'] as string,
        specJson: typeof r['specJson'] === 'string' ? r['specJson'] : JSON.stringify(r['specJson']),
        status: (r['status'] as string) === 'archived' ? 'archived' as const : 'active' as const,
        description: r['description'] as string ?? '',
        created: r['created'] as string ?? '',
        updated: r['updated'] as string ?? '',
      })).sort((a, b) => {
        // Active first, then archived. Within each group, newest first.
        if (a.status !== b.status) return a.status === 'active' ? -1 : 1
        return (b.created || '').localeCompare(a.created || '')
      })
    } catch (e) {
      logError('AppRegistry', 'listApps failed', e)
      return []
    }
  }

  /** Get a single app by its URL slug. */
  async getAppBySlug(slug: string): Promise<AppRecord | null> {
    try {
      const record = await this.pb.collection(COLLECTION_NAME).getFirstListItem(
        `slug = "${slug}"`,
        { requestKey: null },
      )
      return {
        id: record.id,
        name: record['name'] as string,
        slug: record['slug'] as string,
        specJson: typeof record['specJson'] === 'string' ? record['specJson'] : JSON.stringify(record['specJson']),
        status: (record['status'] as string) === 'archived' ? 'archived' : 'active',
        description: record['description'] as string ?? '',
        created: record['created'] as string ?? '',
        updated: record['updated'] as string ?? '',
      }
    } catch {
      return null
    }
  }

  /** Save a new app. Auto-generates slug from name, dedupes if needed. */
  async saveApp(name: string, specJson: string, description?: string): Promise<AppRecord | null> {
    let slug = slugify(name)

    // Deduplicate slug if it already exists.
    let attempt = 0
    while (true) {
      const candidateSlug = attempt === 0 ? slug : `${slug}-${attempt}`
      const existing = await this.getAppBySlug(candidateSlug)
      if (!existing) {
        slug = candidateSlug
        break
      }
      attempt++
      if (attempt > 100) throw new Error('Could not generate unique slug')
    }

    // Validate spec size before parsing.
    if (specJson.length > 2_000_000) {
      throw new Error(`Spec too large (${(specJson.length / 1_000_000).toFixed(1)}MB). Maximum is 2MB.`)
    }

    try {
      // PocketBase json fields expect a parsed object, not a string.
      const specObj = JSON.parse(specJson)
      console.info('[SECURITY] Spec upload:', { name, size: specJson.length })
      const record = await this.pb.collection(COLLECTION_NAME).create({
        name,
        slug,
        specJson: specObj,
        status: 'active',
        description: description ?? '',
      })
      return {
        id: record.id,
        name: record['name'] as string,
        slug: record['slug'] as string,
        specJson: typeof record['specJson'] === 'string' ? record['specJson'] : JSON.stringify(record['specJson']),
        status: 'active',
        description: record['description'] as string ?? '',
        created: record['created'] as string ?? '',
        updated: record['updated'] as string ?? '',
      }
    } catch (e: unknown) {
      // PocketBase ClientResponseError has a `data` field with per-field errors
      const pbErr = e as { data?: Record<string, unknown>; response?: unknown }
      logError('AppRegistry', 'Failed to save app', { error: e, data: pbErr.data, response: pbErr.response })
      throw e
    }
  }

  /** Update an existing app's spec JSON. */
  async updateApp(appId: string, specJson: string): Promise<boolean> {
    try {
      await this.pb.collection(COLLECTION_NAME).update(appId, { specJson: JSON.parse(specJson) })
      return true
    } catch (e) {
      logError('AppRegistry', 'Failed to update app', e)
      return false
    }
  }

  /** Archive an app (hides from users, keeps data). */
  async archiveApp(appId: string): Promise<boolean> {
    try {
      await this.pb.collection(COLLECTION_NAME).update(appId, { status: 'archived' })
      return true
    } catch { return false }
  }

  /** Restore an archived app. */
  async restoreApp(appId: string): Promise<boolean> {
    try {
      await this.pb.collection(COLLECTION_NAME).update(appId, { status: 'active' })
      return true
    } catch { return false }
  }

  /** Permanently delete an app and its record. */
  async deleteApp(appId: string): Promise<boolean> {
    try {
      await this.pb.collection(COLLECTION_NAME).delete(appId)
      return true
    } catch { return false }
  }
}

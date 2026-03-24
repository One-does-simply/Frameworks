import type PocketBase from 'pocketbase'

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
            { name: 'specJson', type: 'text', required: true, maxSize: 5000000 },
            { name: 'status', type: 'text', required: false },
            { name: 'description', type: 'text', required: false },
          ],
          listRule: '',
          viewRule: '',
          createRule: '',
          updateRule: '',
          deleteRule: '',
        })
        console.log('Created _ods_apps collection')
      } catch (e) {
        console.error('Failed to create _ods_apps collection:', e)
        // May already exist from a previous session — try to verify
        try {
          await this.pb.collection(COLLECTION_NAME).getList(1, 1, { requestKey: null })
          console.log('_ods_apps collection already exists (creation failed but collection is usable)')
        } catch (e2) {
          console.error('_ods_apps collection is unusable:', e2)
        }
      }
    }
  }

  /** List all apps (active first, then archived). */
  async listApps(): Promise<AppRecord[]> {
    try {
      const records = await this.pb.collection(COLLECTION_NAME).getFullList({
        requestKey: null,
      })
      return records.map(r => ({
        id: r.id,
        name: r['name'] as string,
        slug: r['slug'] as string,
        specJson: r['specJson'] as string,
        status: (r['status'] as string) === 'archived' ? 'archived' as const : 'active' as const,
        description: r['description'] as string ?? '',
        created: r.created,
        updated: r.updated,
      })).sort((a, b) => {
        // Active first, then archived. Within each group, newest first.
        if (a.status !== b.status) return a.status === 'active' ? -1 : 1
        return b.created.localeCompare(a.created)
      })
    } catch {
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
        specJson: record['specJson'] as string,
        status: (record['status'] as string) === 'archived' ? 'archived' : 'active',
        description: record['description'] as string ?? '',
        created: record.created,
        updated: record.updated,
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

    try {
      const record = await this.pb.collection(COLLECTION_NAME).create({
        name,
        slug,
        specJson,
        status: 'active',
        description: description ?? '',
      })
      return {
        id: record.id,
        name: record['name'] as string,
        slug: record['slug'] as string,
        specJson: record['specJson'] as string,
        status: 'active',
        description: record['description'] as string ?? '',
        created: record.created,
        updated: record.updated,
      }
    } catch (e) {
      console.error('Failed to save app:', e)
      // Re-throw with details so the UI can show a meaningful message
      throw e
    }
  }

  /** Update an existing app's spec JSON. */
  async updateApp(appId: string, specJson: string): Promise<boolean> {
    try {
      await this.pb.collection(COLLECTION_NAME).update(appId, { specJson })
      return true
    } catch (e) {
      console.error('Failed to update app:', e)
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

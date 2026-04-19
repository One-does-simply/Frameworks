import { withSuperadmin } from './pb-client'

/**
 * Dead-simple spec for routing/auth tests that don't exercise any data
 * sources. No dataSources means no PB collections to bootstrap.
 */
export function helloSpec(): object {
  return {
    appName: 'Hello App',
    startPage: 'home',
    pages: {
      home: {
        component: 'page',
        title: 'Home',
        content: [
          { component: 'text', content: 'Hello from the seeded app' },
        ],
      },
    },
    dataSources: {},
  }
}

/**
 * Minimal ODS spec used when a test just needs *some* app to exist.
 * Keep it small — one page, one form, one list, one data source.
 *
 * The form has a `submit` action so pressing Enter / clicking the submit
 * button actually persists a row to the `tasks` data source.
 */
export function minimalTodoSpec(): object {
  return {
    appName: 'E2E Todo',
    startPage: 'home',
    pages: {
      home: {
        component: 'page',
        title: 'Home',
        content: [
          {
            component: 'form',
            id: 'addForm',
            dataSource: 'tasks',
            fields: [
              { name: 'title', type: 'text', label: 'Title', required: true },
              { name: 'done', type: 'checkbox', label: 'Done' },
            ],
          },
          {
            component: 'button',
            label: 'Save Task',
            onClick: [
              { action: 'submit', dataSource: 'tasks', target: 'addForm' },
            ],
          },
          {
            component: 'list',
            dataSource: 'tasks',
            columns: [
              { field: 'title', label: 'Title' },
              { field: 'done', label: 'Done' },
            ],
          },
        ],
      },
    },
    dataSources: {
      tasks: {
        url: 'local://tasks',
        method: 'POST',
        fields: [
          { name: 'title', type: 'text' },
          { name: 'done', type: 'checkbox' },
        ],
      },
    },
  }
}

/**
 * Slug-safe URL part. Mirrors `slugify` in the React app so seeded apps
 * have the slug the router expects.
 */
export function slugify(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^\w\s-]/g, '')
    .replace(/[\s_]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .substring(0, 64)
}

/**
 * Ensures the `_ods_apps` collection exists and inserts an app record.
 * Also pre-creates the per-app data-source collections so unauthenticated
 * pages can use the app without the browser trying to create them (which
 * requires admin auth and fails 401 for guests).
 *
 * Returns the slug so tests can navigate to it.
 */
export async function seedApp(
  name: string,
  spec: object = minimalTodoSpec(),
): Promise<{ id: string; slug: string }> {
  const slug = slugify(name)
  const specJson = JSON.stringify(spec)
  const appName = ((spec as { appName?: string }).appName) ?? name
  const appPrefix = appName.replace(/[^\w]/g, '_').toLowerCase()
  const dataSources = ((spec as { dataSources?: Record<string, unknown> }).dataSources) ?? {}

  return withSuperadmin(async (pb) => {
    // Ensure the _ods_apps collection exists.
    try {
      await pb.collection('_ods_apps').getList(1, 1, { requestKey: null })
    } catch {
      await pb.collections.create({
        name: '_ods_apps',
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
    }

    // Pre-create each data-source collection (`<appPrefix>_<table>`) so the
    // browser doesn't need admin auth to bootstrap them on first load.
    for (const [dsKey, dsVal] of Object.entries(dataSources)) {
      const ds = dsVal as { url?: string; fields?: Array<{ name: string }> }
      const url = ds.url ?? ''
      if (!url.startsWith('local://')) continue
      const table = url.replace(/^local:\/\//, '') || dsKey
      const collName = `${appPrefix}_${table}`
      try {
        await pb.collection(collName).getList(1, 1, { requestKey: null })
      } catch {
        const pbFields = (ds.fields ?? []).map((f) => ({
          name: f.name,
          type: 'text' as const,
          required: false,
        }))
        try {
          await pb.collections.create({
            name: collName,
            type: 'base',
            fields: pbFields,
            listRule: '',
            viewRule: '',
            createRule: '',
            updateRule: '',
            deleteRule: '',
          })
        } catch {
          // Another seeding call may have created it concurrently; ignore.
        }
      }
    }

    const rec = await pb.collection('_ods_apps').create({
      name,
      slug,
      specJson,
      status: 'active',
      description: '',
    })
    return { id: rec.id, slug }
  })
}

/**
 * Ensures the PocketBase `users` auth collection exists so app sign-up
 * flows can write records. Mirrors [AuthService.ensureUsersCollection]
 * but invoked from the test harness directly so tests don't need an
 * admin browser session to bootstrap it.
 */
export async function ensureUsersCollection(): Promise<void> {
  await withSuperadmin(async (pb) => {
    try {
      await pb.collection('users').getList(1, 1, { requestKey: null })
      return
    } catch {
      // fall through
    }
    try {
      await pb.collections.create({
        name: 'users',
        type: 'auth',
        fields: [
          { name: 'username', type: 'text', required: false },
          { name: 'displayName', type: 'text', required: false },
          { name: 'roles', type: 'json', required: false, maxSize: 2000 },
        ],
        listRule: 'id != ""',
        viewRule: 'id != ""',
        createRule: '',
        updateRule: 'id = @request.auth.id',
        deleteRule: null,
      } as unknown as Record<string, unknown>)
    } catch {
      // ignore race — another test may have created it concurrently.
    }
  })
}

/**
 * Inserts rows into an app's data-source collection (`<appPrefix>_<table>`)
 * via the superadmin SDK. Requires the app to already be seeded (so the
 * collection exists). Returns the created record IDs.
 */
export async function seedRows(
  appName: string,
  table: string,
  rows: Array<Record<string, unknown>>,
): Promise<string[]> {
  const appPrefix = appName.replace(/[^\w]/g, '_').toLowerCase()
  const collName = `${appPrefix}_${table}`
  return withSuperadmin(async (pb) => {
    const ids: string[] = []
    for (const row of rows) {
      const rec = await pb.collection(collName).create(row)
      ids.push(rec.id)
    }
    return ids
  })
}

/** Reads a single row back from a data-source collection by id. */
export async function readRow(
  appName: string,
  table: string,
  id: string,
): Promise<Record<string, unknown>> {
  const appPrefix = appName.replace(/[^\w]/g, '_').toLowerCase()
  const collName = `${appPrefix}_${table}`
  return withSuperadmin(async (pb) => {
    return pb.collection(collName).getOne(id, { requestKey: null })
  })
}

/** Deletes every app record so the next test starts from a clean dashboard. */
export async function clearSeededApps(): Promise<void> {
  await withSuperadmin(async (pb) => {
    try {
      const all = await pb.collection('_ods_apps').getFullList({ requestKey: null })
      for (const rec of all) {
        await pb.collection('_ods_apps').delete(rec.id, { requestKey: null })
      }
    } catch {
      // Collection may not exist yet — that's fine.
    }
  })
}

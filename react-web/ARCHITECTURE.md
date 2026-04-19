# ODS React Web — Architecture

Contributor-level internals of the React web renderer. For the product
overview see [product.md](product.md); for the spec format see
[spec.md](spec.md); for the workspace-level picture see
[../../ARCHITECTURE.md](../../ARCHITECTURE.md).

## Code layout

```
src/
├── main.tsx                      Entry point — mounts React
├── App.tsx                       Router + top-level route table
├── models/                       Typed models for the parsed spec
├── parser/                       spec.json → typed models + validation
├── engine/                       Runtime state + business logic + services
├── renderer/                     Models → React components (no state owned)
├── screens/                      Route-level screens (AdminDashboard,
│                                  AdminGuard, AdminSettingsPage, AppLoader,
│                                  LoginScreen, QuickBuild, etc.)
├── components/ui/                shadcn/ui primitives (button, card, dialog…)
├── lib/                          Cross-cutting utilities (pb client, utils)
└── assets/
```

The same layering rule as the Flutter framework:
`models` → `parser` → `engine` → `renderer`. Renderer reads engine
state; engine doesn't know the renderer exists.

## Key modules

### `AppEngine` (the store) ([src/engine/app-store.ts](src/engine/app-store.ts))

Zustand store — the React analogue of the Flutter `AppEngine`
`ChangeNotifier`. Owns:

- The loaded `OdsApp` model and current slug
- Current page id + navigation history
- Per-form values
- Loaded data (rows by data source)
- Auth-related gates: `needsLogin`, `needsAdminSetup`, `pbSuperAdminAvailable`
- `lastMessage` for toasts

Setters are plain Zustand actions. `loadSpec(specJson, dataService,
authService, slug)` is the main entry point — parses the JSON, sets
up the data service's appPrefix, registers data sources, resolves
the start page.

Components read the store via `useAppStore((s) => s.app)` etc.

### `DataService` ([src/engine/data-service.ts](src/engine/data-service.ts))

The PocketBase abstraction. Initialized per-app via
`initialize(appName)` which sets `appPrefix =
appName.replace(/[^\w]/g, '_').toLowerCase()`. Every collection name
is prefixed with that — `tasks` in the spec becomes `myapp_tasks` in
PB. That's how two apps with the same spec-level table name don't
collide.

Key methods: `ensureCollection`, `insert`, `update`, `delete`,
`query`, `queryWithOwnership`, `setupDataSources`,
`tryRestoreAdminAuth`, `authenticateAdmin`.

`ensureCollection` is lazy: it's called on first use of a data
source and creates the PB collection with `listRule: ''`,
`createRule: ''`, etc. (public access — ODS handles RBAC at the
application layer, not at the PB collection layer).

### `AppRegistry` ([src/engine/app-registry.ts](src/engine/app-registry.ts))

Framework-level registry of ODS apps. The `_ods_apps` PB collection
stores `{name, slug, specJson, status, description}` for every app
an admin has loaded. The admin dashboard lists from here;
`/:slug/*` routes resolve apps by querying here.

Also owns `ensureCollection` for `_ods_apps` itself, called by
`AdminGuard` on admin login.

### `AuthService` ([src/engine/auth-service.ts](src/engine/auth-service.ts))

Per-app auth wrapper around PocketBase's native `users` auth
collection. PB handles hashing + sessions + token refresh
natively; `AuthService` adds:

- A `_isSuperAdmin` flag (set when the PB superadmin is operating
  the app directly — bypasses role checks)
- OAuth2 provider discovery + the full start/complete redirect flow
- Rate limiting (5 failed logins / 5 minutes / email)
- `ensureUsersCollection` — creates the `users` collection if it
  doesn't exist yet (fresh PB installs), called by `AdminGuard` on
  admin login. *Essential* — without this, self-registration silently
  fails on fresh installs (see
  [docs/TROUBLESHOOTING.md](../../docs/TROUBLESHOOTING.md)).

Users records carry custom fields: `username`, `displayName`,
`roles` (JSON array stored as text).

### `AdminGuard` ([src/screens/AdminGuard.tsx](src/screens/AdminGuard.tsx))

Wraps every `/admin/*` route. Two states: `loading` (initial PB
auth probe), `login` (show the PB admin credentials card), and
`authenticated` (render the child route via `<Outlet/>`). On
successful auth — either restored session or fresh login — it calls
`AppRegistry.ensureCollection()` and `AuthService.ensureUsersCollection()`
so the rest of the app can assume those exist.

### `AppLoader` ([src/screens/AppLoader.tsx](src/screens/AppLoader.tsx))

Wraps `/:slug/*`. Looks up the app by slug via `AppRegistry`, calls
`AppEngine.loadSpec` with the stored `specJson`, then renders
`AppShell`. Handles three render states: `loading`, `not-found`,
`archived`, `ready`.

### `ActionHandler` ([src/engine/action-handler.ts](src/engine/action-handler.ts))

Interprets `OdsAction` lists — same shape as the Flutter side, same
semantics. Reads form state + current user + current row context from
the store; writes to `DataService`; sets `lastMessage` for
`showMessage` actions.

### Renderer layer ([src/renderer/](src/renderer/))

- `PageRenderer.tsx` walks `OdsPage.content` and dispatches by
  component type.
- `components/*` have one React component per ODS component (Form,
  List, Kanban, Chart, Button, Text, Summary, Detail, Tabs).
- `StyleResolver.ts` translates ODS `styleHint` objects into
  Tailwind classes + CSS variables.
- Theme bridging is handled by `next-themes` + per-app CSS variables
  driven by `branding-service.ts`.

## Routing

React Router v7; route table in [App.tsx](src/App.tsx):

```
/                    → RootRedirect (login OR redirect to default app)
/admin               → AdminGuard → Outlet
  /admin             → AdminDashboard
  /admin/settings    → AdminSettingsPage
  /admin/quick-build → QuickBuildScreen
  /admin/users       → (admin user management)
/:slug/*             → AppLoader → AppShell → PageRenderer
/oauth2-callback     → OAuth2Callback
```

The catch-all `/:slug/*` is positioned *after* `/admin/*`, but an
unknown `/admin/<subroute>` still falls through to the slug catch-all
and renders `<NotFoundScreen slug="admin">`. That quirk is
documented in
[tests/e2e/critical/admin-guard.spec.ts](tests/e2e/critical/admin-guard.spec.ts);
not fatal but worth knowing.

## State flow — a form submit

```
User types in a text field
  ↓
onChange → useAppStore.setState({ formValues: { addForm: { title: 'Buy milk' } } })
  ↓
Zustand subscribers re-render

User clicks Save
  ↓
ButtonComponent.onClick → ActionHandler.executeActions(onClickActions, ctx)
  ├── submit → DataService.insert('tasks', formValues)
  ├── showMessage → useAppStore.setState({ lastMessage: { text, level } })
  └── triggers a re-query of bound data sources
  ↓
ListComponent sees new row; Sonner toast fires on lastMessage change.
```

## Persistence — the PB collection inventory

In a fresh ODS-enabled PB instance, these collections exist at
runtime:

- `_superusers` — PocketBase built-in (created by `superuser upsert`)
- `users` — created by `AuthService.ensureUsersCollection` on first
  admin login. Auth type. Custom fields: `username`, `displayName`,
  `roles` (json).
- `_ods_apps` — created by `AppRegistry.ensureCollection` on first
  admin login. Base type. Holds the app registry.
- `<appPrefix>_<table>` — created lazily by `DataService.ensureCollection`
  when an app with that data source first loads. One per data source
  per app.

The two "created on first admin login" collections are the reason
`AdminGuard` explicitly bootstraps them — without it, self-registration
and app loading silently 404.

## Testing

Tests live under `tests/` with two layers:

- **Unit + component** (Vitest + React Testing Library) — under
  `tests/unit/` and colocated `*.test.ts`. ~1117 tests currently. No
  browser; no PocketBase.
- **E2E** (Playwright) — under `tests/e2e/` in four categories:
  `smoke/`, `critical/`, `regression/`, `accessibility/`. Uses a real
  browser and a real PocketBase instance that's auto-downloaded and
  started by [tests/e2e/global-setup.ts](tests/e2e/global-setup.ts).
  ~50 tests currently.

CI workflow: [.github/workflows/test.yml](.github/workflows/test.yml)
runs both on push/PR to main.

## Off-ramp

- Data export: `src/engine/backup-service.ts` + the Export Data
  dialog emit JSON / CSV / SQL.
- Code generation: `src/engine/code-generator.ts` emits a standalone
  React + PocketBase project. Generated apps don't depend on ODS at
  runtime.

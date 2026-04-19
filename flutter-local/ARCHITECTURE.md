# ODS Flutter Local — Architecture

Contributor-level internals of the Flutter renderer. For the product
overview see [product.md](product.md); for the spec format see
[spec.md](spec.md); for the workspace-level picture see
[../../ARCHITECTURE.md](../../ARCHITECTURE.md).

## Code layout

```
lib/
├── main.dart                     Entry point, MaterialApp, root routing
├── models/                       Plain Dart model classes — no Flutter deps
├── parser/                       spec.json → models, with validation
├── engine/                       Runtime state + business logic
├── renderer/                     Model → Flutter widgets (no state owned here)
├── loader/                       File picker + URL loading + clipboard paste
├── screens/                      Top-level screens (Welcome, Settings, Admin
│                                  setup, Login, Tour, Help, etc.)
├── widgets/                      Shared widget primitives (theme picker,
│                                  color picker, framework user list)
└── debug/                        Debug panel overlay
```

The *layering rule*: `models` → `parser` → `engine` → `renderer`.
Renderer reads engine; engine doesn't know the renderer exists. That
discipline is what made a headless conformance driver possible in the
first place.

## Key classes

### `AppEngine` ([lib/engine/app_engine.dart](lib/engine/app_engine.dart))

The centerpiece. A `ChangeNotifier` that owns:

- The loaded `OdsApp` model (`app` getter)
- Current page id and navigation stack
- Form state (a map of formId → field values)
- Loaded data (rows per data source)
- Auth session (via an owned `AuthService`)
- Framework-level context when the Framework auth is active
  (`skipAppAuth`, `frameworkRoles`, `frameworkEmail`, `frameworkUsername`,
  `frameworkDisplayName` — injected by the framework login flow)
- Current "last message" for toast/snackbar rendering

Exposes methods the renderer calls to mutate state: `loadSpec`,
`navigateTo`, `setFormField`, `clearFormStates`, `dispatchAction`.

Owns but delegates to:

- `DataStore` — all persistence calls go through here
- `AuthService` — per-app auth; receives injected framework session
  when framework-level multi-user is on
- `ActionHandler` — executes `OdsAction` lists (submit, update,
  delete, navigate, showMessage, etc.)

### `DataStore` ([lib/engine/data_store.dart](lib/engine/data_store.dart))

The SQLite abstraction. One database file per app (named
`ods_<app_slug>.db`) under the user-chosen storage folder. Schema:

- `<prefix>_<dataSource>` — the builder-defined tables, auto-created
  from form/dataSource field definitions
- `_ods_settings` — per-app key/value store
- `_ods_users`, `_ods_user_roles` — per-app auth (legacy path; still
  present but typically unused when framework-level multi-user is on)
- Internal columns on every table: `_id` (TEXT PRIMARY KEY),
  `_createdAt`, `_updatedAt`, optionally `_ownerId` when
  row-level security is enabled

Methods: `insert`, `update`, `delete`, `query`, `queryWithOwnership`,
`ensureTable`, `createUser`, `assignRole`, `getUserRoles`, etc.

### `AuthService` and `FrameworkAuthService` ([lib/engine/auth_service.dart](lib/engine/auth_service.dart), [lib/engine/framework_auth_service.dart](lib/engine/framework_auth_service.dart))

Two services, one responsibility split:

- **`AuthService`** is per-app. It owns the per-app `_ods_users`
  table and is the renderer's point of contact for
  `isLoggedIn` / `isAdmin` / `currentRoles`. Accepts an injected
  framework session via `injectFrameworkAuth` so that in
  framework-multi-user mode the per-app surface "just works" without
  a second login.
- **`FrameworkAuthService`** is framework-level. It has its own
  database (`ods_framework_auth.db`) with `_ods_fw_users` and
  `_ods_fw_user_roles`. When `settings.isMultiUserEnabled` is on,
  *all* user management goes through this service — the per-app
  Settings screen and the drawer's Manage Users both render
  [FrameworkUserList](lib/widgets/framework_user_list.dart) backed by
  this service.

Password hashing is SHA-256 + salt (`lib/engine/password_hasher.dart`) —
pure Dart, no platform bindings.

### `SettingsStore` ([lib/engine/settings_store.dart](lib/engine/settings_store.dart))

Framework-level preferences: theme mode, default theme, backup
settings, multi-user flag, default-app id, and the user-chosen
**storage folder**. Persists to `ods_settings.json` inside that
folder.

The storage-folder bootstrap is the interesting bit. `SettingsStore`
resolves the data directory via:

1. Explicit `customPath` parameter (if caller passes one)
2. `ods_bootstrap.json` in `getApplicationSupportDirectory()` (the
   AppData side on Windows, *not* OneDrive-redirected)
3. Default `<Documents>/One Does Simply`

First run: no bootstrap exists → default is used → a dialog asks the
user to confirm or pick a custom folder → chosen path is written to
the bootstrap. Subsequent runs: bootstrap is authoritative. "Move
Data" in Framework Settings uses `moveStorageFolder` /
`resetStorageFolder` to copy files + retarget. See
[docs/TROUBLESHOOTING.md](../../docs/TROUBLESHOOTING.md) for why this
indirection exists.

### `ActionHandler` ([lib/engine/action_handler.dart](lib/engine/action_handler.dart))

Interprets `OdsAction` lists. Actions are declarative
(`{"action": "submit", "target": "addForm", "dataSource": "tasks"}`);
`ActionHandler` runs them in order, short-circuiting on the first
failure (except `showMessage` which is always allowed to fire after
a successful chain).

Reads form state + current user context from `AppEngine`, writes to
`DataStore`.

### Renderer layer ([lib/renderer/](lib/renderer/))

- `page_renderer.dart` walks `OdsPage.content` and dispatches by
  component type.
- `components/` has one widget per ODS component (button, form, list,
  kanban, chart, tabs, detail, summary, text).
- `style_resolver.dart` translates ODS `styleHint` objects into
  Material ThemeData overrides.
- `snackbar_helper.dart` bridges `AppEngine.lastMessage` to Material
  snackbars.

Rule: components read engine state via `context.watch<AppEngine>()`;
they never call `DataStore` directly. Mutations go through engine
methods or `dispatchAction`.

## State flow — a form submit

```
User types "Buy milk" in the Title field
  ↓
TextField.onChanged
  ↓
AppEngine.setFormField('addForm', 'title', 'Buy milk')
  ↓
AppEngine.notifyListeners()
  ↓ (React)
FormComponent rebuilds with new value

User clicks Save button
  ↓
OdsButtonWidget.onPressed
  ↓
AppEngine.dispatchAction(onClickActions, formId: 'addForm')
  ↓
ActionHandler.execute(actions, ctx)
  ├── submit → DataStore.insert('tasks', formValues)
  ├── showMessage → AppEngine._lastMessage = 'Saved!'
  └── notifyListeners()
  ↓
ListComponent sees new row; SnackbarHelper fires toast.
```

Every step is idempotent and inspectable. The engine is the single
mutation point; state shape is the contract.

## Testing

Tests live under `test/` with the convention:

- `test/engine/` — unit tests for engine + data store + auth
- `test/models/` — parser / model validation
- `test/parser/` — spec parser edge cases
- `test/widget/` — widget-level rendering (**skipped on Windows**;
  see [docs/TROUBLESHOOTING.md](../../docs/TROUBLESHOOTING.md))
- `test/integration/` — end-to-end engine behavior (batches 1–6) +
  performance (batch 9)

Current totals and skip status are in
[../../REGRESSION_LOG.md](../../REGRESSION_LOG.md). CI for this
framework is [tracked on TODO.md](../../TODO.md) — there's no
workflow yet; React side has one.

## Platforms

- **Desktop (primary):** Windows / macOS / Linux via `sqflite_common_ffi`
- **Mobile:** iOS / Android via stock `sqflite`
- Web is not a target (use the React framework instead)

## Off-ramp

One of the framework's design goals is "the builder can export their
app if they outgrow ODS." Two mechanisms exist:

- **Data export** ([lib/engine/data_exporter.dart](lib/engine/data_exporter.dart))
  — JSON / CSV / SQL dumps of an app's data.
- **Code generation** ([lib/engine/code_generator.dart](lib/engine/code_generator.dart))
  — emits a standalone Flutter project from an ODS spec. Generated
  apps are plain Flutter; they don't depend on ODS at runtime.

Generated code currently uses `getApplicationDocumentsDirectory()`
directly (doesn't honor the bootstrap mechanism). That's deliberate
— generated apps run on an end-user's machine with no ODS context —
but flagged on [TODO.md](../../TODO.md) for eventual consistency.

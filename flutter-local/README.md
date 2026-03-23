# ODS Flutter Local Framework

**Vibe Coding with Guardrails** — the Flutter Local reference implementation of [One Does Simply](https://github.com/One-does-simply).

## What is this?

This framework takes an ODS JSON spec and renders it as a fully functional Flutter app with local SQLite storage. No internet, no server, no account — your data stays on your device.

Describe your app idea to the AI Build Helper, and it produces a valid ODS spec. Open it here and the framework handles the rest: UI, navigation, forms, lists, charts, data storage, and more.

## Features

- **Instant rendering** — open a JSON spec and your app is live
- **Local SQLite storage** — all data stays on-device via `local://` data sources
- **AI Build Helper** — create apps through conversation, not code
- **Example catalog** — browse and pick from curated examples on first launch
- **Multi-user RBAC** — optional login, roles (guest/user/admin + custom), per-page/field/column visibility, row-level ownership
- **Off-ramp** — export your data (JSON/CSV/SQL) or generate a standalone Flutter project
- **Cross-platform** — runs on Windows, macOS, Linux, iOS, and Android

## Getting Started

1. Clone this repo
2. Run `flutter pub get`
3. Run `flutter run` (or `flutter build windows` / `flutter build macos` / etc.)
4. On first launch, pick some example apps or create your own

## Project Structure

```
lib/
  models/      Pure Dart classes for the ODS spec
  parser/      JSON → models, validation
  engine/      AppEngine (state), ActionHandler, DataStore (SQLite)
  renderer/    Flutter widgets, StyleResolver, components
  loader/      File picker + URL loading
  debug/       Debug panel overlay
  screens/     About, tour, help, login, admin setup, user management
assets/        Build helper prompt
```

## Links

- [ODS Specification](https://github.com/One-does-simply/Specification)
- [Landing Page](https://one-does-simply.github.io/Specification/)
- [Example Catalog](https://one-does-simply.github.io/Specification/Examples/catalog.json)

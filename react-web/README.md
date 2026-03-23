# ODS React Web Framework

The React + PocketBase web implementation of [One Does Simply](https://github.com/One-does-simply).

## What is this?

This framework takes an ODS JSON spec and renders it as a fully functional web app backed by PocketBase. Multi-user auth, role-based access, real-time data — all handled by the framework.

## Features

- **Instant rendering** — paste a JSON spec and your app is live
- **PocketBase backend** — auto-creates collections, handles auth, REST API
- **Multi-user RBAC** — login, roles (guest/user/admin + custom), per-page/field/column visibility
- **Row-level security** — ownership filtering so users see only their own data
- **Beautiful UI** — shadcn/ui components with Tailwind CSS
- **Fully tested** — 300+ unit/component tests with Vitest
- **Cross-platform** — runs in any modern browser

## Stack

| Layer | Technology |
|-------|-----------|
| Build | Vite |
| UI | React 19 + TypeScript |
| Styling | Tailwind CSS v4 + shadcn/ui |
| State | Zustand |
| Backend | PocketBase |
| Charts | Recharts |
| Tests | Vitest + React Testing Library + Playwright |

## Getting Started

### Prerequisites
- Node.js 22+
- [PocketBase](https://pocketbase.io/docs/) (single binary, download and run)

### Setup

```bash
# Install dependencies
npm install

# Start PocketBase (in another terminal)
./pocketbase serve

# Start dev server
npm run dev
```

Open http://localhost:5173, paste an ODS JSON spec, and your app renders instantly.

### Run Tests

```bash
npm test              # Unit + component tests (Vitest)
npm run test:watch    # Watch mode
npm run test:coverage # With coverage report
npm run test:e2e      # E2E tests (Playwright, requires PocketBase)
```

## Project Structure

```
src/
  models/         TypeScript types for the ODS spec
  parser/         JSON -> typed models, validation
  engine/         Core logic: store, actions, evaluators, data/auth services
  renderer/       React components mapping ODS types to shadcn/ui
  screens/        Welcome, app shell, login, admin setup
  components/ui/  shadcn/ui components
  lib/            PocketBase client, utilities
tests/
  unit/           Vitest unit tests (models, parser, engine)
  component/      React Testing Library component tests
  integration/    DataService + AuthService with MSW mocks
  e2e/            Playwright end-to-end tests
```

## Links

- [ODS Specification](https://github.com/One-does-simply/Specification)
- [Flutter Local Framework](../flutter-local/)
- [Build Helper](../../BuildHelpers/Claude/)

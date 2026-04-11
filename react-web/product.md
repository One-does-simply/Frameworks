# ODS React Web — Product Overview

## What Is This?

ODS React Web is a no-code/low-code web framework that transforms JSON specifications into fully functional, multi-user web applications. It is the web implementation of the **One Does Simply** (ODS) platform.

Builders describe *what* they want — pages, forms, lists, charts, actions — in a declarative JSON spec. The framework handles *how*: rendering, navigation, data storage, authentication, theming, and more.

## Who Is It For?

- **Business teams** who need custom internal tools without writing code
- **Developers** building app templates and prototypes rapidly
- **AI assistants** generating specs via the Build Helper prompt

## Key Capabilities

### App Rendering
- 9 component types: Form, List, Button, Chart, Text, Summary, Detail, Tabs, Kanban
- Dynamic page routing with navigation stack
- Conditional visibility (`visibleWhen` rules)
- Role-based page and component access

### Data Management
- PocketBase backend (collections auto-created from spec)
- CRUD operations with form validation
- Row-level ownership and security
- Data export (JSON, CSV, SQL)
- Auto-backup with retention and manual restore

### Authentication & Authorization
- Multi-user mode with self-registration
- Role-based access control (RBAC): admin, user, guest, custom roles
- OAuth2 provider support (Google, Microsoft, GitHub, etc.)
- PocketBase superadmin bypass for framework operators
- Session timeout (30 min idle)
- Login rate limiting (5 attempts / 5 min)

### Theming & Branding
- 35+ built-in themes (DaisyUI-derived, WCAG AA compliant)
- Light/dark/system mode
- Custom color overrides with contrast validation
- Per-app branding (logo, favicon, font, header style)

### Developer Tools
- Debug panel (dev-mode only) with app state inspection
- Structured logging service with localStorage persistence
- Security audit logging (`[SECURITY]` events)
- Code generator: export app as standalone React + Vite project
- AI-assisted spec editing

### Administration
- Admin dashboard for managing multiple apps
- App lifecycle: create, edit, archive, restore, delete
- User management with role assignment
- Framework settings (default app, backup config)

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | React 19 |
| Language | TypeScript 5.9 |
| Routing | React Router 7 |
| State | Zustand 5 |
| Styling | Tailwind CSS 4 |
| Components | shadcn/ui + Base UI |
| Charts | Recharts |
| Backend | PocketBase |
| Build | Vite 8 |
| Testing | Vitest + Playwright |

## Quick Start

```bash
npm install
# Start PocketBase in another terminal
npm run dev          # http://localhost:5173
```

## Commands

| Command | Description |
|---------|-------------|
| `npm run dev` | Development server |
| `npm run build` | Production build (type-check + bundle) |
| `npm test` | Run unit + component tests |
| `npm run test:watch` | Watch mode for TDD |
| `npm run test:coverage` | Tests with V8 coverage report |
| `npm run test:e2e` | Playwright browser tests |
| `npm run test:all` | Unit + E2E sequential |

## Test Coverage

- **43 test files**, **818 test cases**
- Unit tests: engine (15), models (14), parser (2), regression (1)
- Component tests: all 9 renderer components + PageRenderer
- E2E tests: 3 Playwright specs (Chromium + Firefox)
- Coverage provider: V8

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VITE_POCKETBASE_URL` | `http://127.0.0.1:8090` | PocketBase server URL |

## Project Structure

```
src/
  engine/       — Core services (store, auth, data, evaluators, logging)
  models/       — TypeScript interfaces for ODS spec types
  parser/       — JSON parsing and validation
  renderer/     — React components mapping ODS types to UI
  screens/      — Full-page screens (admin, login, editors, settings)
  components/   — Shared components (color picker, theme picker)
  lib/          — PocketBase client, utilities
tests/
  unit/         — Engine, model, parser unit tests
  component/    — Renderer component tests
  e2e/          — Playwright browser tests
```

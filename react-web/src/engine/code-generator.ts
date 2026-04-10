import type { OdsApp } from '@/models/ods-app.ts'
import type { OdsFormComponent, OdsListComponent, OdsButtonComponent, OdsChartComponent, OdsTextComponent, OdsSummaryComponent, OdsDetailComponent } from '@/models/ods-component.ts'
import type { OdsFieldDefinition } from '@/models/ods-field.ts'
import { isLocal, tableName } from '@/models/ods-data-source.ts'

// ---------------------------------------------------------------------------
// CodeGenerator — generates a standalone React + Vite + Tailwind project
// from an ODS spec. The generated project uses localStorage for data (no
// external database) so it's fully self-contained: npm install && npm run dev.
// ---------------------------------------------------------------------------

export interface GeneratedFiles {
  [relativePath: string]: string
}

export function generateProject(app: OdsApp): GeneratedFiles {
  const files: GeneratedFiles = {}
  const safeName = toKebab(app.appName)

  files['README.md'] = genReadme(app, safeName)
  files['package.json'] = genPackageJson(app, safeName)
  files['tsconfig.json'] = genTsConfig()
  files['tsconfig.app.json'] = genTsConfigApp()
  files['vite.config.ts'] = genViteConfig()
  files['index.html'] = genIndexHtml(app)
  files['postcss.config.js'] = genPostCss()
  files['src/main.tsx'] = genMain()
  files['src/App.tsx'] = genApp(app)
  files['src/index.css'] = genCss()
  files['src/lib/database.ts'] = genDatabase(app)
  files['src/components/Layout.tsx'] = genLayout(app)

  for (const [pageId, page] of Object.entries(app.pages)) {
    const fileName = toPascal(pageId)
    files[`src/pages/${fileName}.tsx`] = genPage(pageId, page, app)
  }

  return files
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function toKebab(s: string): string {
  return s.replace(/[^a-zA-Z0-9]+/g, '-').replace(/^-|-$/g, '').toLowerCase()
}

function toPascal(s: string): string {
  return s
    .replace(/[^a-zA-Z0-9]+/g, ' ')
    .split(' ')
    .filter(Boolean)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join('')
}

function toCamel(s: string): string {
  const p = toPascal(s)
  return p.charAt(0).toLowerCase() + p.slice(1)
}

function esc(s: string): string {
  return s.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/`/g, '\\`')
}

function escJsx(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;').replace(/{/g, '&#123;').replace(/}/g, '&#125;')
}

/** Collect columns for a table by looking at forms that submit to it + dataSource fields. */
function collectColumns(dsId: string, app: OdsApp): string[] {
  const cols = new Set<string>()

  // From dataSource.fields
  const ds = app.dataSources[dsId]
  if (ds?.fields) {
    for (const f of ds.fields) cols.add(f.name)
  }

  // From forms that submit to this dataSource
  for (const page of Object.values(app.pages)) {
    for (const comp of page.content) {
      if (comp.component === 'form') {
        const form = comp as OdsFormComponent
        // Check if any button submits this form to this dataSource
        for (const c2 of page.content) {
          if (c2.component === 'button') {
            const btn = c2 as OdsButtonComponent
            for (const action of btn.onClick) {
              if ((action.action === 'submit' || action.action === 'update') && action.dataSource === dsId) {
                for (const f of form.fields) cols.add(f.name)
              }
            }
          }
        }
      }
    }
  }

  // From seed data
  if (ds?.seedData) {
    for (const row of ds.seedData) {
      for (const key of Object.keys(row)) cols.add(key)
    }
  }

  return Array.from(cols)
}

// ---------------------------------------------------------------------------
// README.md
// ---------------------------------------------------------------------------

function genReadme(app: OdsApp, safeName: string): string {
  const pageList = Object.entries(app.pages)
    .map(([id, p]) => `- **${p.title}** (\`src/pages/${toPascal(id)}.tsx\`)`)
    .join('\n')

  return `# ${app.appName}

This is a standalone React app generated from an ODS (One Does Simply) spec.
**You own this code.** Edit anything you want — it's a normal React project now.

---

## Getting Started (New to Coding? Start Here!)

This project uses a few standard tools. Don't worry — you only need to install
them once and the steps below walk you through everything.

### 1. Install Node.js

Node.js is the engine that runs JavaScript outside of a browser. You need it to
install packages and run the development server.

1. Go to https://nodejs.org/ and download the **LTS** (Long Term Support) version (v18 or newer).
2. Run the installer — accept the defaults.
3. Verify it worked by opening a terminal and typing:
   \`\`\`bash
   node --version
   npm --version
   \`\`\`
   You should see version numbers for both.

> **What is npm?** npm (Node Package Manager) is installed automatically with
> Node.js. It downloads and manages the libraries your project depends on.

### 2. Install a Code Editor

You can use any text editor, but **VS Code** is free, popular, and has great
support for React projects.

1. Download it from https://code.visualstudio.com/
2. Install and open it.
3. **Recommended extensions** (optional but helpful):
   - **ESLint** — catches common mistakes as you type
   - **Prettier** — auto-formats your code on save
   - **Tailwind CSS IntelliSense** — autocomplete for Tailwind classes

> **Tip:** Open a terminal inside VS Code with \`Ctrl+\\\`\` (backtick) or
> *Terminal → New Terminal* from the menu bar.

### 3. Open and Run Your Project

\`\`\`bash
# Navigate into the project folder
cd ${safeName}

# Install all dependencies (downloads libraries listed in package.json)
npm install

# Start the development server
npm run dev
\`\`\`

Open the URL shown in the terminal (usually http://localhost:5173).
The browser reloads automatically whenever you save a file.

> **Troubleshooting:** If \`npm install\` fails, make sure Node.js is on your
> PATH. Close and re-open your terminal after installing Node, then try again.

---

## Project Structure

\`\`\`
${safeName}/
  README.md                  ← You are here
  package.json               ← Dependencies and scripts
  vite.config.ts             ← Build tool config
  index.html                 ← HTML entry point
  src/
    main.tsx                 ← React entry point
    App.tsx                  ← Router and routes
    index.css                ← Tailwind CSS + base styles
    lib/
      database.ts            ← localStorage CRUD (tables, queries)
    components/
      Layout.tsx             ← App shell (sidebar, top bar)
    pages/
${Object.keys(app.pages).map((id) => `      ${toPascal(id)}.tsx`).join('\n')}
\`\`\`

### Pages

${pageList}

### database.ts

Handles all data storage using \`localStorage\`. Contains:
- **Table creation** — creates tables on first access
- **Seed data** — pre-loads sample data defined in the original spec
- **CRUD methods** — \`getAll()\`, \`insert()\`, \`update()\`, \`remove()\`

> **Note:** localStorage keeps data in the browser. If a user clears their
> browser data, the app data resets. For a production app with persistent
> storage, consider adding a backend database (see *Next Steps* below).

---

## Common Customizations

### Change colors

In \`src/index.css\`, modify the CSS custom properties or Tailwind classes.

### Change the app title

In \`src/components/Layout.tsx\`, find the app name string.

### Add a new field to a form

Open the page file, find the form JSX, and add a new input. Don't forget to
update the state object and the submit handler.

### Change list columns

Find the \`<table>\` in the page file and edit the \`<th>\` and \`<td>\` elements.

---

## Building for Production

\`\`\`bash
npm run build
\`\`\`

This creates an optimized \`dist/\` folder containing plain HTML, CSS, and JS
files. These static files can be deployed anywhere — no special server required.

> **What does "build" do?** It bundles and minifies your code so it loads faster
> for real users. The \`dist/\` folder is the only thing you upload to a host.

---

## Deploying Your App

Your built app is a set of static files, so there are many free or low-cost
options for hosting it. Here are a few popular choices:

### Option A: Vercel (Recommended for Beginners)

Vercel is the company behind Next.js and has first-class support for Vite/React.

1. Create a free account at https://vercel.com/
2. Install the Vercel CLI:
   \`\`\`bash
   npm install -g vercel
   \`\`\`
3. From your project folder, run:
   \`\`\`bash
   vercel
   \`\`\`
4. Follow the prompts — Vercel auto-detects Vite and configures everything.
5. Your app is live! Vercel gives you a URL like \`your-app.vercel.app\`.

> **Auto-deploys:** Connect your GitHub repo and Vercel redeploys every time
> you push a change.

### Option B: Netlify

Another excellent free option with drag-and-drop deploys.

1. Create a free account at https://www.netlify.com/
2. Option 1 — **Drag and drop:** Run \`npm run build\`, then drag the \`dist/\`
   folder onto the Netlify dashboard.
3. Option 2 — **CLI:**
   \`\`\`bash
   npm install -g netlify-cli
   netlify deploy --prod --dir=dist
   \`\`\`
4. For single-page app routing, create a \`public/_redirects\` file containing:
   \`\`\`
   /*    /index.html   200
   \`\`\`

### Option C: GitHub Pages (Free with a GitHub Account)

Good if your code is already on GitHub.

1. Install the deployment plugin:
   \`\`\`bash
   npm install -D gh-pages
   \`\`\`
2. Add these scripts to \`package.json\`:
   \`\`\`json
   "predeploy": "npm run build",
   "deploy": "gh-pages -d dist"
   \`\`\`
3. If your repo is \`username/repo-name\`, add a \`base\` to \`vite.config.ts\`:
   \`\`\`ts
   export default defineConfig({
     base: '/repo-name/',
     // ... rest of config
   })
   \`\`\`
4. Deploy:
   \`\`\`bash
   npm run deploy
   \`\`\`

### Option D: Cloudflare Pages

Fast, free, and global CDN included.

1. Create a free account at https://pages.cloudflare.com/
2. Connect your GitHub repo — set build command to \`npm run build\` and output
   directory to \`dist\`.
3. Cloudflare deploys automatically on every push.

### Custom Domain

All of the hosts above support custom domains. The general steps are:
1. Buy a domain from a registrar (Namecheap, Google Domains, Cloudflare, etc.).
2. In your host's dashboard, add the domain and follow the DNS instructions.
3. The host will provision an HTTPS certificate automatically.

---

## Next Steps

Once your app is live, here are some things you might want to explore:

- **Add a backend** — If you need user accounts or a real database, look into
  [Supabase](https://supabase.com/) (Postgres + auth, generous free tier) or
  [PocketBase](https://pocketbase.io/) (single-binary backend).
- **Version control with Git** — Track your changes and collaborate with others.
  GitHub Desktop (https://desktop.github.com/) is a beginner-friendly way to
  get started with Git.
- **Learn more React** — The official React docs are excellent:
  https://react.dev/learn

---

*Generated by One Does Simply (ODS) — the spec-driven app framework.*
`
}

// ---------------------------------------------------------------------------
// package.json
// ---------------------------------------------------------------------------

function genPackageJson(app: OdsApp, safeName: string): string {
  const hasChart = Object.values(app.pages).some((p) =>
    p.content.some((c) => c.component === 'chart'),
  )

  const deps: Record<string, string> = {
    react: '^19.0.0',
    'react-dom': '^19.0.0',
    'react-router': '^7.0.0',
  }
  if (hasChart) {
    deps['recharts'] = '^2.15.0'
  }

  const obj = {
    name: safeName,
    private: true,
    version: '1.0.0',
    description: `Generated from ODS spec "${app.appName}"`,
    type: 'module',
    scripts: {
      dev: 'vite',
      build: 'tsc -b && vite build',
      preview: 'vite preview',
    },
    dependencies: deps,
    devDependencies: {
      '@types/react': '^19.0.0',
      '@types/react-dom': '^19.0.0',
      '@vitejs/plugin-react': '^4.3.0',
      autoprefixer: '^10.4.0',
      postcss: '^8.5.0',
      tailwindcss: '^3.4.0',
      typescript: '^5.7.0',
      vite: '^6.0.0',
    },
  }

  return JSON.stringify(obj, null, 2) + '\n'
}

// ---------------------------------------------------------------------------
// Config files
// ---------------------------------------------------------------------------

function genTsConfig(): string {
  return `{
  "files": [],
  "references": [{ "path": "./tsconfig.app.json" }]
}
`
}

function genTsConfigApp(): string {
  return `{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "isolatedModules": true,
    "moduleDetection": "force",
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": false,
    "noUnusedParameters": false,
    "noFallthroughCasesInSwitch": true,
    "noUncheckedSideEffectImports": true,
    "baseUrl": ".",
    "paths": { "@/*": ["./src/*"] }
  },
  "include": ["src"]
}
`
}

function genViteConfig(): string {
  return `import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { resolve } from 'path'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: { '@': resolve(__dirname, './src') },
  },
})
`
}

function genPostCss(): string {
  return `export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
}
`
}

function genIndexHtml(app: OdsApp): string {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>${escJsx(app.appName)}</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
`
}

function genCss(): string {
  return `@tailwind base;
@tailwind components;
@tailwind utilities;

body {
  @apply bg-gray-50 text-gray-900 antialiased;
  font-family: system-ui, -apple-system, sans-serif;
}
`
}

// ---------------------------------------------------------------------------
// src/main.tsx
// ---------------------------------------------------------------------------

function genMain(): string {
  return `import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router'
import App from './App'
import './index.css'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </StrictMode>,
)
`
}

// ---------------------------------------------------------------------------
// src/App.tsx — routes
// ---------------------------------------------------------------------------

function genApp(app: OdsApp): string {
  const imports = Object.keys(app.pages)
    .map((id) => `import ${toPascal(id)} from './pages/${toPascal(id)}'`)
    .join('\n')

  const routes = Object.keys(app.pages)
    .map((id) => `        <Route path="/${id}" element={<Layout><${toPascal(id)} /></Layout>} />`)
    .join('\n')

  return `import { Routes, Route, Navigate } from 'react-router'
import Layout from './components/Layout'
${imports}

export default function App() {
  return (
    <Routes>
${routes}
      <Route path="*" element={<Navigate to="/${app.startPage}" replace />} />
    </Routes>
  )
}
`
}

// ---------------------------------------------------------------------------
// src/components/Layout.tsx — app shell with sidebar nav
// ---------------------------------------------------------------------------

function genLayout(app: OdsApp): string {
  const menuItems = app.menu
    .map((item) => `    { label: '${esc(item.label)}', path: '/${item.mapsTo}' },`)
    .join('\n')

  return `import { useState, type ReactNode } from 'react'
import { useLocation, useNavigate } from 'react-router'

interface LayoutProps {
  children: ReactNode
}

const menuItems = [
${menuItems}
]

export default function Layout({ children }: LayoutProps) {
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const location = useLocation()
  const navigate = useNavigate()

  return (
    <div className="flex min-h-screen">
      {/* Overlay */}
      {sidebarOpen && (
        <div
          className="fixed inset-0 z-30 bg-black/30 md:hidden"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      {/* Sidebar */}
      <aside
        className={\`fixed inset-y-0 left-0 z-40 w-64 transform bg-white shadow-lg transition-transform md:relative md:translate-x-0 \${
          sidebarOpen ? 'translate-x-0' : '-translate-x-full'
        }\`}
      >
        <div className="flex h-14 items-center gap-2 border-b bg-gradient-to-r from-indigo-600 to-violet-600 px-4">
          <h1 className="truncate text-lg font-bold text-white">${escJsx(app.appName)}</h1>
        </div>
        <nav className="flex flex-col gap-1 p-2">
          {menuItems.map((item) => (
            <button
              key={item.path}
              onClick={() => {
                navigate(item.path)
                setSidebarOpen(false)
              }}
              className={\`rounded-lg px-3 py-2 text-left text-sm transition-colors \${
                location.pathname === item.path
                  ? 'bg-indigo-50 font-medium text-indigo-700'
                  : 'text-gray-700 hover:bg-gray-100'
              }\`}
            >
              {item.label}
            </button>
          ))}
        </nav>
      </aside>

      {/* Main content */}
      <div className="flex flex-1 flex-col">
        <header className="sticky top-0 z-20 flex h-14 items-center gap-2 border-b bg-white/95 px-4 backdrop-blur">
          <button
            className="rounded-lg p-2 text-gray-600 hover:bg-gray-100 md:hidden"
            onClick={() => setSidebarOpen(true)}
            aria-label="Open menu"
          >
            <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
            </svg>
          </button>
          <h2 className="text-base font-semibold text-gray-900">
            {menuItems.find((i) => i.path === location.pathname)?.label ?? '${escJsx(app.appName)}'}
          </h2>
        </header>
        <main className="flex-1 p-4 md:p-6">{children}</main>
      </div>
    </div>
  )
}
`
}

// ---------------------------------------------------------------------------
// src/lib/database.ts — localStorage-based CRUD
// ---------------------------------------------------------------------------

function genDatabase(app: OdsApp): string {
  // Build table schema + seed data initialization
  const localSources: { dsId: string; table: string; columns: string[]; seedData?: Record<string, unknown>[] }[] = []

  const seenTables = new Set<string>()
  for (const [dsId, ds] of Object.entries(app.dataSources)) {
    if (!isLocal(ds)) continue
    const tbl = tableName(ds)
    if (seenTables.has(tbl)) continue
    seenTables.add(tbl)
    localSources.push({
      dsId,
      table: tbl,
      columns: collectColumns(dsId, app),
      seedData: ds.seedData,
    })
  }

  const seedBlocks = localSources
    .filter((s) => s.seedData && s.seedData.length > 0)
    .map((s) => {
      const rows = JSON.stringify(s.seedData, null, 2)
      return `  if (getAll('${esc(s.table)}').length === 0) {
    const seed: Record<string, string>[] = ${rows}
    for (const row of seed) {
      insert('${esc(s.table)}', row)
    }
  }`
    })
    .join('\n\n')

  return `// ---------------------------------------------------------------------------
// database.ts — localStorage-based CRUD for ODS-generated app
// ---------------------------------------------------------------------------

const DB_PREFIX = 'ods_db_'

function storageKey(table: string): string {
  return DB_PREFIX + table
}

function readTable(table: string): Record<string, unknown>[] {
  const raw = localStorage.getItem(storageKey(table))
  if (!raw) return []
  try {
    return JSON.parse(raw)
  } catch {
    return []
  }
}

function writeTable(table: string, rows: Record<string, unknown>[]): void {
  localStorage.setItem(storageKey(table), JSON.stringify(rows))
}

let nextId = Date.now()

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export function getAll(table: string): Record<string, unknown>[] {
  return readTable(table)
}

export function insert(table: string, data: Record<string, unknown>): string {
  const rows = readTable(table)
  const id = String(++nextId)
  rows.push({ ...data, _id: id })
  writeTable(table, rows)
  return id
}

export function update(
  table: string,
  data: Record<string, unknown>,
  matchField: string,
  matchValue: string,
): number {
  const rows = readTable(table)
  let count = 0
  for (const row of rows) {
    if (String(row[matchField] ?? '') === matchValue) {
      Object.assign(row, data)
      count++
    }
  }
  writeTable(table, rows)
  return count
}

export function remove(table: string, matchField: string, matchValue: string): number {
  const rows = readTable(table)
  const filtered = rows.filter((r) => String(r[matchField] ?? '') !== matchValue)
  const count = rows.length - filtered.length
  writeTable(table, filtered)
  return count
}

// ---------------------------------------------------------------------------
// Initialize seed data (called once on app start)
// ---------------------------------------------------------------------------

export function initializeDatabase(): void {
${seedBlocks || '  // No seed data defined'}
}
`
}

// ---------------------------------------------------------------------------
// Page generation
// ---------------------------------------------------------------------------

function genPage(
  pageId: string,
  page: import('@/models/ods-page.ts').OdsPage,
  app: OdsApp,
): string {
  const componentName = toPascal(pageId)
  const parts: string[] = []
  const imports = new Set<string>()
  const stateLines: string[] = []
  const effectLines: string[] = []
  const handlerLines: string[] = []
  const jsxParts: string[] = []

  imports.add("import { useState, useEffect } from 'react'")
  imports.add("import { useNavigate } from 'react-router'")
  imports.add("import * as db from '@/lib/database'")

  let hasChart = false

  for (const comp of page.content) {
    switch (comp.component) {
      case 'text':
        jsxParts.push(genTextJsx(comp as OdsTextComponent))
        break
      case 'form':
        genFormParts(comp as OdsFormComponent, page, app, stateLines, handlerLines, jsxParts)
        break
      case 'list':
        genListParts(comp as OdsListComponent, app, stateLines, effectLines, handlerLines, jsxParts)
        break
      case 'button':
        genButtonParts(comp as OdsButtonComponent, page, app, stateLines, handlerLines, jsxParts)
        break
      case 'chart':
        hasChart = true
        genChartParts(comp as OdsChartComponent, app, imports, stateLines, effectLines, jsxParts)
        break
      case 'summary':
        genSummaryParts(comp as OdsSummaryComponent, app, stateLines, effectLines, jsxParts)
        break
      case 'detail':
        genDetailParts(comp as OdsDetailComponent, app, stateLines, effectLines, jsxParts)
        break
    }
  }

  if (hasChart) {
    imports.add("import { BarChart, Bar, LineChart, Line, PieChart, Pie, Cell, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts'")
  }

  // Build the component
  parts.push(Array.from(imports).join('\n'))
  parts.push('')
  parts.push(`export default function ${componentName}() {`)
  parts.push('  const navigate = useNavigate()')

  if (stateLines.length > 0) {
    parts.push('')
    parts.push(...stateLines.map((l) => '  ' + l))
  }

  if (effectLines.length > 0) {
    parts.push('')
    parts.push('  useEffect(() => {')
    parts.push(...effectLines.map((l) => '    ' + l))
    parts.push('  }, [])')
  }

  if (handlerLines.length > 0) {
    parts.push('')
    parts.push(...handlerLines.map((l) => '  ' + l))
  }

  parts.push('')
  parts.push('  return (')
  parts.push('    <div className="space-y-6">')
  parts.push(`      <h1 className="text-2xl font-bold text-gray-900">${escJsx(page.title)}</h1>`)
  parts.push(...jsxParts.map((j) => '      ' + j))
  parts.push('    </div>')
  parts.push('  )')
  parts.push('}')

  return parts.join('\n') + '\n'
}

// ---------------------------------------------------------------------------
// Text component
// ---------------------------------------------------------------------------

function genTextJsx(comp: OdsTextComponent): string {
  return `<p className="text-gray-600">${escJsx(comp.content)}</p>`
}

// ---------------------------------------------------------------------------
// Form component
// ---------------------------------------------------------------------------

function genFormParts(
  comp: OdsFormComponent,
  _page: import('@/models/ods-page.ts').OdsPage,
  _app: OdsApp,
  stateLines: string[],
  handlerLines: string[],
  jsxParts: string[],
): void {
  const formId = comp.id
  const formVar = toCamel(formId)

  // Build initial state object
  const initObj: Record<string, string> = {}
  for (const f of comp.fields) {
    if (f.formula) continue // skip computed fields
    initObj[f.name] = f.defaultValue ?? ''
  }
  stateLines.push(`const [${formVar}, set${toPascal(formId)}] = useState(${JSON.stringify(initObj)})`)

  // onChange handler
  handlerLines.push(`function handle${toPascal(formId)}Change(field: string, value: string) {`)
  handlerLines.push(`  set${toPascal(formId)}((prev) => ({ ...prev, [field]: value }))`)
  handlerLines.push('}')

  // Build form JSX
  const fieldInputs = comp.fields
    .filter((f) => !f.formula)
    .map((f) => genFieldInput(f, formVar, formId))
    .join('\n')

  jsxParts.push(`<div className="rounded-lg border bg-white p-6 shadow-sm">`)
  jsxParts.push(fieldInputs)
  jsxParts.push('</div>')
}

function genFieldInput(field: OdsFieldDefinition, formVar: string, formId: string): string {
  const label = field.label ?? field.name
  const handler = `handle${toPascal(formId)}Change`
  const required = field.required ? ' *' : ''

  if (field.type === 'select' && field.options) {
    const options = field.options.map((o) => `<option value="${esc(o)}">${escJsx(o)}</option>`).join('\n          ')
    return `  <div className="mb-4">
    <label className="mb-1 block text-sm font-medium text-gray-700">${escJsx(label)}${required}</label>
    <select
      value={${formVar}['${esc(field.name)}']}
      onChange={(e) => ${handler}('${esc(field.name)}', e.target.value)}
      className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
    >
      <option value="">Select...</option>
      ${options}
    </select>
  </div>`
  }

  if (field.type === 'checkbox') {
    return `  <div className="mb-4 flex items-center gap-2">
    <input
      type="checkbox"
      checked={${formVar}['${esc(field.name)}'] === 'true'}
      onChange={(e) => ${handler}('${esc(field.name)}', e.target.checked ? 'true' : 'false')}
      className="h-4 w-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
    />
    <label className="text-sm font-medium text-gray-700">${escJsx(label)}</label>
  </div>`
  }

  if (field.type === 'multiline') {
    return `  <div className="mb-4">
    <label className="mb-1 block text-sm font-medium text-gray-700">${escJsx(label)}${required}</label>
    <textarea
      value={${formVar}['${esc(field.name)}']}
      onChange={(e) => ${handler}('${esc(field.name)}', e.target.value)}
      placeholder="${esc(field.placeholder ?? '')}"
      rows={4}
      className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
    />
  </div>`
  }

  // Default: text, email, number, date, datetime
  const inputType =
    field.type === 'email' ? 'email'
    : field.type === 'number' ? 'number'
    : field.type === 'date' ? 'date'
    : field.type === 'datetime' ? 'datetime-local'
    : 'text'

  return `  <div className="mb-4">
    <label className="mb-1 block text-sm font-medium text-gray-700">${escJsx(label)}${required}</label>
    <input
      type="${inputType}"
      value={${formVar}['${esc(field.name)}']}
      onChange={(e) => ${handler}('${esc(field.name)}', e.target.value)}
      placeholder="${esc(field.placeholder ?? '')}"
      className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
    />
  </div>`
}

// ---------------------------------------------------------------------------
// List component
// ---------------------------------------------------------------------------

function genListParts(
  comp: OdsListComponent,
  app: OdsApp,
  stateLines: string[],
  effectLines: string[],
  handlerLines: string[],
  jsxParts: string[],
): void {
  const ds = app.dataSources[comp.dataSource]
  if (!ds || !isLocal(ds)) return
  const tbl = tableName(ds)
  const rowsVar = toCamel(tbl) + 'Rows'

  stateLines.push(`const [${rowsVar}, set${toPascal(tbl)}Rows] = useState<Record<string, unknown>[]>([])`)

  effectLines.push(`set${toPascal(tbl)}Rows(db.getAll('${esc(tbl)}'))`)

  // Refresh function
  handlerLines.push(`function refresh${toPascal(tbl)}() {`)
  handlerLines.push(`  set${toPascal(tbl)}Rows(db.getAll('${esc(tbl)}'))`)
  handlerLines.push('}')

  // Delete handler if needed
  const hasDelete = comp.rowActions.some((ra) => ra.action === 'delete')
  if (hasDelete) {
    handlerLines.push(`function handleDelete${toPascal(tbl)}(matchField: string, matchValue: string) {`)
    handlerLines.push(`  if (!confirm('Are you sure you want to delete this item?')) return`)
    handlerLines.push(`  db.remove('${esc(tbl)}', matchField, matchValue)`)
    handlerLines.push(`  refresh${toPascal(tbl)}()`)
    handlerLines.push('}')
  }

  // Generate table JSX
  const headers = comp.columns
    .map((col) => `<th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">${escJsx(col.header)}</th>`)
    .join('\n              ')

  const cells = comp.columns
    .map((col) => `<td className="whitespace-nowrap px-4 py-3 text-sm text-gray-700">{String(row['${esc(col.field)}'] ?? '')}</td>`)
    .join('\n                ')

  // Row action cells
  let actionHeader = ''
  let actionCell = ''
  if (comp.rowActions.length > 0) {
    actionHeader = `<th className="px-4 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">Actions</th>`

    const actionButtons = comp.rowActions.map((ra) => {
      if (ra.action === 'delete') {
        return `<button onClick={() => handleDelete${toPascal(tbl)}('${esc(ra.matchField)}', String(row['${esc(ra.matchField)}'] ?? ''))} className="text-sm text-red-600 hover:text-red-800">${escJsx(ra.label)}</button>`
      }
      return `<button className="text-sm text-indigo-600 hover:text-indigo-800">${escJsx(ra.label)}</button>`
    }).join('\n                    ')

    actionCell = `<td className="whitespace-nowrap px-4 py-3 text-right text-sm">
                  <div className="flex justify-end gap-2">
                    ${actionButtons}
                  </div>
                </td>`
  }

  // Search
  let searchState = ''
  let searchInput = ''
  let filterExpr = rowsVar
  if (comp.searchable) {
    const searchVar = `${toCamel(tbl)}Search`
    stateLines.push(`const [${searchVar}, set${toPascal(tbl)}Search] = useState('')`)
    searchState = searchVar
    searchInput = `<input
        type="text"
        placeholder="Search..."
        value={${searchState}}
        onChange={(e) => set${toPascal(tbl)}Search(e.target.value)}
        className="mb-4 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
      />`
    filterExpr = `${rowsVar}.filter((row) => Object.values(row).some((v) => String(v).toLowerCase().includes(${searchState}.toLowerCase())))`
  }

  jsxParts.push(`<div className="overflow-hidden rounded-lg border bg-white shadow-sm">`)
  if (searchInput) jsxParts.push(`  ${searchInput}`)
  jsxParts.push(`  <div className="overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              ${headers}
              ${actionHeader}
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {${filterExpr}.map((row, i) => (
              <tr key={String(row._id ?? i)} className="hover:bg-gray-50">
                ${cells}
                ${actionCell}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>`)
}

// ---------------------------------------------------------------------------
// Button component
// ---------------------------------------------------------------------------

function genButtonParts(
  comp: OdsButtonComponent,
  _page: import('@/models/ods-page.ts').OdsPage,
  _app: OdsApp,
  _stateLines: string[],
  handlerLines: string[],
  jsxParts: string[],
): void {
  const handlerName = `handle${toPascal(comp.label.replace(/[^a-zA-Z0-9]/g, ' '))}Click`

  const actionLines: string[] = []
  for (const action of comp.onClick) {
    if (action.action === 'navigate' && action.target) {
      actionLines.push(`navigate('/${action.target}')`)
    } else if (action.action === 'submit' && action.dataSource) {
      const ds = app.dataSources[action.dataSource]
      if (ds && isLocal(ds)) {
        const tbl = tableName(ds)
        // Find which form this button submits
        const form = page.content.find(
          (c): c is OdsFormComponent => c.component === 'form',
        )
        if (form) {
          const formVar = toCamel(form.id)
          actionLines.push(`db.insert('${esc(tbl)}', { ...${formVar} })`)
          // Reset form
          const initObj: Record<string, string> = {}
          for (const f of form.fields) {
            if (!f.formula) initObj[f.name] = f.defaultValue ?? ''
          }
          actionLines.push(`set${toPascal(form.id)}(${JSON.stringify(initObj)})`)
          // Refresh list if one exists on page
          const list = page.content.find(
            (c): c is OdsListComponent => c.component === 'list',
          )
          if (list) {
            const listDs = app.dataSources[list.dataSource]
            if (listDs && isLocal(listDs)) {
              actionLines.push(`refresh${toPascal(tableName(listDs))}()`)
            }
          }
        }
      }
    } else if (action.action === 'update' && action.dataSource && action.matchField) {
      const ds = app.dataSources[action.dataSource]
      if (ds && isLocal(ds)) {
        const tbl = tableName(ds)
        const form = page.content.find(
          (c): c is OdsFormComponent => c.component === 'form',
        )
        if (form) {
          const formVar = toCamel(form.id)
          actionLines.push(`db.update('${esc(tbl)}', { ...${formVar} }, '${esc(action.matchField)}', ${formVar}['${esc(action.matchField)}'])`)

          const list = page.content.find(
            (c): c is OdsListComponent => c.component === 'list',
          )
          if (list) {
            const listDs = app.dataSources[list.dataSource]
            if (listDs && isLocal(listDs)) {
              actionLines.push(`refresh${toPascal(tableName(listDs))}()`)
            }
          }
        }
      }
    }

    // Handle onEnd navigate
    if (action.onEnd?.action === 'navigate' && action.onEnd.target) {
      actionLines.push(`navigate('/${action.onEnd.target}')`)
    }
    if (action.message) {
      actionLines.push(`alert('${esc(action.message)}')`)
    }
  }

  handlerLines.push(`function ${handlerName}() {`)
  handlerLines.push(...actionLines.map((l) => `  ${l}`))
  handlerLines.push('}')

  const isPrimary = comp.styleHint?.variant === 'primary' || comp.onClick.some((a) => a.action === 'submit')
  const btnClass = isPrimary
    ? 'rounded-lg bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500'
    : 'rounded-lg border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-indigo-500'

  jsxParts.push(`<button onClick={${handlerName}} className="${btnClass}">${escJsx(comp.label)}</button>`)
}

// ---------------------------------------------------------------------------
// Chart component
// ---------------------------------------------------------------------------

function genChartParts(
  comp: OdsChartComponent,
  app: OdsApp,
  _imports: Set<string>,
  stateLines: string[],
  effectLines: string[],
  jsxParts: string[],
): void {
  const ds = app.dataSources[comp.dataSource]
  if (!ds || !isLocal(ds)) return
  const tbl = tableName(ds)
  const dataVar = toCamel(tbl) + 'ChartData'

  stateLines.push(`const [${dataVar}, set${toPascal(tbl)}ChartData] = useState<Record<string, unknown>[]>([])`)

  // Aggregate data in the effect
  effectLines.push(`// Chart: aggregate ${comp.chartType} data`)
  effectLines.push(`const rawChartRows = db.getAll('${esc(tbl)}')`)

  if (comp.aggregate === 'count') {
    effectLines.push(`const chartAgg: Record<string, number> = {}`)
    effectLines.push(`for (const r of rawChartRows) { const k = String(r['${esc(comp.labelField)}'] ?? ''); chartAgg[k] = (chartAgg[k] ?? 0) + 1 }`)
    effectLines.push(`set${toPascal(tbl)}ChartData(Object.entries(chartAgg).map(([name, value]) => ({ name, value })))`)
  } else if (comp.aggregate === 'sum') {
    effectLines.push(`const chartAgg: Record<string, number> = {}`)
    effectLines.push(`for (const r of rawChartRows) { const k = String(r['${esc(comp.labelField)}'] ?? ''); chartAgg[k] = (chartAgg[k] ?? 0) + Number(r['${esc(comp.valueField)}'] ?? 0) }`)
    effectLines.push(`set${toPascal(tbl)}ChartData(Object.entries(chartAgg).map(([name, value]) => ({ name, value })))`)
  } else {
    effectLines.push(`set${toPascal(tbl)}ChartData(rawChartRows.map((r) => ({ name: String(r['${esc(comp.labelField)}'] ?? ''), value: Number(r['${esc(comp.valueField)}'] ?? 0) })))`)
  }

  const title = comp.title ? `<h3 className="mb-2 text-lg font-semibold text-gray-800">${escJsx(comp.title)}</h3>` : ''
  const colors = "['#6366f1', '#8b5cf6', '#a78bfa', '#c4b5fd', '#818cf8', '#4f46e5']"

  let chartJsx: string
  if (comp.chartType === 'pie') {
    chartJsx = `<ResponsiveContainer width="100%" height={300}>
          <PieChart>
            <Pie data={${dataVar}} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={100} label>
              {${dataVar}.map((_, i) => <Cell key={i} fill={${colors}[i % ${colors}.length]} />)}
            </Pie>
            <Tooltip />
          </PieChart>
        </ResponsiveContainer>`
  } else if (comp.chartType === 'line') {
    chartJsx = `<ResponsiveContainer width="100%" height={300}>
          <LineChart data={${dataVar}}>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis dataKey="name" />
            <YAxis />
            <Tooltip />
            <Line type="monotone" dataKey="value" stroke="#6366f1" strokeWidth={2} />
          </LineChart>
        </ResponsiveContainer>`
  } else {
    chartJsx = `<ResponsiveContainer width="100%" height={300}>
          <BarChart data={${dataVar}}>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis dataKey="name" />
            <YAxis />
            <Tooltip />
            <Bar dataKey="value" fill="#6366f1" radius={[4, 4, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>`
  }

  jsxParts.push(`<div className="rounded-lg border bg-white p-6 shadow-sm">
        ${title}
        ${chartJsx}
      </div>`)
}

// ---------------------------------------------------------------------------
// Summary component
// ---------------------------------------------------------------------------

function genSummaryParts(
  comp: OdsSummaryComponent,
  _app: OdsApp,
  _stateLines: string[],
  _effectLines: string[],
  jsxParts: string[],
): void {
  jsxParts.push(`<div className="rounded-lg border bg-white p-4 shadow-sm">
        <div className="text-sm text-gray-500">${escJsx(comp.label)}</div>
        <div className="text-2xl font-bold text-gray-900">${escJsx(comp.value)}</div>
      </div>`)
}

// ---------------------------------------------------------------------------
// Detail component
// ---------------------------------------------------------------------------

function genDetailParts(
  comp: OdsDetailComponent,
  app: OdsApp,
  stateLines: string[],
  effectLines: string[],
  jsxParts: string[],
): void {
  const ds = app.dataSources[comp.dataSource]
  if (!ds || !isLocal(ds)) return
  const tbl = tableName(ds)
  const detailVar = toCamel(tbl) + 'Detail'

  stateLines.push(`const [${detailVar}, set${toPascal(tbl)}Detail] = useState<Record<string, unknown> | null>(null)`)
  effectLines.push(`const detailRows = db.getAll('${esc(tbl)}')`)
  effectLines.push(`if (detailRows.length > 0) set${toPascal(tbl)}Detail(detailRows[0])`)

  const fields = comp.fields ?? Object.keys(ds.fields?.reduce((acc, f) => ({ ...acc, [f.name]: true }), {}) ?? {})
  const fieldRows = fields
    .map((f) => {
      const label = comp.labels?.[f] ?? f
      return `<div className="grid grid-cols-3 gap-4 border-b py-2">
            <span className="text-sm font-medium text-gray-500">${escJsx(label)}</span>
            <span className="col-span-2 text-sm text-gray-900">{String(${detailVar}?.['${esc(f)}'] ?? '-')}</span>
          </div>`
    })
    .join('\n          ')

  jsxParts.push(`<div className="rounded-lg border bg-white p-6 shadow-sm">
        {${detailVar} ? (
          <div className="divide-y">
            ${fieldRows}
          </div>
        ) : (
          <p className="text-sm text-gray-500">No data found.</p>
        )}
      </div>`)
}

// ---------------------------------------------------------------------------
// ZIP helper — generates a downloadable ZIP using JSZip-like approach
// (We use a minimal in-memory ZIP builder to avoid external deps at gen time)
// ---------------------------------------------------------------------------

/**
 * Packs the generated files into a ZIP blob for download.
 * Uses the browser's CompressionStream API (available in modern browsers).
 */
export async function packAsZip(files: GeneratedFiles, rootFolder: string): Promise<Blob> {
  // We build a proper ZIP file using the standard format:
  // Local file headers + data, then central directory, then end record.
  const encoder = new TextEncoder()
  const parts: { name: Uint8Array; data: Uint8Array; offset: number }[] = []
  let offset = 0
  const localHeaders: Uint8Array[] = []

  for (const [path, content] of Object.entries(files)) {
    const fullPath = `${rootFolder}/${path}`
    const nameBytes = encoder.encode(fullPath)
    const dataBytes = encoder.encode(content)

    // Local file header (30 bytes + name + data)
    const header = new Uint8Array(30 + nameBytes.length)
    const hv = new DataView(header.buffer)
    hv.setUint32(0, 0x04034b50, true) // Local file header signature
    hv.setUint16(4, 20, true) // Version needed
    hv.setUint16(6, 0, true) // Flags
    hv.setUint16(8, 0, true) // Compression: stored (no compression)
    hv.setUint16(10, 0, true) // Mod time
    hv.setUint16(12, 0, true) // Mod date
    hv.setUint32(14, crc32(dataBytes), true) // CRC-32
    hv.setUint32(18, dataBytes.length, true) // Compressed size
    hv.setUint32(22, dataBytes.length, true) // Uncompressed size
    hv.setUint16(26, nameBytes.length, true) // Name length
    hv.setUint16(28, 0, true) // Extra field length
    header.set(nameBytes, 30)

    parts.push({ name: nameBytes, data: dataBytes, offset })
    localHeaders.push(header)

    offset += header.length + dataBytes.length
  }

  // Central directory
  const centralParts: Uint8Array[] = []
  let centralSize = 0

  for (const part of parts) {
    const entry = new Uint8Array(46 + part.name.length)
    const ev = new DataView(entry.buffer)
    ev.setUint32(0, 0x02014b50, true) // Central directory signature
    ev.setUint16(4, 20, true) // Version made by
    ev.setUint16(6, 20, true) // Version needed
    ev.setUint16(8, 0, true) // Flags
    ev.setUint16(10, 0, true) // Compression
    ev.setUint16(12, 0, true) // Mod time
    ev.setUint16(14, 0, true) // Mod date
    ev.setUint32(16, crc32(part.data), true) // CRC-32
    ev.setUint32(20, part.data.length, true) // Compressed size
    ev.setUint32(24, part.data.length, true) // Uncompressed size
    ev.setUint16(28, part.name.length, true) // Name length
    ev.setUint16(30, 0, true) // Extra field length
    ev.setUint16(32, 0, true) // Comment length
    ev.setUint16(34, 0, true) // Disk number
    ev.setUint16(36, 0, true) // Internal attrs
    ev.setUint32(38, 0, true) // External attrs
    ev.setUint32(42, part.offset, true) // Relative offset
    entry.set(part.name, 46)

    centralParts.push(entry)
    centralSize += entry.length
  }

  // End of central directory
  const endRecord = new Uint8Array(22)
  const erv = new DataView(endRecord.buffer)
  erv.setUint32(0, 0x06054b50, true) // End of central dir signature
  erv.setUint16(4, 0, true) // Disk number
  erv.setUint16(6, 0, true) // Disk with central dir
  erv.setUint16(8, parts.length, true) // Entries on this disk
  erv.setUint16(10, parts.length, true) // Total entries
  erv.setUint32(12, centralSize, true) // Central directory size
  erv.setUint32(16, offset, true) // Central directory offset
  erv.setUint16(20, 0, true) // Comment length

  // Concatenate everything
  const allParts: BlobPart[] = []
  for (let i = 0; i < localHeaders.length; i++) {
    allParts.push(localHeaders[i] as unknown as BlobPart)
    allParts.push(parts[i].data as unknown as BlobPart)
  }
  for (const cp of centralParts) allParts.push(cp as unknown as BlobPart)
  allParts.push(endRecord)

  return new Blob(allParts, { type: 'application/zip' })
}

// CRC-32 lookup table
const crcTable: number[] = []
for (let n = 0; n < 256; n++) {
  let c = n
  for (let k = 0; k < 8; k++) {
    c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
  }
  crcTable[n] = c
}

function crc32(data: Uint8Array): number {
  let crc = 0xffffffff
  for (let i = 0; i < data.length; i++) {
    crc = crcTable[(crc ^ data[i]) & 0xff] ^ (crc >>> 8)
  }
  return (crc ^ 0xffffffff) >>> 0
}

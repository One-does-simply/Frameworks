# ODS JSON Specification Reference

This document defines the JSON specification format consumed by the ODS React Web framework. Both the React and Flutter frameworks implement the same spec format.

## Top-Level Structure

```json
{
  "appName": "My App",
  "startPage": "homePage",
  "auth": { ... },
  "menu": [ ... ],
  "pages": { ... },
  "dataSources": { ... },
  "branding": { ... },
  "settings": { ... },
  "help": { ... },
  "tour": [ ... ]
}
```

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `appName` | string | Display name of the application |
| `startPage` | string or object | Default landing page ID, or role-based map |
| `pages` | object | Map of page IDs to page definitions |

### Optional Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `auth` | object | `{ multiUser: false }` | Authentication configuration |
| `menu` | array | `[]` | Navigation menu items |
| `dataSources` | object | `{}` | Data source definitions |
| `branding` | object | defaults | Theme and visual customization |
| `settings` | object | `{}` | User-configurable app settings |
| `help` | object | null | In-app help content |
| `tour` | array | `[]` | Guided tour steps |

## startPage

Can be a simple string or a role-based object:

```json
// Simple
"startPage": "homePage"

// Role-based
"startPage": {
  "default": "userDashboard",
  "admin": "adminDashboard",
  "manager": "managerView"
}
```

The `default` key is used as fallback when no role matches.

## Pages

Each page has a title and an array of components:

```json
"pages": {
  "homePage": {
    "title": "Home",
    "content": [
      { "component": "text", "content": "Welcome!" },
      { "component": "list", "dataSource": "items", ... }
    ],
    "roles": ["admin"]
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `title` | string | yes | Page heading |
| `content` | array | yes | Array of component objects |
| `roles` | string[] | no | Restrict page to specific roles |

## Components

All components share these base fields:

| Field | Type | Description |
|-------|------|-------------|
| `component` | string | Component type identifier |
| `styleHint` | object | Optional styling hints |
| `visibleWhen` | object | Conditional visibility rule |
| `visible` | string | Expression-based visibility |
| `roles` | string[] | Role-based visibility |

### text

Static or dynamic text content.

```json
{
  "component": "text",
  "content": "Total tasks: {COUNT(tasks)}",
  "format": "markdown"
}
```

| Field | Default | Values |
|-------|---------|--------|
| `content` | — | Literal text. Supports aggregate references like `{COUNT(ds)}`, `{SUM(ds, field)}` |
| `format` | `"plain"` | `"plain"`, `"markdown"` |

### form

Data entry form with typed fields.

```json
{
  "component": "form",
  "id": "addTaskForm",
  "fields": [
    { "name": "title", "label": "Title", "type": "text", "required": true },
    { "name": "priority", "label": "Priority", "type": "select", "options": ["High", "Medium", "Low"] },
    { "name": "dueDate", "label": "Due", "type": "date", "default": "+7d" }
  ],
  "recordSource": "tasksReader"
}
```

| Field | Description |
|-------|-------------|
| `id` | Unique form identifier (referenced by actions) |
| `fields` | Array of field definitions |
| `recordSource` | Optional: pre-fill from a data source with record cursor |

#### Field Types

| Type | Description | Extra Properties |
|------|-------------|-----------------|
| `text` | Single-line text | `placeholder`, `minLength`, `maxLength` |
| `multiline` | Multi-line textarea | `placeholder` |
| `number` | Numeric input | `min`, `max` |
| `date` | Date picker | `default`: `"+7d"`, `"NOW"` |
| `select` | Dropdown | `options`: string array |
| `checkbox` | Toggle | — |
| `computed` | Read-only calculated | `formula`: e.g., `"{qty} * {price}"` |
| `hidden` | Hidden field | `default` |
| `user` | User picker (multi-user) | — |

#### Field Properties

| Property | Type | Description |
|----------|------|-------------|
| `name` | string | Field identifier |
| `label` | string | Display label |
| `type` | string | Field type (see above) |
| `required` | boolean | Validation: must have value |
| `default` | string | Default value |
| `placeholder` | string | Input placeholder text |
| `options` | string[] | Options for select fields |
| `formula` | string | Expression for computed fields |
| `visibleWhen` | object | Conditional visibility |
| `validation` | object | Custom validation rules |

### list

Tabular data display with sorting, filtering, and actions.

```json
{
  "component": "list",
  "dataSource": "tasksReader",
  "searchable": true,
  "columns": [
    { "header": "Task", "field": "title", "sortable": true },
    { "header": "Status", "field": "status", "filterable": true, "colorMap": { "Done": "green" } }
  ],
  "rowActions": [
    { "label": "Delete", "action": "delete", "dataSource": "tasksStore", "matchField": "_id", "confirm": "Delete this task?" }
  ],
  "defaultSort": { "field": "dueDate", "direction": "desc" }
}
```

| Field | Default | Description |
|-------|---------|-------------|
| `dataSource` | — | Data source ID to query |
| `columns` | `[]` | Column definitions |
| `rowActions` | `[]` | Per-row action buttons |
| `searchable` | `false` | Show search input |
| `displayAs` | `"table"` | `"table"` or `"cards"` |
| `defaultSort` | none | Default sort field and direction |
| `summary` | `[]` | Footer summary rules (SUM, COUNT, AVG) |
| `onRowTap` | none | Navigate on row click |

### button

Action trigger with chained actions.

```json
{
  "component": "button",
  "label": "Save",
  "onClick": [
    { "action": "submit", "dataSource": "tasksStore", "target": "addTaskForm" },
    { "action": "showMessage", "message": "Saved!" },
    { "action": "navigate", "target": "listPage" }
  ]
}
```

### chart

Data visualization.

```json
{
  "component": "chart",
  "dataSource": "salesReader",
  "chartType": "bar",
  "labelField": "month",
  "valueField": "revenue",
  "aggregate": "sum"
}
```

| Field | Default | Values |
|-------|---------|--------|
| `chartType` | `"bar"` | `"bar"`, `"line"`, `"pie"` |
| `aggregate` | auto | `"count"`, `"sum"`, `"avg"` |

### summary

KPI / metric card.

```json
{
  "component": "summary",
  "label": "Total Tasks",
  "value": "{COUNT(tasksReader)}",
  "icon": "task"
}
```

### detail

Single-record read-only view.

```json
{
  "component": "detail",
  "dataSource": "tasksReader",
  "fields": ["title", "status", "dueDate"],
  "labels": { "dueDate": "Due Date" },
  "fromForm": "editForm"
}
```

### tabs

Tabbed layout container.

```json
{
  "component": "tabs",
  "tabs": [
    { "label": "Overview", "content": [ ... ] },
    { "label": "Details", "content": [ ... ] }
  ]
}
```

### kanban

Board layout with drag-drop between columns.

```json
{
  "component": "kanban",
  "dataSource": "tasksReader",
  "statusField": "status",
  "titleField": "title",
  "cardFields": ["assignee", "priority", "dueDate"],
  "searchable": true,
  "rowActions": [ ... ]
}
```

The `statusField` must reference a `select` field with defined `options` — these become the column headers.

## Actions

Actions are triggered by buttons and row actions. They execute sequentially.

| Action | Description | Key Fields |
|--------|-------------|------------|
| `navigate` | Go to a page | `target`: page ID |
| `submit` | Insert form data | `target`: form ID, `dataSource` |
| `update` | Update existing record | `target`: form ID or row ID, `dataSource`, `matchField` |
| `delete` | Delete a record | `dataSource`, `matchField` |
| `showMessage` | Show toast message | `message` |
| `firstRecord` | Navigate to first record | — |
| `nextRecord` | Navigate to next record | — |
| `previousRecord` | Navigate to previous record | — |
| `lastRecord` | Navigate to last record | — |

### Action Properties

| Property | Type | Description |
|----------|------|-------------|
| `action` | string | Action type |
| `target` | string | Form ID, page ID, or row ID |
| `dataSource` | string | Data source to operate on |
| `matchField` | string | Field to match for update/delete |
| `withData` | object | Direct data for update (no form needed) |
| `confirm` | string | Confirmation prompt before executing |
| `computedFields` | array | Fields to compute at submit time |
| `onEnd` | object | Chained action after completion |
| `preserveFields` | string[] | Fields to keep after form clear |
| `cascade` | object | Cascade rename config |

## Data Sources

```json
"dataSources": {
  "tasksStore": {
    "url": "local://tasks",
    "method": "POST",
    "fields": [ ... ]
  },
  "tasksReader": {
    "url": "local://tasks",
    "method": "GET"
  }
}
```

| Field | Description |
|-------|-------------|
| `url` | `local://tableName` for local storage |
| `method` | `GET` (read), `POST` (insert), `PUT` (update) |
| `fields` | Field definitions (schema for auto-creation) |
| `seedData` | Initial data rows |
| `ownership` | Row-level security config |

### Reserved Fields

The framework automatically manages these fields on every record. Specs should not define fields with these names.

| Field | Type | Description |
|-------|------|-------------|
| `_id` | string | Unique record identifier. Generated automatically on insert. Opaque — specs should never hardcode `_id` values. Always reference dynamically via `matchField`. Format is a 15-character alphanumeric string. |
| `_createdAt` | string | ISO 8601 timestamp set at insert time. |
| `_owner` | string | Owner identifier (set when ownership is enabled). |

### Ownership

```json
"ownership": {
  "enabled": true,
  "ownerField": "_owner",
  "adminOverride": true
}
```

## Auth

```json
"auth": {
  "multiUser": true,
  "selfRegistration": true,
  "defaultRole": "user",
  "multiUserOnly": false
}
```

| Field | Default | Description |
|-------|---------|-------------|
| `multiUser` | `false` | Enable multi-user mode |
| `selfRegistration` | `false` | Allow users to register |
| `defaultRole` | `"user"` | Role assigned to new users |
| `multiUserOnly` | `false` | Disable guest access entirely |

## Menu

```json
"menu": [
  { "label": "Dashboard", "mapsTo": "dashPage" },
  { "label": "Admin Panel", "mapsTo": "adminPage", "roles": ["admin"] }
]
```

## Branding

```json
"branding": {
  "theme": "nord",
  "mode": "dark",
  "logo": "https://example.com/logo.png",
  "favicon": "https://example.com/favicon.ico",
  "headerStyle": "solid",
  "fontFamily": "Inter",
  "overrides": { "primary": "oklch(50% 0.2 260)" }
}
```

| Field | Default | Values |
|-------|---------|--------|
| `theme` | `"indigo"` | Any of 35+ built-in themes |
| `mode` | `"system"` | `"light"`, `"dark"`, `"system"` |
| `headerStyle` | `"light"` | `"light"`, `"solid"`, `"transparent"` |

## Style Hints

Style hints are an open-ended bag of rendering suggestions:

```json
"styleHint": {
  "variant": "heading",
  "emphasis": "primary",
  "align": "center",
  "color": "info",
  "icon": "star",
  "size": "large",
  "density": "compact",
  "elevation": 2
}
```

## Conditional Visibility

### Field-based (show component when a form field matches)

```json
"visibleWhen": {
  "form": "myForm",
  "field": "category",
  "equals": "premium"
}
```

### Data-based (show component based on data source row count)

```json
"visibleWhen": {
  "source": "tasksReader",
  "countEquals": 0
}
```

## Help & Tour

```json
"help": {
  "overview": "Welcome to the app...",
  "pages": {
    "homePage": "This page shows your tasks."
  }
},
"tour": [
  { "title": "Welcome", "content": "Let's take a quick tour.", "page": "homePage" }
]
```

## Settings

User-configurable app settings:

```json
"settings": {
  "currency": {
    "label": "Currency Symbol",
    "type": "select",
    "default": "$",
    "options": ["$", "EUR", "GBP", "JPY"]
  }
}
```

## Formulas & Expressions

Used in computed fields, summary values, and text content.

- **Field interpolation**: `{fieldName}` resolves to the field's current value
- **Math**: `{quantity} * {unitPrice}` — `+`, `-`, `*`, `/`, parentheses, decimals, negatives
- **Aggregates** (use in summary/text content): `{COUNT(dataSource)}`, `{SUM(dataSource, field)}`, `{AVG(dataSource, field)}`, `{MIN(dataSource, field)}`, `{MAX(dataSource, field)}`
- **Magic values**: `NOW` (current date), `+7d` (relative date; also `-3d`, `+1m`, etc.)
- **Ternary**: `{status} == "done" ? "Complete" : "Pending"` — supports operators `==`, `!=`, `>`, `<`, `>=`, `<=`
  - String comparison for `==` / `!=`; numeric for `>`, `<`, `>=`, `<=`
- **Note**: Text component content does NOT support `{field}` interpolation directly — only aggregate references. Use a computed field for field-based display.

import { parseAuth, type OdsAuth } from './ods-auth.ts'
import { parseBranding, type OdsBranding } from './ods-branding.ts'
import { parseAppSetting, type OdsAppSetting } from './ods-app-setting.ts'
import { parseDataSource, type OdsDataSource } from './ods-data-source.ts'
import { parseHelp, parseTourStep, type OdsHelp, type OdsTourStep } from './ods-help.ts'
import { parseMenuItem, type OdsMenuItem } from './ods-menu-item.ts'
import { parsePage, type OdsPage } from './ods-page.ts'

/** The top-level model representing a complete ODS application. */
export interface OdsApp {
  appName: string
  startPage: string
  /** Role-based start pages (e.g. { admin: 'dashPage', manager: 'reportPage' }). */
  startPageByRole: Record<string, string>
  menu: OdsMenuItem[]
  pages: Record<string, OdsPage>
  dataSources: Record<string, OdsDataSource>
  help?: OdsHelp
  tour: OdsTourStep[]
  settings: Record<string, OdsAppSetting>
  auth: OdsAuth
  branding: OdsBranding
}

/** Resolve startPage to a string. Accepts "pageName" or { default: "pageName", admin: "other" }. */
function parseStartPage(raw: unknown): string {
  if (typeof raw === 'string') return raw
  if (raw && typeof raw === 'object' && 'default' in raw) return (raw as Record<string, string>).default
  return ''
}

/** Build the role→page map, excluding the `default` key (stored in startPage). */
function parseStartPageByRole(raw: unknown): Record<string, string> {
  if (typeof raw === 'string') return {}
  if (raw && typeof raw === 'object') {
    return Object.fromEntries(
      Object.entries(raw as Record<string, unknown>)
        .filter(([k, v]) => k !== 'default' && typeof v === 'string')
        .map(([k, v]) => [k, v as string])
    )
  }
  return {}
}

export function parseApp(json: unknown): OdsApp {
  const j = json as Record<string, unknown>
  const pagesRaw = j['pages'] as Record<string, unknown> | undefined
  const dsRaw = j['dataSources'] as Record<string, unknown> | undefined
  const settingsRaw = j['settings'] as Record<string, unknown> | undefined

  return {
    appName: j['appName'] as string,
    startPage: parseStartPage(j['startPage']),
    startPageByRole: parseStartPageByRole(j['startPage']),
    menu: Array.isArray(j['menu'])
      ? (j['menu'] as unknown[]).map(parseMenuItem)
      : [],
    pages: pagesRaw
      ? Object.fromEntries(
          Object.entries(pagesRaw).map(([k, v]) => [k, parsePage(v)])
        )
      : {},
    dataSources: dsRaw
      ? Object.fromEntries(
          Object.entries(dsRaw).map(([k, v]) => [k, parseDataSource(v)])
        )
      : {},
    help: parseHelp(j['help']),
    tour: Array.isArray(j['tour'])
      ? (j['tour'] as unknown[]).map(parseTourStep)
      : [],
    settings: settingsRaw
      ? Object.fromEntries(
          Object.entries(settingsRaw).map(([k, v]) => [k, parseAppSetting(v)])
        )
      : {},
    auth: parseAuth(j['auth']),
    branding: parseBranding(j['branding']),
  }
}

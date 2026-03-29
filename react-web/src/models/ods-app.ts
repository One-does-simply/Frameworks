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
  menu: OdsMenuItem[]
  pages: Record<string, OdsPage>
  dataSources: Record<string, OdsDataSource>
  help?: OdsHelp
  tour: OdsTourStep[]
  settings: Record<string, OdsAppSetting>
  auth: OdsAuth
  branding: OdsBranding
}

export function parseApp(json: unknown): OdsApp {
  const j = json as Record<string, unknown>
  const pagesRaw = j['pages'] as Record<string, unknown> | undefined
  const dsRaw = j['dataSources'] as Record<string, unknown> | undefined
  const settingsRaw = j['settings'] as Record<string, unknown> | undefined

  return {
    appName: j['appName'] as string,
    startPage: j['startPage'] as string,
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

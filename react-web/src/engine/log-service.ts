/**
 * Logging service for ODS React Web.
 *
 * Provides structured, level-filtered logging with localStorage persistence,
 * automatic retention pruning, and export/download for end-user support.
 *
 * ODS Ethos: Novice users need a way to share what went wrong without
 * understanding developer tools. This service captures runtime events and
 * makes them exportable as a plain-text file they can email.
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type LogLevel = 'debug' | 'info' | 'warn' | 'error'

export interface LogEntry {
  timestamp: string   // ISO 8601
  level: LogLevel
  category: string    // e.g. 'DataService', 'AuthService', 'PocketBase'
  message: string
  data?: unknown      // optional structured context
}

export interface LogSettings {
  level: LogLevel       // minimum level to record (default: 'warn')
  retentionDays: number // auto-prune entries older than N days (default: 7)
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const SETTINGS_KEY = 'ods_log_settings'
const LOGS_KEY = 'ods_logs'
const MAX_ENTRIES = 20_000
const FLUSH_DELAY_MS = 1_000

export const LEVEL_ORDER: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
}

const DEFAULT_SETTINGS: LogSettings = {
  level: 'debug',
  retentionDays: 7,
}

// ---------------------------------------------------------------------------
// Settings persistence
// ---------------------------------------------------------------------------

export function getLogSettings(): LogSettings {
  try {
    const raw = localStorage.getItem(SETTINGS_KEY)
    if (raw) return { ...DEFAULT_SETTINGS, ...JSON.parse(raw) }
  } catch { /* use defaults */ }
  return { ...DEFAULT_SETTINGS }
}

export function setLogSettings(settings: LogSettings): void {
  localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings))
}

// ---------------------------------------------------------------------------
// In-memory buffer + debounced flush
// ---------------------------------------------------------------------------

let buffer: LogEntry[] = []
let flushTimer: ReturnType<typeof setTimeout> | null = null

function scheduleFlush() {
  if (flushTimer) return
  flushTimer = setTimeout(() => {
    flushTimer = null
    flushToStorage()
  }, FLUSH_DELAY_MS)
}

function flushToStorage() {
  if (buffer.length === 0) return
  const stored = readStoredLogs()
  const combined = [...stored, ...buffer]
  buffer = []
  const pruned = pruneEntries(combined)
  try {
    localStorage.setItem(LOGS_KEY, JSON.stringify(pruned))
  } catch {
    // localStorage full — drop oldest half and retry
    const half = pruned.slice(Math.floor(pruned.length / 2))
    try {
      localStorage.setItem(LOGS_KEY, JSON.stringify(half))
    } catch { /* give up silently */ }
  }
}

function readStoredLogs(): LogEntry[] {
  try {
    const raw = localStorage.getItem(LOGS_KEY)
    if (raw) return JSON.parse(raw) as LogEntry[]
  } catch { /* corrupted — start fresh */ }
  return []
}

function pruneEntries(entries: LogEntry[]): LogEntry[] {
  const { retentionDays } = getLogSettings()
  const cutoff = Date.now() - retentionDays * 86_400_000
  let result = entries.filter(e => Date.parse(e.timestamp) >= cutoff)
  if (result.length > MAX_ENTRIES) {
    result = result.slice(result.length - MAX_ENTRIES)
  }
  return result
}

// ---------------------------------------------------------------------------
// Core logging
// ---------------------------------------------------------------------------

function shouldLog(level: LogLevel): boolean {
  const settings = getLogSettings()
  return LEVEL_ORDER[level] >= LEVEL_ORDER[settings.level]
}

export function log(level: LogLevel, category: string, message: string, data?: unknown): void {
  // Always forward to console regardless of level setting
  const consoleFn = level === 'debug' ? console.debug
    : level === 'info' ? console.info
    : level === 'warn' ? console.warn
    : console.error
  if (data !== undefined) {
    consoleFn(`[ODS] [${category}] ${message}`, data)
  } else {
    consoleFn(`[ODS] [${category}] ${message}`)
  }

  if (!shouldLog(level)) return

  const entry: LogEntry = {
    timestamp: new Date().toISOString(),
    level,
    category,
    message,
    ...(data !== undefined && { data: serializeData(data) }),
  }
  buffer.push(entry)
  scheduleFlush()
}

/** Safely serialize data for storage (handles Error objects, circular refs). */
function serializeData(data: unknown): unknown {
  if (data instanceof Error) {
    return { name: data.name, message: data.message, stack: data.stack }
  }
  try {
    // Round-trip through JSON to strip functions, symbols, etc.
    return JSON.parse(JSON.stringify(data))
  } catch {
    return String(data)
  }
}

// ---------------------------------------------------------------------------
// Convenience functions
// ---------------------------------------------------------------------------

export function logDebug(category: string, message: string, data?: unknown): void {
  log('debug', category, message, data)
}

export function logInfo(category: string, message: string, data?: unknown): void {
  log('info', category, message, data)
}

export function logWarn(category: string, message: string, data?: unknown): void {
  log('warn', category, message, data)
}

export function logError(category: string, message: string, data?: unknown): void {
  log('error', category, message, data)
}

/** @deprecated Use logDebug instead */
export const debug = logDebug
/** @deprecated Use logInfo instead */
export const info = logInfo
/** @deprecated Use logWarn instead */
export const warn = logWarn
/** @deprecated Use logError instead */
export const error = logError

// ---------------------------------------------------------------------------
// Reading & export
// ---------------------------------------------------------------------------

/** Get all stored logs plus any unflushed buffer entries. */
export function getLogs(): readonly LogEntry[] {
  flushToStorage() // ensure buffer is written
  return readStoredLogs()
}

/** Get logs filtered to at or above the given level. */
export function getLogsByLevel(minLevel: LogLevel): LogEntry[] {
  const min = LEVEL_ORDER[minLevel]
  return getLogs().filter(e => LEVEL_ORDER[e.level] >= min)
}

/** Get total count of stored log entries. */
export function getLogCount(): number {
  return readStoredLogs().length + buffer.length
}

/** Clear all stored logs and the buffer. */
export function clearLogs(): void {
  buffer = []
  localStorage.removeItem(LOGS_KEY)
}

/** Format all logs as plain text suitable for email/support. */
export function exportLogsAsText(): string {
  const logs = getLogs()
  const header = [
    '=== ODS React Web — Log Export ===',
    `Exported: ${new Date().toISOString()}`,
    `User Agent: ${navigator.userAgent}`,
    `Log Level: ${getLogSettings().level}`,
    `Entries: ${logs.length}`,
    '===================================',
    '',
  ].join('\n')

  const lines = logs.map(e => {
    const level = e.level.toUpperCase().padEnd(5)
    const cat = e.category.padEnd(16)
    let line = `[${e.timestamp}] [${level}] [${cat}] ${e.message}`
    if (e.data !== undefined) {
      try {
        const dataStr = JSON.stringify(e.data, null, 2)
        if (dataStr.length < 500) {
          line += `\n    ${dataStr}`
        } else {
          line += `\n    ${dataStr.substring(0, 500)}...`
        }
      } catch { /* skip */ }
    }
    return line
  })

  return header + lines.join('\n')
}

/** Trigger a .txt file download of the log export. */
export function downloadLogs(): void {
  const text = exportLogsAsText()
  const date = new Date().toISOString().slice(0, 10)
  const blob = new Blob([text], { type: 'text/plain' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `ods_logs_${date}.txt`
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
}

// ---------------------------------------------------------------------------
// Startup
// ---------------------------------------------------------------------------

/** Run on app startup to prune expired logs. */
export function initLogService(): void {
  const stored = readStoredLogs()
  const pruned = pruneEntries(stored)
  if (pruned.length !== stored.length) {
    localStorage.setItem(LOGS_KEY, JSON.stringify(pruned))
  }
  logInfo('LogService', `Initialized — ${pruned.length} stored entries, level=${getLogSettings().level}`)
}

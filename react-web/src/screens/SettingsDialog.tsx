import { useState, useEffect } from 'react'
import { useAppStore } from '@/engine/app-store.ts'
import {
  getThemeMode,
  setThemeMode,
  type ThemeMode,
} from '@/engine/theme-store.ts'
import {
  getBackupSettings,
  setBackupSettings,
  type BackupSettings,
} from '@/engine/backup-service.ts'
import { applyBranding, loadTheme } from '@/engine/branding-service.ts'
import type { OdsBranding } from '@/models/ods-branding.ts'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
// Using native checkbox input styled with Tailwind — the base-ui Checkbox
// has rendering issues in some dialog contexts.
import { Separator } from '@/components/ui/separator'
import { ChevronDown, ChevronRight } from 'lucide-react'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'

// ---------------------------------------------------------------------------
// SettingsDialog — framework settings + app-level settings from the spec
// ---------------------------------------------------------------------------

interface SettingsDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function SettingsDialog({ open, onOpenChange }: SettingsDialogProps) {
  const app = useAppStore((s) => s.app)!
  const debugMode = useAppStore((s) => s.debugMode)
  const toggleDebugMode = useAppStore((s) => s.toggleDebugMode)
  const appSettings = useAppStore((s) => s.appSettings)
  const dataService = useAppStore((s) => s.dataService)

  // Branding overrides (persisted per-app in localStorage)
  const brandingKey = `ods_branding_${app.appName.replace(/[^\w]/g, '_').toLowerCase()}`
  const savedOverrides = (() => {
    try { return JSON.parse(localStorage.getItem(brandingKey) ?? '{}') } catch { return {} }
  })() as Partial<OdsBranding>
  const [selectedTheme, setSelectedTheme] = useState(savedOverrides.theme ?? app.branding.theme)
  const [customizeOpen, setCustomizeOpen] = useState(false)
  const [themeDefaults, setThemeDefaults] = useState<Record<string, string>>({})
  const [tokenOverrides, setTokenOverrides] = useState<Record<string, string>>(
    savedOverrides.overrides ?? app.branding.overrides ?? {}
  )

  // Load theme default colors for the color pickers
  useEffect(() => {
    if (!customizeOpen) return
    loadTheme(selectedTheme).then((data) => {
      if (!data) return
      const mode = document.documentElement.classList.contains('dark') ? 'dark' : 'light'
      const variant = data[mode] as Record<string, unknown> | undefined
      const colors = variant?.['colors'] as Record<string, string> | undefined
      if (colors) setThemeDefaults(colors)
    }).catch(() => {})
  }, [customizeOpen, selectedTheme])

  function applyThemeOverride(themeName: string) {
    setSelectedTheme(themeName)
    const saved = { theme: themeName, ...(Object.keys(tokenOverrides).length > 0 ? { overrides: tokenOverrides } : {}) }
    localStorage.setItem(brandingKey, JSON.stringify(saved))
    applyBranding({ ...app.branding, theme: themeName, overrides: tokenOverrides }).catch(() => {})
  }

  function applyTokenOverride(token: string, value: string) {
    const updated = { ...tokenOverrides }
    if (value) {
      updated[token] = value
    } else {
      delete updated[token]
    }
    setTokenOverrides(updated)
    const saved = { theme: selectedTheme, ...(Object.keys(updated).length > 0 ? { overrides: updated } : {}) }
    localStorage.setItem(brandingKey, JSON.stringify(saved))
    applyBranding({ ...app.branding, theme: selectedTheme, overrides: updated }).catch(() => {})
  }

  function resetBrandingOverride() {
    localStorage.removeItem(brandingKey)
    setSelectedTheme(app.branding.theme)
    setTokenOverrides({})
    setCustomizeOpen(false)
    applyBranding(app.branding).catch(() => {})
  }

  // Theme mode
  const [theme, setTheme] = useState<ThemeMode>(getThemeMode)

  // Backup settings
  const [backupSettings, setBackupState] = useState<BackupSettings>(getBackupSettings)

  function handleThemeChange(mode: ThemeMode) {
    setTheme(mode)
    setThemeMode(mode)
  }

  // Local state for editing text/number settings (tap-to-save pattern)
  const [editingKey, setEditingKey] = useState<string | null>(null)
  const [editingValue, setEditingValue] = useState('')

  const hasAppSettings = app.settings && Object.keys(app.settings).length > 0

  async function handleSetSetting(key: string, value: string) {
    if (!dataService) return
    await dataService.setAppSetting(key, value)
    useAppStore.setState({
      appSettings: { ...appSettings, [key]: value },
    })
  }

  function startEditing(key: string, currentValue: string) {
    setEditingKey(key)
    setEditingValue(currentValue)
  }

  async function commitEdit() {
    if (editingKey) {
      await handleSetSetting(editingKey, editingValue)
      setEditingKey(null)
      setEditingValue('')
    }
  }

  function cancelEdit() {
    setEditingKey(null)
    setEditingValue('')
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Settings</DialogTitle>
          <DialogDescription>
            Configure your app and framework preferences.
          </DialogDescription>
        </DialogHeader>

        <div className="max-h-[60vh] space-y-4 overflow-y-auto">
          {/* ---- App Settings (from spec) ---- */}
          {hasAppSettings && (
            <>
              <div>
                <span className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                  App Settings
                </span>
              </div>

              {Object.entries(app.settings).map(([key, setting]) => {
                const currentValue = appSettings[key] ?? setting.defaultValue

                if (setting.type === 'checkbox') {
                  return (
                    <div key={key} className="flex items-center justify-between">
                      <Label htmlFor={`setting-${key}`}>{setting.label}</Label>
                      <input
                        type="checkbox"
                        id={`setting-${key}`}
                        checked={currentValue === 'true'}
                        onChange={(e) =>
                          handleSetSetting(key, e.target.checked ? 'true' : 'false')
                        }
                        className="h-4 w-4 rounded border-input accent-primary"
                      />
                    </div>
                  )
                }

                if (setting.type === 'select' && setting.options) {
                  return (
                    <div key={key} className="flex items-center justify-between gap-4">
                      <Label>{setting.label}</Label>
                      <Select
                        value={setting.options.includes(currentValue) ? currentValue : setting.defaultValue}
                        onValueChange={(v) => handleSetSetting(key, v ?? '')}
                      >
                        <SelectTrigger>
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          {setting.options.map((opt) => (
                            <SelectItem key={opt} value={opt}>
                              {opt}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                  )
                }

                // text / number — inline display with click-to-edit
                if (editingKey === key) {
                  return (
                    <div key={key} className="space-y-1">
                      <Label>{setting.label}</Label>
                      <div className="flex gap-2">
                        <Input
                          type={setting.type === 'number' ? 'number' : 'text'}
                          value={editingValue}
                          onChange={(e) => setEditingValue(e.target.value)}
                          onKeyDown={(e) => {
                            if (e.key === 'Enter') commitEdit()
                            if (e.key === 'Escape') cancelEdit()
                          }}
                          autoFocus
                          className="flex-1"
                        />
                        <Button size="sm" onClick={commitEdit}>Save</Button>
                        <Button size="sm" variant="outline" onClick={cancelEdit}>Cancel</Button>
                      </div>
                    </div>
                  )
                }

                return (
                  <button
                    key={key}
                    onClick={() => startEditing(key, currentValue)}
                    className="flex w-full items-center justify-between rounded-lg px-2 py-2 text-left text-sm hover:bg-muted"
                  >
                    <span className="font-medium">{setting.label}</span>
                    <span className="text-muted-foreground">
                      {currentValue || '(not set)'}
                    </span>
                  </button>
                )
              })}

              <Separator />
            </>
          )}

          {/* ---- Branding ---- */}
          <div>
            <span className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              Branding
            </span>
          </div>

          {/* Theme selector */}
          <div className="flex items-center justify-between gap-4">
            <Label>Theme</Label>
            <Select value={selectedTheme} onValueChange={applyThemeOverride}>
              <SelectTrigger className="w-40">
                <SelectValue />
              </SelectTrigger>
              <SelectContent className="max-h-60">
                {['light','dark','cupcake','bumblebee','emerald','corporate','synthwave','retro','cyberpunk','valentine','halloween','garden','forest','aqua','lofi','pastel','fantasy','wireframe','black','luxury','dracula','cmyk','autumn','business','acid','lemonade','night','coffee','winter','dim','nord','sunset','caramellatte','abyss','silk'].map((t) => (
                  <SelectItem key={t} value={t}>
                    {t.charAt(0).toUpperCase() + t.slice(1)}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* Customize theme */}
          <button
            onClick={() => setCustomizeOpen(!customizeOpen)}
            className="flex w-full items-center gap-1.5 text-xs font-medium text-muted-foreground hover:text-foreground transition-colors"
          >
            {customizeOpen ? <ChevronDown className="size-3.5" /> : <ChevronRight className="size-3.5" />}
            Customize Theme
          </button>

          {customizeOpen && (
            <div className="space-y-3 rounded-lg border bg-muted/30 p-3">
              <p className="text-[11px] text-muted-foreground">
                Override individual design tokens on top of the selected theme. Leave blank to use the theme default.
              </p>

              {CUSTOMIZABLE_TOKENS.map(({ token, label, description, example, type }) => (
                <div key={token} className="space-y-1">
                  <div className="flex items-center gap-2">
                    {type === 'color' ? (
                      <input
                        type="color"
                        title={`Pick ${label} color`}
                        value={oklchToHexApprox(tokenOverrides[token] || themeDefaults[token] || '')}
                        onChange={(e) => applyTokenOverride(token, hexToOklchApprox(e.target.value))}
                        className="h-6 w-8 cursor-pointer rounded border border-input bg-transparent"
                      />
                    ) : (
                      <div className="w-8" />
                    )}
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="text-xs font-medium">{label}</span>
                        {tokenOverrides[token] && (
                          <button
                            onClick={() => applyTokenOverride(token, '')}
                            className="text-[10px] text-muted-foreground hover:text-foreground"
                          >
                            reset
                          </button>
                        )}
                      </div>
                      <div className="text-[10px] text-muted-foreground">{description}</div>
                    </div>
                  </div>
                  {type === 'size' && (
                    <Input
                      value={tokenOverrides[token] ?? ''}
                      onChange={(e) => applyTokenOverride(token, e.target.value)}
                      placeholder={example}
                      className="h-7 text-xs font-mono"
                    />
                  )}
                </div>
              ))}
            </div>
          )}

          {/* Reset branding */}
          {(savedOverrides.theme || Object.keys(tokenOverrides).length > 0) && (
            <Button variant="ghost" size="sm" className="text-xs text-muted-foreground" onClick={resetBrandingOverride}>
              Reset to spec defaults
            </Button>
          )}

          <Separator />

          {/* ---- Framework Settings ---- */}
          <div>
            <span className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              Framework
            </span>
          </div>

          {/* Light/Dark mode */}
          <div className="flex items-center justify-between gap-4">
            <Label>Mode</Label>
            <div className="flex gap-1 rounded-lg border p-0.5">
              {(['light', 'system', 'dark'] as ThemeMode[]).map((mode) => (
                <button
                  key={mode}
                  onClick={() => handleThemeChange(mode)}
                  className={`rounded-md px-3 py-1 text-xs font-medium transition-colors ${
                    theme === mode
                      ? 'bg-primary text-primary-foreground'
                      : 'text-muted-foreground hover:text-foreground'
                  }`}
                >
                  {mode.charAt(0).toUpperCase() + mode.slice(1)}
                </button>
              ))}
            </div>
          </div>

          {/* Debug mode */}
          <div className="flex items-center justify-between">
            <Label htmlFor="debug-mode">Debug Panel</Label>
            <input
              type="checkbox"
              id="debug-mode"
              checked={debugMode}
              onChange={() => toggleDebugMode()}
              className="h-4 w-4 rounded border-input accent-primary"
            />
          </div>

          <Separator />

          {/* ---- Backup Settings ---- */}
          <div>
            <span className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              Backup
            </span>
          </div>

          {/* Auto-backup toggle */}
          <div className="flex items-center justify-between">
            <Label htmlFor="auto-backup">Auto-Backup</Label>
            <input
              type="checkbox"
              id="auto-backup"
              checked={backupSettings.autoBackup}
              onChange={(e) => {
                const updated = { ...backupSettings, autoBackup: e.target.checked }
                setBackupState(updated)
                setBackupSettings(updated)
              }}
              className="h-4 w-4 rounded border-input accent-primary"
            />
          </div>

          {/* Retention count */}
          {backupSettings.autoBackup && (
            <div className="flex items-center justify-between gap-4">
              <Label>Keep snapshots</Label>
              <Select
                value={String(backupSettings.retention)}
                onValueChange={(v) => {
                  const updated = { ...backupSettings, retention: Number(v) }
                  setBackupState(updated)
                  setBackupSettings(updated)
                }}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {[1, 3, 5, 10, 20].map((n) => (
                    <SelectItem key={n} value={String(n)}>
                      {n}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}
        </div>

        <DialogFooter showCloseButton />
      </DialogContent>
    </Dialog>
  )
}

// ---------------------------------------------------------------------------
// Customizable theme tokens — descriptive list for the customize panel
// ---------------------------------------------------------------------------

const CUSTOMIZABLE_TOKENS: {
  token: string
  label: string
  description: string
  example: string
  type: 'color' | 'size'
}[] = [
  { token: 'primary', label: 'Primary', description: 'Main action color — buttons, links, active states.', example: 'oklch(58% .158 242)', type: 'color' },
  { token: 'secondary', label: 'Secondary', description: 'Supporting color — secondary buttons, tags, accents.', example: 'oklch(65% .241 354)', type: 'color' },
  { token: 'accent', label: 'Accent', description: 'Highlight color — badges, notifications, emphasis.', example: 'oklch(77% .152 182)', type: 'color' },
  { token: 'neutral', label: 'Neutral', description: 'Muted surfaces — sidebar backgrounds, disabled states.', example: 'oklch(14% .005 286)', type: 'color' },
  { token: 'base100', label: 'Background', description: 'Main page background color.', example: 'oklch(100% 0 0)', type: 'color' },
  { token: 'base200', label: 'Surface', description: 'Slightly darker — cards, popovers, elevated areas.', example: 'oklch(98% 0 0)', type: 'color' },
  { token: 'base300', label: 'Border', description: 'Borders, dividers, and input outlines.', example: 'oklch(95% 0 0)', type: 'color' },
  { token: 'baseContent', label: 'Text', description: 'Default text color on backgrounds.', example: 'oklch(21% .006 286)', type: 'color' },
  { token: 'error', label: 'Error', description: 'Danger/error states — delete buttons, validation errors.', example: 'oklch(71% .194 13)', type: 'color' },
  { token: 'success', label: 'Success', description: 'Success states — confirmations, positive indicators.', example: 'oklch(76% .177 163)', type: 'color' },
  { token: 'warning', label: 'Warning', description: 'Warning states — caution indicators, alerts.', example: 'oklch(82% .189 84)', type: 'color' },
  { token: 'info', label: 'Info', description: 'Informational states — help text, tips.', example: 'oklch(74% .16 233)', type: 'color' },
  { token: 'radiusBox', label: 'Corner Radius', description: 'Border radius for cards, modals, and containers. Use CSS units.', example: '.5rem', type: 'size' },
  { token: 'radiusField', label: 'Input Radius', description: 'Border radius for inputs, selects, and form controls.', example: '.25rem', type: 'size' },
]

// ---------------------------------------------------------------------------
// Approximate color conversion helpers (for the color picker)
// ---------------------------------------------------------------------------

function hexToOklchApprox(hex: string): string {
  const r = parseInt(hex.slice(1, 3), 16) / 255
  const g = parseInt(hex.slice(3, 5), 16) / 255
  const b = parseInt(hex.slice(5, 7), 16) / 255
  const toLinear = (c: number) => c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
  const lr = toLinear(r), lg = toLinear(g), lb = toLinear(b)
  const l_ = Math.cbrt(0.4122 * lr + 0.5363 * lg + 0.0514 * lb)
  const m_ = Math.cbrt(0.2119 * lr + 0.6807 * lg + 0.1074 * lb)
  const s_ = Math.cbrt(0.0883 * lr + 0.2817 * lg + 0.6300 * lb)
  const L = 0.2105 * l_ + 0.7936 * m_ - 0.0041 * s_
  const a = 1.9780 * l_ - 2.4286 * m_ + 0.4506 * s_
  const bOk = 0.0259 * l_ + 0.7828 * m_ - 0.8087 * s_
  const C = Math.sqrt(a * a + bOk * bOk)
  let H = (Math.atan2(bOk, a) * 180) / Math.PI
  if (H < 0) H += 360
  return `oklch(${(L * 100).toFixed(1)}% ${C.toFixed(3)} ${H.toFixed(1)})`
}

function oklchToHexApprox(oklch: string): string {
  const m = /oklch\(([\d.]+)%?\s+([\d.]+)\s+([\d.]+)\)/.exec(oklch)
  if (!m) return '#888888'
  let L = parseFloat(m[1]); if (L > 1) L /= 100
  const C = parseFloat(m[2])
  const H = parseFloat(m[3]) * Math.PI / 180
  const a = C * Math.cos(H), b = C * Math.sin(H)
  const l_ = L + 0.3963 * a + 0.2158 * b
  const m_ = L - 0.1056 * a - 0.0639 * b
  const s_ = L - 0.0895 * a - 1.2915 * b
  const l = l_ ** 3, ml = m_ ** 3, s = s_ ** 3
  const r = 4.0767 * l - 3.3077 * ml + 0.2310 * s
  const g = -1.2684 * l + 2.6098 * ml - 0.3413 * s
  const bl = -0.0042 * l - 0.7034 * ml + 1.7076 * s
  const toSrgb = (c: number) => {
    const clamped = Math.max(0, Math.min(1, c))
    return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * clamped ** (1 / 2.4) - 0.055
  }
  const toHex = (c: number) => Math.round(toSrgb(c) * 255).toString(16).padStart(2, '0')
  return `#${toHex(r)}${toHex(g)}${toHex(bl)}`
}

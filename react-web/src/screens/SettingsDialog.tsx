import { useState } from 'react'
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
import { applyBranding } from '@/engine/branding-service.ts'
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

  function applyThemeOverride(themeName: string) {
    setSelectedTheme(themeName)
    const overrides = { theme: themeName }
    localStorage.setItem(brandingKey, JSON.stringify(overrides))
    applyBranding({ ...app.branding, ...overrides }).catch(() => {})
  }

  function resetBrandingOverride() {
    localStorage.removeItem(brandingKey)
    setSelectedTheme(app.branding.theme)
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

          {/* Reset branding */}
          {savedOverrides.theme && (
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

import { useState } from 'react'
import { useAppStore } from '@/engine/app-store.ts'
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
import { Checkbox } from '@/components/ui/checkbox'
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
                      <Checkbox
                        id={`setting-${key}`}
                        checked={currentValue === 'true'}
                        onCheckedChange={(checked: boolean) =>
                          handleSetSetting(key, checked ? 'true' : 'false')
                        }
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

          {/* ---- Framework Settings ---- */}
          <div>
            <span className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              Framework
            </span>
          </div>

          {/* Debug mode */}
          <div className="flex items-center justify-between">
            <Label htmlFor="debug-mode">Debug Panel</Label>
            <Checkbox
              id="debug-mode"
              checked={debugMode}
              onCheckedChange={() => toggleDebugMode()}
            />
          </div>
        </div>

        <DialogFooter showCloseButton />
      </DialogContent>
    </Dialog>
  )
}

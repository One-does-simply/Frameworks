import { useState, useEffect } from 'react'
import {
  fetchCatalog,
  fetchExampleSpec,
  type CatalogEntry,
} from '@/engine/example-catalog.ts'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { toast } from 'sonner'
import { logWarn } from '@/engine/log-service.ts'
import { Loader2, Check, Rocket, ArrowRight } from 'lucide-react'

// ---------------------------------------------------------------------------
// OnboardingScreen — shown on first visit when no apps exist
// ---------------------------------------------------------------------------

const ONBOARDING_KEY = 'ods_onboarding_complete'

/** Check if onboarding has been completed. */
export function isOnboardingComplete(): boolean {
  return localStorage.getItem(ONBOARDING_KEY) === 'true'
}

/** Mark onboarding as complete. */
export function completeOnboarding(): void {
  localStorage.setItem(ONBOARDING_KEY, 'true')
}

interface OnboardingScreenProps {
  onComplete: () => void
  onInstall: (name: string, specJson: string, description: string) => Promise<void>
}

export function OnboardingScreen({ onComplete, onInstall }: OnboardingScreenProps) {
  const [step, setStep] = useState(0)
  const [catalog, setCatalog] = useState<CatalogEntry[] | null>(null)
  const [loading, setLoading] = useState(true)
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [installing, setInstalling] = useState(false)

  useEffect(() => {
    fetchCatalog().then((entries) => {
      setCatalog(entries)
      // Pre-select all by default
      if (entries) {
        setSelected(new Set(entries.map((e) => e.id)))
      }
      setLoading(false)
    })
  }, [])

  function toggleEntry(id: string) {
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  async function handleInstallAndContinue() {
    if (!catalog || selected.size === 0) {
      handleSkip()
      return
    }

    setInstalling(true)
    const toInstall = catalog.filter((e) => selected.has(e.id))
    let installed = 0

    for (const entry of toInstall) {
      const specJson = await fetchExampleSpec(entry.file)
      if (specJson) {
        try {
          await onInstall(entry.name, specJson, entry.description)
          installed++
        } catch (err) {
          logWarn('Onboarding', 'Failed to install example', err)
        }
      }
    }

    setInstalling(false)
    if (installed > 0) {
      toast.success(`Installed ${installed} example app${installed !== 1 ? 's' : ''}`)
    }
    completeOnboarding()
    onComplete()
  }

  function handleSkip() {
    completeOnboarding()
    onComplete()
  }

  // -------------------------------------------------------------------------
  // Step 0: Welcome
  // -------------------------------------------------------------------------

  if (step === 0) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background p-6">
        <Card className="w-full max-w-md text-center">
          <CardContent className="space-y-6 py-10">
            <Rocket className="mx-auto size-12 text-primary" />
            <h1 className="text-2xl font-bold">Welcome to ODS</h1>
            <p className="text-muted-foreground">
              One Does Simply lets you build apps from JSON specifications.
              Let&apos;s get started by installing some example apps.
            </p>
            <div className="flex justify-center gap-3">
              <Button variant="outline" onClick={handleSkip}>
                Skip
              </Button>
              <Button onClick={() => setStep(1)}>
                <ArrowRight className="mr-2 size-4" />
                Choose Examples
              </Button>
            </div>
          </CardContent>
        </Card>
      </div>
    )
  }

  // -------------------------------------------------------------------------
  // Step 1: Select examples
  // -------------------------------------------------------------------------

  return (
    <div className="flex min-h-screen items-center justify-center bg-background p-6">
      <Card className="w-full max-w-lg">
        <CardContent className="space-y-4 py-6">
          <h2 className="text-xl font-bold">Select Example Apps</h2>
          <p className="text-sm text-muted-foreground">
            Pick the examples you'd like to explore. You can always add more later.
          </p>

          {loading ? (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="size-5 animate-spin text-muted-foreground" />
              <span className="ml-2 text-sm text-muted-foreground">
                Loading catalog...
              </span>
            </div>
          ) : !catalog ? (
            <div className="space-y-4 py-4 text-center">
              <p className="text-sm text-muted-foreground">
                Could not load the example catalog. You can add apps manually later.
              </p>
              <Button onClick={handleSkip}>Continue</Button>
            </div>
          ) : (
            <>
              <div className="flex gap-2 text-xs">
                <button
                  onClick={() => setSelected(new Set(catalog.map((e) => e.id)))}
                  className="text-primary hover:underline"
                >
                  Select all
                </button>
                <span className="text-muted-foreground">|</span>
                <button
                  onClick={() => setSelected(new Set())}
                  className="text-primary hover:underline"
                >
                  Select none
                </button>
              </div>

              <div className="max-h-[50vh] space-y-1 overflow-y-auto">
                {catalog.map((entry) => (
                  <label
                    key={entry.id}
                    className="flex cursor-pointer items-start gap-3 rounded-lg px-3 py-2 hover:bg-muted"
                  >
                    <input
                      type="checkbox"
                      checked={selected.has(entry.id)}
                      onChange={() => toggleEntry(entry.id)}
                      className="mt-1 h-4 w-4 rounded border-input accent-primary"
                    />
                    <div className="min-w-0">
                      <div className="text-sm font-medium">{entry.name}</div>
                      <div className="text-xs text-muted-foreground line-clamp-2">
                        {entry.description}
                      </div>
                    </div>
                  </label>
                ))}
              </div>

              <div className="flex justify-end gap-3 pt-2">
                <Button variant="outline" onClick={handleSkip}>
                  Skip
                </Button>
                <Button
                  onClick={handleInstallAndContinue}
                  disabled={installing}
                >
                  {installing ? (
                    <Loader2 className="mr-2 size-4 animate-spin" />
                  ) : (
                    <Check className="mr-2 size-4" />
                  )}
                  Install {selected.size > 0 ? `(${selected.size})` : ''} & Continue
                </Button>
              </div>
            </>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

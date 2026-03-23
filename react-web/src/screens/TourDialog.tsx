import { useCallback, useEffect, useState } from 'react'
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
import { Separator } from '@/components/ui/separator'

// ---------------------------------------------------------------------------
// TourDialog — step-through guided tour, shown on first app launch
// ---------------------------------------------------------------------------
//
// ODS Spec: The `tour` array defines an ordered list of steps, each with a
// `title`, `content`, and optional `page` reference. The framework presents
// them sequentially and navigates to the referenced page when a step has one.
//
// ODS Ethos: Every app should be self-explanatory. The tour walks new users
// through the experience — no external docs needed. It runs automatically
// on first launch and can be replayed from settings.
// ---------------------------------------------------------------------------

const TOUR_SEEN_PREFIX = 'ods_tour_seen_'

function getTourSeenKey(appName: string): string {
  return `${TOUR_SEEN_PREFIX}${appName.replace(/[^\w]/g, '_').toLowerCase()}`
}

function hasTourBeenSeen(appName: string): boolean {
  try {
    return localStorage.getItem(getTourSeenKey(appName)) === 'true'
  } catch {
    return false
  }
}

function markTourSeen(appName: string): void {
  try {
    localStorage.setItem(getTourSeenKey(appName), 'true')
  } catch {
    // localStorage may be unavailable; silently ignore.
  }
}

interface TourDialogProps {
  /** Externally controlled open state. When undefined, the dialog manages its own visibility. */
  open?: boolean
  onOpenChange?: (open: boolean) => void
}

export function TourDialog({ open: controlledOpen, onOpenChange }: TourDialogProps) {
  const app = useAppStore((s) => s.app)
  const navigateTo = useAppStore((s) => s.navigateTo)

  const [internalOpen, setInternalOpen] = useState(false)
  const [currentStep, setCurrentStep] = useState(0)

  const tour = app?.tour ?? []
  const appName = app?.appName ?? ''

  // Determine whether we're controlled or uncontrolled.
  const isControlled = controlledOpen !== undefined
  const isOpen = isControlled ? controlledOpen : internalOpen

  // Auto-show on first load if tour is defined and hasn't been seen.
  useEffect(() => {
    if (!isControlled && tour.length > 0 && appName && !hasTourBeenSeen(appName)) {
      setInternalOpen(true)
      setCurrentStep(0)
    }
  }, [isControlled, tour.length, appName])

  // Navigate to the step's page if it has one.
  const navigateIfNeeded = useCallback(
    (stepIndex: number) => {
      const step = tour[stepIndex]
      if (step?.page) {
        navigateTo(step.page)
      }
    },
    [tour, navigateTo],
  )

  // Navigate to the first step's page when the dialog opens.
  useEffect(() => {
    if (isOpen && tour.length > 0) {
      navigateIfNeeded(0)
    }
    // Only run when the dialog opens, not on every render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen])

  function handleOpenChange(value: boolean) {
    if (!value) {
      // Closing — mark as seen.
      if (appName) markTourSeen(appName)
      setCurrentStep(0)
    }
    if (isControlled) {
      onOpenChange?.(value)
    } else {
      setInternalOpen(value)
    }
  }

  function handleNext() {
    if (currentStep >= tour.length - 1) {
      // Last step — close the dialog.
      handleOpenChange(false)
      return
    }
    const nextStep = currentStep + 1
    setCurrentStep(nextStep)
    navigateIfNeeded(nextStep)
  }

  function handlePrevious() {
    if (currentStep <= 0) return
    const prevStep = currentStep - 1
    setCurrentStep(prevStep)
    navigateIfNeeded(prevStep)
  }

  function handleSkip() {
    handleOpenChange(false)
  }

  // Nothing to render if there's no tour.
  if (tour.length === 0) return null

  const step = tour[currentStep]
  const isFirst = currentStep === 0
  const isLast = currentStep === tour.length - 1
  const progress = ((currentStep + 1) / tour.length) * 100

  return (
    <Dialog open={isOpen} onOpenChange={handleOpenChange}>
      <DialogContent showCloseButton={false} className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{step.title}</DialogTitle>
          <DialogDescription>{step.content}</DialogDescription>
        </DialogHeader>

        {/* Progress indicator */}
        <div className="space-y-1">
          <p className="text-xs text-muted-foreground">
            Step {currentStep + 1} of {tour.length}
          </p>
          <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted">
            <div
              className="h-full rounded-full bg-primary transition-all duration-300"
              style={{ width: `${progress}%` }}
            />
          </div>
        </div>

        <Separator />

        <DialogFooter>
          {!isFirst && (
            <Button variant="outline" onClick={handlePrevious}>
              Back
            </Button>
          )}
          <Button variant="ghost" onClick={handleSkip}>
            Skip Tour
          </Button>
          <Button onClick={handleNext}>
            {isLast ? 'Get Started' : 'Next'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

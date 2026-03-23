import { useCallback, useEffect, useState } from 'react'
import { useAppStore } from '@/engine/app-store.ts'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'

// ---------------------------------------------------------------------------
// TourDialog — step-through guided tour, shown on first app launch
// ---------------------------------------------------------------------------
//
// Renders as a floating card at the bottom-right of the screen with NO
// backdrop overlay, so the user can see the app page behind it. This matches
// the Flutter framework's tour which navigates between pages as the tour
// progresses.

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

  const isControlled = controlledOpen !== undefined
  const isOpen = isControlled ? controlledOpen : internalOpen

  // Auto-show on first load if tour is defined and hasn't been seen.
  useEffect(() => {
    if (!isControlled && tour.length > 0 && appName && !hasTourBeenSeen(appName)) {
      setInternalOpen(true)
      setCurrentStep(0)
    }
  }, [isControlled, tour.length, appName])

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
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen])

  function close() {
    if (appName) markTourSeen(appName)
    setCurrentStep(0)
    if (isControlled) {
      onOpenChange?.(false)
    } else {
      setInternalOpen(false)
    }
  }

  function handleNext() {
    if (currentStep >= tour.length - 1) {
      close()
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

  if (!isOpen || tour.length === 0) return null

  const step = tour[currentStep]
  const isFirst = currentStep === 0
  const isLast = currentStep === tour.length - 1
  const progress = ((currentStep + 1) / tour.length) * 100

  return (
    <div className="fixed bottom-4 right-4 z-50 w-96 animate-in slide-in-from-bottom-4 fade-in duration-300">
      <Card className="shadow-lg border-primary/20">
        <CardHeader className="pb-2">
          <div className="flex items-center justify-between">
            <CardTitle className="text-base">{step.title}</CardTitle>
            <span className="text-xs text-muted-foreground">
              {currentStep + 1} / {tour.length}
            </span>
          </div>
          {/* Progress bar */}
          <div className="h-1 w-full overflow-hidden rounded-full bg-muted">
            <div
              className="h-full rounded-full bg-primary transition-all duration-300"
              style={{ width: `${progress}%` }}
            />
          </div>
        </CardHeader>
        <CardContent className="pb-3">
          <p className="text-sm text-muted-foreground">{step.content}</p>
        </CardContent>
        <CardFooter className="flex justify-end gap-2 pt-0">
          {!isFirst && (
            <Button variant="ghost" size="sm" onClick={handlePrevious}>
              Back
            </Button>
          )}
          <Button variant="ghost" size="sm" onClick={close}>
            Skip
          </Button>
          <Button size="sm" onClick={handleNext}>
            {isLast ? 'Get Started' : 'Next'}
          </Button>
        </CardFooter>
      </Card>
    </div>
  )
}

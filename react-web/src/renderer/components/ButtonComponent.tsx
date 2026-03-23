import { useState } from 'react'
import {
  DollarSign, TrendingUp, TrendingDown, Users, User,
  CheckCircle, Check, AlertTriangle, AlertCircle, Info,
  Star, Heart, ShoppingCart, Package, ListChecks, Timer,
  CalendarDays, Clock, BarChart3, PieChart, LayoutDashboard,
  Receipt, Tag, Layers, List, CheckCheck, Eye, Gauge,
  Dumbbell, UtensilsCrossed, BookOpen, GraduationCap,
  Briefcase, Home, Plane, Car, Plus, Pencil, Trash2,
  Download, Upload, Send, Search, Settings, RefreshCw,
  ArrowLeft, ArrowRight, Save, X, type LucideIcon,
} from 'lucide-react'
import { useAppStore } from '@/engine/app-store.ts'
import { hintEmphasis, hintAlign, hintIcon, hintSize } from '@/models/ods-style-hint.ts'
import type { OdsButtonComponent } from '@/models/ods-component.ts'
import { Button } from '@/components/ui/button.tsx'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog.tsx'
import { cn } from '@/lib/utils.ts'

// ---------------------------------------------------------------------------
// Icon mapping — Material icon names to lucide-react equivalents
// ---------------------------------------------------------------------------

const ICON_MAP: Record<string, LucideIcon> = {
  attach_money: DollarSign,
  money: DollarSign,
  trending_up: TrendingUp,
  trending_down: TrendingDown,
  people: Users,
  person: User,
  check_circle: CheckCircle,
  check: Check,
  warning: AlertTriangle,
  error: AlertCircle,
  info: Info,
  star: Star,
  favorite: Heart,
  shopping_cart: ShoppingCart,
  inventory: Package,
  task: ListChecks,
  timer: Timer,
  calendar_today: CalendarDays,
  schedule: Clock,
  bar_chart: BarChart3,
  pie_chart: PieChart,
  analytics: BarChart3,
  dashboard: LayoutDashboard,
  receipt: Receipt,
  local_offer: Tag,
  category: Layers,
  list: List,
  done: Check,
  done_all: CheckCheck,
  visibility: Eye,
  speed: Gauge,
  fitness_center: Dumbbell,
  restaurant: UtensilsCrossed,
  book: BookOpen,
  school: GraduationCap,
  work: Briefcase,
  home: Home,
  flight: Plane,
  directions_car: Car,
  add: Plus,
  edit: Pencil,
  delete: Trash2,
  download: Download,
  upload: Upload,
  send: Send,
  search: Search,
  settings: Settings,
  refresh: RefreshCw,
  arrow_back: ArrowLeft,
  arrow_forward: ArrowRight,
  save: Save,
  close: X,
  checklist: ListChecks,
}

export function resolveIcon(name: string | undefined): LucideIcon | undefined {
  if (!name) return undefined
  return ICON_MAP[name]
}

// ---------------------------------------------------------------------------
// ButtonComponent
// ---------------------------------------------------------------------------

/**
 * Renders an OdsButtonComponent using shadcn Button.
 *
 * Maps emphasis to shadcn variants:
 *   primary -> default, secondary -> outline, danger -> destructive
 *
 * Supports icon display and per-action confirmation dialogs.
 */
export function ButtonComponent({ model }: { model: OdsButtonComponent }) {
  const executeActions = useAppStore((s) => s.executeActions)
  const [confirmMessage, setConfirmMessage] = useState<string | null>(null)
  const [pendingResolve, setPendingResolve] = useState<((v: boolean) => void) | null>(null)

  const emphasis = hintEmphasis(model.styleHint)
  const align = hintAlign(model.styleHint)
  const iconName = hintIcon(model.styleHint)
  const size = hintSize(model.styleHint)

  // Map ODS emphasis to shadcn Button variant.
  const variant = resolveVariant(emphasis)
  const buttonSize = resolveSize(size)
  const Icon = resolveIcon(iconName)

  const handleClick = async () => {
    await executeActions(model.onClick, async (message: string) => {
      return new Promise<boolean>((resolve) => {
        setConfirmMessage(message)
        setPendingResolve(() => resolve)
      })
    })
  }

  const handleConfirm = () => {
    pendingResolve?.(true)
    setConfirmMessage(null)
    setPendingResolve(null)
  }

  const handleCancel = () => {
    pendingResolve?.(false)
    setConfirmMessage(null)
    setPendingResolve(null)
  }

  const alignClass =
    align === 'center' ? 'flex justify-center' :
    align === 'right' ? 'flex justify-end' :
    ''

  return (
    <div className={cn('py-2', alignClass)}>
      <Button variant={variant} size={buttonSize} onClick={handleClick}>
        {Icon && <Icon data-icon="inline-start" className="size-4" />}
        {model.label}
      </Button>

      {/* Confirmation dialog */}
      <AlertDialog open={confirmMessage != null}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Confirm</AlertDialogTitle>
            <AlertDialogDescription>{confirmMessage}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel onClick={handleCancel}>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={handleConfirm}>Confirm</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function resolveVariant(emphasis: string | undefined): 'default' | 'outline' | 'destructive' | 'secondary' | 'ghost' {
  switch (emphasis) {
    case 'primary': return 'default'
    case 'secondary': return 'outline'
    case 'danger': return 'destructive'
    default: return 'default'
  }
}

function resolveSize(size: string | undefined): 'default' | 'sm' | 'lg' | 'xs' {
  switch (size) {
    case 'compact': return 'sm'
    case 'large': return 'lg'
    default: return 'default'
  }
}

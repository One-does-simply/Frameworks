import { useState, useEffect, useCallback, useMemo, useRef } from 'react'
import { useAppStore } from '@/engine/app-store'
import { evaluateFormula } from '@/engine/formula-evaluator'
import { validateField, isComputed, type OdsFieldDefinition, type OdsOptionsFrom } from '@/models/ods-field'
import type { OdsFormComponent } from '@/models/ods-component'

import { Input } from '@/components/ui/input'
import { Textarea } from '@/components/ui/textarea'
import { Label } from '@/components/ui/label'
import { Checkbox } from '@/components/ui/checkbox'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'

// ---------------------------------------------------------------------------
// Magic default helpers
// ---------------------------------------------------------------------------

function resolveMagicDefault(defaultValue: string, fieldType: string, authService?: { currentUsername: string; currentDisplayName: string; currentEmail: string; isLoggedIn: boolean } | null): string {
  const upper = defaultValue.toUpperCase()

  // User-context magic defaults: CURRENT_USER.NAME, CURRENT_USER.EMAIL, etc.
  // For logged-in users: resolve to their info. For guests: return empty string.
  if (upper.startsWith('CURRENT_USER.') || upper === 'CURRENT_USER') {
    if (!authService?.isLoggedIn) return ''
    if (upper === 'CURRENT_USER') return authService.currentDisplayName
    const prop = upper.slice('CURRENT_USER.'.length)
    switch (prop) {
      case 'NAME': return authService.currentDisplayName
      case 'EMAIL': return authService.currentEmail
      case 'USERNAME': return authService.currentUsername
      default: return ''
    }
  }

  if (upper === 'NOW' || upper === 'CURRENTDATE') {
    const now = new Date()
    if (fieldType === 'datetime') {
      // datetime-local input expects YYYY-MM-DDThh:mm
      return now.toISOString().slice(0, 16)
    }
    // date input expects YYYY-MM-DD
    return now.toISOString().slice(0, 10)
  }

  // Relative date offsets: +7d, +1m, etc.
  const offsetMatch = /^\+(\d+)([dm])$/i.exec(defaultValue)
  if (offsetMatch) {
    const amount = parseInt(offsetMatch[1], 10)
    const unit = offsetMatch[2].toLowerCase()
    const date = new Date()
    if (unit === 'd') {
      date.setDate(date.getDate() + amount)
    } else if (unit === 'm') {
      date.setMonth(date.getMonth() + amount)
    }
    if (fieldType === 'datetime') {
      return date.toISOString().slice(0, 16)
    }
    return date.toISOString().slice(0, 10)
  }

  return defaultValue
}

// ---------------------------------------------------------------------------
// Visibility helper
// ---------------------------------------------------------------------------

function isFieldVisible(
  field: OdsFieldDefinition,
  formState: Record<string, string>,
  authService: { hasAccess: (roles: string[] | undefined) => boolean } | null,
  isMultiUser: boolean,
): boolean {
  // Hidden fields carry data but never render.
  if (field.type === 'hidden') return false

  // Role-based visibility.
  if (field.roles && field.roles.length > 0 && isMultiUser && authService) {
    if (!authService.hasAccess(field.roles)) return false
  }

  // visibleWhen: conditionally show/hide based on sibling field value.
  if (field.visibleWhen) {
    const watchedValue = formState[field.visibleWhen.field] ?? ''
    if (watchedValue !== field.visibleWhen.equals) return false
  }

  return true
}

// ---------------------------------------------------------------------------
// Individual field renderer
// ---------------------------------------------------------------------------

interface FieldProps {
  field: OdsFieldDefinition
  formId: string
  value: string
  onChange: (name: string, value: string) => void
}

function FormField({ field, formId, value, onChange }: FieldProps) {
  const [error, setError] = useState<string | undefined>(undefined)
  const [touched, setTouched] = useState(false)
  const appSettings = useAppStore((s) => s.appSettings)
  const formState = useAppStore((s) => s.getFormState(formId))

  const handleBlur = useCallback(() => {
    setTouched(true)

    // Required check.
    if (field.required && !value.trim()) {
      setError(`${field.label || field.name} is required`)
      return
    }

    // Email format check.
    if (field.type === 'email' && value) {
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value)) {
        setError('Please enter a valid email address')
        return
      }
    }

    // Validation rules.
    const validationError = validateField(field.validation, value, field.type)
    setError(validationError)
  }, [field, value])

  // Clear error when value changes after touching.
  useEffect(() => {
    if (touched && error) {
      if (field.required && !value.trim()) return
      const validationError = validateField(field.validation, value, field.type)
      if (!validationError && !(field.required && !value.trim())) {
        setError(undefined)
      }
    }
  }, [value, touched, error, field])

  const handleChange = useCallback(
    (newValue: string) => {
      onChange(field.name, newValue)
    },
    [field.name, onChange],
  )

  // Read-only fields with display variants render as clean text.
  if (field.readOnly && field.displayVariant) {
    const variant = field.displayVariant
    const label = field.label || field.name

    // Apply currency formatting for display.
    let displayValue = value
    if (field.currency && field.type === 'number' && value) {
      const currency = appSettings['currency'] ?? ''
      if (currency && !isNaN(Number(value))) {
        displayValue = `${currency}${value}`
      }
    }

    if (variant === 'plain' || variant === 'heading' || variant === 'caption' || variant === 'subtitle') {
      let valueClassName = ''
      switch (variant) {
        case 'heading':
          valueClassName = 'text-xl font-semibold'
          break
        case 'caption':
          valueClassName = 'text-sm text-muted-foreground'
          break
        case 'subtitle':
          valueClassName = 'text-base font-medium'
          break
        default: // plain
          valueClassName = 'text-base'
          break
      }

      return (
        <div className="space-y-1">
          <span className="text-xs text-muted-foreground">{label}</span>
          <p className={valueClassName}>{displayValue}</p>
        </div>
      )
    }
  }

  // Currency formatting for read-only number fields (default variant).
  let displayValue = value
  if (field.readOnly && field.currency && field.type === 'number' && value) {
    const currency = appSettings['currency'] ?? ''
    if (currency && !isNaN(Number(value))) {
      displayValue = `${currency}${value}`
    }
  }

  return (
    <div className="space-y-1">
      <Label htmlFor={`${formId}-${field.name}`}>
        {field.label || field.name}
        {field.required && <span className="text-destructive"> *</span>}
      </Label>
      {renderInput(field, formId, value, displayValue, handleChange, handleBlur, formState)}
      {error && <p className="text-sm text-destructive">{error}</p>}
    </div>
  )
}

function renderInput(
  field: OdsFieldDefinition,
  formId: string,
  value: string,
  displayValue: string,
  onChange: (value: string) => void,
  onBlur: () => void,
  formState: Record<string, string>,
) {
  const id = `${formId}-${field.name}`
  const placeholder = field.placeholder ?? ''

  switch (field.type) {
    case 'multiline':
      return (
        <Textarea
          id={id}
          value={value}
          placeholder={placeholder}
          readOnly={field.readOnly}
          onBlur={onBlur}
          onChange={(e) => onChange(e.target.value)}
          rows={4}
        />
      )

    case 'select':
      if (field.optionsFrom) {
        return (
          <DynamicSelect
            field={field}
            formId={formId}
            value={value}
            optionsFrom={field.optionsFrom}
            formState={formState}
            onChange={onChange}
            onBlur={onBlur}
          />
        )
      }
      return (
        <Select value={value || undefined} onValueChange={(v) => onChange(v ?? '')}>
          <SelectTrigger id={id} onBlur={onBlur}>
            <SelectValue placeholder={placeholder || 'Select...'} />
          </SelectTrigger>
          <SelectContent>
            {(field.options ?? []).map((opt, i) => {
              const label =
                field.optionLabels && field.optionLabels[i]
                  ? field.optionLabels[i]
                  : opt
              return (
                <SelectItem key={opt} value={opt}>
                  {label}
                </SelectItem>
              )
            })}
          </SelectContent>
        </Select>
      )

    case 'checkbox':
      return (
        <div className="flex items-center gap-2 pt-1">
          <Checkbox
            id={id}
            checked={value === 'true'}
            onCheckedChange={(checked) =>
              onChange(checked === true ? 'true' : 'false')
            }
            onBlur={onBlur}
          />
          <Label htmlFor={id} className="font-normal cursor-pointer">
            {placeholder || field.label || field.name}
          </Label>
        </div>
      )

    case 'date':
      return (
        <Input
          id={id}
          type="date"
          value={value}
          readOnly={field.readOnly}
          onBlur={onBlur}
          onChange={(e) => onChange(e.target.value)}
        />
      )

    case 'datetime':
      return (
        <Input
          id={id}
          type="datetime-local"
          value={value}
          readOnly={field.readOnly}
          onBlur={onBlur}
          onChange={(e) => onChange(e.target.value)}
        />
      )

    case 'number':
      return field.readOnly ? (
        <Input
          id={id}
          type="text"
          value={displayValue}
          readOnly
          disabled
          className="bg-muted"
        />
      ) : (
        <Input
          id={id}
          type="number"
          value={value}
          placeholder={placeholder}
          readOnly={field.readOnly}
          onBlur={onBlur}
          onChange={(e) => onChange(e.target.value)}
          min={field.validation?.min}
          max={field.validation?.max}
        />
      )

    case 'email':
      return (
        <Input
          id={id}
          type="email"
          value={value}
          placeholder={placeholder}
          readOnly={field.readOnly}
          onBlur={onBlur}
          onChange={(e) => onChange(e.target.value)}
        />
      )

    case 'hidden':
      return <input type="hidden" id={id} value={value} />

    case 'user':
      return (
        <UserFieldSelect
          id={id}
          value={value}
          placeholder={placeholder}
          readOnly={field.readOnly}
          onChange={onChange}
          onBlur={onBlur}
        />
      )

    case 'text':
    default:
      return (
        <Input
          id={id}
          type="text"
          value={value}
          placeholder={placeholder}
          readOnly={field.readOnly}
          onBlur={onBlur}
          onChange={(e) => onChange(e.target.value)}
        />
      )
  }
}

// ---------------------------------------------------------------------------
// Dynamic select (optionsFrom) sub-component
// ---------------------------------------------------------------------------

interface DynamicSelectProps {
  field: OdsFieldDefinition
  formId: string
  value: string
  optionsFrom: OdsOptionsFrom
  formState: Record<string, string>
  onChange: (value: string) => void
  onBlur: () => void
}

function DynamicSelect({ field, formId, value, optionsFrom, formState, onChange, onBlur }: DynamicSelectProps) {
  const queryDataSource = useAppStore((s) => s.queryDataSource)
  const [options, setOptions] = useState<string[]>([])
  const [loading, setLoading] = useState(true)

  // Determine the dependency field value for filtered/dependent dropdowns.
  const filterDependencyValue = optionsFrom.filter
    ? (formState[optionsFrom.filter.fromField] ?? '')
    : undefined

  useEffect(() => {
    let cancelled = false
    const load = async () => {
      setLoading(true)
      let rows = await queryDataSource(optionsFrom.dataSource)

      // Apply dependent dropdown filter.
      if (optionsFrom.filter && filterDependencyValue) {
        rows = rows.filter(
          (row) =>
            String(row[optionsFrom.filter!.field] ?? '') === filterDependencyValue,
        )
      }

      // Extract unique values from the valueField column.
      const unique = new Set<string>()
      for (const row of rows) {
        const val = row[optionsFrom.valueField]
        if (val != null && String(val) !== '') {
          unique.add(String(val))
        }
      }

      if (!cancelled) {
        setOptions(Array.from(unique))
        setLoading(false)
      }
    }
    load()
    return () => { cancelled = true }
  }, [optionsFrom.dataSource, optionsFrom.valueField, optionsFrom.filter, filterDependencyValue, queryDataSource])

  const id = `${formId}-${field.name}`
  const placeholder = field.placeholder ?? ''

  if (loading) {
    return (
      <Select disabled>
        <SelectTrigger id={id}>
          <SelectValue placeholder="Loading..." />
        </SelectTrigger>
        <SelectContent />
      </Select>
    )
  }

  if (options.length === 0) {
    return (
      <Select disabled>
        <SelectTrigger id={id}>
          <SelectValue placeholder="No options available" />
        </SelectTrigger>
        <SelectContent />
      </Select>
    )
  }

  const effectiveValue = options.includes(value) ? value : undefined

  return (
    <Select value={effectiveValue} onValueChange={(v) => onChange(v ?? '')}>
      <SelectTrigger id={id} onBlur={onBlur}>
        <SelectValue placeholder={placeholder || 'Select...'} />
      </SelectTrigger>
      <SelectContent>
        {options.map((opt) => (
          <SelectItem key={opt} value={opt}>
            {opt}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  )
}

// ---------------------------------------------------------------------------
// User field — dropdown of users (multi-user) or plain text (single-user)
// ---------------------------------------------------------------------------

interface UserFieldSelectProps {
  id: string
  value: string
  placeholder: string
  readOnly?: boolean
  onChange: (value: string) => void
  onBlur: () => void
}

function UserFieldSelect({ id, value, placeholder, readOnly, onChange, onBlur }: UserFieldSelectProps) {
  const authService = useAppStore((s) => s.authService)
  const isMultiUser = useAppStore((s) => s.isMultiUser)
  const [users, setUsers] = useState<{ value: string; label: string }[]>([])
  const [loading, setLoading] = useState(false)
  const loadedRef = useRef(false)

  useEffect(() => {
    if (!isMultiUser || !authService || loadedRef.current) return
    loadedRef.current = true
    setLoading(true)
    authService.listUsers().then((list) => {
      setUsers(
        list.map((u) => ({
          value: String(u.username ?? u.email ?? u._id ?? ''),
          label: String(u.displayName ?? u.username ?? u.email ?? ''),
        })),
      )
      setLoading(false)
    })
  }, [isMultiUser, authService])

  // Single-user mode: plain text input
  if (!isMultiUser) {
    return (
      <Input
        id={id}
        type="text"
        value={value}
        placeholder={placeholder}
        readOnly={readOnly}
        onBlur={onBlur}
        onChange={(e) => onChange(e.target.value)}
      />
    )
  }

  // Multi-user mode: dropdown of users
  if (loading) {
    return (
      <Select disabled>
        <SelectTrigger id={id}>
          <SelectValue placeholder="Loading users..." />
        </SelectTrigger>
        <SelectContent />
      </Select>
    )
  }

  return (
    <Select value={value || undefined} onValueChange={(v) => onChange(v ?? '')}>
      <SelectTrigger id={id} onBlur={onBlur}>
        <SelectValue placeholder={placeholder || 'Select user...'} />
      </SelectTrigger>
      <SelectContent>
        {users.map((u) => (
          <SelectItem key={u.value} value={u.value}>
            {u.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  )
}

// ---------------------------------------------------------------------------
// Computed (formula) field renderer
// ---------------------------------------------------------------------------

interface ComputedFieldProps {
  field: OdsFieldDefinition
  formId: string
  allFields: OdsFieldDefinition[]
  formState: Record<string, string>
}

function ComputedField({ field, formId, allFields, formState }: ComputedFieldProps) {
  const updateFormField = useAppStore((s) => s.updateFormField)
  const appSettings = useAppStore((s) => s.appSettings)

  // Build values map from form state.
  const values: Record<string, string | null | undefined> = {}
  for (const f of allFields) {
    values[f.name] = formState[f.name] ?? undefined
  }

  const result = evaluateFormula(field.formula!, field.type, values)

  // Push computed value into the store so it is available for submit.
  useEffect(() => {
    if (result) {
      updateFormField(formId, field.name, result)
    }
  }, [result, formId, field.name, updateFormField])

  // Apply currency symbol for fields marked with currency: true,
  // or fall back to all number computed fields when no field opts in.
  let displayResult = result
  const anyCurrency = allFields.some((f) => f.currency)
  if (field.currency || (!anyCurrency && field.type === 'number')) {
    const currency = appSettings['currency'] ?? ''
    if (currency && !isNaN(Number(result)) && result !== '') {
      displayResult = `${currency}${result}`
    }
  }

  return (
    <div className="space-y-1">
      <Label htmlFor={`${formId}-${field.name}`}>
        {field.label || field.name}
        <span className="text-muted-foreground text-xs ml-1">(computed)</span>
      </Label>
      <Input
        id={`${formId}-${field.name}`}
        type="text"
        value={displayResult}
        readOnly
        disabled
        className="bg-muted"
      />
    </div>
  )
}

// ---------------------------------------------------------------------------
// Main FormComponent
// ---------------------------------------------------------------------------

interface FormComponentProps {
  model: OdsFormComponent
}

export function FormComponent({ model }: FormComponentProps) {
  const formState = useAppStore((s) => s.getFormState(model.id))
  const updateFormField = useAppStore((s) => s.updateFormField)
  const recordCursors = useAppStore((s) => s.recordCursors)
  const recordGeneration = useAppStore((s) => s.recordGeneration)
  const authService = useAppStore((s) => s.authService)
  const isMultiUser = useAppStore((s) => s.isMultiUser)

  const cursor = recordCursors[model.id]

  // Initialize defaults on mount (including hidden fields).
  useEffect(() => {
    for (const field of model.fields) {
      // Only set default if the field does not already have a value.
      if (formState[field.name] != null && formState[field.name] !== '') continue

      if (field.defaultValue != null) {
        const resolved = resolveMagicDefault(field.defaultValue, field.type, authService)
        updateFormField(model.id, field.name, resolved)
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [model.id, recordGeneration])

  const handleFieldChange = useCallback(
    (name: string, value: string) => {
      updateFormField(model.id, name, value)
    },
    [model.id, updateFormField],
  )

  // Filter to visible fields.
  const visibleFields = useMemo(
    () =>
      model.fields.filter((f) =>
        isFieldVisible(f, formState, authService, isMultiUser),
      ),
    [model.fields, formState, authService, isMultiUser],
  )

  return (
    <div className="space-y-3 py-2">
      {/* Record cursor indicator */}
      {cursor && cursor.count > 0 && (
        <p className="text-center text-sm font-semibold text-primary">
          Record {cursor.currentIndex + 1} of {cursor.count}
        </p>
      )}

      {visibleFields.map((field) =>
        isComputed(field) ? (
          <ComputedField
            key={`${model.id}_${field.name}_${recordGeneration}`}
            field={field}
            formId={model.id}
            allFields={model.fields}
            formState={formState}
          />
        ) : (
          <FormField
            key={`${model.id}_${field.name}_${recordGeneration}`}
            field={field}
            formId={model.id}
            value={formState[field.name] ?? ''}
            onChange={handleFieldChange}
          />
        ),
      )}
    </div>
  )
}

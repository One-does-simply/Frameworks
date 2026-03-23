import { useState, useEffect, useCallback, useMemo } from 'react'
import { useAppStore } from '@/engine/app-store'
import { evaluateFormula } from '@/engine/formula-evaluator'
import { validateField, isComputed, type OdsFieldDefinition } from '@/models/ods-field'
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

function resolveMagicDefault(defaultValue: string, fieldType: string): string {
  const upper = defaultValue.toUpperCase()

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

  return (
    <div className="space-y-1">
      <Label htmlFor={`${formId}-${field.name}`}>
        {field.label || field.name}
        {field.required && <span className="text-destructive"> *</span>}
      </Label>
      {renderInput(field, formId, value, handleChange, handleBlur)}
      {error && <p className="text-sm text-destructive">{error}</p>}
    </div>
  )
}

function renderInput(
  field: OdsFieldDefinition,
  formId: string,
  value: string,
  onChange: (value: string) => void,
  onBlur: () => void,
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
      return (
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

  return (
    <div className="space-y-1">
      <Label htmlFor={`${formId}-${field.name}`}>
        {field.label || field.name}
        <span className="text-muted-foreground text-xs ml-1">(computed)</span>
      </Label>
      <Input
        id={`${formId}-${field.name}`}
        type="text"
        value={result}
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
        const resolved = resolveMagicDefault(field.defaultValue, field.type)
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

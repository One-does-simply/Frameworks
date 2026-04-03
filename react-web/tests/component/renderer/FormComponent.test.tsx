import { describe, it, expect, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import { FormComponent } from '../../../src/renderer/components/FormComponent.tsx'
import type { OdsFormComponent } from '../../../src/models/ods-component.ts'
import type { OdsFieldDefinition } from '../../../src/models/ods-field.ts'
import { useAppStore } from '../../../src/engine/app-store.ts'

function field(overrides?: Partial<OdsFieldDefinition>): OdsFieldDefinition {
  return {
    name: 'testField',
    type: 'text',
    label: 'Test Field',
    required: false,
    currency: false,
    readOnly: false,
    ...overrides,
  }
}

function formModel(overrides?: Partial<OdsFormComponent>): OdsFormComponent {
  return {
    component: 'form',
    id: 'testForm',
    fields: [field()],
    styleHint: {},
    ...overrides,
  }
}

describe('FormComponent', () => {
  beforeEach(() => {
    useAppStore.setState({
      formStates: {},
      recordCursors: {},
      recordGeneration: 0,
      authService: null,
      isMultiUser: false,
      appSettings: {},
      updateFormField: useAppStore.getState().updateFormField,
      getFormState: useAppStore.getState().getFormState,
    } as never)
  })

  it('renders a text field with its label', () => {
    render(<FormComponent model={formModel()} />)
    expect(screen.getByText('Test Field')).toBeTruthy()
  })

  it('renders multiple fields', () => {
    const model = formModel({
      fields: [
        field({ name: 'first', label: 'First Name' }),
        field({ name: 'last', label: 'Last Name' }),
      ],
    })
    render(<FormComponent model={model} />)
    expect(screen.getByText('First Name')).toBeTruthy()
    expect(screen.getByText('Last Name')).toBeTruthy()
  })

  it('renders a required field with asterisk indicator', () => {
    const model = formModel({
      fields: [field({ required: true, label: 'Email' })],
    })
    render(<FormComponent model={model} />)
    expect(screen.getByText('*')).toBeTruthy()
  })

  it('renders a number field as number input', () => {
    const model = formModel({
      fields: [field({ name: 'amount', type: 'number', label: 'Amount' })],
    })
    render(<FormComponent model={model} />)
    const input = document.querySelector('input[type="number"]')
    expect(input).toBeTruthy()
  })

  it('renders a date field as date input', () => {
    const model = formModel({
      fields: [field({ name: 'dueDate', type: 'date', label: 'Due Date' })],
    })
    render(<FormComponent model={model} />)
    const input = document.querySelector('input[type="date"]')
    expect(input).toBeTruthy()
  })

  it('renders a multiline field as textarea', () => {
    const model = formModel({
      fields: [field({ name: 'notes', type: 'multiline', label: 'Notes' })],
    })
    render(<FormComponent model={model} />)
    const textarea = document.querySelector('textarea')
    expect(textarea).toBeTruthy()
  })

  it('renders a checkbox field', () => {
    const model = formModel({
      fields: [field({ name: 'done', type: 'checkbox', label: 'Done' })],
    })
    render(<FormComponent model={model} />)
    expect(screen.getByRole('checkbox')).toBeTruthy()
  })

  it('hides hidden fields from the UI', () => {
    const model = formModel({
      fields: [
        field({ name: 'visible', type: 'text', label: 'Visible' }),
        field({ name: 'secret', type: 'hidden', label: 'Secret' }),
      ],
    })
    render(<FormComponent model={model} />)
    expect(screen.getByText('Visible')).toBeTruthy()
    expect(screen.queryByText('Secret')).toBeNull()
  })

  it('renders computed fields as read-only with (computed) label', () => {
    const model = formModel({
      fields: [
        field({ name: 'qty', type: 'number', label: 'Quantity' }),
        field({ name: 'total', type: 'number', label: 'Total', formula: '{qty} * 2', readOnly: true }),
      ],
    })
    render(<FormComponent model={model} />)
    expect(screen.getByText('Total')).toBeTruthy()
    expect(screen.getByText('(computed)')).toBeTruthy()
  })

  it('renders select field with options', () => {
    const model = formModel({
      fields: [
        field({
          name: 'priority',
          type: 'select',
          label: 'Priority',
          options: ['Low', 'Medium', 'High'],
        }),
      ],
    })
    render(<FormComponent model={model} />)
    expect(screen.getByText('Priority')).toBeTruthy()
  })

  it('does not crash with an empty fields array', () => {
    const model = formModel({ fields: [] })
    const { container } = render(<FormComponent model={model} />)
    expect(container).toBeTruthy()
  })
})

import { describe, it, expect, beforeEach } from 'vitest'
import { RecordCursor, useAppStore } from '../../../src/engine/app-store.ts'

// ===========================================================================
// RecordCursor unit tests
// ===========================================================================

describe('RecordCursor', () => {
  const sampleRows = [
    { id: '1', name: 'Alice' },
    { id: '2', name: 'Bob' },
    { id: '3', name: 'Charlie' },
  ]

  // -------------------------------------------------------------------------
  // Construction
  // -------------------------------------------------------------------------

  it('initializes with rows and default index 0', () => {
    const cursor = new RecordCursor(sampleRows)
    expect(cursor.currentIndex).toBe(0)
    expect(cursor.count).toBe(3)
  })

  it('initializes with custom starting index', () => {
    const cursor = new RecordCursor(sampleRows, 2)
    expect(cursor.currentIndex).toBe(2)
    expect(cursor.currentRecord).toEqual({ id: '3', name: 'Charlie' })
  })

  // -------------------------------------------------------------------------
  // Navigation
  // -------------------------------------------------------------------------

  it('currentRecord returns row at current index', () => {
    const cursor = new RecordCursor(sampleRows, 1)
    expect(cursor.currentRecord).toEqual({ id: '2', name: 'Bob' })
  })

  it('currentRecord returns undefined for out-of-bounds index', () => {
    const cursor = new RecordCursor(sampleRows, 5)
    expect(cursor.currentRecord).toBeUndefined()
  })

  it('currentRecord returns undefined for negative index', () => {
    const cursor = new RecordCursor(sampleRows, -1)
    expect(cursor.currentRecord).toBeUndefined()
  })

  it('hasNext is true when not at last row', () => {
    const cursor = new RecordCursor(sampleRows, 0)
    expect(cursor.hasNext).toBe(true)
  })

  it('hasNext is false at last row', () => {
    const cursor = new RecordCursor(sampleRows, 2)
    expect(cursor.hasNext).toBe(false)
  })

  it('hasPrevious is false at first row', () => {
    const cursor = new RecordCursor(sampleRows, 0)
    expect(cursor.hasPrevious).toBe(false)
  })

  it('hasPrevious is true when not at first row', () => {
    const cursor = new RecordCursor(sampleRows, 1)
    expect(cursor.hasPrevious).toBe(true)
  })

  it('isEmpty is true for empty rows', () => {
    const cursor = new RecordCursor([])
    expect(cursor.isEmpty).toBe(true)
  })

  it('isEmpty is false for non-empty rows', () => {
    const cursor = new RecordCursor(sampleRows)
    expect(cursor.isEmpty).toBe(false)
  })

  it('position returns human-readable string', () => {
    const cursor = new RecordCursor(sampleRows, 1)
    expect(cursor.position).toBe('2 of 3')
  })

  it('allows setting currentIndex', () => {
    const cursor = new RecordCursor(sampleRows)
    cursor.currentIndex = 2
    expect(cursor.currentIndex).toBe(2)
    expect(cursor.currentRecord).toEqual({ id: '3', name: 'Charlie' })
  })
})

// ===========================================================================
// App store — navigation and form state tests
// ===========================================================================

describe('useAppStore', () => {
  beforeEach(() => {
    useAppStore.setState({
      app: null,
      currentPageId: null,
      navigationStack: [],
      formStates: {},
      recordCursors: {},
      recordGeneration: 0,
      validation: null,
      loadError: null,
      debugMode: false,
      isLoading: false,
      lastActionError: null,
      lastMessage: null,
      appSettings: {},
      dataService: null,
      authService: null,
      currentSlug: null,
      isMultiUser: false,
      needsAdminSetup: false,
      needsLogin: false,
      isMultiUserOnly: false,
    })
  })

  // -------------------------------------------------------------------------
  // Navigation
  // -------------------------------------------------------------------------

  describe('navigateTo', () => {
    const minimalApp = {
      appName: 'Test',
      startPage: 'home',
      startPageByRole: {},
      menu: [],
      pages: {
        home: { title: 'Home', content: [] },
        about: { title: 'About', content: [] },
      },
      dataSources: {},
      tour: [],
      settings: {},
      auth: { multiUser: false, selfRegistration: false, defaultRole: 'user', multiUserOnly: false },
      branding: { theme: 'indigo', mode: 'system', headerStyle: 'light' },
    }

    it('navigates to a valid page', () => {
      useAppStore.setState({ app: minimalApp as any, currentPageId: 'home' })
      useAppStore.getState().navigateTo('about')
      expect(useAppStore.getState().currentPageId).toBe('about')
    })

    it('pushes current page to navigation stack', () => {
      useAppStore.setState({ app: minimalApp as any, currentPageId: 'home' })
      useAppStore.getState().navigateTo('about')
      expect(useAppStore.getState().navigationStack).toEqual(['home'])
    })

    it('ignores navigation to non-existent page', () => {
      useAppStore.setState({ app: minimalApp as any, currentPageId: 'home' })
      useAppStore.getState().navigateTo('nonexistent')
      expect(useAppStore.getState().currentPageId).toBe('home')
    })

    it('ignores navigation when app is null', () => {
      useAppStore.getState().navigateTo('home')
      expect(useAppStore.getState().currentPageId).toBeNull()
    })
  })

  // -------------------------------------------------------------------------
  // Go back
  // -------------------------------------------------------------------------

  describe('goBack', () => {
    it('pops previous page from stack', () => {
      useAppStore.setState({
        currentPageId: 'about',
        navigationStack: ['home'],
      })
      useAppStore.getState().goBack()
      expect(useAppStore.getState().currentPageId).toBe('home')
      expect(useAppStore.getState().navigationStack).toEqual([])
    })

    it('does nothing when stack is empty', () => {
      useAppStore.setState({ currentPageId: 'home', navigationStack: [] })
      useAppStore.getState().goBack()
      expect(useAppStore.getState().currentPageId).toBe('home')
    })
  })

  describe('canGoBack', () => {
    it('returns true when stack has entries', () => {
      useAppStore.setState({ navigationStack: ['home'] })
      expect(useAppStore.getState().canGoBack()).toBe(true)
    })

    it('returns false when stack is empty', () => {
      useAppStore.setState({ navigationStack: [] })
      expect(useAppStore.getState().canGoBack()).toBe(false)
    })
  })

  // -------------------------------------------------------------------------
  // Form state
  // -------------------------------------------------------------------------

  describe('updateFormField', () => {
    it('sets a field value on a form', () => {
      useAppStore.getState().updateFormField('form1', 'name', 'Alice')
      expect(useAppStore.getState().formStates['form1']['name']).toBe('Alice')
    })

    it('preserves existing form fields', () => {
      useAppStore.getState().updateFormField('form1', 'name', 'Alice')
      useAppStore.getState().updateFormField('form1', 'email', 'alice@test.com')
      const state = useAppStore.getState().formStates['form1']
      expect(state['name']).toBe('Alice')
      expect(state['email']).toBe('alice@test.com')
    })
  })

  describe('clearForm', () => {
    it('removes all fields from a form', () => {
      useAppStore.setState({
        formStates: { form1: { name: 'Alice', email: 'alice@test.com' } },
      })
      useAppStore.getState().clearForm('form1')
      expect(useAppStore.getState().formStates['form1']).toBeUndefined()
    })

    it('preserves specified fields', () => {
      useAppStore.setState({
        formStates: { form1: { name: 'Alice', email: 'alice@test.com', role: 'admin' } },
      })
      useAppStore.getState().clearForm('form1', ['email'])
      const state = useAppStore.getState().formStates['form1']
      expect(state['email']).toBe('alice@test.com')
      expect(state['name']).toBeUndefined()
    })

    it('handles clearing a non-existent form gracefully', () => {
      useAppStore.getState().clearForm('nonexistent')
      expect(useAppStore.getState().formStates['nonexistent']).toBeUndefined()
    })
  })

  describe('getFormState', () => {
    it('returns existing form state', () => {
      useAppStore.setState({ formStates: { form1: { name: 'Bob' } } })
      expect(useAppStore.getState().getFormState('form1')).toEqual({ name: 'Bob' })
    })

    it('creates and returns empty state for new form', () => {
      const state = useAppStore.getState().getFormState('newForm')
      expect(state).toEqual({})
      expect(useAppStore.getState().formStates['newForm']).toEqual({})
    })
  })

  // -------------------------------------------------------------------------
  // Reset
  // -------------------------------------------------------------------------

  describe('reset', () => {
    it('resets store to initial state', () => {
      useAppStore.setState({
        currentPageId: 'about',
        navigationStack: ['home'],
        formStates: { form1: { name: 'test' } },
        loadError: 'some error',
        debugMode: true,
      })
      useAppStore.getState().reset()
      const s = useAppStore.getState()
      expect(s.currentPageId).toBeNull()
      expect(s.navigationStack).toEqual([])
      expect(s.formStates).toEqual({})
      expect(s.loadError).toBeNull()
    })
  })

  // -------------------------------------------------------------------------
  // Debug mode
  // -------------------------------------------------------------------------

  describe('toggleDebugMode', () => {
    it('toggles debug mode on and off', () => {
      expect(useAppStore.getState().debugMode).toBe(false)
      useAppStore.getState().toggleDebugMode()
      expect(useAppStore.getState().debugMode).toBe(true)
      useAppStore.getState().toggleDebugMode()
      expect(useAppStore.getState().debugMode).toBe(false)
    })
  })
})

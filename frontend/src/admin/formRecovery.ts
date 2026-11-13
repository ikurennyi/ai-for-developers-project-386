export interface AdminFormDraft {
  name: string
  description: string
  duration: string
  slug: string
}

interface RecoveryState {
  id: string
  generation: number
  draft?: { path: string; fields: AdminFormDraft }
}

// History belongs to this tab; unlike sessionStorage its contents are not
// cloned into an opener's new tab. The storage marker contains no form data.
const saved = window.history.state?.calendarAdminForm as RecoveryState | undefined
const state: RecoveryState =
  saved && sessionStorage.getItem(`calendar-admin-form:${saved.id}`) === String(saved.generation)
    ? saved
    : { id: crypto.randomUUID(), generation: 0 }

export function persistAdminForm() {
  sessionStorage.setItem(`calendar-admin-form:${state.id}`, String(state.generation))
  window.history.replaceState(
    { ...window.history.state, calendarAdminForm: JSON.parse(JSON.stringify(state)) },
    '',
  )
}

export function recoverAdminForm(path: string): AdminFormDraft | undefined {
  return state.draft?.path === path ? { ...state.draft.fields } : undefined
}

export function retainAdminForm(path: string, fields: AdminFormDraft) {
  state.draft = { path, fields: { ...fields } }
  persistAdminForm()
}

export function discardAdminForm() {
  delete state.draft
  state.generation++
  persistAdminForm()
}

export function adminFormNavigated(path: string, returnTo: unknown) {
  if (
    state.draft &&
    path !== state.draft.path &&
    !(path === '/admin/login' && returnTo === state.draft.path)
  )
    discardAdminForm()
  else persistAdminForm()
}

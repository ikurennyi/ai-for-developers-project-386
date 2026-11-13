interface TabGeneration {
  id: string
  generation: number
}

// History is tab-local; sessionStorage holds only an invalidation marker, never
// private fields. Keep retention/discard policies with each caller.
export function tabHistory<T extends TabGeneration>(key: string, marker: string, initial: () => T) {
  const saved = window.history.state?.[key] as T | undefined
  const state =
    saved && sessionStorage.getItem(`${marker}:${saved.id}`) === String(saved.generation)
      ? saved
      : initial()
  return {
    state,
    persist() {
      sessionStorage.setItem(`${marker}:${state.id}`, String(state.generation))
      window.history.replaceState(
        { ...window.history.state, [key]: JSON.parse(JSON.stringify(state)) },
        '',
      )
    },
  }
}

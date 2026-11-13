import { getAdminSession, logoutAdmin } from '../generated/sdk'
import type { Router } from 'vue-router'

export const adminRequestHeaders = { 'X-Calendar-Request': '1' as const }

// Never accept an external URL (including protocol-relative URLs) as a return
// target. The router guard must still authenticate the resolved page.
export function adminReturnTarget(value: unknown): string {
  return typeof value === 'string' &&
    /^\/admin(?:\/|$)/.test(value) &&
    !value.startsWith('/admin/login') &&
    !/[\\\r\n]/.test(value)
    ? value
    : '/admin'
}

export async function hasAdminSession(): Promise<boolean> {
  const { response } = await getAdminSession()
  if (response?.status === 401) return false
  if (!response?.ok) throw new Error('Unable to check administrator access. Please try again.')
  return true
}

// Future administrative forms can preserve drafts in sessionStorage before
// calling this on 401; requests are never queued or replayed after login.
export async function requireAdminLogin(router: Router): Promise<void> {
  const returnTo = adminReturnTarget(router.currentRoute.value.fullPath)
  await router.replace({ name: 'admin-login', query: { returnTo } })
}

export async function logOut(router: Router): Promise<void> {
  const { response } = await logoutAdmin({ headers: adminRequestHeaders })
  if (!response?.ok) throw new Error('Unable to log out. Please try again.')
  await router.replace({ name: 'admin-login' })
}

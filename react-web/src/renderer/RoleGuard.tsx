import type { ReactNode } from 'react'
import { useAppStore } from '@/engine/app-store.ts'

/**
 * Conditionally renders children based on role-based access control.
 *
 * - If no roles are specified, always renders children.
 * - If the app is not multi-user, always renders children.
 * - Otherwise, delegates to authService.hasAccess() to check
 *   whether the current user has at least one matching role.
 */
export function RoleGuard({
  roles,
  children,
}: {
  roles?: string[]
  children: ReactNode
}) {
  const isMultiUser = useAppStore((s) => s.isMultiUser)
  const authService = useAppStore((s) => s.authService)

  // No role restriction — always show.
  if (!roles || roles.length === 0) return <>{children}</>

  // Single-user mode — always show.
  if (!isMultiUser) return <>{children}</>

  // Multi-user: check access via auth service.
  if (authService && authService.hasAccess(roles)) {
    return <>{children}</>
  }

  // User lacks required role — hide.
  return null
}

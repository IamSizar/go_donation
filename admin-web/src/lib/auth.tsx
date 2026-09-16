// auth.tsx — the signed-in admin's identity, as a context plus the hook that
// reads it.
//
// The <AuthProvider> and <RequireAuth> components live in AuthProvider.tsx.
// They are split because a file that exports a component may not also export a
// hook or a context: fast refresh recreates a module's bindings on every edit,
// so a context declared beside a component would be swapped for a brand-new
// one and every Provider/consumer pair would come apart mid-session
// (react-refresh/only-export-components). useAuth is imported by two dozen
// files and the two components by three, so the hook kept the module name.

import { createContext, useContext } from 'react'
import type { StoredUser } from './api'

export type AuthCtx = {
  user: StoredUser | null
  isAuthenticated: boolean
  login: (token: string, user: StoredUser) => void
  logout: () => Promise<void>
}

export const AuthContext = createContext<AuthCtx | null>(null)

export function useAuth(): AuthCtx {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>')
  return ctx
}

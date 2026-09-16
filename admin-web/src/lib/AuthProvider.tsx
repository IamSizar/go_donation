// AuthProvider.tsx — the two auth components.
//
// Split out of auth.tsx so that file can keep exporting the context and the
// useAuth hook without mixing them with component exports (see the note
// there). Behaviour is unchanged.

import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'
import { Navigate, useLocation } from 'react-router-dom'
import { api, getStoredUser, getToken, setStoredUser, setToken, type StoredUser } from './api'
import { AuthContext, useAuth, type AuthCtx } from './auth'

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<StoredUser | null>(() => getStoredUser())

  const login = useCallback((token: string, u: StoredUser) => {
    setToken(token)
    setStoredUser(u)
    setUser(u)
  }, [])

  const logout = useCallback(async () => {
    try {
      await api.post('/api/auth/logout')
    } catch {
      // best-effort
    }
    setToken(null)
    setStoredUser(null)
    setUser(null)
  }, [])

  // Cross-tab sync: another tab logging out should reflect here.
  useEffect(() => {
    const onStorage = () => setUser(getStoredUser())
    window.addEventListener('storage', onStorage)
    return () => window.removeEventListener('storage', onStorage)
  }, [])

  const value = useMemo<AuthCtx>(
    () => ({ user, isAuthenticated: !!user && !!getToken(), login, logout }),
    [user, login, logout],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function RequireAuth({ children }: { children: ReactNode }) {
  const { isAuthenticated } = useAuth()
  const location = useLocation()
  if (!isAuthenticated) {
    return <Navigate to="/login" state={{ from: location }} replace />
  }
  return <>{children}</>
}

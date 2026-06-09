import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { Navigate, useLocation } from 'react-router-dom'
import { api, getStoredUser, getToken, setStoredUser, setToken, type StoredUser } from './api'

type AuthCtx = {
  user: StoredUser | null
  isAuthenticated: boolean
  login: (token: string, user: StoredUser) => void
  logout: () => Promise<void>
}

const AuthContext = createContext<AuthCtx | null>(null)

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

export function useAuth(): AuthCtx {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>')
  return ctx
}

export function RequireAuth({ children }: { children: ReactNode }) {
  const { isAuthenticated } = useAuth()
  const location = useLocation()
  if (!isAuthenticated) {
    return <Navigate to="/login" state={{ from: location }} replace />
  }
  return <>{children}</>
}

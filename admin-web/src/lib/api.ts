import axios, { AxiosError } from 'axios'

const TOKEN_KEY = 'humanitarian.admin.token'
const USER_KEY = 'humanitarian.admin.user'

export type StoredUser = {
  user_id: number
  phone: string
  role_id: number | null
  is_admin: number  // 1 = admin, 0 = not
}

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY)
}

export function setToken(token: string | null) {
  if (token) localStorage.setItem(TOKEN_KEY, token)
  else localStorage.removeItem(TOKEN_KEY)
}

export function getStoredUser(): StoredUser | null {
  const raw = localStorage.getItem(USER_KEY)
  if (!raw) return null
  try {
    return JSON.parse(raw) as StoredUser
  } catch {
    return null
  }
}

export function setStoredUser(user: StoredUser | null) {
  if (user) localStorage.setItem(USER_KEY, JSON.stringify(user))
  else localStorage.removeItem(USER_KEY)
}

export const api = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL || '',
  timeout: 15000,
})

// Attach Bearer token automatically.
api.interceptors.request.use((config) => {
  const token = getToken()
  if (token) {
    config.headers = config.headers ?? {}
    config.headers['Authorization'] = `Bearer ${token}`
  }
  return config
})

// Auto-logout on 401 (except for the login/OTP endpoints themselves).
api.interceptors.response.use(
  (res) => res,
  (err: AxiosError) => {
    if (err.response?.status === 401) {
      const url = err.config?.url ?? ''
      const isAuthEntry =
        url.includes('/api/auth/login') ||
        url.includes('/api/auth/otp/')
      if (!isAuthEntry) {
        setToken(null)
        setStoredUser(null)
        if (window.location.pathname !== '/login') {
          window.location.href = '/login'
        }
      }
    }
    return Promise.reject(err)
  },
)

// Tiny helper: convert axios errors into a flat message string.
export function describeError(err: unknown): string {
  if (axios.isAxiosError(err)) {
    const data = err.response?.data as { error?: string; details?: string } | undefined
    if (data?.error) return data.error
    if (data?.details) return data.details
    return err.message
  }
  if (err instanceof Error) return err.message
  return 'Unknown error.'
}

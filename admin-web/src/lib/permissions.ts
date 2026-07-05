// Section 24 — client-side access to the effective per-module/per-action
// permission matrix for the CURRENT staff user (tier defaults + Super-Admin
// overrides), served by GET /api/admin/permissions/me.
//
// The matrix is fetched once and cached at module scope, so the many places
// that ask "can this tier export donations?" share a single request.
import { useEffect, useState } from 'react'
import { api, canExportData, type StoredUser } from './api'

type PermMatrix = Record<string, Record<string, boolean>>

let cache: PermMatrix | null = null
let inflight: Promise<PermMatrix | null> | null = null

function fetchMatrix(): Promise<PermMatrix | null> {
  if (cache) return Promise.resolve(cache)
  if (!inflight) {
    inflight = api
      .get<{ permissions: PermMatrix }>('/api/admin/permissions/me')
      .then((r) => {
        cache = r.data?.permissions ?? {}
        return cache
      })
      // On failure return null WITHOUT caching — callers fall back to the tier
      // gate so a transient error never hides every export button.
      .catch(() => null)
      .finally(() => {
        inflight = null
      })
  }
  return inflight
}

/** Whether the current user may export `module`. Uses the effective matrix when
 *  loaded; falls back to the tier gate while loading or if the fetch failed. */
export function useExportAllowed(module: string, user: StoredUser | null): boolean {
  const [matrix, setMatrix] = useState<PermMatrix | null>(cache)
  useEffect(() => {
    let active = true
    fetchMatrix().then((m) => {
      if (active && m) setMatrix(m)
    })
    return () => {
      active = false
    }
  }, [])
  // Known module in the loaded matrix → use its export bit. Unknown module
  // (or matrix not loaded yet / fetch failed) → fall back to the tier gate.
  if (matrix && matrix[module]) return matrix[module].export === true
  return canExportData(user)
}

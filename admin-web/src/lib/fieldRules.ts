// fieldRules — Note 33. Generalizes what Note 32 built for the Beneficiary
// case form (originally lib/caseFieldRules.ts) into a reusable hook any
// admin create/edit form can use: fetch the Field Rules table once, and
// return each field's state (required / optional / hidden) filtered to
// fields with a given key prefix (e.g. "case_", "marriage_") — mirrors the
// prefix convention already used when seeding rows (migrations 045/054/056)
// so different forms' field keys never collide.
import { useEffect, useState } from 'react'
import { api } from './api'

export type FieldRuleState = 'required' | 'optional' | 'hidden'

type FieldRuleRow = { field_key: string; state: FieldRuleState; display_order: number }

// Returns a map of field key (WITHOUT the prefix, e.g. "public_title") →
// state, plus whether the initial fetch is still in flight. A field missing
// from the map (fetch not done yet, or the row was never seeded) is treated
// as "optional" by callers — same fallback as before Note 33.
export function useFieldRules(prefix: string): { state: Record<string, FieldRuleState>; loading: boolean } {
  const [state, setState] = useState<Record<string, FieldRuleState>>({})
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let cancelled = false
    api
      .get<{ items: FieldRuleRow[] }>('/api/admin/registration/field-rules')
      .then((r) => {
        if (cancelled) return
        const map: Record<string, FieldRuleState> = {}
        for (const row of r.data.items ?? []) {
          if (row.field_key.startsWith(prefix)) {
            map[row.field_key.slice(prefix.length)] = row.state
          }
        }
        setState(map)
      })
      .catch(() => { /* keep every field optional if this fails to load */ })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [prefix])

  return { state, loading }
}

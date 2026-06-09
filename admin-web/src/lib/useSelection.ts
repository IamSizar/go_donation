// useSelection — small hook the list pages share for row selection.
//
// Holds a Set<id>, exposes helpers that work with the row type, and a Set
// for the page to iterate when applying bulk actions.
//
// The hook does NOT keep selection in sync with the row list — if the page
// changes filter or paginates, the page is responsible for calling clear().
// In practice every list page resets selection inside the filter `onChange`.

import { useCallback, useState } from 'react'
import type { Selection } from '../components/Table'

export function useSelection<T>(getId: (row: T) => number) {
  const [selected, setSelected] = useState<Set<number>>(new Set())

  const toggle = useCallback(
    (row: T) => {
      setSelected((prev) => {
        const id = getId(row)
        const next = new Set(prev)
        if (next.has(id)) next.delete(id)
        else next.add(id)
        return next
      })
    },
    [getId],
  )

  const toggleAll = useCallback(
    (rows: T[]) => {
      setSelected((prev) => {
        const ids = rows.map(getId)
        const allOn = ids.length > 0 && ids.every((id) => prev.has(id))
        if (allOn) {
          // Remove just the current-page ids; keep selections from other pages
          const next = new Set(prev)
          ids.forEach((id) => next.delete(id))
          return next
        }
        const next = new Set(prev)
        ids.forEach((id) => next.add(id))
        return next
      })
    },
    [getId],
  )

  const clear = useCallback(() => setSelected(new Set()), [])

  // Build the Selection<T> the Table component expects, given the rows
  // currently rendered.
  const forRows = useCallback(
    (rows: T[]): Selection<T> => ({
      isSelected: (row) => selected.has(getId(row)),
      onToggle: toggle,
      onToggleAll: toggleAll,
      allSelected: rows.length > 0 && rows.every((r) => selected.has(getId(r))),
    }),
    [selected, getId, toggle, toggleAll],
  )

  return { selected, count: selected.size, clear, forRows, toggle, toggleAll }
}

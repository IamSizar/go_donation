// DialogHost.tsx — the rendering half of dialogs.ts.
//
// Split out so dialogs.tsx can keep exporting askForText/askToConfirm without
// mixing them with a component export (see the note there). Behaviour is
// unchanged.

import { useCallback, useEffect, useRef, useState } from 'react'
import { AnimatePresence } from 'framer-motion'
import AskDialog from '../components/AskDialog'
import {
  setDialogEnqueue,
  takeRequestId,
  type DialogAnswer,
  type Pending,
} from './dialogs'

/**
 * DialogHost — mount once at the app root, inside I18nProvider (the dialog
 * localizes its own buttons).
 *
 * Holds a FIFO queue rather than a single slot. Nothing in the app opens two
 * dialogs at once today — every caller awaits — but a dropped request would be
 * a promise that never settles, which is an await that hangs forever and a
 * frozen action. Queueing makes that unrepresentable.
 */
export function DialogHost() {
  const [queue, setQueue] = useState<Pending[]>([])
  // Guards against a double-settle (a click landing at the same time as an
  // Escape) resolving one request and dequeuing two.
  const settledIdRef = useRef<number | null>(null)

  useEffect(() => {
    setDialogEnqueue((request) =>
      new Promise<DialogAnswer>((resolve) => {
        setQueue((q) => [...q, { id: takeRequestId(), request, resolve }])
      }),
    )
    return () => {
      setDialogEnqueue(null)
    }
  }, [])

  const current = queue[0]

  const settle = useCallback(
    (answer: DialogAnswer) => {
      if (!current || settledIdRef.current === current.id) return
      settledIdRef.current = current.id
      current.resolve(answer)
      setQueue((q) => q.filter((p) => p.id !== current.id))
    },
    [current],
  )

  // AnimatePresence keeps the exit animation alive after the request leaves the
  // queue; the key makes a second queued dialog a fresh mount (fresh focus,
  // empty input) rather than a re-render of the previous one.
  return (
    <AnimatePresence>
      {current && <AskDialog key={current.id} request={current.request} onSettle={settle} />}
    </AnimatePresence>
  )
}

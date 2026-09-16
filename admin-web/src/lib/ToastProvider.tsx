// ToastProvider — owns the live toast list and renders the top-right host.
//
// Split out of toast.tsx so that file can keep exporting the context and the
// useToast hook without mixing them with a component export (see the note
// there). Behaviour is unchanged: push() appends a toast and removes it again
// after 4s.

import { useCallback, useMemo, useState, type ReactNode } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { ToastContext, type Toast, type ToastCtx, type ToastKind } from './toast'

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([])

  const push = useCallback((kind: ToastKind, message: string) => {
    const id = Date.now() + Math.random()
    setToasts((t) => [...t, { id, kind, message }])
    setTimeout(() => {
      setToasts((t) => t.filter((x) => x.id !== id))
    }, 4000)
  }, [])

  const value = useMemo<ToastCtx>(() => ({
    push,
    success: (m) => push('success', m),
    error:   (m) => push('error', m),
    info:    (m) => push('info', m),
  }), [push])

  return (
    <ToastContext.Provider value={value}>
      {children}
      <ToastHost toasts={toasts} onClose={(id) => setToasts((t) => t.filter((x) => x.id !== id))} />
    </ToastContext.Provider>
  )
}

function ToastHost({ toasts, onClose }: { toasts: Toast[]; onClose: (id: number) => void }) {
  return (
    <div className="toast-host">
      {/* AnimatePresence handles enter/exit per toast. `popLayout` lets the
          remaining toasts slide up to fill the gap when one dismisses. */}
      <AnimatePresence mode="popLayout" initial={false}>
        {toasts.map((t) => (
          <ToastItem key={t.id} toast={t} onClose={() => onClose(t.id)} />
        ))}
      </AnimatePresence>
    </div>
  )
}

function ToastItem({ toast, onClose }: { toast: Toast; onClose: () => void }) {
  return (
    <motion.div
      className={`toast toast-${toast.kind}`}
      onClick={onClose}
      role="status"
      // Slide in from the right; fade up out on dismiss. Layout makes the
      // surviving toasts spring into position when their neighbor disappears.
      layout
      initial={{ opacity: 0, x: 40, scale: 0.96 }}
      animate={{ opacity: 1, x: 0, scale: 1 }}
      exit={{ opacity: 0, x: 24, scale: 0.94, transition: { duration: 0.18 } }}
      transition={{ type: 'spring', stiffness: 320, damping: 26 }}
      whileHover={{ scale: 1.02 }}
    >
      <span className="toast-icon">
        {toast.kind === 'success' ? '✓' : toast.kind === 'error' ? '✕' : 'ℹ'}
      </span>
      <span className="toast-message">{toast.message}</span>
    </motion.div>
  )
}

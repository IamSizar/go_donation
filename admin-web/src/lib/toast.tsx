// Toast notifications — top-right pop-ups that auto-dismiss.
// Mount <ToastProvider /> once at the app root, then call useToast() from
// anywhere to push success/error messages.
//
// The context and the hook live here; the provider component lives in
// ToastProvider.tsx. They are split because a file that exports a component
// may not also export a hook or a context: fast refresh recreates a module's
// bindings on every edit, so a context declared beside a component would be
// swapped for a brand-new one and every Provider/consumer pair would come
// apart mid-session (react-refresh/only-export-components). useToast is
// imported by ~57 files and the provider by three, so the hook kept the
// module name.

import { createContext, useContext } from 'react'

export type ToastKind = 'success' | 'error' | 'info'

export type Toast = {
  id: number
  kind: ToastKind
  message: string
}

export type ToastCtx = {
  push: (kind: ToastKind, message: string) => void
  success: (message: string) => void
  error: (message: string) => void
  info: (message: string) => void
}

export const ToastContext = createContext<ToastCtx | null>(null)

export function useToast(): ToastCtx {
  const ctx = useContext(ToastContext)
  if (!ctx) throw new Error('useToast must be inside <ToastProvider>')
  return ctx
}

// pwa.ts — the app side of the Progressive Web App: service-worker
// registration, connectivity state, and the "install this app" prompt.
//
// The worker itself lives in public/sw.js (it must be served from the origin
// root to control the whole scope). Read the long header comment in that file
// before changing anything here — in particular the rule that no
// authenticated response is ever cached.
//
// WHY THE DASHBOARD IS A PWA AT ALL
// The owner runs this dashboard from a phone. Installed, it gets a home-screen
// icon, no browser chrome eating vertical space, and a shell that opens on a
// weak connection instead of a blank tab.

import { useCallback, useEffect, useState, useSyncExternalStore } from 'react'

// ─── Service-worker registration ────────────────────────────────────────

/**
 * Register /sw.js.
 *
 * Called once from main.tsx. Deliberately a no-op in development: a service
 * worker intercepting requests fights Vite's HMR, and the caching behaviour
 * that matters is the production behaviour anyway (verify it against
 * `npm run build && npm run preview`, not the dev server).
 *
 * Failures are logged and swallowed — a browser without service-worker support
 * (or a page served over plain HTTP on a LAN address) must still get a fully
 * working dashboard, just without offline support.
 */
export function registerServiceWorker(): void {
  if (!import.meta.env.PROD) return
  if (!('serviceWorker' in navigator)) return

  // Registered after `load` so the worker's install-time precache competes with
  // nothing for bandwidth during first paint.
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch((err) => {
      console.warn('[pwa] service worker registration failed', err)
    })
  })
}

// ─── Connectivity ───────────────────────────────────────────────────────

/** Subscribe to the browser's online/offline transitions. */
function subscribeToConnectivity(onChange: () => void): () => void {
  window.addEventListener('online', onChange)
  window.addEventListener('offline', onChange)
  return () => {
    window.removeEventListener('online', onChange)
    window.removeEventListener('offline', onChange)
  }
}

/**
 * Is the browser currently online?
 *
 * useSyncExternalStore rather than useState+useEffect: connectivity is external
 * state that can change between render and commit, and this reads it without
 * the extra render an effect-based mirror would cost.
 *
 * Caveat worth knowing: `navigator.onLine === true` only means the device has
 * *a* network interface up — it does not prove the API is reachable. So this
 * drives an "you are offline" banner (a true negative is reliable) and never
 * an "everything is fine" claim; individual screens still surface their own
 * request failures.
 */
export function useOnlineStatus(): boolean {
  return useSyncExternalStore(
    subscribeToConnectivity,
    () => navigator.onLine,
    // Server snapshot — unused (this SPA never renders on a server), but
    // required by the hook's contract. Assume online so nothing pre-renders
    // an offline banner.
    () => true,
  )
}

// ─── Install prompt ─────────────────────────────────────────────────────

/**
 * The non-standard event Chromium fires when the app meets the install
 * criteria. Typed locally because it is not in lib.dom.d.ts.
 */
type BeforeInstallPromptEvent = Event & {
  prompt: () => Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

/**
 * Expose the browser's install prompt as a button the admin can press.
 *
 * `canInstall` is false unless the browser has actually offered a prompt, so
 * the button never appears where it would do nothing — already-installed apps,
 * and iOS Safari, which has no such API (there the admin uses Share → Add to
 * Home Screen, and the manifest's apple-touch-icon covers the rest).
 *
 * @returns `canInstall` and a `promptInstall` that resolves once the admin has
 *          answered the browser's own dialog.
 */
export function useInstallPrompt(): { canInstall: boolean; promptInstall: () => Promise<void> } {
  const [deferred, setDeferred] = useState<BeforeInstallPromptEvent | null>(null)

  useEffect(() => {
    const onBeforeInstallPrompt = (e: Event) => {
      // Suppress Chromium's own mini-infobar so the prompt appears where we
      // put it (a labelled button in the topbar) rather than over the content.
      e.preventDefault()
      setDeferred(e as BeforeInstallPromptEvent)
    }
    // Once installed the saved event is spent — drop it so the button goes away
    // instead of firing a prompt the browser will ignore.
    const onInstalled = () => setDeferred(null)

    window.addEventListener('beforeinstallprompt', onBeforeInstallPrompt)
    window.addEventListener('appinstalled', onInstalled)
    return () => {
      window.removeEventListener('beforeinstallprompt', onBeforeInstallPrompt)
      window.removeEventListener('appinstalled', onInstalled)
    }
  }, [])

  const promptInstall = useCallback(async () => {
    if (!deferred) return
    await deferred.prompt()
    await deferred.userChoice
    // The event can only be used once, whatever the admin chose.
    setDeferred(null)
  }, [deferred])

  return { canInstall: deferred !== null, promptInstall }
}

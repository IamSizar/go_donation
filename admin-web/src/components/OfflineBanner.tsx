// OfflineBanner — a persistent, app-wide notice that the device has no
// network, so nothing on screen can be trusted to be current.
//
// WHY THIS EXISTS (and why it is not a toast)
// Installed as a PWA, the shell now opens from cache when the connection is
// dead. That is the point — but it creates a specific, dangerous lie: every
// list renders its empty state, and "No donations yet" over an unreachable API
// reads as a fact about the database rather than a fact about the phone's
// signal. A toast would fade after four seconds and leave that lie on screen.
// This does not disappear until the connection comes back.
//
// It complements, and does not replace, per-request error states: `useOnlineStatus`
// only knows whether the device has an interface up, so a reachable Wi-Fi with
// an unreachable API still shows nothing here — that case is caught by each
// list's own `error` + Retry (see Table.tsx).

import { WifiOff } from 'lucide-react'
import { useI18n } from '../lib/i18n'
import { useOnlineStatus } from '../lib/pwa'

export default function OfflineBanner() {
  const { t } = useI18n()
  const online = useOnlineStatus()

  if (online) return null

  return (
    // role="status" + aria-live="polite": a screen reader announces the change
    // when it happens without interrupting whatever is being read. assertive
    // would be wrong — losing signal is not an error the admin caused.
    <div className="offline-banner" role="status" aria-live="polite">
      <WifiOff size={16} strokeWidth={2.4} aria-hidden="true" />
      <div className="offline-banner-text">
        <strong>{t('pwa.offline_title')}</strong>
        <span>{t('pwa.offline_body')}</span>
      </div>
    </div>
  )
}

// InstallAppButton — topbar button that triggers the browser's own
// "install this app" flow.
//
// WHY A BUTTON RATHER THAN THE BROWSER'S DEFAULT PROMPT
// Chromium's built-in mini-infobar appears once, at a moment the admin did not
// choose, over whatever they were reading — and once dismissed it does not
// come back for months. A labelled control in the topbar is guidance the admin
// can act on when they want to (house rule 5.9: non-obvious features get
// contextual guidance).
//
// It renders NOTHING unless the browser has actually offered a prompt, so it is
// invisible once the app is installed, and on iOS Safari — which exposes no
// install API at all, and where the route is Share → Add to Home Screen.

import { Download } from 'lucide-react'
import { useI18n } from '../lib/i18n'
import { useInstallPrompt } from '../lib/pwa'

export default function InstallAppButton() {
  const { t } = useI18n()
  const { canInstall, promptInstall } = useInstallPrompt()

  if (!canInstall) return null

  return (
    <button
      type="button"
      className="secondary install-app-btn"
      onClick={promptInstall}
      title={t('pwa.install_title')}
      aria-label={t('pwa.install')}
    >
      <Download size={16} strokeWidth={2.3} aria-hidden="true" />
      {/* The label is hidden by CSS on narrow screens, the same way the
          top-action-bar buttons collapse to icons — the aria-label above keeps
          the button named for assistive tech either way. */}
      <span>{t('pwa.install')}</span>
    </button>
  )
}

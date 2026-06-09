// SoundMenu — speaker icon in the topbar with a dropdown for:
//   • Sound on / off  (persisted)
//   • Test chime
//   • Enable OS notifications (one-tap permission request)
//
// State lives in GlobalAlertsProvider — this component is just the UI.

import { useEffect, useRef, useState } from 'react'
import { useGlobalAlerts } from '../lib/globalAlerts'
import { useI18n } from '../lib/i18n'

export default function SoundMenu() {
  const { t } = useI18n()
  const {
    sound,
    setSound,
    audioUnlocked,
    osNotify,
    setOsNotify,
    notifPermission,
    requestOSNotifications,
    playTest,
  } = useGlobalAlerts()

  const [open, setOpen] = useState(false)
  const rootRef = useRef<HTMLDivElement>(null)

  // Close on outside click. Capture phase so we run before any other
  // popover handlers below us in the topbar.
  useEffect(() => {
    if (!open) return
    function onDown(e: MouseEvent) {
      if (!rootRef.current?.contains(e.target as Node)) setOpen(false)
    }
    function onEsc(e: KeyboardEvent) {
      if (e.key === 'Escape') setOpen(false)
    }
    window.addEventListener('pointerdown', onDown, true)
    window.addEventListener('keydown', onEsc)
    return () => {
      window.removeEventListener('pointerdown', onDown, true)
      window.removeEventListener('keydown', onEsc)
    }
  }, [open])

  // Icon decision:
  //   sound=on,  unlocked → 🔊 (emerald)
  //   sound=on,  locked   → 🔊 (amber, pulsing — "click to enable")
  //   sound=off           → 🔇 (neutral)
  const iconChar = sound ? '🔊' : '🔇'
  const btnClass =
    sound && !audioUnlocked ? 'sound-btn needs-unlock' :
    sound                   ? 'sound-btn is-on' :
                              'sound-btn'

  const title =
    sound && !audioUnlocked
      ? t('sound.manage_locked')
      : sound
      ? t('sound.manage_on')
      : t('sound.manage_off')

  return (
    <div className="sound-menu" ref={rootRef}>
      <button
        type="button"
        className={btnClass}
        title={title}
        aria-label={title}
        aria-expanded={open}
        aria-haspopup="menu"
        onClick={() => setOpen((v) => !v)}
      >
        {iconChar}
      </button>

      {open && (
        <div className="sound-popover" role="menu">
          <button
            type="button"
            className={sound ? 'is-active' : ''}
            role="menuitemradio"
            aria-checked={sound}
            onClick={() => { setSound(true); /* keep open so admin can hit Test */ }}
          >
            <span>{sound ? '✓' : ''}</span>
            <span>{t('sound.on')}</span>
          </button>
          <button
            type="button"
            className={!sound ? 'is-active' : ''}
            role="menuitemradio"
            aria-checked={!sound}
            onClick={() => { setSound(false) }}
          >
            <span>{!sound ? '✓' : ''}</span>
            <span>{t('sound.off')}</span>
          </button>
          <hr />
          <button type="button" onClick={() => { playTest() }}>
            <span aria-hidden="true">▶</span>
            <span>{t('sound.test')}</span>
          </button>
          {/* OS-notification toggle. Three states matter:
                  unsupported → hide entirely (very old browsers)
                  default     → "Enable when tab is hidden" (asks permission)
                  granted     → on/off toggle for osNotify
                  denied      → show greyed-out hint */}
          {notifPermission !== 'unsupported' && (
            <>
              <hr />
              {notifPermission === 'granted' ? (
                <button
                  type="button"
                  className={osNotify ? 'is-active' : ''}
                  onClick={() => setOsNotify(!osNotify)}
                >
                  <span>{osNotify ? '✓' : ''}</span>
                  <span>{t('sound.notify_hidden')}</span>
                </button>
              ) : notifPermission === 'denied' ? (
                <div className="sound-popover-hint">
                  {t('sound.denied')}
                </div>
              ) : (
                <button type="button" onClick={() => { void requestOSNotifications() }}>
                  <span aria-hidden="true">🔔</span>
                  <span>{t('sound.enable_hidden')}</span>
                </button>
              )}
            </>
          )}
          {sound && !audioUnlocked && (
            <div className="sound-popover-hint">
              {t('sound.unlock_hint')}
            </div>
          )}
        </div>
      )}
    </div>
  )
}

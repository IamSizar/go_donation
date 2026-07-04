import { useNavigate } from 'react-router-dom'
import { ArrowLeft, ArrowRight, RotateCw, Save } from 'lucide-react'
import { useI18n } from '../lib/i18n'

// Unified top action bar shown on every dashboard section (global notice #7).
// Back / Next use browser history; Refresh reloads the current view; Save fires
// a global 'app:save' event that any open form can listen for (it's a no-op on
// pages without a save action, so the button is always present and consistent).
export default function TopActionBar() {
  const navigate = useNavigate()
  const { t } = useI18n()

  const refresh = () => window.location.reload()
  const save = () => window.dispatchEvent(new CustomEvent('app:save'))

  return (
    <div className="top-action-bar" role="toolbar" aria-label={t('common.actions')}>
      <button className="secondary" onClick={() => navigate(-1)} title={t('toolbar.back')}>
        <ArrowLeft size={15} strokeWidth={2.2} />
        <span>{t('toolbar.back')}</span>
      </button>
      <button className="secondary" onClick={() => navigate(1)} title={t('toolbar.next')}>
        <span>{t('toolbar.next')}</span>
        <ArrowRight size={15} strokeWidth={2.2} />
      </button>
      <button className="secondary" onClick={refresh} title={t('toolbar.refresh')}>
        <RotateCw size={15} strokeWidth={2.2} />
        <span>{t('toolbar.refresh')}</span>
      </button>
      <div style={{ flex: 1 }} />
      <button className="primary" onClick={save} title={t('toolbar.save')}>
        <Save size={15} strokeWidth={2.2} />
        <span>{t('toolbar.save')}</span>
      </button>
    </div>
  )
}

import { useLocation } from 'react-router-dom'
import { useI18n } from '../lib/i18n'

// Placeholder for sections that get implemented in Phase 5.
export default function PlaceholderPage({ title }: { title: string }) {
  const loc = useLocation()
  const { t } = useI18n()
  return (
    <div className="stack">
      <h1>{title}</h1>
      <p className="muted">
        {t('placeholder.body')}
      </p>
      <div className="card">
        <div className="muted">{t('placeholder.route', { path: loc.pathname })}</div>
      </div>
    </div>
  )
}

// BannedWordsPage — admin-managed banned-words blocklist (#25). A comment
// containing any of these words is held for review at submit time.
// GET /api/admin/banned-words · POST {word} · DELETE /:id
import { useEffect, useState } from 'react'
import { api, describeError } from '../lib/api'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import PageHead from '../components/PageHead'

type Word = { id: number; word: string; created_at: string }

export default function BannedWordsPage() {
  const { t } = useI18n()
  const toast = useToast()
  const [items, setItems] = useState<Word[]>([])
  // `loading` is derived from which reload tick last came back, so the fetch
  // effect below sets nothing synchronously. `reload()` bumps the tick, which
  // is what re-runs the effect.
  const [tick, setTick] = useState(0)
  const [loadedTick, setLoadedTick] = useState(-1)
  const loading = loadedTick !== tick
  const reload = () => setTick((n) => n + 1)
  const [err, setErr] = useState<string | null>(null)
  const [draft, setDraft] = useState('')
  const [adding, setAdding] = useState(false)

  const load = () => {
    api
      .get<{ items: Word[] }>('/api/admin/banned-words')
      .then((res) => {
        setItems(res.data.items ?? [])
        setErr(null)
      })
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoadedTick(tick))
  }
  useEffect(load, [tick])

  const add = async () => {
    if (!draft.trim()) {
      toast.error(t('bannedWords.need_word'))
      return
    }
    setAdding(true)
    try {
      await api.post('/api/admin/banned-words', { word: draft.trim() })
      toast.success(t('bannedWords.added'))
      setDraft('')
      reload()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setAdding(false)
    }
  }

  const remove = async (id: number) => {
    try {
      await api.delete(`/api/admin/banned-words/${id}`)
      toast.success(t('bannedWords.deleted'))
      reload()
    } catch (e) {
      toast.error(describeError(e))
    }
  }

  return (
    <div className="stack">
      <PageHead>
        <div>
          <h1>{t('bannedWords.title')}</h1>
          <p className="muted">{t('bannedWords.subtitle')}</p>
        </div>
      </PageHead>

      {err && <div className="error-box">{err}</div>}

      <div className="card">
        <h3>{t('bannedWords.add_new')}</h3>
        <div style={{ display: 'flex', gap: 8 }}>
          <input
            type="text"
            value={draft}
            placeholder={t('bannedWords.placeholder')}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') add() }}
            style={{ flex: 1 }}
          />
          <button className="btn primary" onClick={add} disabled={adding}>
            {adding ? t('common.saving') : t('bannedWords.add_new')}
          </button>
        </div>
      </div>

      {loading && <p className="muted">{t('common.loading')}</p>}
      {!loading && items.length === 0 && <p className="muted">{t('bannedWords.empty')}</p>}

      {!loading && items.length > 0 && (
        <div className="card">
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
            {items.map((w) => (
              <span
                key={w.id}
                className="badge"
                style={{ display: 'inline-flex', alignItems: 'center', gap: 6, padding: '6px 10px' }}
              >
                {w.word}
                <button
                  className="icon"
                  title={t('common.delete')}
                  onClick={() => remove(w.id)}
                  style={{ border: 'none', background: 'transparent', cursor: 'pointer' }}
                >
                  ✕
                </button>
              </span>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

// TasksPage — client note "Task Verification". Staff assign a task (title +
// description) to a user by id; the user sees it in the app and marks it
// done themselves. GET/POST/DELETE /api/admin/tasks.
import { useEffect, useState } from 'react'
import { api, describeError } from '../lib/api'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'

type Task = {
  id: number
  user_id: number
  title: string
  description: string
  status: 'pending' | 'completed'
  created_at: string
  completed_at?: string | null
}

export default function TasksPage() {
  const { t } = useI18n()
  const toast = useToast()
  const [items, setItems] = useState<Task[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [assigning, setAssigning] = useState(false)
  const [userId, setUserId] = useState('')
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')

  const load = () => {
    setLoading(true)
    api
      .get<{ tasks: Task[] }>('/api/admin/tasks')
      .then((res) => {
        setItems(res.data.tasks ?? [])
        setErr(null)
      })
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoading(false))
  }
  useEffect(load, [])

  const assign = async () => {
    const uid = Number(userId)
    if (!uid || uid <= 0) {
      toast.error(t('tasks.need_user_id'))
      return
    }
    if (!title.trim()) {
      toast.error(t('tasks.need_title'))
      return
    }
    setAssigning(true)
    try {
      await api.post('/api/admin/tasks', { user_id: uid, title, description })
      toast.success(t('tasks.assigned'))
      setUserId('')
      setTitle('')
      setDescription('')
      load()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setAssigning(false)
    }
  }

  const remove = async (id: number) => {
    if (!window.confirm(t('tasks.confirm_delete'))) return
    try {
      await api.delete(`/api/admin/tasks/${id}`)
      toast.success(t('tasks.deleted'))
      load()
    } catch (e) {
      toast.error(describeError(e))
    }
  }

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('tasks.title')}</h1>
          <p className="muted">{t('tasks.subtitle')}</p>
        </div>
      </div>

      {err && <div className="error-box">{err}</div>}

      <div className="card">
        <h3>{t('tasks.assign_new')}</h3>
        <label className="field">
          <span className="muted">{t('tasks.user_id')}</span>
          <input
            type="number"
            dir="ltr"
            value={userId}
            onChange={(e) => setUserId(e.target.value)}
            placeholder={t('tasks.user_id_hint')}
          />
        </label>
        <label className="field">
          <span className="muted">{t('tasks.field_title')}</span>
          <input type="text" value={title} onChange={(e) => setTitle(e.target.value)} />
        </label>
        <label className="field">
          <span className="muted">{t('tasks.field_description')}</span>
          <textarea rows={3} value={description} onChange={(e) => setDescription(e.target.value)} />
        </label>
        <button className="btn primary" onClick={assign} disabled={assigning}>
          {assigning ? t('common.saving') : t('tasks.assign_new')}
        </button>
      </div>

      {loading && <p className="muted">{t('common.loading')}</p>}

      {!loading && items.length === 0 && <p className="muted">{t('tasks.empty')}</p>}

      {!loading &&
        items.map((task) => (
          <div className="card" key={task.id}>
            <div className="page-head">
              <h3>{task.title}</h3>
              <span className={`badge tone-${task.status === 'completed' ? 'success' : 'warning'}`}>
                {task.status === 'completed' ? t('tasks.status_completed') : t('tasks.status_pending')}
              </span>
            </div>
            {task.description && <p className="muted">{task.description}</p>}
            <p className="muted">
              {t('tasks.assigned_to')}: #{task.user_id} · {new Date(task.created_at).toLocaleString()}
            </p>
            <div style={{ display: 'flex', gap: 8 }}>
              <button className="btn danger" onClick={() => remove(task.id)}>
                {t('common.delete')}
              </button>
            </div>
          </div>
        ))}
    </div>
  )
}

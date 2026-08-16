// TasksPage — client note "Task Verification". Staff assign a task (title +
// description) to one person or to several at once (#5); each assignee sees it
// in the app and marks their own copy done.
// GET/POST/DELETE /api/admin/tasks.
import { useEffect, useMemo, useState } from 'react'
import { api, describeError } from '../lib/api'
import { askToConfirm } from '../lib/dialogs'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import PageHead from '../components/PageHead'
import UserPicker, { type PickedUser } from '../components/UserPicker'
import { fmtId } from '../lib/formatId'
import { formatDateTime } from '../lib/dates'

type Task = {
  id: number
  user_id: number
  title: string
  description: string
  status: 'pending' | 'completed'
  // Rows sharing a group_id were assigned together. Absent on tasks created
  // before migration 095, which are groups of one.
  group_id?: number | null
  created_at: string
  completed_at?: string | null
}

/** One card in the list: a task and everyone it was assigned to. */
type Group = {
  key: string
  title: string
  description: string
  created_at: string
  members: Task[]
}

/** Collapse rows into cards, preserving the newest-first order the API sent. */
function groupTasks(items: Task[]): Group[] {
  const out: Group[] = []
  const byKey = new Map<string, Group>()
  for (const it of items) {
    // An ungrouped row keys on its own id, so it stands alone — and can never
    // collide with a real group_id, which keys on the other prefix.
    const key = it.group_id ? `g${it.group_id}` : `t${it.id}`
    let g = byKey.get(key)
    if (!g) {
      g = {
        key,
        title: it.title,
        description: it.description,
        created_at: it.created_at,
        members: [],
      }
      byKey.set(key, g)
      out.push(g)
    }
    g.members.push(it)
  }
  return out
}

export default function TasksPage() {
  const { t } = useI18n()
  const toast = useToast()
  const [items, setItems] = useState<Task[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [assigning, setAssigning] = useState(false)
  // The people this task is going to. UserPicker picks one at a time; each
  // pick lands here as a chip and resets the picker for the next one.
  const [assignees, setAssignees] = useState<PickedUser[]>([])
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

  const groups = useMemo(() => groupTasks(items), [items])

  const addAssignee = (u: PickedUser | null) => {
    if (!u) return
    setAssignees((prev) => (prev.some((p) => p.user_id === u.user_id) ? prev : [...prev, u]))
  }

  const assign = async () => {
    if (assignees.length === 0) {
      toast.error(t('tasks.need_assignee'))
      return
    }
    if (!title.trim()) {
      toast.error(t('tasks.need_title'))
      return
    }
    setAssigning(true)
    try {
      await api.post('/api/admin/tasks', {
        user_ids: assignees.map((a) => a.user_id),
        title,
        description,
      })
      toast.success(t('tasks.assigned'))
      setAssignees([])
      setTitle('')
      setDescription('')
      load()
    } catch (e) {
      toast.error(describeError(e))
    } finally {
      setAssigning(false)
    }
  }

  // Deleting one member of a group unassigns that person only; deleting the
  // whole group removes it from everyone. Both are spelled out in the
  // confirmation so an admin can't mistake one for the other.
  const removeRows = async (rows: Task[], confirmKey: string) => {
    if (!(await askToConfirm({ message: t(confirmKey, { count: rows.length }), destructive: true }))) return
    try {
      await Promise.all(rows.map((r) => api.delete(`/api/admin/tasks/${r.id}`)))
      toast.success(t('tasks.deleted'))
      load()
    } catch (e) {
      toast.error(describeError(e))
    }
  }

  return (
    <div className="stack">
      <PageHead>
        <div>
          <h1>{t('tasks.title')}</h1>
          <p className="muted">{t('tasks.subtitle')}</p>
        </div>
      </PageHead>

      {err && <div className="error-box">{err}</div>}

      <div className="card">
        <h3>{t('tasks.assign_new')}</h3>

        <label className="field">
          <span className="muted">{t('tasks.assignees')}</span>
          {assignees.length > 0 && (
            <div className="row assignee-chips">
              {assignees.map((a) => (
                <span className="badge tone-primary assignee-chip" key={a.user_id}>
                  {a.full_name || a.phone || fmtId(a.user_id)}
                  <button
                    type="button"
                    className="icon"
                    aria-label={t('common.remove')}
                    disabled={assigning}
                    onClick={() =>
                      setAssignees((prev) => prev.filter((p) => p.user_id !== a.user_id))
                    }
                  >
                    ✕
                  </button>
                </span>
              ))}
            </div>
          )}
          <UserPicker
            value={null}
            onChange={addAssignee}
            disabled={assigning}
            placeholder={t('tasks.add_assignee')}
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
          {assigning
            ? t('common.saving')
            : assignees.length > 1
              ? t('tasks.assign_to_count', { count: assignees.length })
              : t('tasks.assign_new')}
        </button>
      </div>

      {loading && <p className="muted">{t('common.loading')}</p>}

      {!loading && groups.length === 0 && <p className="muted">{t('tasks.empty')}</p>}

      {!loading &&
        groups.map((g) => {
          const done = g.members.filter((m) => m.status === 'completed').length
          const all = done === g.members.length
          return (
            <div className="card" key={g.key}>
              <div className="page-head">
                <h3>{g.title}</h3>
                <span className={`badge tone-${all ? 'success' : 'warning'}`}>
                  {g.members.length > 1
                    ? t('tasks.done_of', { done, total: g.members.length })
                    : all
                      ? t('tasks.status_completed')
                      : t('tasks.status_pending')}
                </span>
              </div>
              {g.description && <p className="muted">{g.description}</p>}
              <p className="muted">{formatDateTime(g.created_at)}</p>

              <div className="stack task-members">
                {g.members.map((m) => (
                  <div className="row task-member" key={m.id}>
                    <span className={`badge tone-${m.status === 'completed' ? 'success' : 'warning'}`}>
                      {m.status === 'completed' ? t('tasks.status_completed') : t('tasks.status_pending')}
                    </span>
                    <span>{fmtId(m.user_id)}</span>
                    {m.completed_at && <span className="muted">{formatDateTime(m.completed_at)}</span>}
                    {g.members.length > 1 && (
                      <button
                        type="button"
                        className="secondary task-member-remove"
                        onClick={() => removeRows([m], 'tasks.confirm_delete_one')}
                      >
                        {t('tasks.unassign')}
                      </button>
                    )}
                  </div>
                ))}
              </div>

              <div style={{ display: 'flex', gap: 8 }}>
                <button
                  className="btn danger"
                  onClick={() =>
                    removeRows(
                      g.members,
                      g.members.length > 1 ? 'tasks.confirm_delete_group' : 'tasks.confirm_delete',
                    )
                  }
                >
                  {t('common.delete')}
                </button>
              </div>
            </div>
          )
        })}
    </div>
  )
}

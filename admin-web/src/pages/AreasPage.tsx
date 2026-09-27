// AreasPage — cities, districts (أقضية) and sub-districts (نواحي) for each of
// the 18 governorates (migration 136, client meeting).
//
// The governorates stay fixed (the app's list); everything under them is
// managed here as three linked columns: pick a governorate, its cities list;
// pick a city, its districts list; pick a district, its sub-districts list.
// Each column adds / edits (4 languages) / hides / reorders / deletes its own
// level. What is hidden here disappears from the app's pickers — a hidden
// city takes its districts and sub-districts with it.
//
// GET /api/admin/areas?governorate= · POST · PATCH /:id · POST /reorder · DELETE /:id
import { useCallback, useEffect, useMemo, useState } from 'react'
import axios from 'axios'
import { api, describeError, getStoredUser, isAdminLevel } from '../lib/api'
import { askToConfirm } from '../lib/dialogs'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import PageHead from '../components/PageHead'
import EditModal, { type FieldSpec } from '../components/EditModal'
import ActionsMenu from '../components/ActionsMenu'

/** The app's fixed governorate keys (humanitarian/lib/data/iraq_governorates.dart),
 *  in the app's order — the backend only accepts these. */
const GOVERNORATES: { key: string; ar: string }[] = [
  { key: 'Baghdad', ar: 'بغداد' },
  { key: 'Basra', ar: 'البصرة' },
  { key: 'Nineveh', ar: 'نينوى' },
  { key: 'Erbil', ar: 'أربيل' },
  { key: 'Sulaymaniyah', ar: 'السليمانية' },
  { key: 'Duhok', ar: 'دهوك' },
  { key: 'Kirkuk', ar: 'كركوك' },
  { key: 'Anbar', ar: 'الأنبار' },
  { key: 'Najaf', ar: 'النجف' },
  { key: 'Karbala', ar: 'كربلاء' },
  { key: 'Wasit', ar: 'واسط' },
  { key: 'Babil', ar: 'بابل' },
  { key: 'Diyala', ar: 'ديالى' },
  { key: 'Salah al-Din', ar: 'صلاح الدين' },
  { key: 'Dhi Qar', ar: 'ذي قار' },
  { key: 'Maysan', ar: 'ميسان' },
  { key: 'Muthanna', ar: 'المثنى' },
  { key: 'Al-Qadisiyyah', ar: 'القادسية' },
]

type Level = 'city' | 'district' | 'subdistrict'

type Area = {
  id: number
  governorate: string
  parent_id: number | null
  level: Level
  name_en: string
  name_ar: string
  name_ckb: string
  name_kmr: string
  display_order: number
  active: boolean
  children: number
}

const NAME_FIELDS: FieldSpec[] = [
  { key: 'name_ar', label: 'Arabic name', labelKey: 'page.areas.name_ar', type: 'text', required: true, dir: 'rtl' },
  { key: 'name_en', label: 'English name', labelKey: 'page.areas.name_en', type: 'text', dir: 'ltr' },
  { key: 'name_ckb', label: 'Sorani name', labelKey: 'page.areas.name_ckb', type: 'text', dir: 'rtl' },
  { key: 'name_kmr', label: 'Badini name', labelKey: 'page.areas.name_kmr', type: 'text', dir: 'rtl' },
]

function displayName(a: Area): string {
  return a.name_ar || a.name_en || `#${a.id}`
}

export default function AreasPage() {
  const { t } = useI18n()
  const toast = useToast()
  const canEdit = isAdminLevel(getStoredUser())
  const [gov, setGov] = useState(GOVERNORATES[0].key)
  const [items, setItems] = useState<Area[]>([])
  const [tick, setTick] = useState(0)
  const [loadedKey, setLoadedKey] = useState<string | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [cityId, setCityId] = useState<number | null>(null)
  const [districtId, setDistrictId] = useState<number | null>(null)
  // The add / edit dialog: which level, under which parent, and (edit) which row.
  const [editor, setEditor] = useState<{ level: Level; parentId: number | null; row: Area | null } | null>(null)

  const requestKey = `${gov}|${tick}`
  const loading = loadedKey !== requestKey
  const reload = () => setTick((n) => n + 1)

  const load = useCallback(() => {
    api
      .get<{ items: Area[] }>('/api/admin/areas', { params: { governorate: gov } })
      .then((res) => { setItems(res.data.items ?? []); setErr(null) })
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoadedKey(requestKey))
  }, [gov, requestKey])
  useEffect(load, [load])

  const cities = useMemo(() => items.filter((a) => a.level === 'city'), [items])
  const districts = useMemo(
    () => (cityId == null ? [] : items.filter((a) => a.level === 'district' && a.parent_id === cityId)),
    [items, cityId],
  )
  const subdistricts = useMemo(
    () => (districtId == null ? [] : items.filter((a) => a.level === 'subdistrict' && a.parent_id === districtId)),
    [items, districtId],
  )
  // A selection that no longer exists (deleted, or another governorate) is
  // treated as no selection rather than showing an orphan column.
  const city = cities.find((c) => c.id === cityId) ?? null
  const district = districts.find((d) => d.id === districtId) ?? null

  const changeGov = (g: string) => {
    setGov(g)
    setCityId(null)
    setDistrictId(null)
  }

  const save = async (patch: Record<string, unknown>) => {
    if (!editor) return
    if (editor.row) {
      await api.patch(`/api/admin/areas/${editor.row.id}`, { ...editor.row, ...patch })
      toast.success(t('page.areas.saved'))
    } else {
      await api.post('/api/admin/areas', {
        governorate: gov,
        level: editor.level,
        parent_id: editor.parentId,
        ...patch,
      })
      toast.success(t('page.areas.added'))
    }
    reload()
  }

  const toggleActive = async (a: Area) => {
    try {
      await api.patch(`/api/admin/areas/${a.id}`, { ...a, active: !a.active })
      reload()
    } catch (e) {
      toast.error(describeError(e))
    }
  }

  const move = async (list: Area[], index: number, dir: -1 | 1) => {
    const next = [...list]
    const j = index + dir
    if (j < 0 || j >= next.length) return
    ;[next[index], next[j]] = [next[j], next[index]]
    try {
      await api.post('/api/admin/areas/reorder', { ids: next.map((a) => a.id) })
      reload()
    } catch (e) {
      toast.error(describeError(e))
    }
  }

  const remove = async (a: Area) => {
    if (a.children > 0) {
      toast.error(t(`page.areas.has_children_${a.level}`))
      return
    }
    if (!(await askToConfirm({ message: t('page.areas.confirm_delete', { name: displayName(a) }), destructive: true }))) return
    try {
      await api.delete(`/api/admin/areas/${a.id}`)
      toast.success(t('page.areas.deleted'))
      if (a.id === cityId) { setCityId(null); setDistrictId(null) }
      if (a.id === districtId) setDistrictId(null)
      reload()
    } catch (e) {
      if (axios.isAxiosError(e) && e.response?.data?.code === 'has_children') {
        toast.error(t(`page.areas.has_children_${a.level}`))
      } else {
        toast.error(describeError(e))
      }
    }
  }

  const govAr = GOVERNORATES.find((g) => g.key === gov)?.ar ?? gov

  // One column. `parent` is the row the list hangs off (null for cities);
  // `blocked` is the hint shown when there is no parent picked yet.
  const column = (
    level: Level,
    list: Area[],
    parentId: number | null,
    title: string,
    blocked: string | null,
    selectedId: number | null,
    onSelect: ((a: Area) => void) | null,
  ) => (
    <section className="card areas-col" aria-label={title}>
      <header className="areas-col-head">
        <div>
          <h2>{title}</h2>
          {!blocked && <span className="muted">{t('page.areas.count', { n: list.length })}</span>}
        </div>
        {canEdit && !blocked && (
          <button type="button" onClick={() => setEditor({ level, parentId, row: null })}>
            {t(`page.areas.add_${level}`)}
          </button>
        )}
      </header>
      {blocked ? (
        <p className="muted areas-empty">{blocked}</p>
      ) : list.length === 0 ? (
        <p className="muted areas-empty">{t(`page.areas.empty_${level}`)}</p>
      ) : (
        <ul className="areas-list">
          {list.map((a, i) => {
            const selected = a.id === selectedId
            return (
              <li
                key={a.id}
                className={`areas-row${selected ? ' selected' : ''}${a.active ? '' : ' inactive'}`}
              >
                <button
                  type="button"
                  className="areas-row-main"
                  onClick={onSelect ? () => onSelect(a) : undefined}
                  disabled={!onSelect}
                  aria-pressed={onSelect ? selected : undefined}
                >
                  <span className="areas-row-text">
                    <span className="areas-row-name">{displayName(a)}</span>
                    {a.name_en && a.name_ar && <span className="areas-row-sub" dir="ltr">{a.name_en}</span>}
                  </span>
                  <span className="areas-row-badges">
                    {!a.active && <span className="badge off">{t('page.areas.hidden')}</span>}
                    {level !== 'subdistrict' && (
                      <span className="badge">{t(`page.areas.children_${level}`, { n: a.children })}</span>
                    )}
                  </span>
                </button>
                {canEdit && (
                  <span className="areas-row-actions">
                    <ActionsMenu
                      items={[
                        { key: 'edit', label: t('common.edit'), onClick: () => setEditor({ level, parentId, row: a }) },
                        { key: 'toggle', label: a.active ? t('page.areas.hide') : t('page.areas.show'), onClick: () => toggleActive(a) },
                        { key: 'up', label: t('page.areas.move_up'), onClick: () => move(list, i, -1), disabled: i === 0 },
                        { key: 'down', label: t('page.areas.move_down'), onClick: () => move(list, i, 1), disabled: i === list.length - 1 },
                        { key: 'delete', label: t('common.delete'), onClick: () => remove(a), danger: true },
                      ]}
                    />
                  </span>
                )}
              </li>
            )
          })}
        </ul>
      )}
    </section>
  )

  return (
    <div className="stack">
      <PageHead>
        <div>
          <h1>{t('page.areas.title')}</h1>
          <p className="muted">{t('page.areas.subtitle')}</p>
        </div>
        <div className="row">
          <label className="muted" htmlFor="areas-gov">{t('page.areas.governorate')}</label>
          <select id="areas-gov" value={gov} onChange={(e) => changeGov(e.target.value)} style={{ width: 'auto' }}>
            {GOVERNORATES.map((g) => (
              <option key={g.key} value={g.key}>{g.ar}</option>
            ))}
          </select>
        </div>
      </PageHead>

      {err && <div className="error-box">{err}</div>}
      {!canEdit && <p className="muted">{t('page.areas.read_only')}</p>}

      {loading && items.length === 0 ? (
        <p className="muted">{t('common.loading')}</p>
      ) : (
        <div className="areas-grid">
          {column('city', cities, null, t('page.areas.col_city', { gov: govAr }), null, cityId,
            (a) => { setCityId(a.id); setDistrictId(null) })}
          {column('district', districts, city?.id ?? null,
            city ? t('page.areas.col_district', { city: displayName(city) }) : t('page.areas.col_district_plain'),
            city ? null : t('page.areas.pick_city'), districtId, (a) => setDistrictId(a.id))}
          {column('subdistrict', subdistricts, district?.id ?? null,
            district ? t('page.areas.col_subdistrict', { district: displayName(district) }) : t('page.areas.col_subdistrict_plain'),
            district ? null : t('page.areas.pick_district'), null, null)}
        </div>
      )}

      <EditModal
        open={editor !== null}
        mode={editor?.row ? 'edit' : 'create'}
        title={editor ? t(editor.row ? `page.areas.edit_${editor.level}` : `page.areas.new_${editor.level}`) : ''}
        initial={editor?.row ? { ...editor.row } : { name_ar: '', name_en: '', name_ckb: '', name_kmr: '' }}
        fields={NAME_FIELDS}
        onSave={save}
        onClose={() => setEditor(null)}
      />
    </div>
  )
}

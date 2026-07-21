// FieldRulesPage — admin sets whether each data field is Required, Optional,
// or Hidden (#43, extended by Note #33). Loads
// GET /api/admin/registration/field-rules and updates each via
// POST /api/admin/registration/field-rules/:key with {state}.
import { useEffect, useState } from 'react'
import { api, describeError } from '../lib/api'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'

type FieldRuleState = 'required' | 'optional' | 'hidden'
type Rule = { field_key: string; state: FieldRuleState; display_order: number }

// Humanize a field_key for display (admin-facing).
const humanize = (k: string) =>
  k.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())

// Note #32 — the beneficiary Add Case form's fields are seeded here with a
// "case_" prefix (migration 054) so a Super-Admin can toggle each one
// Required/Optional. They reuse the exact same field.* labels the Add Case
// form itself shows, instead of a humanized raw key, so an admin recognizes
// them as the same fields they see in that form.
const CASE_PREFIX = 'case_'
const CASE_FIELD_LABEL_KEYS: Record<string, string> = {
  public_title: 'field.public_title_en',
  full_name: 'field.full_name',
  national_id: 'field.national_id',
  gender: 'field.gender',
  date_of_birth: 'field.date_of_birth',
  marital_status: 'field.marital_status',
  phone: 'field.phone',
  governorate: 'field.governorate',
  district: 'field.district',
  address: 'field.address',
  family_members_count: 'field.family_members',
  income_amount: 'field.income_amount',
  housing_status: 'field.housing_status',
  work_status: 'field.work_status',
  health_status: 'field.health_status',
  education_status: 'field.education_status',
  actual_needs: 'field.actual_needs',
}

// Note #33 — the Marriage/Engagement form's applicant-data fields, seeded
// with a "marriage_" prefix (migration 056). Same label-reuse pattern as
// the case fields above.
const MARRIAGE_PREFIX = 'marriage_'
const MARRIAGE_FIELD_LABEL_KEYS: Record<string, string> = {
  gender: 'field.gender',
  age: 'dbfield.age',
  city: 'field.city',
  social_summary: 'field.social_summary',
  private_notes: 'field.private_notes',
}

// Note #34 — the dashboard's "Add New User" window's applicant-data fields,
// seeded with a "user_" prefix (migration 057). Kept independent from the
// un-prefixed general registration rules above since this is a separate,
// admin-only screen.
const NEW_USER_PREFIX = 'user_'
const NEW_USER_FIELD_LABEL_KEYS: Record<string, string> = {
  full_name: 'field.full_name',
  gender: 'field.gender',
  date_of_birth: 'field.date_of_birth',
  address: 'field.address',
  city: 'field.city',
  occupation: 'field.occupation',
  housing_status: 'field.housing_status',
  family_size: 'field.family_size',
  monthly_income: 'field.monthly_income',
  availability: 'field.availability',
  experience: 'field.experience',
  skills: 'field.skills',
  profile_picture: 'field.profile_picture',
}

export default function FieldRulesPage() {
  const { t } = useI18n()
  const toast = useToast()
  const [items, setItems] = useState<Rule[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [savingKey, setSavingKey] = useState<string | null>(null)

  const load = () => {
    setLoading(true)
    api
      .get<{ items: Rule[] }>('/api/admin/registration/field-rules')
      .then((res) => { setItems(res.data.items ?? []); setErr(null) })
      .catch((e) => setErr(describeError(e)))
      .finally(() => setLoading(false))
  }
  useEffect(load, [])

  const setState = async (r: Rule, state: FieldRuleState) => {
    const prev = r.state
    setItems((xs) => xs.map((x) => (x.field_key === r.field_key ? { ...x, state } : x)))
    setSavingKey(r.field_key)
    try {
      await api.post(`/api/admin/registration/field-rules/${r.field_key}`, { state })
      toast.success(t('fieldRules.saved'))
    } catch (e) {
      toast.error(describeError(e))
      setItems((xs) => xs.map((x) => (x.field_key === r.field_key ? { ...x, state: prev } : x)))
    } finally {
      setSavingKey(null)
    }
  }

  const stateSelect = (r: Rule) => (
    <select
      value={r.state}
      disabled={savingKey === r.field_key}
      onChange={(e) => setState(r, e.target.value as FieldRuleState)}
      style={{ width: 'auto' }}
    >
      <option value="required">{t('fieldRules.required')}</option>
      <option value="optional">{t('fieldRules.optional')}</option>
      <option value="hidden">{t('fieldRules.hidden')}</option>
    </select>
  )

  const renderPrefixedSection = (prefix: string, labelKeys: Record<string, string>) =>
    items.filter((r) => r.field_key.startsWith(prefix)).map((r) => {
      const suffix = r.field_key.slice(prefix.length)
      const labelKey = labelKeys[suffix]
      return (
        <div className="card" key={r.field_key}>
          <label className="field" style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
            <span style={{ flex: 1 }}><strong>{labelKey ? t(labelKey) : humanize(suffix)}</strong></span>
            {stateSelect(r)}
          </label>
        </div>
      )
    })

  return (
    <div className="stack">
      <div className="page-head">
        <div>
          <h1>{t('fieldRules.title')}</h1>
          <p className="muted">{t('fieldRules.subtitle')}</p>
        </div>
      </div>

      {err && <div className="error-box">{err}</div>}
      {loading && <p className="muted">{t('common.loading')}</p>}

      {!loading && (
        <>
          <h3 style={{ margin: '8px 0 0' }}>{t('fieldRules.section_registration')}</h3>
          {items
            .filter((r) => !r.field_key.startsWith(CASE_PREFIX) && !r.field_key.startsWith(MARRIAGE_PREFIX) && !r.field_key.startsWith(NEW_USER_PREFIX))
            .map((r) => (
              <div className="card" key={r.field_key}>
                <label className="field" style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
                  <span style={{ flex: 1 }}><strong>{humanize(r.field_key)}</strong></span>
                  {stateSelect(r)}
                </label>
              </div>
            ))}

          <h3 style={{ margin: '16px 0 0' }}>{t('fieldRules.section_case')}</h3>
          <p className="muted" style={{ marginTop: 0 }}>{t('fieldRules.section_case_desc')}</p>
          {renderPrefixedSection(CASE_PREFIX, CASE_FIELD_LABEL_KEYS)}

          <h3 style={{ margin: '16px 0 0' }}>{t('fieldRules.section_marriage')}</h3>
          <p className="muted" style={{ marginTop: 0 }}>{t('fieldRules.section_marriage_desc')}</p>
          {renderPrefixedSection(MARRIAGE_PREFIX, MARRIAGE_FIELD_LABEL_KEYS)}

          <h3 style={{ margin: '16px 0 0' }}>{t('fieldRules.section_new_user')}</h3>
          <p className="muted" style={{ marginTop: 0 }}>{t('fieldRules.section_new_user_desc')}</p>
          {renderPrefixedSection(NEW_USER_PREFIX, NEW_USER_FIELD_LABEL_KEYS)}
        </>
      )}
    </div>
  )
}

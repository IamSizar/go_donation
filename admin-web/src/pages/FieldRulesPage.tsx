// FieldRulesPage — admin sets whether each data field is Required, Optional,
// or Hidden (#43, extended by Note #33). Loads
// GET /api/admin/registration/field-rules and updates each via
// POST /api/admin/registration/field-rules/:key with {state}.
//
// One section per form, split on the key prefix the migrations seed rows with.
// The labels themselves live in lib/fieldRuleLabels.ts — this file only
// renders them.
import { useEffect, useState, type ReactNode } from 'react'
import { api, describeError } from '../lib/api'
import { useI18n } from '../lib/i18n'
import { useToast } from '../lib/toast'
import PageHead from '../components/PageHead'
import {
  humanize,
  ALL_PREFIXES,
  REGISTRATION_FIELD_LABEL_KEYS,
  GRANTOR_PREFIX, GRANTOR_FIELD_LABEL_KEYS,
  RECIPIENT_PREFIX, RECIPIENT_FIELD_LABEL_KEYS,
  VOLUNTEER_PREFIX, VOLUNTEER_FIELD_LABEL_KEYS,
  CASE_PREFIX, CASE_FIELD_LABEL_KEYS,
  MARRIAGE_PREFIX, MARRIAGE_FIELD_LABEL_KEYS,
  NEW_USER_PREFIX, NEW_USER_FIELD_LABEL_KEYS,
} from '../lib/fieldRuleLabels'

type FieldRuleState = 'required' | 'optional' | 'hidden'
type Rule = {
  field_key: string
  state: FieldRuleState
  display_order: number
  // Client note — Marriage "Search": independent of required/optional/hidden
  // on the form, a field can also be enabled as a search filter.
  searchable: boolean
}

/**
 * One collapsible form section.
 *
 * WHY: this page listed all 234 rules expanded, one card each, and measured
 * 23,158px on the live dashboard — about thirty-three screens. Seven headings
 * now fit on one, each saying how many rules it holds, so the form you came
 * to configure is a click away instead of a scroll away.
 *
 * <details> rather than state: keyboard operation and the open/closed state
 * being announced come free, and the page needs no new hook.
 *
 * DEFINED AT MODULE SCOPE, not inside the page. A component created during
 * render is a new type on every render, so React unmounts and remounts the
 * whole subtree — which would reset each section's open/closed state and drop
 * focus out of any control inside it. The first version of this got that
 * wrong and eslint's react-hooks/static-components caught it.
 *
 * `title` and `desc` arrive already translated, so this needs no access to
 * the page's t().
 */
function RuleSection({ title, desc, count, children }: {
  title: string
  desc: string
  count: number
  children: ReactNode
}) {
  return (
    <details className="rule-section">
      <summary className="rule-section-head">
        <span className="rule-section-title">{title}</span>
        {/* dir="ltr" because a bare numeral beside Arabic text is reordered
            by the bidi algorithm otherwise. */}
        <span className="rule-section-count" dir="ltr">{count}</span>
      </summary>
      <p className="muted rule-section-desc">{desc}</p>
      {children}
    </details>
  )
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

  const setSearchable = async (r: Rule, searchable: boolean) => {
    const prev = r.searchable
    setItems((xs) => xs.map((x) => (x.field_key === r.field_key ? { ...x, searchable } : x)))
    setSavingKey(r.field_key)
    try {
      await api.post(`/api/admin/registration/field-rules/${r.field_key}/searchable`, { searchable })
      toast.success(t('fieldRules.saved'))
    } catch (e) {
      toast.error(describeError(e))
      setItems((xs) => xs.map((x) => (x.field_key === r.field_key ? { ...x, searchable: prev } : x)))
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

  const renderPrefixedSection = (
    prefix: string,
    labelKeys: Record<string, string>,
    showSearchable = false,
  ) =>
    items.filter((r) => r.field_key.startsWith(prefix)).map((r) => {
      const suffix = r.field_key.slice(prefix.length)
      const labelKey = labelKeys[suffix]
      return (
        <div className="card" key={r.field_key}>
          <label className="field" style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
            <span style={{ flex: 1 }}><strong>{labelKey ? t(labelKey) : humanize(suffix)}</strong></span>
            {stateSelect(r)}
          </label>
          {showSearchable && (
            <label
              className="field"
              style={{ flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 8 }}
            >
              <input
                type="checkbox"
                checked={r.searchable}
                disabled={savingKey === r.field_key}
                onChange={(e) => setSearchable(r, e.target.checked)}
              />
              <span className="muted">{t('fieldRules.searchable')}</span>
            </label>
          )}
        </div>
      )
    })

  return (
    <div className="stack">
      <PageHead>
        <div>
          <h1>{t('fieldRules.title')}</h1>
          <p className="muted">{t('fieldRules.subtitle')}</p>
        </div>
      </PageHead>

      {err && <div className="error-box">{err}</div>}
      {loading && <p className="muted">{t('common.loading')}</p>}

      {!loading && (
        <>
          <RuleSection
            title={t('fieldRules.section_registration')}
            desc={t('fieldRules.section_registration_desc')}
            count={items.filter((r) => ALL_PREFIXES.every((p) => !r.field_key.startsWith(p))).length}
          >
          {items
            .filter((r) => ALL_PREFIXES.every((p) => !r.field_key.startsWith(p)))
            .map((r) => (
              <div className="card" key={r.field_key}>
                <label className="field" style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
                  <span style={{ flex: 1 }}><strong>{REGISTRATION_FIELD_LABEL_KEYS[r.field_key] ? t(REGISTRATION_FIELD_LABEL_KEYS[r.field_key]) : humanize(r.field_key)}</strong></span>
                  {stateSelect(r)}
                </label>
              </div>
            ))}
          </RuleSection>

          {/* The three role-specific registration forms. Each is its own
              section because their field keys repeat across roles — a flat
              list would show "Primary phone number" three times with nothing
              saying which role's form it belongs to. */}
          <RuleSection
            title={t('fieldRules.section_grantor')}
            desc={t('fieldRules.section_grantor_desc')}
            count={items.filter((r) => r.field_key.startsWith(GRANTOR_PREFIX)).length}
          >
            {renderPrefixedSection(GRANTOR_PREFIX, GRANTOR_FIELD_LABEL_KEYS)}
          </RuleSection>

          <RuleSection
            title={t('fieldRules.section_recipient')}
            desc={t('fieldRules.section_recipient_desc')}
            count={items.filter((r) => r.field_key.startsWith(RECIPIENT_PREFIX)).length}
          >
            {renderPrefixedSection(RECIPIENT_PREFIX, RECIPIENT_FIELD_LABEL_KEYS)}
          </RuleSection>

          <RuleSection
            title={t('fieldRules.section_volunteer')}
            desc={t('fieldRules.section_volunteer_desc')}
            count={items.filter((r) => r.field_key.startsWith(VOLUNTEER_PREFIX)).length}
          >
            {renderPrefixedSection(VOLUNTEER_PREFIX, VOLUNTEER_FIELD_LABEL_KEYS)}
          </RuleSection>

          <RuleSection
            title={t('fieldRules.section_case')}
            desc={t('fieldRules.section_case_desc')}
            count={items.filter((r) => r.field_key.startsWith(CASE_PREFIX)).length}
          >
            {renderPrefixedSection(CASE_PREFIX, CASE_FIELD_LABEL_KEYS)}
          </RuleSection>

          <RuleSection
            title={t('fieldRules.section_marriage')}
            desc={t('fieldRules.section_marriage_desc')}
            count={items.filter((r) => r.field_key.startsWith(MARRIAGE_PREFIX)).length}
          >
            {renderPrefixedSection(MARRIAGE_PREFIX, MARRIAGE_FIELD_LABEL_KEYS, true)}
          </RuleSection>

          <RuleSection
            title={t('fieldRules.section_new_user')}
            desc={t('fieldRules.section_new_user_desc')}
            count={items.filter((r) => r.field_key.startsWith(NEW_USER_PREFIX)).length}
          >
            {renderPrefixedSection(NEW_USER_PREFIX, NEW_USER_FIELD_LABEL_KEYS)}
          </RuleSection>
        </>
      )}
    </div>
  )
}

/**
 * KindCards — the choice between a masked group and a team group.
 *
 * Two selectable cards instead of a select, because the difference is the
 * whole point of the decision and a select would hide it: each card carries
 * an icon, a title and the one-line consequence of choosing it (masked hides
 * names and contact details; team shows real names). With only two options
 * both explanations fit on screen at once, which a dropdown cannot offer.
 *
 * Built on the dashboard's existing `.target-tile` cards (the push page's
 * channel and target pickers), as a radiogroup of role="radio" buttons, so
 * the selected state is the same accent border and tinted icon used there.
 */
import { EyeOff, Users } from 'lucide-react'
import { useId } from 'react'
import type { ChatGroupKind } from '../../lib/chatGroupsApi'
import { useI18n } from '../../lib/i18n'

/** The cards, in order, with the icon each one shows. */
const KIND_OPTIONS: { kind: ChatGroupKind; Icon: typeof Users }[] = [
  { kind: 'masked', Icon: EyeOff },
  { kind: 'team', Icon: Users },
]

type Props = {
  /** The chosen kind, or null before one is chosen. */
  value: ChatGroupKind | null
  disabled: boolean
  onChange: (kind: ChatGroupKind) => void
}

export default function KindCards({ value, disabled, onChange }: Props) {
  const { t } = useI18n()
  const labelId = useId()

  return (
    <div>
      <span id={labelId} className="form-label" style={{ display: 'block', marginBlockEnd: 'var(--space-2)' }}>
        {t('chat_groups.create.kind_label')}
      </span>
      <div
        role="radiogroup"
        aria-labelledby={labelId}
        style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: 'var(--space-3)' }}
      >
        {KIND_OPTIONS.map(({ kind, Icon }, index) => {
          const selected = value === kind
          return (
            <button
              key={kind}
              type="button"
              role="radio"
              aria-checked={selected}
              className={`target-tile${selected ? ' is-selected' : ''}`}
              disabled={disabled}
              data-autofocus={index === 0 ? '' : undefined}
              onClick={() => onChange(kind)}
            >
              <span className="target-code" aria-hidden="true">
                <Icon size={20} strokeWidth={2.2} />
              </span>
              <span className="target-text">
                <strong>{t(`chat_groups.create.kind_${kind}_title`)}</strong>
                <span className="muted">{t(`chat_groups.create.kind_${kind}_desc`)}</span>
              </span>
              {selected && (
                <svg
                  className="target-check"
                  width="18"
                  height="18"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2.5"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  aria-hidden="true"
                >
                  <polyline points="20 6 9 17 4 12" />
                </svg>
              )}
            </button>
          )
        })}
      </div>
    </div>
  )
}

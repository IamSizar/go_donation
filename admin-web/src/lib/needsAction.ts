// needsAction — which rows the sidebar badges are actually counting.
//
// THE PROBLEM THIS SOLVES
// The sidebar says «المساهمات ④». Opening the page showed sixteen rows with
// nothing marking WHICH four. Every badged section had the same gap: the
// number was a promise the page did not keep.
//
// The rows are not un-marked, exactly: every list already draws a 4px status
// stripe, and the "needs admin action" states map to amber. But a stripe
// cannot answer this question, for two reasons:
//
//   1. NOTHING SAYS WHAT AMBER MEANS. There is no legend anywhere, so the
//      colour is only readable by someone who already knows the mapping.
//   2. THE COLOUR CAN DISAGREE WITH THE BADGE. stripeForDonation promotes a
//      FAILED PAYMENT to red regardless of delivery_status — deliberately,
//      and rightly. So a donation with delivery_status='registered' and a
//      failed payment is counted by the badge and drawn RED. Colour alone can
//      therefore never be a reliable index of the badge.
//
// Hence an explicit, worded tag, driven by the table below.
//
// ─── THIS FILE MIRRORS SQL, AND MUST NOT DRIFT FROM IT ──────────────────────
// The badges are computed in Postgres, in backend/internal/handlers/
// pending_counts.go. If that query changes and this table does not, the pages
// mark a different set of rows than the numbers they are explaining — which
// is worse than marking none, because it looks authoritative and nothing on
// screen reveals the mismatch.
//
// `npm run check:pending-parity` parses that Go file and fails on ANY
// disagreement — a changed value, a changed column, a badge added there and
// not here, or a rule here with no badge behind it. It is keyed by TABLE NAME
// precisely so the two can be compared mechanically; the pages are a
// presentation detail, the table is the contract.

/** One badge's rule: the column it looks at, and the values that count. */
export type NeedsActionRule = {
  /** The column named in the pending-counts query for this table. */
  column: string
  /** The values that mean "waiting on staff". Lowercase. */
  values: string[]
}

/**
 * Every rule behind a sidebar badge, keyed by the table pending_counts.go
 * reads. Transcribed from that query and held to it by the parity check —
 * do not edit one without the other.
 */
export const NEEDS_ACTION_RULES: Record<string, NeedsActionRule> = {
  donations: { column: 'delivery_status', values: ['registered'] },
  sponsorships: { column: 'status', values: ['pending'] },
  beneficiary_cases: { column: 'verification_status', values: ['pending'] },
  beneficiary_project_requests: { column: 'status', values: ['under_review'] },
  marketplace_orders: { column: 'status', values: ['pending', 'processing'] },
  support_tickets: { column: 'status', values: ['open', 'in_progress'] },
  in_kind_donations: { column: 'status', values: ['scheduled'] },
  volunteer_applications: { column: 'status', values: ['submitted'] },
  volunteer_mission_signups: { column: 'status', values: ['pending', 'completion_requested'] },
  marriage_profiles: { column: 'status', values: ['submitted'] },
  users: { column: 'registration_status', values: ['pending'] },
}

/** The tables this module knows about — the keys of the rule table. */
export type NeedsActionTable = keyof typeof NEEDS_ACTION_RULES

/**
 * Whether this row is one the sidebar badge for `table` is counting.
 *
 * Compared trimmed and case-insensitively, against Postgres's exact `=`. That
 * asymmetry is deliberate and one-directional: a value differing only in case
 * is the same lifecycle state to a human, so this can only ever OVER-mark,
 * never under-mark. A row the badge counts is never left untagged — which is
 * the failure that would matter, since the tag exists to account for a number
 * the operator can already see.
 */
export function needsAction(
  table: NeedsActionTable,
  row: Record<string, unknown> | null | undefined,
): boolean {
  if (!row) return false
  const rule = NEEDS_ACTION_RULES[table]
  if (!rule) return false
  const raw = row[rule.column]
  if (typeof raw !== 'string') return false
  return rule.values.includes(raw.trim().toLowerCase())
}

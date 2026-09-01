// needsAction — which rows the sidebar badge is actually counting.
//
// THE PROBLEM THIS SOLVES
// The sidebar says «المساهمات ④». Opening the page showed sixteen rows with
// nothing marking WHICH four the badge meant. The number was a promise the
// page did not keep.
//
// The rows are not un-marked, exactly: every list already draws a 4px status
// stripe, and `registered` maps to amber. But a stripe cannot answer this
// question, for two reasons:
//
//   1. NOTHING SAYS WHAT AMBER MEANS. There is no legend anywhere, so the
//      colour is only readable by someone who already knows the mapping.
//   2. THE COLOUR CAN DISAGREE WITH THE BADGE. stripeForDonation promotes a
//      FAILED PAYMENT to red regardless of delivery_status — deliberately,
//      and rightly. So a donation with delivery_status='registered' and a
//      failed payment is counted by the badge and drawn RED. Colour alone
//      can therefore never be a reliable index of the badge.
//
// Hence an explicit, worded tag, driven by the predicate below.
//
// ─── THIS FILE MIRRORS SQL, AND MUST NOT DRIFT FROM IT ──────────────────────
// The badge is computed in Postgres, in backend/internal/handlers/
// pending_counts.go. If that query changes and this file does not, the page
// marks a different set of rows than the number it is explaining — which is
// worse than marking none, because it looks authoritative.
//
// `npm run check:pending-parity` reads the Go file and fails when the two
// disagree, the same way check-labels derives its truth from the backend
// rather than trusting a copy.

/**
 * The donations lifecycle value the badge counts.
 *
 * Mirrors: `SELECT COUNT(*) FROM donations WHERE delivery_status =
 * 'registered'` in pending_counts.go. Exported (rather than inlined) so the
 * parity check has one literal to compare against.
 */
export const DONATION_NEEDS_ACTION_DELIVERY_STATUS = 'registered'

/**
 * Whether this donation row is one the sidebar badge is counting.
 *
 * Compared case-insensitively and with surrounding space trimmed: the column
 * is plain text, and a value that differs only in case is the same lifecycle
 * state to a human. Postgres `=` would disagree, which would mean the badge
 * counts a row this does not mark — so this is deliberately the more generous
 * of the two, and can only ever over-mark, never under-mark.
 */
export function donationNeedsAction(row: { delivery_status?: string | null }): boolean {
  const v = (row.delivery_status ?? '').trim().toLowerCase()
  return v === DONATION_NEEDS_ACTION_DELIVERY_STATUS
}

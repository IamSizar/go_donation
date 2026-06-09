// statusColors.ts — single source of truth for row-stripe colors.
//
// Phase 17 — every list page (Donations, Sponsorships, Beneficiary, Support,
// Marketplace, In-kind, Volunteers, Marriage) renders a 4px colored stripe
// on the left of each row based on that row's status string. Mapping is
// centralised here so adding/renaming a status value only needs editing
// ONE file. The CSS classes are defined in index.css.
//
// Tones — picked to match the rest of the design system:
//   amber → needs admin action          (.row-stripe-amber)
//   blue  → in progress / mid-flight    (.row-stripe-blue)
//   green → completed successfully      (.row-stripe-green)
//   red   → bad outcome (rejected, etc) (.row-stripe-red)
//   grey  → neutral / closed / paused   (.row-stripe-grey)
//   ''    → no stripe (unknown status)
//
// The map values are lowercase. Callers should `.toLowerCase()` before
// lookup; the helper `stripeForStatus()` does that for you.

export type StatusTone = 'amber' | 'blue' | 'green' | 'red' | 'grey'

// Cross-page status → tone map. The same string in different tables means
// the same thing (e.g. 'pending' is always amber). When tables use unique
// values, they're listed below in their natural category.
const TONE_BY_STATUS: Record<string, StatusTone> = {
  // -------- needs admin action (amber) --------
  pending:      'amber',
  registered:   'amber', // donations.delivery_status before review
  under_review: 'amber',
  open:         'amber',
  scheduled:    'amber', // in_kind_donations awaiting handoff
  submitted:    'amber', // volunteer_applications
  new:          'amber',

  // -------- in progress (blue) --------
  processing:  'blue',
  received:    'blue',  // donations: confirmed receipt, not yet delivered
  in_progress: 'blue',
  active:      'blue',  // sponsorships, marriage profiles (subscription live)
  paused:      'blue',  // sponsorships paused are still "ongoing"

  // -------- done well (green) --------
  delivered: 'green',
  approved:  'green',
  completed: 'green',
  resolved:  'green',
  success:   'green',
  acknowledged: 'green',

  // -------- bad outcome (red) --------
  rejected:  'red',
  cancelled: 'red',
  failed:    'red',
  refunded:  'red',
  declined:  'red',

  // -------- neutral / closed (grey) --------
  closed:    'grey',
  archived:  'grey',
  expired:   'grey',
  inactive:  'grey',
}

// stripeForStatus returns the CSS className to apply via `rowProps`.
// Pass any status string (case-insensitive); returns '' for unknown values
// so unstyled rows simply render with no stripe.
export function stripeForStatus(status: string | undefined | null): string {
  if (!status) return ''
  const tone = TONE_BY_STATUS[String(status).trim().toLowerCase()]
  return tone ? `row-stripe-${tone}` : ''
}

// stripeForDonation — donations have TWO status fields. delivery_status
// drives the stripe (it's the lifecycle of the donation); payment_status
// is folded into red when it indicates failure regardless of delivery.
export function stripeForDonation(args: {
  delivery_status?: string | null
  payment_status?: number | null
}): string {
  // Numeric payment_status: 1=pending, 2=success, 3=failed (matches existing
  // paymentStatusLabel() in api-types.ts). A failed payment trumps whatever
  // delivery_status says — admin should see red and investigate.
  if (args.payment_status === 3) return 'row-stripe-red'
  return stripeForStatus(args.delivery_status)
}

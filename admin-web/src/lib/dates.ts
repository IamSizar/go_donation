// Note #20 — extracted from DonationsPage.tsx (Note #14) so both it and
// VolunteersPage.tsx (and any future table) share one implementation instead
// of duplicating it. Splits an ISO timestamp into separate date/time strings
// so a table cell can stack them on two lines instead of one long combined
// string.
export function formatDateParts(iso: string | null | undefined): { date: string; time: string } {
  if (!iso) return { date: '', time: '' }
  const d = new Date(iso)
  if (isNaN(d.getTime())) return { date: iso, time: '' }
  return { date: d.toLocaleDateString(), time: d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) }
}

// A timestamp rendered on one line as date + time, for the many table cells
// that previously showed `iso.slice(0, 10)` — i.e. the date only, with the
// time silently dropped.
//
// Only for columns that actually carry a time. DATE columns (media_posts
// .event_date, sponsorships.next_due_date) have no time component, so
// formatting them this way would print a meaningless 00:00 — those keep
// using formatDateOnly below.
export function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return ''
  const d = new Date(iso)
  if (isNaN(d.getTime())) return iso
  return d.toLocaleString([], {
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit',
  })
}

/** A true DATE column — no time exists to show. */
export function formatDateOnly(iso: string | null | undefined): string {
  if (!iso) return ''
  const d = new Date(iso)
  if (isNaN(d.getTime())) return iso.length >= 10 ? iso.slice(0, 10) : iso
  return d.toLocaleDateString()
}

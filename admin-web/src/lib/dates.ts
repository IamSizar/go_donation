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

/// A timestamp in the format the owner asked for: dd/mm/yyyy hh:mm:ss, 12-hour.
///
/// WHY THIS IS EXPLICIT RATHER THAN `toLocaleString()`
/// The formatters above delegate the ORDER and the clock to the browser's
/// locale, which is right for most of the dashboard — an operator reads dates
/// the way their machine is set. It is wrong for an evidence record. A
/// check-in is a claim about a moment ("I was there at this time"), reviewed
/// by a person who may be on a differently-configured machine from the one
/// that wrote it, and `06/08/2026` meaning June to one reader and August to
/// another is exactly the ambiguity a record must not have.
///
/// So this pins day-first, four-digit year, seconds, and a 12-hour clock, in
/// every locale. Latin digits deliberately: the surrounding evidence — GPS
/// coordinates, hours served — is Latin too, and mixing numeral systems inside
/// one record makes it harder to compare two rows at a glance.
export function formatEvidenceTimestamp(iso: string | null | undefined): string {
  if (!iso) return ''
  const d = new Date(iso)
  if (isNaN(d.getTime())) return iso
  const pad = (n: number) => String(n).padStart(2, '0')
  const hours24 = d.getHours()
  const hours12 = hours24 % 12 === 0 ? 12 : hours24 % 12
  const meridiem = hours24 < 12 ? 'AM' : 'PM'
  return (
    `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ` +
    `${pad(hours12)}:${pad(d.getMinutes())}:${pad(d.getSeconds())} ${meridiem}`
  )
}

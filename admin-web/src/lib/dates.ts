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

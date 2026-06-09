// Phone display helper. The DB stores one canonical form ("07508582031");
// everywhere we show a phone we group it with spaces ("0750 858 2031").
//
// Accepts any stored form (canonical, "964…", bare "750…") and falls back to
// the trimmed input when it can't reduce to a 10-digit national number.
export function formatPhone(raw: string | null | undefined): string {
  if (!raw) return ''
  let d = String(raw).replace(/\D/g, '')
  d = d.replace(/^(00)?964/, '').replace(/^0+/, '')
  if (d.length !== 10) return String(raw).trim()
  return `0${d.slice(0, 3)} ${d.slice(3, 6)} ${d.slice(6)}`
}

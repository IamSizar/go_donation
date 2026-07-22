// Phone display helper. The DB stores one canonical form
// ("<dial code><national number>", e.g. "9647508582031") — Iraqi numbers
// display in their familiar local grouping ("0750 858 2031"); any other
// country displays as "+<dial code><number>" (#39 — international support).
//
// Accepts any stored/legacy form (new canonical, old "0…" canonical, bare
// "750…") and falls back to the trimmed input when it isn't a recognizable
// digit string.
export function formatPhone(raw: string | null | undefined): string {
  if (!raw) return ''
  const digits = String(raw).replace(/\D/g, '')
  if (!digits) return String(raw).trim()

  const national = digits.replace(/^(00)?964/, '').replace(/^0+/, '')
  if (national.length === 10) {
    return `0${national.slice(0, 3)} ${national.slice(3, 6)} ${national.slice(6)}`
  }

  return `+${digits}`
}

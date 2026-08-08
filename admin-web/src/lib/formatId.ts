// Record ids are shown to staff with a "T" prefix: 12 renders as "#T12".
//
// One helper rather than a literal `#{x.id}` scattered through the pages, so
// the display format is a single edit if it ever changes again. The same
// prefix is baked into the `*_ref` strings in the locale files (e.g.
// "User #T{id}"), which are interpolated by the i18n layer rather than going
// through this function — keep the two in step.
export function fmtId(id: number | string | null | undefined): string {
  if (id === null || id === undefined || id === '') return ''
  return `#T${id}`
}

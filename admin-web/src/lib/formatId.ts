// Record ids are shown to staff with a "T" prefix: 12 renders as "#T12".
//
// One helper rather than a literal `#{x.id}` scattered through the pages, so
// the display format is a single edit if it ever changes again. The same
// prefix is baked into the `*_ref` strings in the locale files (e.g.
// "User #T{id}"), which are interpolated by the i18n layer rather than going
// through this function — keep the two in step.
//
// Wrapped in a Unicode LTR isolate (U+2066 … U+2069). "#" is a bidi-neutral
// character, so under the RTL layout an id sitting next to Arabic text gets
// reordered and "#T12" is drawn as "T12#" — the prefix jumps to the wrong end.
// Isolating the run pins it left-to-right in every locale without affecting
// how the surrounding sentence flows.
export function fmtId(id: number | string | null | undefined): string {
  if (id === null || id === undefined || id === '') return ''
  return `\u2066#T${id}\u2069`
}

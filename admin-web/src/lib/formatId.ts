// Record ids are shown to staff as one letter plus the number, the letters
// taken from the word TAWAZN so each section reads differently at a glance:
//   T accounts · Z donations and cases · N shop purchases · A marriage ·
//   W every other section.  12 renders as "#T12" for an account, "#Z12" for a
// donation.
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
export function fmtId(id: number | string | null | undefined, letter: SectionLetter = 'T'): string {
  if (id === null || id === undefined || id === '') return ''
  return `\u2066#${letter}${id}\u2069`
}

/** The letters a section's ids can carry (from the word TAWAZN). */
export type SectionLetter = 'T' | 'Z' | 'N' | 'A' | 'W'

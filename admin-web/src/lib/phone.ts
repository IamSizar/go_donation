// Phone helpers — one place for how a number is DISPLAYED and one place for
// how a typed number is CLEANED before it is sent to the API.
//
// The DB stores one canonical form ("<dial code><national number>", e.g.
// "9647508582031"). Iraqi numbers display in their familiar local grouping
// ("0750 858 2031"); any other country displays as "+<dial code><number>"
// (#39 — international support).

// Every character a human might type between the digits, plus the invisible
// ones an Arabic keyboard/RTL layout inserts on its own. Mirrors the backend's
// `phoneStripRE` (backend/internal/auth/phone.go) exactly:
//   \s      ASCII whitespace
//   \p{Z}   all Unicode separators (incl. U+00A0 non-breaking space)
//   \p{Cf}  format/bidi/zero-width marks (U+200E/U+200F/U+200D/U+202A–202E)
//   - ( ) . the usual human grouping punctuation
const PHONE_STRIP_RE = /[\s\p{Z}\p{Cf}\-().]+/gu

// Iraq stays the implicit country when the input carries no "+"/"00" prefix,
// matching the backend (`iraqDialCode`). A local Iraqi NSN is 10 digits.
const IRAQ_DIAL_CODE = '964'
const IRAQ_NSN_LENGTH = 10

// H10 — the character the server builds a redaction from (U+2022 BULLET, see
// backend/internal/sensitive). It cannot occur in a real phone number, so its
// presence is a reliable "this value was never shown to me".
const REDACTION_MARK = '•'

/**
 * Whether a value came back redacted because this staff member does not hold
 * the "Sensitive contact data" permission.
 *
 * Covers emails as well as phone numbers — it lives here rather than in
 * lib/permissions.ts only because this module is a leaf with no imports, and
 * formatPhone below needs it. Every helper has to know: a redaction is NOT a
 * phone number, and the moment one is treated as one it stops being readable.
 * formatPhone would draw "••••03" as "+03" (it strips non-digits) and
 * canonicalPhone would reduce it to '', which is how a mask becomes an empty
 * write.
 */
export function isRedactedContact(raw: unknown): boolean {
  return typeof raw === 'string' && raw.includes(REDACTION_MARK)
}

/**
 * Remove every space, bidi mark and human separator from a typed phone number,
 * leaving only the digits and any leading "+".
 *
 * E7 — the client asked for this as a global rule: "إلغاء الفراغات والمساحات
 * الزائدة (Trim Spaces) داخل حقول أرقام الهواتف برمجياً". Trimming the ends is
 * not enough — an inner space is what actually breaks things, because the
 * dashboard's write endpoints store the string as typed (see canonicalPhone's
 * note), and a stored "0750 858 2031" never matches a sign-in lookup again.
 */
export function stripPhoneFormatting(raw: string | null | undefined): string {
  if (!raw) return ''
  return String(raw).replace(PHONE_STRIP_RE, '')
}

/**
 * Reduce any way of writing a number to the ONE canonical form the database
 * stores: `<dial code><national number>`, digits only, no "+", no trunk "0".
 * Returns '' when the input cannot be read as a valid number.
 *
 * This mirrors `auth.NormalizePhone` in backend/internal/auth/phone.go, and
 * the Go function is the authority — this copy exists because the two admin
 * write paths do NOT call it: `POST /api/admin/users`
 * (handlers/admin_status.go CreateUser) and `PATCH /api/admin/users/:id`
 * (handlers/admin_edit.go) both store the raw string after a bare
 * `strings.TrimSpace`. Sign-in normalises the number the person types and
 * looks it up with `WHERE phone = $1`, so a row saved in any other shape
 * cannot sign in. Until the two handlers call NormalizePhone themselves — the
 * real single-source fix, recorded in VERIFICATION_REPORT.md as a backend
 * change this pass was not allowed to make — the dashboard must not hand them
 * a non-canonical string.
 *
 * Kept deliberately in step with the Go tests in
 * backend/internal/auth/phone_test.go.
 */
export function canonicalPhone(raw: string | null | undefined): string {
  let p = stripPhoneFormatting(raw)
  if (p === '') return ''

  // An explicit "+" or "00" means the number already carries its country code.
  let explicitCountryCode = false
  if (p.startsWith('+')) {
    p = p.slice(1)
    explicitCountryCode = true
  } else if (p.startsWith('00')) {
    p = p.slice(2)
    explicitCountryCode = true
  }
  if (p === '' || !/^\d+$/.test(p)) return ''

  if (!explicitCountryCode) {
    // Bare input, no "+"/"00" — assume Iraq. Accept a number that already
    // carries the Iraq dial code, or a local one with/without the trunk "0".
    if (p.startsWith(IRAQ_DIAL_CODE)) {
      const national = p.slice(IRAQ_DIAL_CODE.length)
      if (national.length === IRAQ_NSN_LENGTH) return IRAQ_DIAL_CODE + national
    }
    const national = p.replace(/^0+/, '')
    if (national.length === IRAQ_NSN_LENGTH) return IRAQ_DIAL_CODE + national
    return ''
  }

  // Basic E.164 sanity range: 7–15 digits, country code included.
  if (p.length < 7 || p.length > 15) return ''
  return p
}

/**
 * Render a stored number for a human. Accepts any stored/legacy form (new
 * canonical, old "0…" canonical, bare "750…") and falls back to the trimmed
 * input when it isn't a recognizable digit string.
 *
 * E1 — the result is wrapped in a Unicode LTR isolate (U+2066 … U+2069), the
 * same treatment `fmtId` gives record ids and for the same reason. The spaces
 * between the digit groups are bidi-neutral, so under the RTL layout the
 * groups are reordered by the bidi algorithm and "0750 858 2031" is drawn as
 * "2031 858 0750" — the number reads backwards to an Arabic reader. Isolating
 * the run pins it left-to-right in every locale without disturbing how the
 * surrounding line flows.
 *
 * Display only: the CSV exports deliberately write the raw stored `phone`, so
 * the isolate characters never reach a file or an API call.
 */
export function formatPhone(raw: string | null | undefined): string {
  if (!raw) return ''
  // H10 — a redaction is not a number. Without this guard the digit-stripping
  // below turns the server's "••••03" into "+03", which reads as a real (wrong)
  // phone number rather than as "you are not allowed to see this".
  //
  // It still gets the LTR isolate, for the reason in the paragraph above: the
  // bullets are bidi-neutral, so under the Arabic layout "••••03" is drawn as
  // "03••••" — the hint jumps to the wrong end and stops lining up with the
  // real numbers in the same column. Verified in the browser at ar.
  if (isRedactedContact(raw)) return `⁦${String(raw)}⁩`
  const digits = String(raw).replace(/\D/g, '')
  if (!digits) return String(raw).trim()

  const national = digits.replace(/^(00)?964/, '').replace(/^0+/, '')
  if (national.length === IRAQ_NSN_LENGTH) {
    return `\u20660${national.slice(0, 3)} ${national.slice(3, 6)} ${national.slice(6)}\u2069`
  }

  return `\u2066+${digits}\u2069`
}

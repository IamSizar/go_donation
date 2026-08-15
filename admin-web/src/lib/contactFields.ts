// Client-side validation for a content page's contact details (K13).
//
// WHY THIS EXISTS AND WHY IT IS NOT lib/phone.ts
// `phone.ts` canonicalizes a SIGN-IN number: it strips every separator down to
// "<dial code><national number>", because that string is a database key and a
// stored "0750 858 2031" would never match a login lookup again. These fields
// are the opposite job — a number to DISPLAY and dial, which may legitimately
// be a landline with an area code or carry an extension. Canonicalizing it
// would destroy exactly the formatting the owner typed for readers.
//
// THE SERVER IS THE SOURCE OF TRUTH.
// Every rule here mirrors `ValidateContact` in
// `backend/internal/content/contact.go`, which is what actually protects the
// data; this copy exists so the operator is told at the field instead of by a
// failed save. Change one, change the other — the Go file names this one in its
// own comment for the same reason.

/** The K13 contact fields of a content page. Mirrors content.Content's tail. */
export type ContactFields = {
  logo_path: string
  contact_phone: string
  contact_whatsapp: string
  contact_email: string
  social_links: string
  address_en: string
  address_ar: string
  address_ckb: string
  address_kmr: string
}

// Caps, matching backend/internal/content/contact.go.
const MAX_PHONE = 64
const MAX_EMAIL = 255
const MAX_PATH = 500
const MAX_SOCIAL = 2000
const MAX_ADDRESS = 500

// What separates a phone number from prose. Counting digits rather than banning
// letters keeps "(0750) 858-2031 ext. 12" valid while rejecting "call us".
const MIN_PHONE_DIGITS = 5

function digitCount(v: string): number {
  return (v.match(/\d/g) ?? []).length
}

function phoneError(v: string): string | null {
  if (!v.trim()) return null
  if (v.length > MAX_PHONE || /[\n\r]/.test(v)) return 'invalid_phone'
  return digitCount(v) < MIN_PHONE_DIGITS ? 'invalid_phone' : null
}

function emailError(v: string): string | null {
  if (!v.trim()) return null
  if (v.length > MAX_EMAIL || /\s/.test(v)) return 'invalid_email'
  const at = v.indexOf('@')
  if (at <= 0 || at === v.length - 1) return 'invalid_email'
  const domain = v.slice(at + 1)
  if (domain.includes('@')) return 'invalid_email'
  const dot = domain.indexOf('.')
  // A dot is required, and it may be neither the first nor the last character:
  // "@localhost" and "@example." are both mistakes, not addresses.
  if (dot <= 0 || dot === domain.length - 1) return 'invalid_email'
  return null
}

function socialLinksError(v: string): string | null {
  if (!v.trim()) return null
  if (v.length > MAX_SOCIAL) return 'invalid_social_links'
  // Same split the app's parser uses (shared/utils/social_links.dart): newlines
  // and commas, with blank fragments dropped.
  for (const raw of v.split(/[\n\r,]+/)) {
    const link = raw.trim()
    if (!link) continue
    if (/\s/.test(link)) return 'invalid_social_links'
    const bare = link.includes('://') ? link.slice(link.indexOf('://') + 3) : link
    const host = bare.split('/')[0]
    // The app prefixes a bare host with https:// and opens it, so a handle with
    // no host ("@page") would become a chip that opens nothing.
    if (!host.includes('.') || host.startsWith('.') || host.endsWith('.')) {
      return 'invalid_social_links'
    }
  }
  return null
}

/**
 * Validates every contact field and returns `{ field: errorCode }` for each one
 * that fails — all of them at once, so the operator sees every box that needs
 * fixing rather than discovering them one save at a time.
 *
 * An empty object means the page can be saved. Every field is optional: empty
 * is the state every page is in today and the state the owner fills in over
 * time, so "" is always acceptable.
 *
 * The codes are the same ones the server sends back, so `error.<code>` renders
 * the identical sentence whichever side caught it.
 */
export function validateContactFields(c: ContactFields): Record<string, string> {
  const errors: Record<string, string> = {}

  if (c.logo_path.length > MAX_PATH || /[\n\r]/.test(c.logo_path)) {
    errors.logo_path = 'invalid_logo_path'
  }
  const phone = phoneError(c.contact_phone)
  if (phone) errors.contact_phone = phone
  const whatsapp = phoneError(c.contact_whatsapp)
  if (whatsapp) errors.contact_whatsapp = whatsapp
  const email = emailError(c.contact_email)
  if (email) errors.contact_email = email
  const social = socialLinksError(c.social_links)
  if (social) errors.social_links = social

  for (const key of ['address_en', 'address_ar', 'address_ckb', 'address_kmr'] as const) {
    if (c[key].length > MAX_ADDRESS) errors[key] = 'value_too_long'
  }
  return errors
}

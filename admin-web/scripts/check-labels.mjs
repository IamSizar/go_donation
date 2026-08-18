// Fails when the dashboard can print a raw database token at an operator.
//
// WHY THIS EXISTS
// `statusLabel` returns its input unchanged when no `status.*` entry matches,
// which is the right fallback for free text (a name, a city someone typed) and
// the wrong one for a controlled value. The failure is silent and looks like
// data: an Arabic screen showing `first_aid`, `topup`, `overdue` beside fully
// translated neighbours, with nothing thrown and nothing logged.
//
// So this checks the three things a raw token can come from:
//   1. every value a CHECK constraint in backend/migrations permits, and every
//      value the Go status allowlists permit, has a `status.*` label;
//   2. every module in the backend's permissions.Modules list has an entry in
//      PermissionsPage's MODULE_LABEL — `tasks` was missing, so the matrix
//      printed the slug;
//   3. every table `trashRow` can move a row out of has an entry in TrashPage's
//      MODULE_TKEY, which otherwise prints the bare table name.
//
// The backend is the source of truth in both cases, which is the point: this
// cannot drift by someone adding a value on the server and forgetting the SPA.
//
// Zero dependencies, so it runs anywhere node does:  npm run check:labels
import { readFileSync, readdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const web = join(here, '..')
const backend = join(web, '..', 'backend')

const read = (p) => readFileSync(p, 'utf8')

/** Keys defined in one section of a locale file. */
function localeKeys(file, section) {
  const src = read(join(web, 'src/lib/locales', file))
  const body = new RegExp(`\\n  ${section}: \\{(.*?)\\n  \\},`, 's').exec(src)
  if (!body) throw new Error(`no "${section}" section in ${file}`)
  // Strip comments first: a word followed by a colon inside prose would
  // otherwise register as a key and hide a real gap.
  const code = body[1].replace(/\/\/[^\n]*/g, '')
  return new Set([...code.matchAll(/(?:^|[\s{,])([A-Za-z0-9_]+)\s*:/gm)].map((m) => m[1]))
}

/** Every value the database or the Go allowlists permit. */
function backendValues() {
  const values = new Set()
  const migrations = join(backend, 'migrations')
  for (const f of readdirSync(migrations).filter((f) => f.endsWith('.sql'))) {
    const sql = read(join(migrations, f))
    for (const m of sql.matchAll(/CHECK\s*\(\s*[a-z_]+\s+IN\s*\(([^)]+)\)/gi)) {
      for (const v of m[1].matchAll(/'([a-z_]+)'/g)) values.add(v[1])
    }
  }
  const handlers = join(backend, 'internal/handlers/admin_status.go')
  const go = read(handlers)
  for (const m of go.matchAll(/Statuses\s*=\s*\[\]string\{([^}]+)\}/g)) {
    for (const v of m[1].matchAll(/"([a-z_]+)"/g)) values.add(v[1])
  }
  return values
}

/**
 * Every table a row can be moved into the Trash from.
 *
 * There is no single list on the server: `trashRow` takes the table as a
 * literal at each of its ~31 call sites (it is interpolated into the SQL, so it
 * MUST be a literal — see the warning above trashRow in admin_delete.go). So
 * the call sites themselves are the source of truth, and this reads them.
 * Tests are excluded: they trash tables the handlers do not.
 */
function backendTrashTables() {
  const dir = join(backend, 'internal/handlers')
  const tables = new Set()
  for (const f of readdirSync(dir).filter((f) => f.endsWith('.go') && !f.endsWith('_test.go'))) {
    const go = read(join(dir, f))
    // trashRow(c, <pool expression>, "table", id)  |  deleteRow(c, "table")
    for (const m of go.matchAll(/trashRow\(\s*c\s*,[^,]+,\s*"([a-z_]+)"/g)) tables.add(m[1])
    for (const m of go.matchAll(/deleteRow\(\s*c\s*,\s*"([a-z_]+)"/g)) tables.add(m[1])
  }
  return [...tables].sort()
}

/** Modules the permissions matrix must be able to name. */
function backendModules() {
  const src = read(join(backend, 'internal/permissions/permissions.go'))
  const block = /var Modules = \[\]string\{([\s\S]*?)\}/.exec(src)
  if (!block) throw new Error('could not find permissions.Modules')
  return [...block[1].matchAll(/"([a-z_]+)"/g)].map((m) => m[1])
}

const failures = []

// ─── 1. Controlled values ────────────────────────────────────────────────
const en = localeKeys('en.ts', 'status')
const ar = localeKeys('ar.ts', 'status')

// Values that are never rendered as a label. Each needs a reason, because an
// unexplained exemption is how a real gap hides.
const NOT_RENDERED = new Set([
  'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun', // day keys — dayLabelFor owns these

  // ─── Each exemption below was traced to the constraint it comes from AND to
  // every consumer of that column, in both the Go backend and this SPA. The
  // rule applied: a value is exempt only when NO admin-facing response carries
  // it, or when the only consumer compares it in code and never prints it. A
  // value that merely has no screen *yet* while an admin endpoint already
  // returns it is a gap, not an exemption — see the contact-block note.

  // audit_log.severity — 001_full_v2.sql:151. `critical` is labelled already
  // (it is also a case priority_level), `info` and `warning` are not, and they
  // cannot be: `grep -rn severity backend --include='*.go'` returns NOTHING.
  // No Go code writes the column, no query selects it, and `audit_log` is not
  // one of the sixteen resources in admin_detail.go's detailColumns map, so no
  // API response can carry it. It is a column inherited from the pre-Go MySQL
  // schema, sitting at its DEFAULT 'info' on every row.
  'info', 'warning',

  // otp_codes.mode — 001_full_v2.sql:546. Its one consumer in this SPA is
  // LoginPage.tsx:70, `data.mode === 'demo' && data.demo_code` — a branch that
  // prefills the OTP box on a demo backend. The value is compared, never
  // printed; the operator sees the six digits, not the word.
  'demo',

  // 'real' is the two-family case, and neither family renders it:
  //   • otp_codes.mode (above), and
  //   • user_profiles.display_name_mode — 073_privacy_and_eligible_recipient_
  //     fields.sql:29, the "show my real name or my alias" privacy choice.
  // display_name_mode is read only by backend/internal/privacy/privacy.go:226
  // (to decide WHICH name the app shows, so the choice reaches a screen as a
  // name, never as the word) and by internal/users/users.go:293, which serves
  // the person's OWN /api/profile/privacy-extras in the phone app. It is in
  // neither admin_detail.go's `users` column list nor its
  // userDetailProfileColumns, so the dashboard never receives it.
  'real', 'alias',

  // wallet_transactions.type — 065_wallet.sql:24. `topup` and `refund` happen
  // to be labelled already as generic money vocabulary; `donation` and
  // `purchase` are exempt because the ledger has NO admin surface: the only
  // route that returns these rows is GET /api/wallet/transactions, registered
  // on the `authed` (phone-app, own-ledger) group at cmd/server/main.go:638,
  // and this SPA calls exactly one wallet route — POST .../wallet/topup from
  // UsersPage.tsx:528. The dashboard shows the balance, never the ledger.
  'donation', 'purchase',

  // marriage_meeting_requests.request_type — 099_section_about_contact_and_
  // catalogue.sql:81. Written by internal/marriage/marriage.go:410, and then
  // dropped: ListMeetingRequests (internal/marriagechat/marriagechat.go:63-76)
  // does not select the column and MeetingRequestView has no field for it, so
  // MarriageMeetingRequestsPage.tsx cannot print it. Exempt because nothing
  // renders it — but note that this is the backend gap migration 099 was
  // written to close ("staff could not tell what was being asked for"), so the
  // three values must get labels the moment the column is selected again.
  'meeting', 'intermediary', 'visit',

  // chat_contact_blocks.kind — 116_chat_contact_blocks.sql:64. The one gap
  // here is on the SPA side: the admin route exists (GET
  // /api/admin/chats/:id/contact-blocks, cmd/server/main.go:917) and returns
  // `kind`, but nothing under admin-web/src fetches it — MessagesPage.tsx
  // calls only /api/admin/chats, .../messages, .../claim and .../release. So
  // no screen can print these today. When that supervision panel is built,
  // delete this exemption instead of labelling around it: `both` in
  // particular must not become a global status.* word, because statusLabel is
  // one flat namespace and "both" is not inherently about contact details.
  'phone', 'email', 'both',
])

for (const value of [...backendValues()].sort()) {
  if (NOT_RENDERED.has(value)) continue
  if (!en.has(value)) failures.push(`status.${value} — no English label`)
  else if (!ar.has(value)) failures.push(`status.${value} — no Arabic label`)
}

// Parity in the other direction too: an Arabic entry with no English one means
// an English operator gets the token instead.
for (const key of [...ar].sort()) {
  if (!en.has(key)) failures.push(`status.${key} — Arabic only, English would print the token`)
}

// ─── 2. Permission modules ───────────────────────────────────────────────
const page = read(join(web, 'src/pages/PermissionsPage.tsx'))
const mapBlock = /const MODULE_LABEL: Record<string, string> = \{([\s\S]*?)\n\}/.exec(page)
if (!mapBlock) failures.push('could not find MODULE_LABEL in PermissionsPage.tsx')
else {
  const mapped = new Set([...mapBlock[1].matchAll(/([a-z_]+)\s*:/g)].map((m) => m[1]))
  for (const mod of backendModules()) {
    if (!mapped.has(mod)) failures.push(`MODULE_LABEL.${mod} — the matrix would print the raw slug`)
  }
}

// ─── 3. Trash source tables ──────────────────────────────────────────────
// Same failure, third surface: TrashPage's module column falls back to
// `<code>{it.source_table}</code>`, so a table with no MODULE_TKEY entry prints
// a raw database identifier — `volunteer_mission_signups` — on an Arabic
// screen. The map is complete today; it has been completed three separate times
// (the H15, M7 and E15 comments in the file record each one), which is the
// argument for checking it here rather than noticing it again later.
const trashPage = read(join(web, 'src/pages/TrashPage.tsx'))
const trashBlock = /const MODULE_TKEY: Record<string, string> = \{([\s\S]*?)\n\}/.exec(trashPage)
if (!trashBlock) failures.push('could not find MODULE_TKEY in TrashPage.tsx')
else {
  // Strip comments first, for the same reason localeKeys does.
  const body = trashBlock[1].replace(/\/\/[^\n]*/g, '')
  const mapped = new Set([...body.matchAll(/([a-z_]+)\s*:/g)].map((m) => m[1]))
  for (const table of backendTrashTables()) {
    if (!mapped.has(table)) failures.push(`MODULE_TKEY.${table} — the Trash would print the raw table name`)
  }
}

if (failures.length) {
  console.error(
    `\n${failures.length} value(s) would render as a raw token to an operator:\n` +
      failures.map((f) => `  • ${f}`).join('\n') +
      '\n\nAdd the label to src/lib/locales/{en,ar}.ts (or to MODULE_LABEL /\n' +
      'MODULE_TKEY), or, if the value genuinely is never rendered, add it to\n' +
      'NOT_RENDERED with a reason naming where you verified that.\n',
  )
  process.exit(1)
}
console.log('check-labels: every controlled value and permission module has a label.')

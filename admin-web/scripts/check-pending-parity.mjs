// Fails when the dashboard marks a different set of rows than the sidebar
// badge counts.
//
// WHY THIS EXISTS
// The badge is computed in Postgres — `SELECT COUNT(*) FROM donations WHERE
// delivery_status = 'registered'` in backend/internal/handlers/
// pending_counts.go — and the page marks the matching rows from a constant in
// src/lib/needsAction.ts. Two copies of one rule.
//
// If the SQL changes and the constant does not, the page marks the wrong
// rows while still LOOKING authoritative, which is worse than marking none:
// an operator would trust a tag that no longer means what the number means.
// Nothing about that failure is visible on screen, and no type or test
// catches it, because the two halves are in different languages.
//
// So the backend stays the source of truth and this reads it, the same way
// check-labels derives its expected vocabulary from the Go allowlists rather
// than trusting a transcription.
//
// Zero dependencies:  npm run check:pending-parity
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const web = join(dirname(fileURLToPath(import.meta.url)), '..')
const failures = []

const goSrc = readFileSync(
  join(web, '..', 'backend', 'internal', 'handlers', 'pending_counts.go'),
  'utf8',
)
// The donations sub-select, whitespace-tolerant: the query is formatted for
// humans and gets re-indented.
const sql = /FROM\s+donations\s+WHERE\s+delivery_status\s*=\s*'([a-z_]+)'/i.exec(goSrc)
if (!sql) {
  failures.push(
    'could not find the donations pending-count query in pending_counts.go — ' +
      'if it was restructured, re-aim this check rather than deleting it',
  )
}

const tsSrc = readFileSync(join(web, 'src/lib/needsAction.ts'), 'utf8')
const ts = /DONATION_NEEDS_ACTION_DELIVERY_STATUS\s*=\s*'([a-z_]+)'/.exec(tsSrc)
if (!ts) failures.push('could not find DONATION_NEEDS_ACTION_DELIVERY_STATUS in src/lib/needsAction.ts')

if (sql && ts && sql[1] !== ts[1]) {
  failures.push(
    `the badge counts delivery_status='${sql[1]}' but the page tags ` +
      `'${ts[1]}'. The sidebar number and the rows it explains would ` +
      `disagree. Update src/lib/needsAction.ts to match pending_counts.go.`,
  )
}

if (failures.length) {
  console.error(
    `\n${failures.length} pending-count parity problem(s):\n` +
      failures.map((f) => `  • ${f}`).join('\n') +
      '\n',
  )
  process.exit(1)
}
console.log(`check-pending-parity: the page tags exactly what the badge counts ('${ts[1]}').`)

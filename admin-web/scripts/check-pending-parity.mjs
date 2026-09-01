// Fails when the dashboard marks a different set of rows than the sidebar
// badges count.
//
// WHY THIS EXISTS
// The badges are computed in Postgres — backend/internal/handlers/
// pending_counts.go — and the pages mark the matching rows from a table in
// src/lib/needsAction.ts. Two copies of eleven rules, in two languages.
//
// If the SQL changes and the table does not, the pages mark the wrong rows
// while still LOOKING authoritative, which is worse than marking none: an
// operator would trust a tag that no longer means what the number means.
// Nothing about that failure is visible on screen, no type catches it, and no
// unit test can — the two halves are Go and TypeScript.
//
// So the backend stays the source of truth and this reads it, the same way
// check-labels derives its expected vocabulary from the Go allowlists rather
// than trusting a transcription.
//
// It checks BOTH directions: a rule whose value or column drifted, a badge
// added in Go and not mirrored here, and a rule here with no badge behind it.
// The last one matters because a stale rule tags rows for a number that is no
// longer on screen.
//
// Zero dependencies:  npm run check:pending-parity
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const web = join(dirname(fileURLToPath(import.meta.url)), '..')
const goPath = join(web, '..', 'backend', 'internal', 'handlers', 'pending_counts.go')
const tsPath = join(web, 'src/lib/needsAction.ts')
const failures = []

// ─── 1 · What Postgres actually counts ────────────────────────────────────
// Every `FROM <table> WHERE <column> = '<v>'` or `... IN ('a', 'b')` inside
// the pending-counts query. Whitespace-tolerant: the SQL is formatted for
// humans and gets re-indented.
const goSrc = readFileSync(goPath, 'utf8')
const query = /const q = `([\s\S]*?)`/.exec(goSrc)
if (!query) {
  failures.push(`could not find the pending-counts query in ${goPath} — if it was restructured, re-aim this check rather than deleting it`)
}

const fromGo = new Map()
if (query) {
  const body = query[1].replace(/--[^\n]*/g, '') // strip SQL comments
  const re = /FROM\s+([a-z_]+)\s+WHERE\s+([a-z_]+)\s*(?:=\s*'([a-z_]+)'|IN\s*\(([^)]*)\))/gi
  for (const m of body.matchAll(re)) {
    const [, table, column, single, list] = m
    const values = single
      ? [single]
      : [...list.matchAll(/'([a-z_]+)'/gi)].map((x) => x[1])
    fromGo.set(table, { column, values: values.map((v) => v.toLowerCase()).sort() })
  }
  if (fromGo.size === 0) failures.push('parsed the query but found no table predicates — the regex has stopped matching')
}

// ─── 2 · What the dashboard tags ──────────────────────────────────────────
// Parsed rather than imported: this script has no TypeScript loader, and the
// shape is a plain literal by design so it can be read this way.
const tsSrc = readFileSync(tsPath, 'utf8')
const tableBlock = /NEEDS_ACTION_RULES:\s*Record<string,\s*NeedsActionRule>\s*=\s*\{([\s\S]*?)\n\}/.exec(tsSrc)
if (!tableBlock) failures.push('could not find NEEDS_ACTION_RULES in src/lib/needsAction.ts')

const fromTs = new Map()
if (tableBlock) {
  const re = /([a-z_]+):\s*\{\s*column:\s*'([a-z_]+)',\s*values:\s*\[([^\]]*)\]/gi
  for (const m of tableBlock[1].matchAll(re)) {
    const [, table, column, list] = m
    const values = [...list.matchAll(/'([a-z_]+)'/gi)].map((x) => x[1].toLowerCase()).sort()
    fromTs.set(table, { column, values })
  }
}

// ─── 3 · Compare, both directions ─────────────────────────────────────────
const same = (a, b) => a.column === b.column && a.values.join(',') === b.values.join(',')

for (const [table, go] of fromGo) {
  const ts = fromTs.get(table)
  if (!ts) {
    failures.push(
      `${table}: counted by a badge (${go.column} in ${go.values.map((v) => `'${v}'`).join(', ')}) ` +
        `but NEEDS_ACTION_RULES has no entry — those rows go untagged while the number still shows`,
    )
    continue
  }
  if (!same(go, ts)) {
    failures.push(
      `${table}: the badge counts ${go.column} in [${go.values.join(', ')}] but the page tags ` +
        `${ts.column} in [${ts.values.join(', ')}] — the number and the rows it explains would disagree`,
    )
  }
}
for (const table of fromTs.keys()) {
  if (!fromGo.has(table)) {
    failures.push(
      `${table}: NEEDS_ACTION_RULES has a rule for it, but no badge counts it any more — ` +
        `the page would tag rows for a number that is no longer shown`,
    )
  }
}

if (failures.length) {
  console.error(
    `\n${failures.length} pending-count parity problem(s):\n` +
      failures.map((f) => `  • ${f}`).join('\n') +
      `\n\nThe backend is the source of truth. Update src/lib/needsAction.ts\n` +
      `to match ${goPath.split('/go_donation/')[1] ?? goPath}.\n`,
  )
  process.exit(1)
}
console.log(
  `check-pending-parity: all ${fromGo.size} badge rules match — every page tags exactly what its badge counts.`,
)

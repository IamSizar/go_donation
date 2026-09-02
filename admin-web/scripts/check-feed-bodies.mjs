// Fails when a feed row would print English prose to an Arabic operator.
//
// WHY THIS EXISTS
// The Flutter app used to compose the sentence itself — "password login
// succeeded", "Marketplace order from app cart" — and EventsFeed prints an
// event's note verbatim, so the live feed read as English inside an Arabic
// dashboard. The app now sends machine values and the dashboard composes the
// sentence in the reader's language.
//
// That split only holds while BOTH sides agree. The next event type someone
// adds to the app will render through the `event_label` fallback — in English
// — unless a body key is added here too, and nothing would fail. So this
// checks the two directions that can drift:
//
//   1. every eventType the APP emits has either a FEED_BODY_KEY entry or a
//      hand-written branch in bodyFor (donations, sponsorships, admin_user_*);
//   2. every key those maps name actually exists in en.ts AND ar.ts, so a
//      typo cannot render as the key itself.
//
// The app is the source of truth for (1), which is the point: this cannot pass
// by someone editing only the dashboard.
//
// Zero dependencies:  npm run check:feed-bodies
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const web = join(here, '..')
const app = join(web, '..', 'humanitarian', 'lib')

const read = (p) => readFileSync(p, 'utf8')
const feed = read(join(web, 'src/components/EventsFeed.tsx'))

/** Event types the app actually emits. */
const emitted = new Set()
const walk = (d) => {
  for (const e of readdirSync(d)) {
    const p = join(d, e)
    if (statSync(p).isDirectory()) walk(p)
    else if (p.endsWith('.dart')) {
      for (const m of read(p).matchAll(/eventType:\s*'([a-z_]+)'/g)) emitted.add(m[1])
      // Ternaries: `eventType: isLogin ? 'guest_login' : 'guest_register'`.
      for (const m of read(p).matchAll(/eventType:[^,\n]*\?\s*'([a-z_]+)'\s*:\s*'([a-z_]+)'/g)) {
        emitted.add(m[1])
        emitted.add(m[2])
      }
    }
  }
}
walk(app)

/** Types bodyFor handles with their own branch, so they need no body key. */
const HAND_WRITTEN = new Set(['donation_submit', 'sponsorship_submit'])

const bodyKeys = new Map()
const block = /const FEED_BODY_KEY: Record<string, string> = \{([\s\S]*?)\n\}/.exec(feed)
if (!block) throw new Error('FEED_BODY_KEY not found in EventsFeed.tsx')
for (const m of block[1].matchAll(/([a-z_]+):\s*'([^']+)'/g)) bodyKeys.set(m[1], m[2])

const methodBlock = /const METHOD_KEY: Record<string, string> = \{([\s\S]*?)\n\}/.exec(feed)
const methodKeys = [...methodBlock[1].matchAll(/'([^']+)'/g)].map((m) => m[1])

const problems = []

for (const type of [...emitted].sort()) {
  if (HAND_WRITTEN.has(type) || type.startsWith('admin_user_')) continue
  if (!bodyKeys.has(type)) {
    problems.push(
      `the app emits "${type}" and no FEED_BODY_KEY covers it — the feed would ` +
        `print the app's English event_label to an Arabic operator`,
    )
  }
}

// Both locale files, not only English: a key present in en.ts and missing in
// ar.ts renders the English string, which is the bug this whole split exists
// to remove.
//
// The locale modules are IMPORTED and the dotted path walked, rather than
// grepped for the leaf name. A leaf like `marketplace_order_submit` also
// exists under status.*, so a name-only search reported a key as present when
// feed.body had lost it — a false pass, checked and seen.
const at = (obj, path) =>
  path.split('.').reduce((o, k) => (o == null ? undefined : o[k]), obj)

for (const file of ['en', 'ar']) {
  const mod = (await import(join(web, 'src/lib/locales', `${file}.ts`))).default
  for (const key of [...bodyKeys.values(), ...methodKeys]) {
    if (typeof at(mod, key) !== 'string') {
      problems.push(`${key} has no entry in ${file}.ts`)
    }
  }
}

if (problems.length === 0) {
  console.log(
    `check-feed-bodies: ${emitted.size} app event types, ${bodyKeys.size} localized bodies, all covered.`,
  )
  process.exit(0)
}
console.error(`\n${problems.length} problem(s) that would show English in the feed:\n`)
for (const p of problems) console.error('  • ' + p)
console.error('')
process.exit(1)

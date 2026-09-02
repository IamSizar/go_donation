// Fails when the stylesheet reads a CSS custom property that nothing defines.
//
// WHY THIS EXISTS
// `.sound-popover` and `.up-list` were written as
//
//     background: var(--color-surface-1);
//
// and --color-surface-1 has never existed — the palette defines
// --color-surface, --color-surface-2 and --color-surface-3. A var() naming an
// undefined token, with no fallback, makes the whole declaration invalid at
// computed-value time. So those two menus had NO background: the notifications
// popover rendered transparent, with the page's buttons and table headers
// showing through the text. It is silent — no console warning, no build error,
// and it survived every type check and lint run in this repo, because CSS
// custom properties are just strings until the browser resolves them.
//
// A one-character typo is all it takes, which is exactly why this is a script
// and not a code review note.
//
// Zero dependencies:  npm run check:css-tokens
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const src = join(here, '..', 'src')

const files = []
const scripts = []
const walk = (d) => {
  for (const e of readdirSync(d)) {
    const p = join(d, e)
    if (statSync(p).isDirectory()) walk(p)
    else if (/\.css$/.test(p)) files.push(p)
    else if (/\.tsx?$/.test(p)) scripts.push(p)
  }
}
walk(src)

const defined = new Set()
const used = new Map() // name -> [{file, line}]

for (const f of files) {
  const text = readFileSync(f, 'utf8')
  text.split('\n').forEach((line, i) => {
    // A definition: `  --token: value;` — the name at the START of a
    // declaration, not inside a var().
    for (const m of line.matchAll(/(^|[;{]|^\s*)\s*(--[A-Za-z0-9_-]+)\s*:/g)) {
      defined.add(m[2])
    }
    // A use: var(--token) or var(--token, fallback). A use WITH a fallback is
    // safe by construction, so only bare ones are collected.
    for (const m of line.matchAll(/var\(\s*(--[A-Za-z0-9_-]+)\s*\)/g)) {
      const list = used.get(m[1]) ?? []
      list.push({ file: f.replace(src + '/', ''), line: i + 1 })
      used.set(m[1], list)
    }
  })
}

// A token can also be defined at runtime, as an inline style — e.g.
// PushNotificationsPage sets ['--tpl-accent']: tpl.accent per row so one rule
// can colour every template. Those are real definitions and must not be
// reported, so the TSX is scanned for them too.
for (const f of scripts) {
  const text = readFileSync(f, 'utf8')
  for (const m of text.matchAll(/['"](--[A-Za-z0-9_-]+)['"]\s*(?:as\s+string\s*)?\]?\s*:/g)) {
    defined.add(m[1])
  }
}

const missing = [...used.entries()].filter(([name]) => !defined.has(name))
if (missing.length === 0) {
  console.log(`check-css-tokens: ${used.size} tokens read, all defined.`)
  process.exit(0)
}

console.error(`\n${missing.length} CSS token(s) are read but never defined:\n`)
for (const [name, spots] of missing) {
  console.error(`  • ${name}`)
  for (const s of spots) console.error(`      ${s.file}:${s.line}`)
}
console.error(
  '\nA var() with no fallback naming an undefined token voids the whole\n' +
    'declaration — silently. Define the token, fix the name, or give the\n' +
    'var() a fallback: var(--maybe-missing, #101728).\n',
)
process.exit(1)

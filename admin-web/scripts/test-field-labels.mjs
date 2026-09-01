// test-field-labels.mjs — pins that no box in the New/Edit User modal is
// labelled with a raw i18n key.
//
// WHY THIS EXISTS
// The modal's labels were pointed at `dbfield.<column>` and resolved with a
// PLAIN t() lookup, which returns the key itself when that one namespace has
// no entry. 63 of the 98 editable profile columns are translated under
// `field.<column>` instead — so an Arabic operator opening "+ مستخدم جديد"
// read `DBFIELD.TRIBE_CLAN`, `DBFIELD.NATIONALITY`, `DBFIELD.MARITAL_STATUS`
// and sixty more, while the correct Arabic sat one namespace away the whole
// time. Nothing threw; the form simply looked broken.
//
// It survived because `npm run check:labels` checks controlled VALUES
// (statuses, permission modules, trash tables) and never looked at field
// LABELS. This closes that gap for the one form where a column's label is
// generated rather than written by hand.
//
// WHAT IT ACTUALLY CHECKS
// The resolution is duplicated here from `fieldLabelFor` (i18n.tsx) on
// purpose: importing that module would drag React in, and a copy that walks
// the same three namespaces in the same order is enough to catch the failure
// this file is named for. English is the runtime fallback for every locale, so
// a key missing from `en` renders raw for EVERYONE — that case is a hard
// failure. A key present in `en` but missing from `ar` renders English, which
// is a translation gap rather than a broken-looking form, and is reported
// separately.
//
// Zero dependencies, like the other scripts here:   npm run test:field-labels
// Arrange → Act → Assert throughout.
import assert from 'node:assert/strict'
import test from 'node:test'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import en from '../src/lib/locales/en.ts'
import ar from '../src/lib/locales/ar.ts'
import { USER_PROFILE_GROUPS } from '../src/lib/userProfileFields.ts'

const web = join(dirname(fileURLToPath(import.meta.url)), '..')

// ─── Helpers ─────────────────────────────────────────────────────────────

/** The namespaces fieldLabelFor walks, in its order. */
const NAMESPACES = ['dbfield', 'col', 'field']

/** The label one locale gives a column, or null when no namespace has it. */
const labelIn = (dict, key) => {
  for (const ns of NAMESPACES) {
    const v = dict?.[ns]?.[key]
    if (typeof v === 'string') return v
  }
  return null
}

/**
 * Every column the modal actually renders a box for.
 * `editable: false` columns (the assign-once identity codes, device-captured
 * GPS) are dropped by toFieldSpec before a label is ever needed.
 */
const editableColumns = () =>
  USER_PROFILE_GROUPS.flatMap((g) => g.fields.filter((f) => f.editable).map((f) => f.key))

// ─── Tests ───────────────────────────────────────────────────────────────

test('every editable profile column has an English label', () => {
  const columns = editableColumns()
  assert.ok(columns.length > 0, 'no editable columns found — the parse is wrong, not the data')

  const raw = columns.filter((key) => labelIn(en, key) === null)
  assert.deepEqual(
    raw,
    [],
    `${raw.length} column(s) would render a RAW KEY in the New/Edit User modal, ` +
      `in every language, because no dbfield.* / col.* / field.* entry exists in ` +
      `en.ts. Add one there (and the Arabic in ar.ts).`,
  )
})

test('every editable profile column has an Arabic label', () => {
  // Softer than the English case by nature: these fall back to English rather
  // than to a raw key. It is still a violation of the project's standing rule
  // that no English string is shown to an Arabic user, so it fails the suite.
  const raw = editableColumns().filter((key) => labelIn(ar, key) === null)
  assert.deepEqual(
    raw,
    [],
    `${raw.length} column(s) would show ENGLISH to an Arabic operator. Add the ` +
      `Arabic to the matching namespace in src/lib/locales/ar.ts.`,
  )
})

test('the profile boxes are labelled by column, not by a hard-coded namespace', () => {
  // The regression pinned at its CAUSE rather than its symptom. The two tests
  // above pass even with the bug present: the translations existed all along,
  // they were simply unreachable because every generated spec carried
  // `labelKey: 'dbfield.<column>'` — a single-namespace lookup.
  //
  // Asserted against the SOURCE rather than the built spec because node's type
  // stripping cannot resolve userEditFields' extensionless imports. It is one
  // specific line either way, and it is the line that decides the behaviour.
  const src = readFileSync(join(web, 'src/lib/userEditFields.ts'), 'utf8')
  const generator = src.slice(src.indexOf('function toFieldSpec'), src.indexOf('export const PROFILE_EDIT_FIELDS'))
  assert.ok(generator.length > 0, 'could not find toFieldSpec — this test needs re-aiming')

  assert.ok(
    /labelField:\s*field\.key/.test(generator),
    'toFieldSpec must set `labelField: field.key` so EditModal resolves the ' +
      'label through the dbfield.* -> col.* -> field.* walk',
  )
  assert.ok(
    !/labelKey:\s*`dbfield\./.test(generator),
    'toFieldSpec pins the dbfield.* namespace again — that is the exact bug ' +
      'that printed DBFIELD.TRIBE_CLAN at an Arabic operator',
  )

  // And EditModal must honour it, or the field above is inert.
  const modal = readFileSync(join(web, 'src/components/EditModal.tsx'), 'utf8')
  assert.ok(
    /labelField\s*\?\s*fieldLabel\(f\.labelField\)/.test(modal),
    'EditModal must resolve labelField through useFieldLabel()',
  )
})

test('the columns that broke in production resolve through the walk', () => {
  // Wording under `field.*` only — a dbfield.-pinned lookup rendered these raw.
  const underFieldOnly = editableColumns().filter(
    (key) => typeof en.dbfield?.[key] !== 'string' && typeof en.field?.[key] === 'string',
  )
  assert.ok(
    underFieldOnly.length > 0,
    'expected some columns to be translated only under field.* — if that is no ' +
      'longer true this test has stopped protecting anything and should be re-aimed',
  )
  for (const key of underFieldOnly) {
    assert.equal(typeof labelIn(en, key), 'string', `${key} must resolve through the walk`)
  }
})

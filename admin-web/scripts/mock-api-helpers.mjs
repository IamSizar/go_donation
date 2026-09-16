// mock-api-helpers.mjs — the small pieces every mock-api route module shares:
// who the mock staff member is, the backend's two reply envelopes, new ids and
// timestamps, and the paging and search rules the admin lists follow.
//
// Imported by scripts/mock-api-routes.mjs and scripts/mock-api-chat-routes.mjs.
// It holds no state of its own: every function that changes state is handed it.
import { MOCK_STAFF_USER } from '../src/test/fixtures/session.ts'

/** The signed-in mock staff member; every write is attributed to them. */
export const STAFF_ID = MOCK_STAFF_USER.user_id

/** That staff member's display name, as the fixtures' staff messages show it. */
export const STAFF_NAME = 'Rana Aziz'

/**
 * A 200 reply in the backend's success envelope.
 *
 * @param {object} [fields]  merged in beside `success: true`.
 * @returns {{ status: number, body: object }}
 */
export function ok(fields = {}) {
  return { status: 200, body: { success: true, ...fields } }
}

/**
 * A failure in the backend's error envelope.
 *
 * @param {number} status   the HTTP status.
 * @param {string} error    the English message the Go handler sends.
 * @param {object} [extra]  more fields, such as a machine-readable `code`.
 * @returns {{ status: number, body: object }}
 */
export function fail(status, error, extra = {}) {
  return { status, body: { success: false, error, ...extra } }
}

/**
 * The id for a row this mock creates. State starts above every fixture id, so
 * a new row can never collide with one.
 */
export function nextId(state) {
  return ++state.lastId
}

/** The current time as the ISO-8601 string the API sends. */
export function now() {
  return new Date().toISOString()
}

/**
 * A positive whole-number query parameter.
 *
 * @returns the parsed number, or `fallback` when it is absent or not one.
 */
export function positiveInt(query, name, fallback) {
  const n = Number(query.get(name))
  return Number.isInteger(n) && n > 0 ? n : fallback
}

/**
 * One page of rows with the fields every admin list envelope carries
 * (envelopePage in handlers/admin_lists.go). `page` defaults to 1 and
 * `per_page` to 20.
 */
export function paginate(rows, query) {
  const page = positiveInt(query, 'page', 1)
  const perPage = positiveInt(query, 'per_page', 20)
  const totalPages = Math.max(1, Math.ceil(rows.length / perPage))
  return {
    items: rows.slice((page - 1) * perPage, page * perPage),
    page,
    per_page: perPage,
    total_items: rows.length,
    total_pages: totalPages,
    has_more: page < totalPages,
  }
}

/**
 * A row filter keeping rows where any of `fields` contains `q`, ignoring case.
 * An empty or missing q keeps every row. It approximates the backends' ILIKE
 * searches, which match on similar columns.
 */
export function matchesQuery(q, fields) {
  const needle = (q ?? '').trim().toLowerCase()
  return (row) => !needle || fields.some((f) => String(row[f] ?? '').toLowerCase().includes(needle))
}

/** Whether a message request carries a non-blank `body`, the check every send route makes. */
export function hasBody(body) {
  return typeof body?.body === 'string' && body.body.trim() !== ''
}

/** The chat group with this id, or undefined. */
export function findGroup(state, id) {
  return state.groups.find((g) => g.id === id)
}

# Retire-direct-chats: is it ready to run? (2026-09-16)

**For Zaid.** This is the read-and-verify pass over
`docs/runbooks/retire-direct-chats.md` before the production run — the last
deploy step of OPOS #25284. It was written against `origin/main` `a554ec3`.

Nothing in this check touched production. Every SQL block in the runbook was
run against a **fresh local throwaway database** (`gd_runbook_readiness_0916`,
created, migrated, and dropped again — see "How this was checked"). That is a
**schema check, not a data check**: it proves the queries still parse and still
match real tables and columns, not what production holds.

---

## Verdict

**Ready to run, after three small runbook corrections — all of which are now
made** (commit 2 on this branch). No code change is needed, and nothing about
the run itself is unsafe.

The script, its two SQL statements, the freeze list, the pre-flight, the
post-checks and the section 10 restore all still match the code. This week's
changes (migration 124's index, PR #127/#130's read rewrites, #129's profile
write locks) do not change what the run does or what the runbook's queries
mean.

What was wrong in the runbook, and is now fixed:

1. **Risk 4 was out of date.** It said a retired pending invitation can still
   be accepted. That stopped being true: `Accept` now refuses an ended,
   paused or archived thread before it does anything
   (`backend/internal/handlers/chat.go:283`,
   `backend/internal/handlers/chat_lifecycle_gate.go:121-126`). It has moved to
   the "resolved" list.
2. **The actor-lookup query could show a staff member twice.** It used a plain
   `LEFT JOIN user_profiles`, and a user with two profile rows duplicates.
   It now uses the same `LEFT JOIN LATERAL … ORDER BY p.id LIMIT 1` form the
   product's own reads were moved to in PR #127/#130
   (`backend/internal/chat/chat.go:640-643`).
3. **Two line citations had drifted** by a few lines after #116 merged:
   `admin_trash.go:273` → `:278`, `admin_trash.go:296` → `:301`.

**The one thing to be careful about on the day** is caveat C1 below (a thread
deleted after the run and then restored). It is a known, narrow case, and the
action is one extra check before you use the rollback.

---

## Step-by-step table: every runbook step against the code

| Runbook step | Status | Evidence |
|---|---|---|
| §1 "build must contain PR #79" check (`git grep ErrDirectChatRetired`) | **verified** | `backend/internal/chat/chat.go:39`, and the 410 at `backend/internal/handlers/chat.go:176` |
| §1 "`retire.go` header names #26412" | **verified** | `backend/internal/chatlifecycle/retire.go:1-24` |
| §2 statement 1 (end + archive open/paused) | **verified**, identical text | `backend/internal/chatlifecycle/retire.go:97-106` |
| §2 statement 2 (archive ended, visible) | **verified**, identical text | `backend/internal/chatlifecycle/retire.go:113-118` |
| §2 actor lock `SELECT … FOR SHARE` | **verified** | `retire.go:88`, used at `retire.go:170-183` |
| §2 reason text (em dash U+2014) | **verified**, byte-for-byte | `retire.go:41` |
| §2 "one transaction, all or nothing" | **verified** | `retire.go:140-162` |
| §2 "who may be the actor" (staff tiers, `is_admin` not read) | **verified** | `retire.go:179` via `permissions.CanAccessDashboard` |
| §3 item 6 actor-lookup query | **was duplicating — fixed** | plain profile join; product form is `chat.go:640-643` |
| §3 item 7 freeze list | **verified** — see the freeze section below | see below |
| §4 pre-flight query 0 (migrations 118/119) | **verified**, both rows returned locally | `backend/migrations/118_chat_lifecycle.sql`, `119_chat_support_threads.sql` |
| §4 queries 1–4 (counts, breakdown, untouched, messages) | **verified**, same selectors as the code | mirror `retire.go:106` and `:118` |
| §4 query 5 (actor row) | **verified** | `users.staff_tier/active/account_status` all exist |
| §4 query 6 (trashed direct threads) | **verified** | `trash_items` columns at `backend/migrations/016_trash.sql:9-17`; `kind` at `119_chat_support_threads.sql:28` |
| §5 snapshot `CREATE TABLE … AS` | **verified**, ran locally | columns from `118_chat_lifecycle.sql:44-51` |
| §6 the command and its flags | **verified** | `backend/cmd/retire-direct-chats/main.go:32-64` |
| §6 expected output lines | **verified**, exact format strings | `main.go:63-64` |
| §6 failure-output table (8 rows) | **verified**, every message matches | `main.go:35,43,47,56,59`; `retire.go:75-80,143,158,177,194,198` |
| §7a–7c post-checks | **verified** | mirror `retire.go:106`, `:118`; ran locally |
| §7d, 7f, 7g (need the snapshot table) | **verified**, ran locally | — |
| §7e (re-run pre-flight 3) | **verified** | — |
| §7h (Trash activity since the snapshot) | **verified**, ran locally | `trash_items.deleted_at/restored_at` exist |
| §8 "threads leave participants' lists" | **verified** | `archived_at IS NULL` filter at `backend/internal/chat/chat.go:389` |
| §8 "staff still see them, at the top" | **verified** | admin list has no archive filter and orders by `updated_at DESC`: `chat.go:611-659` |
| §8 "staff activity count drops" | **verified** | `AND lifecycle = 'open'` at `backend/internal/staffactivity/store.go:195,197` |
| §9 resolved-by-#26412 list | **verified** | `retire.go:9-15` |
| §9 resolved-by-#26431 list (PR #103) | **verified** | conditional write at `backend/internal/chatlifecycle/apply.go:182-206`; the CONCURRENCY note at `apply.go:57-76` |
| §9 resolved-by-#26466 list (PR #116) | **verified** | `admin_chat_lifecycle.go:207`, `:247-248`, `:369-382`; `retire_one.go:53` |
| §9 risk 4 "a retired invitation can still be accepted" | **was stale — fixed** | `handlers/chat.go:283`, `chat_lifecycle_gate.go:121-126` |
| §9 other "still open" risks (was 1, 2, 3, 5–9; now 1–8 after risk 4 moved out) | **verified**, still true | the round-trip claim matches `retire.go:141,172,192,196,157`; the "risk 3" cross-reference in §10 still points at the right item |
| §10 "ended cannot be undone in the product" | **verified** | `apply.go:121-134` returns `ErrEnded`/`ErrNotPaused` |
| §10 Unarchive as partial recovery | **verified** | `apply.go:229-236` clears `archived_at` and `archived_by` |
| §10 snapshot restore query + `run_ts` guard | **verified**, ran locally | — |
| §10 Trash bullets (3 cases) | **verified** — see caveat C1 | no `updated_at` trigger on `chat_threads` (only `staff_chat_threads`, `marriage_chat_threads`, `case_volunteer_chat_threads` have one); restore re-inserts the payload verbatim at `admin_trash.go:278` |
| §10 foreign-key (23503) recovery | **verified** | `lifecycle_changed_by`/`archived_by` are `ON DELETE SET NULL`: `118_chat_lifecycle.sql:50` |

### This week's changes, and why they change nothing here

- **Migration 124** adds one index on `user_profiles(user_id)`. It touches no
  chat table and no column the runbook reads. The only knock-on is the actor
  lookup, fixed above.
- **PR #127 / #130** rewrote profile reads to `LEFT JOIN LATERAL … LIMIT 1`.
  That is application-side only; no runbook query changed meaning. The runbook's
  own actor query is now written the same way.
- **PR #129** added locks to the three profile writers. It does not touch
  `chat_threads` and needs no freeze.

---

## The commands, in order, with what to expect

Everything below is run by you, from a checkout of `main` at the reviewed SHA,
on a machine close to the database.

**0. Before anything.** Backup done and confirmed. Staff told (see "Who to
tell"). Record `git rev-parse HEAD`.

```sh
git grep -n ErrDirectChatRetired $(git rev-parse HEAD) -- backend/internal/chat/chat.go
```
*Expect:* one match. If nothing, you are on the wrong commit — stop.

**1. Pre-flight (read-only).** Run §4 of the runbook.
```sh
PGOPTIONS='-c default_transaction_read_only=on' psql "$DATABASE_URL" -X
```
*Expect:* two migration rows; `will_end` (N1) and `will_archive` (N2) — write
both down, and N = N1 + N2; the breakdown; the untouched table (**save it**);
the message count; **exactly one** actor row, `staff_tier` one of
super_admin/admin/supervisor/employee, `active = 1`, `account_status = 'active'`;
the Trash table (**save it**).
*If N is 0:* stop, there is nothing to do.
*If the actor row is wrong:* pick another id now, not later.

**2. Freeze starts.** See the freeze section. Announce it.

**3. Snapshot.** Run §5, in a normal read-write session.
*Expect:* `snapshot_rows` equal to N. If it isn't, something changed between
pre-flight and snapshot — re-run the pre-flight and reconcile before running.

**4. The run.** Immediately after the snapshot:
```sh
cd backend
read -rs DATABASE_URL; export DATABASE_URL     # paste; not echoed, not in history
go run ./cmd/retire-direct-chats -actor=<staff_user_id>
unset DATABASE_URL
```
*Expect,* exit 0, two lines:
```
retire-direct-chats: ended+archived N thread(s)
retire-direct-chats: ended N1 open/paused thread(s), archived N2 already-ended thread(s)
```
The numbers must be the pre-flight's N, N1, N2 (small differences mean staff or
participants acted in between — record them, they are not a failure in
themselves).
*How long:* it is one transaction with five round trips regardless of how many
threads there are — an actor check and two set-based `UPDATE`s. Seconds, not
minutes, for any realistic N. `go run` compiling the binary the first time is
the slowest part.

**5. Post-checks.** Run §7 read-only, with `<actor>` filled in.
*Expect:* 7a `0`; 7b `N1`; 7c no rows; 7d no rows; 7e identical to your saved
pre-flight query 3 except `direct | ended | t`, which is higher by exactly N;
7f at least the pre-flight message count; 7g **one row — write down `run_ts`
exactly, all six decimals**; 7h normally no rows.

**6. Idempotence check (recommended).** Run the same command again.
*Expect:* `ended+archived 0 thread(s)` and `ended 0 open/paused thread(s),
archived 0 already-ended thread(s)`. A second run is safe: the two statements
select only rows that are not yet retired, so they match nothing. This is
covered by `TestRetireAllDirectThreadsIsIdempotent`, which passes.

**7. Dashboard eyeball.** Messages → direct: the threads are still there, at
the top, with an Ended badge and an Unarchive button, no Resume. In the app, a
participant's Messages list no longer shows them.

**8. Freeze ends.** Announce it. Record everything in OPOS #25284 and
`HANDOFF.md`: who ran it, when, the actor id, N/N1/N2, the SHA, `run_ts`, and
the pre-flight and post-check output.

**9. After the observation window.** `DROP TABLE ops_retire_direct_chats_snapshot;`

### How you know it worked

All four together, not any one alone:
- the command exited 0 and printed N/N1/N2 matching the pre-flight;
- 7a is 0 and 7c returns no rows (no direct chat is left open, paused, or
  ended-but-visible — this is the state the whole run exists to reach);
- 7b equals N1 (the threads the run ended carry the full stamp);
- 7e shows only `direct | ended | t` moved, by exactly N (nothing else changed).

---

## If a check fails mid-run

| What you see | What it means | Do this |
|---|---|---|
| `refused, nothing was changed: …` | Actor id is wrong or not staff. **Nothing changed.** | Pick a valid staff id (pre-flight query 5) and run again. |
| `-actor=… is required` / `DATABASE_URL is required` / `connect: …` | Never connected. **Nothing changed.** | Fix the input and run again. |
| `… (rolled back, nothing changed): …` | A database error inside the run; it rolled back. | Fix the cause, then run again. The snapshot is still valid. |
| `commit failed, outcome unknown, run the runbook post-checks: …` | The connection died at the commit. It may or may not have committed. | Run 7a and 7c. Both 0 → it committed, carry on at step 5. Still matching the pre-flight → it did not, run again. Re-running is safe either way. |
| Pre-flight `N = 0` | Nothing to retire. | Stop. Do not run. |
| `snapshot_rows ≠ N` | Something changed between pre-flight and snapshot. | Re-run the pre-flight; reconcile; only then run. |
| 7a or 7c returns anything | The run did not commit, or a direct thread changed after it. | Run the script again — it selects exactly those rows. |
| 7b < N1 | Some threads were written again after the run (staff action, or a message that landed during it). | Not a failure. Identify them with 7g's extra rows and record them; they are the rows the rollback will skip. |
| 7g shows more than one row | Some snapshot rows were written outside the run. | Take `run_ts` from the row whose count is closest to N. Record the others. |
| 7h returns rows | A direct chat was deleted to, or restored from, the Trash in the window. | Not a failure — record each one, and read caveat C1 before using the rollback. |

**If you need to undo it**, use §10 of the runbook with the recorded `run_ts`:
expect `restored_rows = snapshot_rows`. If `restored_rows` is 0, `run_ts` is
wrong — `ROLLBACK`, copy it again from 7g, retry. If it is lower, rows were
changed after the run and were deliberately skipped; the listed-rows query in
§10 names them, and each is a human decision.

---

## The freeze: what, how long, who

**Freeze these dashboard actions on direct chats, from the snapshot until the
post-checks are done** — realistically minutes, not hours:

- **End, archive, unarchive** — each rewrites the row, shifting 7b/7c/7d/7g and
  making the §10 restore skip that thread.
- **Claim and release** — still need freezing. Both write
  `updated_at = CURRENT_TIMESTAMP` (`backend/internal/chat/chat.go:314`,
  `:330`). They do not corrupt anything, but a claimed or released thread's
  `updated_at` is no longer `run_ts`, so the rollback would skip it.

**These do NOT need freezing:**

- **Pause and resume** — since PR #103 (#26431), a lifecycle write only lands
  while the thread's lifecycle is still the one the action was decided from
  (`backend/internal/chatlifecycle/apply.go:191-200`). One that reaches the
  thread first is then ended by the run (which selects paused threads too); one
  that loses the race is refused with 409 and the thread stays ended. Verified
  in code and covered by `apply_race_test.go`.
- **Trash delete and Trash restore** — since PR #116 (#26466), a delete locks
  the thread `FOR UPDATE` and snapshots children from `DELETE … RETURNING *`
  (`admin_chat_lifecycle.go:207`, `:247-248`), and a restore closes a direct
  chat in the same transaction (`admin_trash.go:301`,
  `admin_chat_lifecycle.go:369-382`, `chatlifecycle/retire_one.go:53`). A
  restored direct chat is never open. They still show up in 7e and 7h, so
  **record each one**.

**Who to tell, and when:**
- Dashboard staff, before the freeze: what not to click, for how long, and that
  every direct conversation is about to close.
- Support/ops, because participants with a chat open lose it mid-conversation
  and get a generic "failed, try again" on the next send.
- You (the project owner) give the explicit go before step 3, and get the
  result after step 5.

---

## Known caveats

**C1 — the section 10 rollback and a thread that went through the Trash.
Still true; confirmed against the code today.**
A direct chat that is **deleted after the run and then restored** comes back
carrying `updated_at = run_ts`. The restore re-inserts the payload verbatim
(`admin_trash.go:278`), nothing bumps `updated_at` on `chat_threads` (that
table has no `updated_at` trigger — only the marriage, staff and case-volunteer
thread tables do), and the close does nothing because the row is already ended
and archived (`retire_one.go:53`, whose two statements match no row). So the
`run_ts` guard does **not** protect it, and the §10 restore would put that
thread back to its pre-run state — undoing a deletion decision staff made
*after* the run.

*What to do:* **before running the §10 restore, run post-check 7h.** If any row
has a `restored_at` after the snapshot, that thread was deleted and restored
during or after the run. Exclude it by hand — add `AND t.id NOT IN (…)` to the
restore's `WHERE` — or decide deliberately that it should be reverted too. If
7h is empty, the restore is safe as written.

**C2 — rollback is not a complete undo.** §10 restores the seven columns the
run wrote, on rows that nobody has touched since. It cannot undo:
- threads someone wrote after the run (they are skipped by design; the §10
  listed-rows query names them);
- threads still sitting in the Trash (there is no live row to restore);
- messages participants could not send during the window (they are simply
  gone — nobody retried them for them);
- the fact that participants saw their chats disappear;
- anything in the product itself: `ended` has no transition out
  (`apply.go:121-134`), so the *only* way back to an open direct chat is this
  SQL restore, or a new thread.

**C3 — the reason text is internal English.** `lifecycle_reason` is shown
verbatim in the app's ended banner. It stays invisible while the thread is
archived, but **if staff unarchive one, both participants read
"OPOS #25284 Phase 4 — direct donor-owner chat retired"**. It is also in the
raw 409 body. Unchanged, and still worth knowing before anyone unarchives.

**C4 — the actor's account state is not checked.** The script checks the tier,
not `active` or `account_status`. Pre-flight query 5 is that check; do not skip
it.

**C5 — credentials leave the platform.** The script is not in the production
image, so it runs from a checkout with the production `DATABASE_URL` in the
environment. Use `read -rs`, and `unset` it afterwards.

**C6 — a message can land in a thread the run just ended.** A send that already
passed its lifecycle check finishes after the commit. It is kept, and only
staff can read it. Harmless; it is why 7f can be higher than the pre-flight.

**C7 — the snapshot table is outside the migrations.** Get it approved, and
drop it after the observation window.

---

## How this was checked

- Read end to end: `docs/runbooks/retire-direct-chats.md`,
  `backend/cmd/retire-direct-chats/main.go`,
  `backend/internal/chatlifecycle/{retire.go,retire_one.go,apply.go}`, the
  relevant `handlers` and `chat` code, migrations 016/118/119/124, and the
  `HANDOFF.md` entries for PR #103, #116, #114 and #120.
- **Local schema check only, no production access and no production
  credentials.** A throwaway database `gd_runbook_readiness_0916` was created
  with `createdb`, migrated by the test harness
  (`[migrate] done: 122 newly applied, 122 total migration files`), then every
  SQL block from runbook sections 4, 5, 7 and 10 was executed verbatim against
  it (empty tables, actor id 1). All of them ran without error. The database
  was dropped afterwards, and `SELECT count(*) FROM pg_database WHERE datname
  LIKE 'gd_runbook_readiness%'` printed `0`.
- `go test ./internal/chatlifecycle/ -count=1` → `ok` (includes the
  idempotence, hardening and race tests).
- **This proves the queries are valid against the current schema. It proves
  nothing about production data.**

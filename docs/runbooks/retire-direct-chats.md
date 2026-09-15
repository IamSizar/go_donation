# Runbook: retire open direct chats (`cmd/retire-direct-chats`)

| | |
|---|---|
| Script | `backend/cmd/retire-direct-chats/main.go` |
| Logic | `chatlifecycle.RetireAllDirectThreads` in `backend/internal/chatlifecycle/retire.go` |
| Feature | OPOS #25284 Phase 4 (PR #79) retired the donor ↔ campaign-owner direct chat |
| Runbook | OPOS #26402, verified against a local throwaway database on 2026-09-15 at `origin/main` `9bcc053` (see the appendix) |
| Production run | **Not performed yet.** This is a one-off ops step that needs an explicit go-ahead. |

A coding session must never run this against production on its own initiative.

---

## 1. Purpose and when to run it

Phase 4 stopped new direct chats from being created. `POST /api/chats/request` now answers **410** "Direct messaging has been retired. Ask staff to connect you instead." Existing direct threads were not touched by that deploy: they still work, and participants can keep messaging in them.

This script closes those existing conversations. It **ends** and **archives** every `chat_threads` row with `kind = 'direct'` and `lifecycle = 'open'`.

Run it once, **after** the production backend is running a build that contains PR #79. If it runs earlier, direct threads created after the run stay open.

To check that the build contains PR #79, run this against the deployed commit. It must print a match:

```sh
git grep -n ErrDirectChatRetired <deployed-sha> -- backend/internal/chat/chat.go
```

---

## 2. What it changes, exactly

The script selects:

```sql
SELECT id FROM chat_threads WHERE kind = 'direct' AND lifecycle = 'open'
```

For each id it calls `chatlifecycle.Apply` twice: `end`, then `archive`. Both calls use the same actor and the fixed reason `OPOS #25284 Phase 4 — direct donor-owner chat retired`. The dash is an em dash, U+2014. It then prints the count.

**Columns written on each selected `chat_threads` row:**

| Column | Value after the run |
|---|---|
| `lifecycle` | `'ended'` |
| `lifecycle_reason` | `'OPOS #25284 Phase 4 — direct donor-owner chat retired'` |
| `lifecycle_changed_at` | time of the `end` statement |
| `lifecycle_changed_by` | the `-actor` id |
| `archived_at` | time of the `archive` statement. Any earlier archive time is overwritten. |
| `archived_by` | the `-actor` id. Any earlier archiver is overwritten. |
| `updated_at` | time of the run |

**What it records:**
- The only trace of who ran it is `lifecycle_changed_by` and `archived_by`, plus the reason text.
- It writes no audit-log row and no trash entry.
- It sends no push notification or SMS. The dashboard's lifecycle route doesn't send any either.

**What it leaves alone:**
- `kind = 'support'` threads.
- Direct threads that are already `ended`. They are not archived, so if they are visible to participants now, they stay visible.
- Direct threads that are **`paused`**. See risk 2 in section 9.
- The `status` column (`pending`, `active` or `declined` stay as they were).
- `chat_messages`, `chat_reads` and `chat_contact_blocks`. Nothing is deleted, and the history stays readable by staff.
- The other chat systems' tables: marriage, staff, case-volunteer, and chat groups.

**Not atomic.** The run is not one transaction. Each thread gets two separate auto-committed updates. See risk 1 in section 9.

---

## 3. Prerequisites

1. **Who runs it:** the engineer who owns production deploys, after the project owner has given an explicit "go". Tell staff beforehand. The dashboard's Messages page will change (see section 8).
2. **Backup first:** take a fresh production database backup (the platform's Postgres backup, or `pg_dump -Fc`). Confirm it completed before going further.
3. **A checkout of the reviewed commit.** The production Docker image contains only `/app/server`, so this script is **not** in the image. Run it from a checkout of `main`, on a commit that contains PR #79, and record `git rev-parse HEAD`.
4. **Go 1.26.2**, as `backend/go.mod` requires. With `GOTOOLCHAIN=auto`, an older Go downloads that toolchain on first use.
5. **Database access:** a production `DATABASE_URL` that is reachable from that machine, obtained through the normal secret channel.
   - Keep it out of shell history, for example with `read -rs DATABASE_URL; export DATABASE_URL`, then paste the value.
   - Unset it when you're done.
6. **Choose the actor.** Use the id of the accountable staff member, normally the person running it, with `staff_tier` of `admin` or `super_admin`.
   - The script does **not** check the tier. Any existing `users.id` is accepted.
   - A nonexistent id fails on the first thread with a foreign-key error (SQLSTATE 23503) and changes nothing. This was verified locally.

```sql
SELECT u.id, p.full_name, u.staff_tier, u.active
  FROM users u
  LEFT JOIN user_profiles p ON p.user_id = u.id
 WHERE u.staff_tier IN ('super_admin', 'admin')
 ORDER BY u.staff_tier, u.id;
```

7. **Pick a quiet window.** Anyone who has a direct chat open during the run loses it mid-conversation (see section 8).

---

## 4. Pre-flight: read-only preview

The script has no dry-run mode. This query is the dry run, because it uses the script's own selector.

Open a read-only session. `PGOPTIONS` makes the server refuse any write, and the `BEGIN READ ONLY` below is a second guard in case a connection pooler drops `PGOPTIONS`:

```sh
PGOPTIONS='-c default_transaction_read_only=on' psql "$DATABASE_URL" -X
```

```sql
BEGIN READ ONLY;

-- 0. The schema the script needs is present (expect 2 rows).
SELECT version FROM schema_migrations
 WHERE version IN ('118_chat_lifecycle.sql', '119_chat_support_threads.sql');

-- 1. Rows the script WILL end + archive. Record this number as N.
SELECT count(*) AS will_retire
  FROM chat_threads
 WHERE kind = 'direct' AND lifecycle = 'open';

-- 2. Breakdown of those rows (status, and whether staff already archived them).
SELECT status, (archived_at IS NOT NULL) AS already_archived, count(*) AS threads
  FROM chat_threads
 WHERE kind = 'direct' AND lifecycle = 'open'
 GROUP BY 1, 2
 ORDER BY 1, 2;

-- 3. Rows the script will NOT touch. Save this output; the post-check must match it.
SELECT kind, lifecycle, (archived_at IS NOT NULL) AS archived, count(*) AS threads
  FROM chat_threads
 WHERE NOT (kind = 'direct' AND lifecycle = 'open')
 GROUP BY 1, 2, 3
 ORDER BY 1, 2, 3;

-- 4. Messages inside the rows that will be retired (they are kept).
SELECT count(*) AS messages_in_retired_threads
  FROM chat_messages m
  JOIN chat_threads t ON t.id = m.thread_id
 WHERE t.kind = 'direct' AND t.lifecycle = 'open';

-- 5. Confirm the actor exists (expect exactly 1 row).
SELECT id, staff_tier, active FROM users WHERE id = <actor>;

ROLLBACK;
```

**What to expect:**
- `will_retire` is N. The script must print exactly N.
- In query 3:
  - `direct | paused` rows will **not** be retired. Decide what to do about them before running (risk 2 in section 9).
  - `direct | ended | f` rows stay visible to participants as read-only.
- Migration 119 says no support thread existed in production when it was written, so `support` rows may be few or none.
- If `will_retire` is 0, stop. There is nothing to do.

---

## 5. Snapshot for rollback (a production write that needs approval)

Take the snapshot right before the run, in a normal read-write session. It is the only way to reverse the run exactly (see section 7). It adds a table outside the migrations, so get it approved, and drop the table after the observation window.

```sql
CREATE TABLE ops_retire_direct_chats_snapshot AS
SELECT id, lifecycle, lifecycle_reason, lifecycle_changed_at, lifecycle_changed_by,
       archived_at, archived_by, updated_at,
       CURRENT_TIMESTAMP AS snapshot_taken_at
  FROM chat_threads
 WHERE kind = 'direct' AND lifecycle = 'open';

SELECT count(*) AS snapshot_rows FROM ops_retire_direct_chats_snapshot;  -- must equal N
```

If a new table is not approved, keep an off-box copy of the same `SELECT` instead, with `\copy (SELECT ...) TO 'retire-direct-chats-snapshot.csv' WITH CSV HEADER`. A restore from that file first has to load it into a table.

Start the run immediately after the snapshot. If staff resume a paused direct thread in between, the script retires a row the snapshot doesn't hold.

---

## 6. Run

From the reviewed checkout:

```sh
cd backend
git rev-parse HEAD                    # record it
read -rs DATABASE_URL; export DATABASE_URL   # paste the production URL; not echoed
go run ./cmd/retire-direct-chats -actor=<staff_user_id>
unset DATABASE_URL
```

**Expected output** (exit 0), with N equal to the pre-flight `will_retire`:

```
retire-direct-chats: ended+archived N thread(s)
```

**Failure outputs** (exit 1):

| Output | Meaning |
|---|---|
| `-actor=<staff_user_id> is required` | Flag missing. Nothing connected, nothing changed. |
| `DATABASE_URL is required` | Env var missing. Nothing connected, nothing changed. |
| `... violates foreign key constraint "chat_threads_lifecycle_changed_by_fkey" (SQLSTATE 23503)` | The actor id doesn't exist. It fails on the first thread and nothing changes. |
| any other error | The run stopped part-way. Threads before the failure are retired. Do the post-checks (especially 7c), fix the cause, then re-run. Re-running is safe. |

Each thread costs four round trips (two reads, two updates). Run time grows with N and with network latency, so run from a machine close to the database.

---

## 7. Post-checks

Run these in a read-only session (section 4), replacing `<actor>`.

```sql
BEGIN READ ONLY;

-- 7a. Nothing open is left (expect 0).
SELECT count(*) FROM chat_threads WHERE kind = 'direct' AND lifecycle = 'open';

-- 7b. Every retired row carries the full stamp (expect N).
SELECT count(*) FROM chat_threads
 WHERE kind = 'direct' AND lifecycle = 'ended' AND archived_at IS NOT NULL
   AND lifecycle_reason = 'OPOS #25284 Phase 4 — direct donor-owner chat retired'
   AND lifecycle_changed_by = <actor> AND archived_by = <actor>;

-- 7c. Partial-failure detector: ended by the script but NOT archived (expect 0 rows).
SELECT id FROM chat_threads
 WHERE kind = 'direct'
   AND lifecycle_reason = 'OPOS #25284 Phase 4 — direct donor-owner chat retired'
   AND archived_at IS NULL;

-- 7d. Untouched rows: re-run pre-flight query 3; the output must be identical.

-- 7e. History kept: must equal pre-flight query 4.
SELECT count(*) FROM chat_messages m
  JOIN chat_threads t ON t.id = m.thread_id
 WHERE t.lifecycle_reason = 'OPOS #25284 Phase 4 — direct donor-owner chat retired';

ROLLBACK;
```

**If 7c returns rows,** archive them with the dashboard's **Archive** button on the Messages page (`POST /api/admin/chats/:id/lifecycle` with `{"action":"archive"}`). Re-running the script will **not** fix them, because it only selects `lifecycle = 'open'`.

**Optional:** re-run the script with the same actor. It must print `ended+archived 0 thread(s)`.

**Dashboard check:** the Messages page still lists the threads, with an Ended badge and archived. A participant's Messages list in the app no longer shows them.

---

## 8. What users experience afterwards

**Participants (donors and campaign owners):**
- **The thread disappears from their Messages list.** `GET /api/chats` filters `archived_at IS NULL`.
- **Old links fail.** Opening an old link or notification to the thread gives **404** "Chat not found." (`GET /api/chats/:id/messages`). A 404 rather than a 403 is deliberate: it doesn't reveal the moderation decision.
- **An open conversation screen freezes.** If they have it open during the run, the 3-second silent poll starts failing without showing anything, so the screen keeps its last messages.
- **Sending fails with a generic message.** A send gets **409** with code `chat_lifecycle_closed`. The app shows its generic, localized "failed, try again" message (`failureMessage`), not the server's text.
- **Starting a new direct chat is refused with 410.** That was already true once PR #79 was deployed, so the run changes nothing here.
- **Nobody is notified by the run.**

**Staff (dashboard):**
- **The threads stay visible.** The Messages page, direct kind, still lists every retired thread (its query has no archive filter) with an Ended badge and an Unarchive button. Resume is not offered, because ending is final.
- **They jump to the top.** Retired threads move to the top of that page, because the run bumps `updated_at`.
- **Staff activity figures can drop.** Its "Chats assigned now" count only includes `lifecycle = 'open'` threads.

---

## 9. Risks a human must accept before the production run

1. **Not atomic, and a re-run doesn't repair a half-retired thread.**
   - What happens: a crash, network drop or Ctrl-C between a thread's `end` and `archive` leaves it ended but still visible.
   - Why a re-run won't help: the script skips it, because it is no longer `open`.
   - Mitigation: post-check 7c catches it, and section 7 gives the fix.
2. **Paused direct threads are skipped.**
   - Why it matters: the send path checks `status` and `lifecycle`, but not `kind`. So if staff later **resume** a paused direct thread, it becomes a working direct chat again.
   - What to decide: before the run, whether to end and archive `direct | paused` threads by hand from the dashboard.
3. **Already-ended direct threads are not archived.** They stay in participants' lists as read-only.
4. **Earlier archive records are overwritten.** For threads staff had already archived, the original `archived_at` and `archived_by` are replaced. Only the snapshot (section 5) keeps them.
5. **The actor isn't validated as staff.** Any existing user id is accepted and recorded.
6. **Internal wording is stored as the user-facing reason.** The reason text is English ticket wording, and the app shows `lifecycle_reason` verbatim in the banner. Users don't see it while the thread is archived. **If staff unarchive a thread, both participants see** "Reason: OPOS #25284 Phase 4 — direct donor-owner chat retired". It is also in the raw 409 body.
7. **A retired pending invitation can still be accepted.**
   - What happens: `POST /api/chats/:id/accept` has no lifecycle or archive check, so the recipient can still flip it to `active`, and the initiator gets a "chat accepted" push.
   - Why it is low-impact: the thread stays ended and archived, so nobody can read it or send.
   - How this is known: from reading the code, not from a run.
8. **No audit trail beyond the columns.** Record the run in OPOS and `HANDOFF.md`: who ran it, when, the actor, N, the commit SHA, and the pre-flight and post-check output.
9. **Credentials leave the platform.** The script runs outside the production image with the production `DATABASE_URL`, so protect that URL.

---

## 10. Rollback and recovery

**Inside the product, `ended` can't be undone.** `chatlifecycle` has no transition out of `ended`. `resume` and `pause` return `ErrEnded` (HTTP 409), and the dashboard hides Resume. This is deliberate: "reopening" a conversation means a new thread.

**Partial recovery in the product: Unarchive.** Use the dashboard button, or `POST /api/admin/chats/:id/lifecycle` with `{"action":"unarchive"}`. The thread returns to both participants' lists as **read-only** history, with the ended banner showing the script's reason (risk 6). Unarchive clears `archived_at` and `archived_by`.

**Full recovery: restore from the snapshot.** This was verified locally, and it restores every column exactly. It only touches rows that still carry the script's reason, so threads staff changed by hand after the run are not overwritten.

```sql
BEGIN;

WITH restored AS (
  UPDATE chat_threads t
     SET lifecycle            = s.lifecycle,
         lifecycle_reason     = s.lifecycle_reason,
         lifecycle_changed_at = s.lifecycle_changed_at,
         lifecycle_changed_by = s.lifecycle_changed_by,
         archived_at          = s.archived_at,
         archived_by          = s.archived_by,
         updated_at           = s.updated_at
    FROM ops_retire_direct_chats_snapshot s
   WHERE t.id = s.id
     AND t.kind = 'direct'
     AND t.lifecycle = 'ended'
     AND t.lifecycle_reason = 'OPOS #25284 Phase 4 — direct donor-owner chat retired'
  RETURNING t.id
)
SELECT (SELECT count(*) FROM restored) AS restored_rows,
       (SELECT count(*) FROM ops_retire_direct_chats_snapshot) AS snapshot_rows;

-- COMMIT only if restored_rows is what you expect (normally = snapshot_rows).
-- Otherwise ROLLBACK and investigate.
COMMIT;
```

Notes on the restore:
- **If `restored_rows` is 0 but `snapshot_rows` isn't,** the em dash in the reason was probably mangled when you pasted. Run `ROLLBACK` and re-copy the literal.
- **Restored threads work normally again,** even though new direct chats still can't be created.

**Last resort: restore the pre-run backup.** This loses every other production write made since the backup. Use it only if something far worse than this script went wrong.

**Cleanup:** after the agreed observation window, run `DROP TABLE ops_retire_direct_chats_snapshot;`.

---

## Appendix: local verification (2026-09-15, OPOS #26402)

The run used a fresh local Postgres database, `gd_retire_runbook_26402`, created with `createdb` and dropped afterwards. No remote database was involved.

1. **Migrations**, applied the way the tests apply them:
   ```
   TEST_DATABASE_URL=... go test ./internal/chatlifecycle/ -count=1 -v
   ```
   Output: `[migrate] done: 121 newly applied, 121 total migration files`, both `TestRetireAllDirectThreads*` tests `PASS`, and `ok`.
2. **Seed:** one staff user (id 900001, `staff_tier = 'admin'`), seven app users, seven threads and four messages.
3. **Pre-flight** printed `will_retire = 4`.
   - Breakdown: `active/f 1`, `active/t 1`, `declined/f 1`, `pending/f 1`.
   - Untouched: `direct/ended/f 1`, `direct/paused/f 1`, `support/open/f 1`.
   - Messages in the rows to retire: 2.
4. **Guard runs**, all exit 1 with no rows changed (the report was identical afterwards):
   - `-actor=999999999` → `chatlifecycle set ended on chat_threads/910001: ... violates foreign key constraint "chat_threads_lifecycle_changed_by_fkey" (SQLSTATE 23503)`
   - no `-actor` → `-actor=<staff_user_id> is required`
   - `DATABASE_URL` removed → `DATABASE_URL is required`
   - `PGOPTIONS='-c default_transaction_read_only=on'` + an `UPDATE` → `cannot execute UPDATE in a read-only transaction`
5. **Snapshot:** `snapshot_rows = 4`.
6. **Run 1** (`-actor=900001`): `retire-direct-chats: ended+archived 4 thread(s)`, exit 0.
7. **Run 2** (same command): `retire-direct-chats: ended+archived 0 thread(s)`, exit 0. Every row, timestamps included, was identical to after run 1.
8. **Restore** (section 10): `restored_rows = 4 | snapshot_rows = 4`. Every row was identical to the "before" state again, including thread 910003's original `archived_at`.

| id | kind | status | Before | After run 1 (and run 2) | After restore |
|---|---|---|---|---|---|
| 910001 | direct | active | open, not archived, 2 messages | ended + archived by 900001, 2 messages | as before |
| 910002 | direct | pending | open, not archived | ended + archived by 900001 | as before |
| 910003 | direct | active | open, archived 2026-09-01 10:00 by 900001 | ended + archived **12:47:04 (overwritten)** | archived 2026-09-01 10:00 |
| 910004 | direct | declined | open, not archived | ended + archived by 900001 | as before |
| 910005 | direct | active | ended (staff reason), not archived | unchanged | unchanged |
| 910006 | direct | active | paused (staff reason) | **unchanged, still paused** | unchanged |
| 910007 | support | active | open | unchanged | unchanged |

Counts by kind, lifecycle and archived:

| | Before | After runs 1 and 2 |
|---|---|---|
| `direct / open / f` | 3 | 0 |
| `direct / open / t` | 1 | 0 |
| `direct / ended / t` | 0 | 4 |
| `direct / ended / f` | 1 | 1 |
| `direct / paused / f` | 1 | 1 |
| `support / open / f` | 1 | 1 |
| `chat_messages` total | 4 | 4 |

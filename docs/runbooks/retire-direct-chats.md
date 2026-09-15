# Runbook: retire direct chats (`cmd/retire-direct-chats`)

| | |
|---|---|
| Script | `backend/cmd/retire-direct-chats/main.go` |
| Logic | `chatlifecycle.RetireAllDirectThreads` in `backend/internal/chatlifecycle/retire.go` |
| Feature | OPOS #25284 Phase 4 (PR #79) retired the donor ↔ campaign-owner direct chat |
| Runbook | OPOS #26402. Updated for the OPOS #26412 hardening, and re-verified against a local throwaway database on 2026-09-15 (see the appendix). OPOS #26467 revised the freeze after OPOS #26431 (PR #103): pause and resume off; claim, release, delete and Trash restore on. It also added the Trash checks. Updated for OPOS #26466: Trash delete and restore come off the freeze, and a Trash-restored direct chat comes back ended and archived |
| Production run | **Not performed yet.** This is a one-off ops step that needs an explicit go-ahead. |

A coding session must never run this against production on its own initiative.

---

## 1. Purpose and when to run it

Phase 4 stopped new direct chats from being created. `POST /api/chats/request` now answers **410** "Direct messaging has been retired. Ask staff to connect you instead." Existing direct threads were not touched by that deploy: they still work, and participants can keep messaging in them.

This script retires those existing conversations. For every `chat_threads` row with `kind = 'direct'`:
- **open** and **paused** threads are **ended** and **archived**;
- **ended** threads that participants can still see (not archived) are **archived**.

Run it once, **after** the production backend is running a build that contains PR #79. If it runs earlier, direct threads created after the run stay open. It must also run from a commit that contains the OPOS #26412 hardening: `retire.go` opens with a header comment naming #26412.

To check that the build contains PR #79, run this against the deployed commit. It must print a match:

```sh
git grep -n ErrDirectChatRetired <deployed-sha> -- backend/internal/chat/chat.go
```

---

## 2. What it changes, exactly

The whole run is **one transaction**. It either changes everything below or nothing. In order:

```sql
BEGIN;

-- 0. Refuse an actor who is not dashboard staff. The row stays locked until COMMIT.
SELECT staff_tier FROM users WHERE id = <actor> FOR SHARE;

-- 1. End AND archive open and paused direct threads in the same statement.
--    An archive stamp staff already set is kept.
UPDATE chat_threads
   SET lifecycle            = 'ended',
       lifecycle_reason     = 'OPOS #25284 Phase 4 — direct donor-owner chat retired',
       lifecycle_changed_at = CURRENT_TIMESTAMP,
       lifecycle_changed_by = <actor>,
       archived_at          = COALESCE(archived_at, CURRENT_TIMESTAMP),
       archived_by          = CASE WHEN archived_at IS NULL THEN <actor> ELSE archived_by END,
       updated_at           = CURRENT_TIMESTAMP
 WHERE kind = 'direct' AND lifecycle IN ('open', 'paused');

-- 2. Archive ended direct threads that participants can still see.
UPDATE chat_threads
   SET archived_at = CURRENT_TIMESTAMP, archived_by = <actor>, updated_at = CURRENT_TIMESTAMP
 WHERE kind = 'direct' AND lifecycle = 'ended' AND archived_at IS NULL;

COMMIT;
```

`CURRENT_TIMESTAMP` is the transaction's start time, so every row the run writes carries the same timestamp. The dash in the reason is an em dash, U+2014. The script prints the count of each statement (section 6).

**Columns written by statement 1** (open or paused direct threads, N1 of them):

| Column | Value after the run |
|---|---|
| `lifecycle` | `'ended'` |
| `lifecycle_reason` | `'OPOS #25284 Phase 4 — direct donor-owner chat retired'`. It replaces a paused thread's pause reason. |
| `lifecycle_changed_at` | the run's timestamp |
| `lifecycle_changed_by` | the `-actor` id |
| `archived_at` | the run's timestamp, **or the original value if the thread was already archived** |
| `archived_by` | the `-actor` id, **or the original value (even NULL) if the thread was already archived** |
| `updated_at` | the run's timestamp |

**Columns written by statement 2** (ended, not archived direct threads, N2 of them):

| Column | Value after the run |
|---|---|
| `archived_at` | the run's timestamp |
| `archived_by` | the `-actor` id |
| `updated_at` | the run's timestamp |

Statement 2 does not touch `lifecycle_reason`, `lifecycle_changed_at` or `lifecycle_changed_by`. The end stays attributed to whoever ended the thread.

**What it records:**
- The only trace of who ran it is `lifecycle_changed_by` and `archived_by`, plus the reason text.
- It writes no audit-log row and no trash entry.
- It sends no push notification or SMS. The dashboard's lifecycle route doesn't send any either.

**What it leaves alone:**
- `kind = 'support'` threads, in every state.
- Direct threads that are already `ended` **and** archived.
- The `status` column (`pending`, `active` or `declined` stay as they were).
- `chat_messages`, `chat_reads` and `chat_contact_blocks`. Nothing is deleted, and the history stays readable by staff.
- The other chat systems' tables: marriage, staff, case-volunteer, and chat groups.

**Who may be the actor:** a dashboard staff account, meaning `staff_tier` is `super_admin`, `admin`, `supervisor` or `employee`. It is the same rule every `/api/admin` request uses (`auth.IsDashboardStaff`). The legacy `is_admin` flag is not read. Any other id, or an id with no user, is refused before any row changes.

---

## 3. Prerequisites

1. **Who runs it:** the engineer who owns production deploys, after the project owner has given an explicit "go". Tell staff beforehand. The dashboard's Messages page will change (see section 8).
2. **Backup first:** take a fresh production database backup (the platform's Postgres backup, or `pg_dump -Fc`). Confirm it completed before going further.
3. **A checkout of the reviewed commit.** The production Docker image contains only `/app/server`, so this script is **not** in the image. Run it from a checkout of `main`, on a commit that contains PR #79 and the OPOS #26412 hardening, and record `git rev-parse HEAD`.
4. **Go 1.26.2**, as `backend/go.mod` requires. With `GOTOOLCHAIN=auto`, an older Go downloads that toolchain on first use.
5. **Database access:** a production `DATABASE_URL` that is reachable from that machine, obtained through the normal secret channel.
   - Keep it out of shell history, for example with `read -rs DATABASE_URL; export DATABASE_URL`, then paste the value.
   - Unset it when you're done.
6. **Choose the actor.** Use the id of the accountable staff member, normally the person running it. `admin` or `super_admin` is recommended.
   - The script refuses anyone who is not dashboard staff (section 2), and changes nothing when it does.
   - It does **not** check `active` or `account_status`. Pre-flight query 5 shows both: use an account that is `active = 1` and `account_status = 'active'`.

```sql
SELECT u.id, p.full_name, u.staff_tier, u.active, u.account_status
  FROM users u
  LEFT JOIN user_profiles p ON p.user_id = u.id
 WHERE u.staff_tier IN ('super_admin', 'admin')
 ORDER BY u.staff_tier, u.id;
```

7. **Pick a quiet window, and freeze these dashboard chat actions for it.**
   - Anyone who has a direct chat open during the run loses it mid-conversation (see section 8).
   - From the snapshot until the post-checks are done, staff must not **end**, **archive**, **unarchive**, **claim** or **release** a direct chat.
     - **End, archive, unarchive, claim and release** still leave a valid thread if they race the run, but they write the row again. An end with a reason replaces the run's reason and actor, archive re-stamps `archived_at`, unarchive clears it, and claim or release bumps `updated_at`. That shifts post-checks 7b, 7c, 7d and 7g, and the restore (section 10) skips those rows, because their `updated_at` is no longer `run_ts`.
     - **Delete and Trash restore no longer need freezing** (OPOS #26466).
     - A delete reads the thread `FOR UPDATE` (`backend/internal/handlers/admin_chat_lifecycle.go:207`) and snapshots each child table from its own `DELETE … RETURNING *` (`:247-248`). A delete that reaches a thread while the run holds it waits for the commit, and stores the ended and archived row.
     - A restore re-inserts the copy (`admin_trash.go:273`) and then, in the same transaction, `closeRestoredDirectChat` (`admin_trash.go:296`, `admin_chat_lifecycle.go:369`) applies the run's own two statements to that one thread (`chatlifecycle/retire_one.go:31`, `:35`, `:53`). A restored direct chat is never open, whatever its copy held.
     - They still change counts: a delete or restore in the window shows up in post-checks 7e and 7h. Record each one.
   - **Pause and resume no longer need freezing.** Since PR #103 (`95ea8fb`, OPOS #26431), a pause or resume can't leave a direct thread un-ended. One that reaches the thread before the run is ended by the run (see section 5 for the restore). One that loses the race, or comes after the run, is refused with 409.

---

## 4. Pre-flight: read-only preview

The script has no dry-run mode. These queries are the dry run, because they use the script's own selectors.

Open a read-only session. `PGOPTIONS` makes the server refuse any write, and the `BEGIN READ ONLY` below is a second guard in case a connection pooler drops `PGOPTIONS`:

```sh
PGOPTIONS='-c default_transaction_read_only=on' psql "$DATABASE_URL" -X
```

```sql
BEGIN READ ONLY;

-- 0. The schema the script needs is present (expect 2 rows).
SELECT version FROM schema_migrations
 WHERE version IN ('118_chat_lifecycle.sql', '119_chat_support_threads.sql');

-- 1. Rows the script WILL change. Record will_end as N1 and will_archive as N2.
--    N = N1 + N2.
SELECT count(*) FILTER (WHERE lifecycle IN ('open', 'paused'))               AS will_end,
       count(*) FILTER (WHERE lifecycle = 'ended' AND archived_at IS NULL)   AS will_archive
  FROM chat_threads
 WHERE kind = 'direct';

-- 2. Breakdown of those rows. already_archived = t rows keep their archive stamp.
SELECT lifecycle, status, (archived_at IS NOT NULL) AS already_archived, count(*) AS threads
  FROM chat_threads
 WHERE kind = 'direct'
   AND (lifecycle IN ('open', 'paused') OR (lifecycle = 'ended' AND archived_at IS NULL))
 GROUP BY 1, 2, 3
 ORDER BY 1, 2, 3;

-- 3. Rows the script will NOT touch. Save this output for post-check 7e.
SELECT kind, lifecycle, (archived_at IS NOT NULL) AS archived, count(*) AS threads
  FROM chat_threads
 WHERE NOT (kind = 'direct'
            AND (lifecycle IN ('open', 'paused') OR (lifecycle = 'ended' AND archived_at IS NULL)))
 GROUP BY 1, 2, 3
 ORDER BY 1, 2, 3;

-- 4. Messages inside the rows that will change (they are kept).
SELECT count(*) AS messages_in_retired_threads
  FROM chat_messages m
  JOIN chat_threads t ON t.id = m.thread_id
 WHERE t.kind = 'direct'
   AND (t.lifecycle IN ('open', 'paused') OR (t.lifecycle = 'ended' AND t.archived_at IS NULL));

-- 5. The actor (expect exactly 1 row; staff_tier one of super_admin, admin,
--    supervisor, employee; active = 1; account_status = 'active').
SELECT id, staff_tier, active, account_status FROM users WHERE id = <actor>;

-- 6. Direct threads already in the Trash. The run doesn't touch them; a restore
--    closes each one (section 9, resolved by OPOS #26466).
--    Save this output for post-check 7h.
SELECT payload->>'lifecycle' AS lifecycle,
       (payload->>'archived_at') IS NOT NULL AS archived,
       count(*) AS trashed_direct_threads
  FROM trash_items
 WHERE source_table = 'chat_threads'
   AND restored_at IS NULL
   AND payload->>'kind' = 'direct'
 GROUP BY 1, 2
 ORDER BY 1, 2;

ROLLBACK;
```

**What to expect:**
- The script's second output line must print exactly `will_end` and `will_archive`. Its first line must print N.
- Query 3 has no `direct | open`, `direct | paused` or `direct | ended | f` rows, because those are exactly what the run changes.
- Migration 119 says no support thread existed in production when it was written, so `support` rows may be few or none.
- If query 5's `staff_tier` is not a staff tier, the script will refuse. Pick another actor now.
- Query 6 is not part of N. The run leaves those copies as they are. A restore by an `admin` or `super_admin` brings any of them back ended and archived, with the run's reason, the restoring staff member as `lifecycle_changed_by` and `archived_by`, any existing end or archive stamp kept, and its messages intact (`admin_chat_lifecycle.go:369`, `retire.go:97-118`). So every row is safe to restore, and the Trash is not a way to reopen a retired chat. Threads deleted before migration 119 have no `kind` in their copy and are not counted: their restore fails on the `NOT NULL` `kind` column.
- If N is 0, stop. There is nothing to do.

---

## 5. Snapshot for rollback (a production write that needs approval)

Take the snapshot right before the run, in a normal read-write session. It is the only way to reverse the run exactly (see section 10). It adds a table outside the migrations, so get it approved, and drop the table after the observation window.

```sql
CREATE TABLE ops_retire_direct_chats_snapshot AS
SELECT id, lifecycle, lifecycle_reason, lifecycle_changed_at, lifecycle_changed_by,
       archived_at, archived_by, updated_at,
       CURRENT_TIMESTAMP AS snapshot_taken_at
  FROM chat_threads
 WHERE kind = 'direct'
   AND (lifecycle IN ('open', 'paused') OR (lifecycle = 'ended' AND archived_at IS NULL));

SELECT count(*) AS snapshot_rows FROM ops_retire_direct_chats_snapshot;  -- must equal N
```

If a new table is not approved, keep an off-box copy of the same `SELECT` instead, with `\copy (SELECT ...) TO 'retire-direct-chats-snapshot.csv' WITH CSV HEADER`. A restore from that file, and post-checks 7d and 7f, first need it loaded into a table.

Start the run immediately after the snapshot. If staff unarchive an ended direct thread in between, the script archives a row the snapshot doesn't hold. Pause and resume are not frozen (section 3, item 7). One made in between is still ended by the run, but the section 10 restore puts back the state the snapshot recorded, from before that pause or resume.

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

**Expected output** (exit 0), with N, N1 and N2 from pre-flight query 1:

```
retire-direct-chats: ended+archived N thread(s)
retire-direct-chats: ended N1 open/paused thread(s), archived N2 already-ended thread(s)
```

**Failure outputs** (exit 1). Every one of them except the last means **nothing changed**:

| Output | Meaning |
|---|---|
| `-actor=<staff_user_id> is required` | Flag missing. Nothing connected. |
| `DATABASE_URL is required` | Env var missing. Nothing connected. |
| `retire-direct-chats: connect: ...` | `DATABASE_URL` could not be parsed. Nothing connected. |
| `retire direct threads: begin: ...` | Could not open the transaction, typically because the database is unreachable. |
| `refused, nothing was changed: no user has id <id>; ...` | The actor id doesn't exist. Pick a staff id (section 3). |
| `refused, nothing was changed: user <id> is not dashboard staff (staff_tier "user"); ...` | The actor isn't staff. Pick a staff id (section 3). |
| `retire direct threads: ... (rolled back, nothing changed): ...` | A database error inside the run. The transaction was rolled back. Fix the cause, then re-run. |
| `retire direct threads: commit failed, outcome unknown, run the runbook post-checks: ...` | The connection failed at the commit, so the server may or may not have committed. Run post-checks 7a and 7c. If both are 0, it committed. If they still match pre-flight query 1, it did not, so re-run. Re-running is safe either way. |

The number of round trips stays the same however large N is. It is one transaction: an actor check, then two set-based updates. The rows it changes stay locked until the commit. A participant action that writes one of those rows, such as a message send bumping `updated_at`, waits for the commit rather than failing.

---

## 7. Post-checks

Run these in a read-only session (section 4), replacing `<actor>`.

```sql
BEGIN READ ONLY;

-- 7a. No direct thread is left open or paused (expect 0).
SELECT count(*) FROM chat_threads
 WHERE kind = 'direct' AND lifecycle IN ('open', 'paused');

-- 7b. Every thread statement 1 ended carries the full stamp (expect N1).
--     lifecycle_changed_at = updated_at keeps only the threads this run ended,
--     because every row one run writes carries that run's single timestamp.
--     Without it, a thread an earlier interrupted run had already ended would
--     be counted too.
SELECT count(*) FROM chat_threads
 WHERE kind = 'direct' AND lifecycle = 'ended' AND archived_at IS NOT NULL
   AND lifecycle_reason = 'OPOS #25284 Phase 4 — direct donor-owner chat retired'
   AND lifecycle_changed_by = <actor>
   AND lifecycle_changed_at = updated_at;

-- 7c. Partial-state detector: a direct thread that is ended but still visible.
--     After a completed run this is ALWAYS 0 rows.
SELECT id FROM chat_threads
 WHERE kind = 'direct' AND lifecycle = 'ended' AND archived_at IS NULL;

-- 7d. Earlier archive stamps kept (expect 0 rows). Needs the snapshot table.
SELECT t.id
  FROM chat_threads t
  JOIN ops_retire_direct_chats_snapshot s ON s.id = t.id
 WHERE s.archived_at IS NOT NULL
   AND (t.archived_at IS DISTINCT FROM s.archived_at OR t.archived_by IS DISTINCT FROM s.archived_by);

-- 7e. Untouched rows: re-run pre-flight query 3. Every row must be identical,
--     except direct | ended | t, which must be higher by exactly N.

-- 7f. History kept: at least pre-flight query 4. Needs the snapshot table.
--     It is higher only by messages sent between the pre-flight and the run.
--     A send already past its lifecycle check can still land during the run
--     (section 8).
SELECT count(*) FROM chat_messages m
  JOIN ops_retire_direct_chats_snapshot s ON s.id = m.thread_id;

-- 7g. The run's timestamp. Normally exactly 1 row, with threads = N. Record
--     its run_ts: the restore (section 10) needs it. An extra row means those
--     threads were written after the run, or were changed between the snapshot
--     and the run. Take run_ts from the row whose threads is close to N.
SELECT t.updated_at AS run_ts, count(*) AS threads
  FROM chat_threads t
  JOIN ops_retire_direct_chats_snapshot s ON s.id = t.id
 GROUP BY 1
 ORDER BY 2 DESC;

-- 7h. Direct threads deleted to, or restored from, the Trash since the
--     snapshot. Needs the snapshot table. Delete and restore are not frozen
--     (section 3, item 7), so a row here is an action to record, not a failure.
--     A restored direct thread comes back ended and archived. Re-run pre-flight
--     query 6 too. Apart from these rows it should match its saved output. Any
--     other difference is a purge, or a delete or restore made between the
--     pre-flight and the snapshot. Check those with 7a and 7c.
SELECT ti.id AS trash_item_id, ti.row_id AS thread_id,
       ti.payload->>'lifecycle' AS lifecycle,
       (ti.payload->>'archived_at') IS NOT NULL AS archived,
       ti.deleted_at, ti.restored_at
  FROM trash_items ti
 WHERE ti.source_table = 'chat_threads'
   AND ti.payload->>'kind' = 'direct'
   AND (ti.deleted_at  >= (SELECT min(snapshot_taken_at) FROM ops_retire_direct_chats_snapshot)
     OR ti.restored_at >= (SELECT min(snapshot_taken_at) FROM ops_retire_direct_chats_snapshot))
 ORDER BY ti.deleted_at;

ROLLBACK;
```

**If 7a or 7c returns anything,** the run did not commit, or a direct thread changed afterwards. Re-run the script: it selects exactly those rows.

**If 7h returns a row,** record it for the section 10 restore: a thread in the snapshot that is still in the Trash can't be restored from the snapshot, and one that was deleted and restored may be skipped (section 10). If `restored_at` is set, the thread is live again but ended and archived, so 7a and 7c still show nothing for it.

**Optional:** re-run the script with the same actor. It must print `ended+archived 0 thread(s)` and `ended 0 open/paused thread(s), archived 0 already-ended thread(s)`.

**Dashboard check:** the Messages page still lists the threads, with an Ended badge and archived. A participant's Messages list in the app no longer shows them.

---

## 8. What users experience afterwards

**Participants (donors and campaign owners):**
- **Every direct thread disappears from their Messages list.** `GET /api/chats` filters `archived_at IS NULL`. This includes threads staff had paused or ended earlier, which participants could still read before the run.
- **Old links fail.** Opening an old link or notification to the thread gives **404** "Chat not found." (`GET /api/chats/:id/messages`). A 404 rather than a 403 is deliberate: it doesn't reveal the moderation decision.
- **An open conversation screen freezes.** If they have it open during the run, the 3-second silent poll starts failing without showing anything, so the screen keeps its last messages.
- **Sending fails with a generic message.** A send gets **409** with code `chat_lifecycle_closed`. The app shows its generic, localized "failed, try again" message (`failureMessage`), not the server's text.
- **A message sent at the moment of the run can still land.** A send checks the lifecycle before it writes, so a send already past that check finishes once the run commits. The message is kept in the now-ended thread, where only staff can read it.
- **Starting a new direct chat is refused with 410.** That was already true once PR #79 was deployed, so the run changes nothing here.
- **Nobody is notified by the run.**

**Staff (dashboard):**
- **The threads stay visible.** The Messages page, direct kind, still lists every retired thread (its query has no archive filter) with an Ended badge and an Unarchive button. Resume is not offered, because ending is final. That includes formerly paused threads.
- **They jump to the top.** Retired threads move to the top of that page, because the run bumps `updated_at`.
- **Staff activity figures can drop.** Its "Chats assigned now" count only includes `lifecycle = 'open'` threads.

---

## 9. Risks a human must accept before the production run

**Resolved by OPOS #26412, no longer risks:**
- the run was not atomic, and a re-run could not repair a half-retired thread;
- paused direct threads were skipped, so staff could resume them into working direct chats;
- already-ended direct threads stayed visible;
- earlier archive records were overwritten;
- the actor was not validated as staff.

**Resolved by OPOS #26431 (PR #103, `95ea8fb`), no longer a risk:**
- a dashboard pause or resume that raced the run could write `paused` or `open` over its `ended`, leaving the thread archived but resumable. `chatlifecycle.Apply` now writes only while the thread's lifecycle is still the one it read. A pause or resume that loses the race reads again and is refused with 409, and the thread stays ended. This is tested against the run's own statements, both when they commit first and while they hold their locks. One that reaches the row first lands, and the run then ends that thread, because it selects paused threads too. End, archive, unarchive, claim and release stay frozen, for other reasons (section 3, item 7).

**Resolved by OPOS #26466, no longer a risk:**
- a direct chat in the Trash could come back as a working chat. A Trash restore re-inserted the copy as it was, and a delete copied the thread with a plain `SELECT`, so a delete racing the run could store the state from before it. The delete now locks the thread `FOR UPDATE` and snapshots children from `DELETE … RETURNING *` (`admin_chat_lifecycle.go:207`, `:247-248`). A restore of a direct chat closes it in the same transaction with the run's reason and the restoring staff member as actor, keeping existing stamps (`admin_trash.go:296`, `admin_chat_lifecycle.go:369`, `chatlifecycle/retire_one.go:53`). Other chat kinds restore unchanged. Direct chats already in the Trash stay as they are until someone restores them.

**Still open:**

1. **Paused and staff-ended threads leave participants' lists too.** That is the point of retiring all direct chats, but it is a visible change for threads staff deliberately left readable. A paused thread's pause reason, `lifecycle_changed_at` and `lifecycle_changed_by` are replaced by the retirement's. Only the snapshot (section 5) keeps the originals.
2. **The actor's account state isn't checked.** The tier is checked, but `active` and `account_status` are not. Pre-flight query 5 is the check.
3. **Internal wording is stored as the user-facing reason.** The reason text is English ticket wording, and the app shows `lifecycle_reason` verbatim in the banner. Users don't see it while the thread is archived. **If staff unarchive a thread that statement 1 ended, both participants see** "Reason: OPOS #25284 Phase 4 — direct donor-owner chat retired". It is also in the raw 409 body.
4. **A retired pending invitation can still be accepted.**
   - What happens: `POST /api/chats/:id/accept` has no lifecycle or archive check, so the recipient can still flip it to `active`, and the initiator gets a "chat accepted" push.
   - Why it is low-impact: the thread stays ended and archived, so nobody can read it or send.
   - How this is known: from reading the code, not from a run.
5. **Rows are locked for the length of the run.** Writes to those `chat_threads` rows, and to the actor's `users` row, wait until the commit. With five round trips this is short, but run it from a machine close to the database.
6. **A lost connection at commit is ambiguous.** Section 6 says how the post-checks settle it.
7. **No audit trail beyond the columns.** Record the run in OPOS and `HANDOFF.md`: who ran it, when, the actor, N1 and N2, the commit SHA, and the pre-flight and post-check output.
8. **Credentials leave the platform.** The script runs outside the production image with the production `DATABASE_URL`, so protect that URL.
9. **A message can land in a thread the run just ended** (section 8). It is harmless: the message is kept, and only staff can read it.

---

## 10. Rollback and recovery

**Inside the product, `ended` can't be undone.** `chatlifecycle` has no transition out of `ended`. `resume` and `pause` return `ErrEnded` (HTTP 409), and the dashboard hides Resume. This is deliberate: "reopening" a conversation means a new thread.

**Partial recovery in the product: Unarchive.** Use the dashboard button, or `POST /api/admin/chats/:id/lifecycle` with `{"action":"unarchive"}`. The thread returns to both participants' lists as **read-only** history, with the ended banner showing its reason (risk 3). Unarchive clears `archived_at` and `archived_by`.

**Full recovery: restore from the snapshot.** This was verified locally (see the appendix), and it restores every column exactly.
- It only touches rows whose `updated_at` is still the run's timestamp, `run_ts` from post-check 7g.
- Every write to a thread bumps `updated_at`: a staff lifecycle action, and a message send. So threads anyone changed after the run are not overwritten.
- **Threads that went through the Trash (OPOS #26466).** Nothing in the migrations bumps `chat_threads.updated_at` on its own, so a Trash restore keeps the copy's `updated_at` (`backend/internal/handlers/admin_trash.go:273`). Restoring its messages doesn't write the thread (`admin_chat_lifecycle.go:332`). The close writes only when it changes something (`chatlifecycle/retire.go:106`, `:118`). So:
  - **Deleted after the run, then restored:** the copy is the run's row. The close changes nothing, and `updated_at` is still `run_ts`, so this restore puts the snapshot's state back, like any other row.
  - **Deleted between the snapshot and the run, then restored:** the close ends or archives it, and `updated_at` becomes the restore time. This restore skips it, and the skipped-rows query below lists it.
  - **Still in the Trash:** there is no live row, so it is skipped silently, and `restored_rows` is lower. Neither the section 5 snapshot nor this restore covers rows in the Trash, and a Trash restore brings a direct chat back closed. It is not a way to reopen a retired chat.
- Replace `<run_ts>` with the recorded value, keeping the quotes and all six decimal places.

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
     AND t.archived_at IS NOT NULL
     AND t.updated_at = '<run_ts>'
  RETURNING t.id
)
SELECT (SELECT count(*) FROM restored) AS restored_rows,
       (SELECT count(*) FROM ops_retire_direct_chats_snapshot) AS snapshot_rows;

-- COMMIT only if restored_rows is what you expect (normally = snapshot_rows).
-- Otherwise ROLLBACK and investigate.
COMMIT;
```

Notes on the restore:
- **If `restored_rows` is 0 but `snapshot_rows` isn't,** `<run_ts>` is wrong. Run `ROLLBACK`, copy it again from 7g, and retry.
- **Rows changed after the run are skipped.** For example, staff unarchived or re-archived the thread, or a message sent during the run bumped its `updated_at`. `restored_rows` is then lower than `snapshot_rows` by that many. This query lists them, before or after the restore, so a human can decide about each one:
  ```sql
  SELECT t.id, t.lifecycle, t.archived_at, t.archived_by, t.updated_at
    FROM ops_retire_direct_chats_snapshot s
    JOIN chat_threads t ON t.id = s.id
   WHERE t.updated_at <> '<run_ts>' AND t.updated_at <> s.updated_at;
  ```
- **If the restore fails with a foreign-key error (SQLSTATE 23503),** a user recorded in the snapshot has been deleted since. Run `ROLLBACK`. Then do to the snapshot what `ON DELETE SET NULL` did to the live rows, and run the restore again:
  ```sql
  UPDATE ops_retire_direct_chats_snapshot s SET lifecycle_changed_by = NULL
   WHERE lifecycle_changed_by IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM users u WHERE u.id = s.lifecycle_changed_by);
  UPDATE ops_retire_direct_chats_snapshot s SET archived_by = NULL
   WHERE archived_by IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM users u WHERE u.id = s.archived_by);
  ```
- **Restored threads work normally again,** even though new direct chats still can't be created. That includes resuming a restored paused thread.

**Last resort: restore the pre-run backup.** This loses every other production write made since the backup. Use it only if something far worse than this script went wrong.

**Cleanup:** after the agreed observation window, run `DROP TABLE ops_retire_direct_chats_snapshot;`.

---

## Appendix: local verification (2026-09-15, OPOS #26412)

The run used a fresh local Postgres database, `gd_retire_run_26412`, created with `createdb` and dropped afterwards. No remote database was involved. Every SQL block in sections 4, 5, 7 and 10 was run verbatim, with `<actor>` = 900001 and `<run_ts>` taken from 7g. Pre-flight query 6 and post-check 7h were added later, by OPOS #26467, and were run on a separate throwaway database (see `HANDOFF.md`). The first verification, of the original script (OPOS #26402), is in this file as of commit `dfa632d`. Its findings are what OPOS #26412 fixed.

1. **Migrations**, applied the way the tests apply them:
   ```
   TEST_DATABASE_URL=... go test ./internal/chatlifecycle/ -count=1 -run '^TestRetireAllDirectThreadsIsIdempotent$' -v
   ```
   Output: `[migrate] done: 121 newly applied, 121 total migration files`, then `PASS` and `ok`. Afterwards `chat_threads` and `chat_messages` were empty. The 6 `users` rows present come from the migrations.
2. **Seed:**
   - users: 900001 (`admin`, the actor), 900002 (`supervisor`), 900003 (`user`), 900004 (`is_admin = 1`, `staff_tier = 'user'`), and 20 app users;
   - 10 threads (the table below);
   - 5 messages.
3. **Pre-flight** (read-only session):
   - `will_end = 4`, `will_archive = 2`;
   - breakdown: `ended/active/f 2`, `open/active/f 1`, `open/active/t 1`, `open/pending/f 1`, `paused/active/f 1`;
   - untouched: `direct/ended/t 1`, `support/ended/f 1`, `support/open/f 1`, `support/paused/f 1`;
   - messages in the rows to change: 4;
   - actor: `900001 | admin | 1 | active`.
4. **Refusals.** Every one exited 1, and the checksum of every `chat_threads` row was unchanged afterwards (`md5 0127123e…`):
   - `-actor=900003` → `retire-direct-chats: refused, nothing was changed: user 900003 is not dashboard staff (staff_tier "user"); pass the id of a super_admin, admin, supervisor or employee account`
   - `-actor=900004` (`is_admin = 1`) → the same message, for user 900004
   - `-actor=999999999` → `retire-direct-chats: refused, nothing was changed: no user has id 999999999; pass the id of a dashboard staff account (staff_tier super_admin, admin, supervisor or employee)`
   - no `-actor` → `retire-direct-chats: -actor=<staff_user_id> is required`
5. **Snapshot:** `snapshot_rows = 6`.
6. **Run 1** (`-actor=900001`), exit 0:
   ```
   retire-direct-chats: ended+archived 6 thread(s)
   retire-direct-chats: ended 4 open/paused thread(s), archived 2 already-ended thread(s)
   ```
7. **Post-checks:**
   - 7a `0`, 7c `0 rows`, 7d `0 rows`, 7f `4`.
   - 7b `4`. A first version of 7b without `lifecycle_changed_at = updated_at` printed `5`, because it also counted 910006, which an earlier run had ended. That is why the condition is there.
   - 7e: only `direct | ended | t` changed, from 1 to 7, which is higher by N = 6.
8. **Run 2** (same command), exit 0: `ended+archived 0 thread(s)` and `ended 0 open/paused thread(s), archived 0 already-ended thread(s)`. The checksum `2377f9b3…` was identical to the one taken after run 1.
9. **Restore, first pass:** `restored_rows = 6 | snapshot_rows = 6`, and the checksum was back to `0127123e…`, identical to before run 1. That pass used an earlier guard, matching on the reason plus the actor.
   - A code review then found that this guard also matches a thread staff unarchived and re-archived after the run, so the restore would silently undo that action.
   - The guard was replaced by the `updated_at = '<run_ts>'` guard now in section 10, and post-check 7g was added to record `run_ts`.
10. **Second pass** (same database, snapshot re-taken from the restored state):
    - **Run 1:** the same two output lines, exit 0.
    - **Post-checks:** 7a `0`, 7b `4`, 7c `0 rows`, 7d `0 rows`, 7f `4`. 7g returned one row: `2026-09-15 13:35:38.522824 | 6`.
    - **Simulated staff action after the run:** 910002 was unarchived, then re-archived as 900001, using the same updates the dashboard makes. 7g then showed `…38.522824 | 5` and `…39.179944 | 1`. A read-only count showed the earlier guard would have restored 6 rows, 910002 included.
    - **Restore** with `<run_ts>` = `2026-09-15 13:35:38.522824`: `restored_rows = 5 | snapshot_rows = 6`.
      - The skipped-rows query listed only 910002, still ended and archived at `13:35:39.179944` by 900001.
      - The checksum of every other `chat_threads` row was `69426f0e…` both before run 1 and after the restore.
      - `chat_messages` stayed at 5.

| id | kind | status | Before | After runs 1 and 2 | After restore |
|---|---|---|---|---|---|
| 910001 | direct | active | open, not archived, 2 messages | ended + archived by 900001, 2 messages | as before |
| 910002 | direct | pending | open, not archived | ended + archived by 900001 | as before |
| 910003 | direct | active | open, archived 2026-09-01 10:00 by 900002 | ended by 900001; **archive stamp kept** (2026-09-01 10:00, 900002) | as before |
| 910004 | direct | active | paused ("cooling off", 900002) | ended + archived by 900001 | as before |
| 910005 | direct | active | ended ("closed by staff", 900002), not archived | archived by 900001; **end stamp kept** | as before |
| 910006 | direct | active | ended with the script's reason by 900001 on 2026-09-10, not archived (the original script's partial state) | archived by 900001; end stamp kept | as before |
| 910007 | direct | declined | ended and archived | unchanged, `updated_at` included | unchanged |
| 910008 | support | active | open | unchanged | unchanged |
| 910009 | support | active | paused | unchanged | unchanged |
| 910010 | support | active | ended, not archived | unchanged | unchanged |

In run 1, every changed row's `lifecycle_changed_at` (where the run set it), `archived_at` (where the run set it) and `updated_at` was the same value, `2026-09-15 13:26:49.371534`: one transaction.

Counts by kind, lifecycle and archived:

| | Before | After runs 1 and 2 | After restore |
|---|---|---|---|
| `direct / open / f` | 2 | 0 | 2 |
| `direct / open / t` | 1 | 0 | 1 |
| `direct / paused / f` | 1 | 0 | 1 |
| `direct / ended / f` | 2 | 0 | 2 |
| `direct / ended / t` | 1 | 7 | 1 |
| `support / open / f` | 1 | 1 | 1 |
| `support / paused / f` | 1 | 1 | 1 |
| `support / ended / f` | 1 | 1 | 1 |
| `chat_messages` total | 5 | 5 | 5 |

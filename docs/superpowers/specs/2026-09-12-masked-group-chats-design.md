# OPOS #25284 — Masked, Staff-Mediated Group Chats

**Status:** Approved design, ready for implementation planning.
**Date:** 2026-09-12

## 1. Problem

The ticket's literal title is "replace direct donor↔owner chat with staff-mediated
masked group chats," but the client's actual policy, given during scoping, is
broader than the donor/owner pair alone:

- **Donor↔beneficiary, donor↔volunteer, and beneficiary↔volunteer must never
  communicate directly, in any form.** Reasons given: protecting donor and
  beneficiary privacy, not burdening donors with unsolicited contact, and the
  fact that volunteers are numerous, rotating, and work irregular hours — donor
  and beneficiary data must not be exposed to them.
- The **only** way these roles interact is through a group chat **created by
  staff**, where every non-staff participant is shown only a staff-assigned
  label — never a real name, username, phone number, or avatar. Staff always
  sees real identities.
- **Volunteers may also be organized into staff-created team groups**
  (e.g. "Distribution team") — these are *not* masked; real names, ordinary
  group chat, staff curates membership.
- A donor or beneficiary can **request** to be connected (analogous to the
  existing marriage module's "request to talk to this partner" flow); staff
  reviews and either creates the masked group or declines.
- Volunteer↔staff and donor↔staff 1:1 chat (today's `kind=support` chat) is
  **unaffected** — it already involves only that person and staff.
- The marriage module's existing masked-relay chat is **unaffected** — it
  already does exactly what this policy asks for for one specific pair
  (requester/owner) and stays as its own separate implementation.

## 2. Current state (audited before designing anything)

Four existing chat systems live under `backend/internal/`, each a fixed
two-column-pair thread (no group-membership schema exists anywhere today):

| Package | Pair | Masking today |
|---|---|---|
| `chat` | `donor_user_id` / `owner_user_id` (+ a `kind='support'` variant for donor/volunteer/beneficiary↔staff) | None — real names/phones both ways |
| `staffchat` | staff↔staff | N/A, unaffected by this project |
| `casevolchat` | `volunteer_user_id` / `beneficiary_user_id` | None — deliberately unmasked today ("they need to actually know who they're talking to"), **being shut down entirely** by this project |
| `marriagechat` | `requester_user_id` / `owner_user_id` | **Already masked** — `sender_role` only, generic placeholder/profile-code identity, staff unmasked. Out of scope, stays as-is. |

All four share `internal/chatlifecycle` for pause/end/archive/export/delete
(`lifecycle`, `lifecycle_reason`, `lifecycle_changed_at/_by`,
`archived_at/_by` — **not** a single `status` enum). Delivery is polling only
(mobile list 5s / open thread 3s; admin-web identical) — no websockets
anywhere in the stack. `internal/notify` fires a push on every new message,
looping over counterpart IDs for fan-out.

The donor↔owner chat is entered only from a donation (`My Donations` →
"chat with owner") or a campaign's donor list ("message this donor"); starting
one discloses "Support can also view this chat," and staff can already view
any thread and post into it anonymously as "Support"
(`ChatHandler.AdminPostMessage`) — that half of "staff-mediated" already
exists for this specific pair.

## 3. Decision: one new package, two modes (not two packages, not extending `chat` in place)

New package `internal/chatgroups`. A `masked` flag on each group governs
identity projection; everything else (threads, membership, messages, reads,
lifecycle, notification fan-out, contact-info filtering) is shared code.

**Why not two separate packages** (a `teamgroups` + a `maskedgroups`): the two
use cases share ~90% of their surface. They differ in exactly one dimension —
identity projection at read time — which is resolved once, at the read
boundary, into two distinct response types (see §5). If that projection
decision is ever found scattered across more than the message-projection and
the contact-filter gate, that is the signal the design has drifted and needs
revisiting — not a reason to fork the schema today.

**Why not extend the existing `chat` package in place**: `chat_threads` is a
live, working table that the still-needed `kind=support` traffic depends on.
The audit found its two-column-pair assumption baked into the K19 contact-block
filter, the CSV export, and the notification fan-out loop. Retrofitting
N-member support into all of that is higher blast-radius than building a new,
isolated package and is not necessary — nothing about `kind=support` needs to
change.

## 4. Data model (new migration, `backend/migrations/NNN_chat_groups.sql`)

No foreign-key constraints (matches this codebase's existing convention;
handlers validate existence explicitly). CHECK constraints are used, matching
the convention in migration 073.

```
chat_group_threads
  id                    BIGINT PK
  kind                  VARCHAR(16) NOT NULL CHECK (kind IN ('masked','team'))
  member_title          VARCHAR(200)   -- shown to members; team groups only,
                                       -- NEVER settable/shown for masked groups
                                       -- (prevents staff typing an identifying
                                       -- title like "Ahmed <-> donor Zaid")
  created_by_staff_id   INTEGER NOT NULL
  lifecycle             VARCHAR(16) NOT NULL DEFAULT 'open'   -- open|paused|ended
  lifecycle_reason      TEXT
  lifecycle_changed_at  TIMESTAMP
  lifecycle_changed_by  INTEGER
  archived_at           TIMESTAMP
  archived_by           INTEGER
  created_at, updated_at

chat_group_staff_notes            -- staff-only context, physically unreachable
  group_id              BIGINT NOT NULL       -- from any member-facing query
  context_note          TEXT     -- e.g. "Case #123 coordination"
  created_by            INTEGER NOT NULL
  updated_at

chat_group_members
  id                    BIGINT PK   -- THIS is the client-facing speaker handle,
                                    -- never user_id (see §5)
  group_id              BIGINT NOT NULL
  user_id               INTEGER NOT NULL
  role_in_group         VARCHAR(16)   -- donor|beneficiary|volunteer|staff, informational
  masked                BOOLEAN NOT NULL DEFAULT true   -- ALWAYS derived
                                       -- server-side from the parent group's
                                       -- `kind` inside AddMember — never
                                       -- accepted as caller input, so a
                                       -- masked group cannot end up with an
                                       -- unmasked member by a client mistake
  masked_label          VARCHAR(100)   -- staff-assigned; auto-generated on add
                                       -- ("Donor 1"), staff can override.
                                       -- NOT the same concept as user_profiles
                                       -- .alias_name (a user's own privacy
                                       -- preference) — that is NEVER consulted
                                       -- on the masked read path.
  added_by_staff_id     INTEGER NOT NULL
  added_at              TIMESTAMP
  removed_at            TIMESTAMP     -- soft-remove ONLY, never DELETE — a
  removed_by            INTEGER       -- deleted row breaks historical alias
                                      -- resolution and fails open
  CHECK (NOT masked OR (masked_label IS NOT NULL AND masked_label <> ''))
  UNIQUE (group_id, user_id)
  -- partial unique index on (group_id, lower(masked_label)) WHERE masked
  --   AND removed_at IS NULL, so two active masked members can't collide

chat_group_messages
  id                    BIGINT PK
  group_id              BIGINT NOT NULL
  sender_user_id        INTEGER NOT NULL   -- ALWAYS the real id; masking is a
                                           -- read-time projection, never a
                                           -- storage-time decision
  body                  TEXT NOT NULL
  created_at            TIMESTAMP

chat_group_reads
  group_id, user_id, last_read_msg_id
  UNIQUE (group_id, user_id)

chat_group_contact_blocks              -- mirrors chat_contact_blocks; the
  group_id, message_id, ...            -- K19 phone/contact-info filter gates
                                        -- on `group.kind == 'masked'`, NOT on
                                        -- the existing staff-exemption logic
                                        -- (which would silently disable the
                                        -- filter, since staff is *always* in
                                        -- a masked group)

chat_group_connect_requests
  id                    BIGINT PK
  requester_user_id     INTEGER NOT NULL
  context_type          VARCHAR(16) CHECK (context_type IN ('donation','case'))
  context_id            BIGINT NOT NULL
  target_hint           BIGINT     -- nullable; populated when the app already
                                   -- knows the specific counterpart (e.g. a
                                   -- sponsorship-derived beneficiary) — a bare
                                   -- donation id does not always determine one
  message               TEXT NOT NULL
  group_id              BIGINT     -- set when approved; approval creates the
                                   -- group in the SAME transaction (§6), so
                                   -- there is never an "approved, no group
                                   -- yet" dangling state
  status                VARCHAR(16) NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending','approved','declined'))
  decline_reason        TEXT
  decided_by_staff_id   INTEGER
  decided_at            TIMESTAMP
  created_at            TIMESTAMP
  -- partial unique index on (requester_user_id, context_type, context_id)
  --   WHERE status = 'pending' — a resubmit is an idempotent no-op, not spam
```

## 5. Masking mechanism — structurally leak-proof, not "remember to hide it"

Two distinct Go response types, mirroring `marriagechat`'s proven pattern
(not `chat`'s — the existing `chat.ListMessagesForViewer` returns the same
struct as the unmasked path with only the name blanked, and its
`SenderUserID` field ships to the mobile client regardless; that is the
mistake this design avoids by construction):

```go
// GroupMessage — the type a non-staff member's response is built from.
// Has NO user-id field. It is not possible to leak a real identity through
// this type because the type cannot hold one.
type GroupMessage struct {
    ID              int64
    SenderMemberID  int64  // chat_group_members.id — scoped to ONE (group,
                           // user) pair, lets the UI group bubbles by speaker
                           // WITHOUT correlating that person across groups
    SenderLabel     string // masked_label, or the real name for team groups
    IsMine          bool
    Body            string
    CreatedAt       time.Time
}

// AdminGroupMessage — staff only. Carries the real identity.
type AdminGroupMessage struct {
    GroupMessage
    SenderUserID int64
    SenderName   string
}
```

The for-member query joins `chat_group_members` and selects `masked_label`
(or the real name for `kind='team'`) directly in SQL — `sender_user_id` is
scanned into a local variable purely to compute `IsMine` and is never
assigned to a struct field that reaches JSON. `ListMessagesForMember` and
`AdminListMessages` are named so it is not possible to reach for the wrong
one by accident (the naming rule `chat.go` itself documents but the design
must actually follow).

**No avatars in masked groups.** The client renders an initial derived from
the label or a neutral role glyph. Team groups return real avatar URLs.

**Alias quality:**
- Auto-generated on add (`"Donor 1"`, `"Beneficiary 1"`, localized) so
  `masked_label` is never empty by default — staff typing one is an override,
  not a required step.
- `moderation.ScanContact` runs over the label text itself at write time
  (a staff member pasting a phone number into a label is a realistic slip).
- If, despite the CHECK constraint, no label resolves for a masked member
  at read time, the projection returns a fixed neutral placeholder — it must
  never fall through to any query that touches `user_profiles`.

**Removal is a soft-delete** (`removed_at`/`removed_by`). Membership lookups
for access control filter `removed_at IS NULL`; label resolution for historical
messages does not — so a removed member's past messages keep their label.

**Notifications get their own template**, taking an alias, never a name:
`GroupMaskedNewMessageMsg(alias, preview, groupID)`, resolved *before* the
fan-out loop, with its own `RelatedEntityType` (`chat_group_thread`) so it
deep-links correctly and is never confused with the existing
`ChatNewMessageMsg` (which puts a real name in the title — reusing it for a
masked group would leak the sender on the recipient's lock screen, and the
notification record persists in the in-app Alerts tab permanently, not just
transiently). Team groups keep the existing name-bearing template.

## 6. Connect-request flow

A donor (from a donation) or a beneficiary/volunteer (from an approved case)
submits a request: context type + id, plus a free-text message explaining
what they're asking for. The admin inbox resolves and displays the context
server-side (campaign title, case number, donation amount/date) — never a
bare id, since staff cannot make a privacy decision from `context_id: 4471`.

**Approving a request creates the group in the same transaction** — staff
sets title (team groups only), adds members, and assigns/accepts
auto-generated labels right in the approval dialog. There is no
"approved but no group yet" intermediate state to track or lose. Declining
requires a reason, shown back to the requester.

## 7. Retiring the old donor↔owner direct chat

Removing the Flutter buttons is not access control. The retirement is:

1. `ChatHandler.RequestThread` refuses new `kind='direct'` requests
   server-side, unconditionally, once this ships.
2. Every existing open `kind='direct'` thread transitions through
   `chatlifecycle` to `ended` (permanently read-only — "reopening is a new
   thread" is the existing package's own model) and then `archived`.
   `CanSend()` is `Lifecycle == StateOpen`; archiving alone does not stop
   sends, which is why `end` must happen first.
3. This is scoped precisely to `WHERE kind = 'direct'` — `kind='support'`
   (donor/volunteer/beneficiary↔staff) is untouched throughout.
4. No migration of old threads into the new system — they are historical
   records only, still visible to staff for reference.
5. Flutter: remove `_chatWithOwner`/`_suggestChat` entry points and the
   donor/owner branch of `ChatActions.startChat`.
6. `casevolchat`'s direct-messaging capability and UI are removed entirely
   (not just deprecated) — case coordination moves to a staff-created masked
   group per case, using the new `chatgroups` package, added under
   `context_type='case'`.

**Coordination note:** the branch `fix/messaging-channels-reachable`
(unmerged, two commits) fixes and surfaces the exact entry points this
section deletes. Per the scoping conversation, that branch is **dropped**,
not merged — its fixes are for a feature this project removes.

## 8. Registering a fifth chat kind

`chatlifecycle.Systems()` is a hardcoded, tested slice of four. Adding
`chatgroups` touches: the systems registry, the three lifecycle test files
that enumerate kinds by name, `deleteguard`'s per-kind message/case counts
(made group-aware — a departing member doesn't destroy the group, only their
own message attribution), and admin trash/restore/export. This is its own
checklist item in the implementation plan, not an incidental detail.

## 9. Staff membership & permissions

- `role_in_group='staff'` rows are for notification targeting and ownership
  ("who is responsible for this group"), not the access-control mechanism.
- Actual read/post/manage authority comes from the existing `messages`
  permission on admin routes — any admin holding it can act, matching every
  other chat system here (not gated to the specific staff member added to
  the group).
- Members see all staff replies under one collective label ("Support"),
  never a specific admin's name — matching the existing anonymous-support
  convention in `chat`.
- Group CRUD is gated `perm("messages", ...)`. Viewing unmasked real
  identities in a masked group additionally requires `sensitive_data:view`
  (matching how contact info is already gated in `admin_detail.go`).
- Group creation, membership changes, and label edits are logged via
  `internal/staffactivity` — "who unmasked whom" is the audit question this
  feature will eventually be asked.

## 10. Pagination & fan-out

`ListMessagesForMember`/`AdminListMessages` take `(groupID, viewerID,
afterMessageID, limit)` — the poll passes the highest id it already holds and
normally receives an empty array back. This is a deliberate improvement over
the *existing* chat/marriagechat queries, which are unbounded
(`WHERE thread_id = $1 ORDER BY id ASC`, no LIMIT) — not repeating that gap
in new code, and not a scope increase into fixing the old systems.

Notification fan-out batches the recipient lookup into one query rather than
one per member; the existing per-recipient `go func()` pattern is kept
(it currently carries no request-scoped context, so it survives the HTTP
response being written — verify this holds for the new call sites too).

## 11. Client changes

**Flutter** (`humanitarian/lib/modules/chatgroups/`, mirroring the structure
of `modules/chat/`):
- "My Connections" (masked groups) and "My Team Groups" (volunteer teams)
  sections in the Messages tab.
- Conversation screen: label + no avatar for masked groups; real name +
  avatar for team groups.
- "Request to connect" entry point from a donation and from an approved case.
- Removes the old direct-chat buttons (§7) and all of `casevolchat`'s
  messaging UI.

**Admin-web** (new page, modeled on the existing `MarriageChatsPage.tsx`
staff-sees-real/participants-see-masked split):
- Create-group flow: pick kind, add members with auto-suggested labels,
  staff can override.
- Connect-request inbox: resolved context, approve (opens create-group
  pre-filled) or decline with a reason.
- Old donor/owner section of `MessagesPage.tsx` becomes read-only history.
- `CaseVolunteerChatsPage.tsx`'s direct-message view is retired alongside
  the backend shutdown, replaced by an entry into the new group-creation
  flow scoped to that case.

## 12. Testing

- `TEST_DATABASE_URL`-gated Go integration tests for the Store layer: group
  CRUD, the connect-request-approval-creates-group transaction, and —
  specifically — an HTTP-level test that seeds a masked group with a
  distinctively-named member, hits the mobile route as the counterpart, and
  asserts the raw response body contains neither the real name, the phone,
  nor the sender's user id as a string anywhere. This is the single
  highest-value test in the whole feature and must be mutation-checked.
- `flutter analyze` / admin-web `tsc --noEmit` + `npm run build`, per this
  project's standard gate.
- `ecc:tdd-guide` is used before writing implementation code; `ecc:code-reviewer`
  and `ecc:security-reviewer` run on every PR touching `chatgroups` (privacy-
  and auth-sensitive by nature); `ecc:doc-updater` updates any architecture
  docs once this ships, per this project's standing rule for
  architecture-level changes.

## 13. Implementation phasing

This spec describes one coherent policy, but it is too large for one PR —
consistent with how every other task in this project has shipped (one
branch per slice, tested and verified before the next). The implementation
plan should split it roughly as:

1. `chatgroups` schema + Store + masked/unmasked projection + its own test
   suite (§4, §5) — no routes, no client changes yet. The masking test from
   §12 is written and passing before anything else builds on top of it.
2. Mobile + admin routes, permission gating, `chatlifecycle`/`deleteguard`
   registration (§8, §9, §10).
3. Connect-request flow end to end (§6).
4. Retirement of the old donor↔owner direct chat and `casevolchat`'s direct
   mode (§7) — sequenced *after* step 2 so the replacement exists before the
   old path closes.
5. Flutter client (§11).
6. Admin-web client (§11).

Each phase gets its own branch, its own tests, and its own PR, matching this
project's established workflow.

## 14. Explicitly out of scope

- The marriage module's masked relay chat — already correct, untouched.
- `staffchat` (internal staff↔staff) — unaffected.
- The existing `kind=support` donor/volunteer/beneficiary↔staff 1:1 chat —
  unaffected, stays direct and unmasked (it is already just that person and
  staff).
- Real-time delivery infrastructure (websockets) — polling is kept
  deliberately; the fix here is bounding the existing unbounded query, not
  replacing the transport.
- Migrating historical donor↔owner thread content into the new system.

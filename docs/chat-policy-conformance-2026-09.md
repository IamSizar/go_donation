# Chat policy conformance audit — 2026-09

Read-only audit of every chat system in the product against the eight rules the
client stated in OPOS #25284. Audited at `origin/main` = `fcc5b10`.

Nothing in this pass changes behaviour. Where a rule does not hold, the entry
says exactly what is reachable, by whom, and the smallest fix.

Evidence convention: every claim cites `file:line`. Where a rule is judged to
hold because a code path *cannot* express the forbidden thing, the type or the
statement that makes it impossible is cited, not the comment that claims it.

---

## The rules, as stated

1. No communication between donor, beneficiary and volunteer, in any
   direction, ever.
2. No communication between volunteer and beneficiary. Volunteers talk to
   staff, or to specific volunteers staff choose.
3. The donor is contacted only by staff.
4. A volunteer can contact staff for instructions.
5. Volunteer chat happens in groups created by staff, who add specific
   volunteers (field team, training team, distribution team).
6. A masked group between donor, beneficiary and staff is created by staff,
   who may add donors, beneficiaries or volunteers. It hides real names; staff
   assign a label instead.
7. Marriage: users never message each other. They ask staff, and staff open a
   masked chat that shows neither party's real data.
8. Every chat can be paused, resumed, archived, exported as a file, and
   deleted.

---

## Verdict table

| # | Rule | Verdict | Evidence |
|---|---|---|---|
| 1 | No donor ↔ beneficiary ↔ volunteer comms | **Partial** | Origination is closed: `backend/internal/chat/chat.go:104-107` (`RequestThread` returns `ErrDirectChatRetired` and writes nothing); `backend/cmd/server/main.go:736`. But **pre-existing** `chat_threads` rows remain postable — `backend/internal/handlers/chat.go:387-411` checks only `status='active'` and the lifecycle gate, never the thread's kind. Closing them is a manual script run (`backend/cmd/retire-direct-chats`, `backend/internal/chatlifecycle/retire.go:1-24`), not a migration. Second gap: team groups accept any role (see below). |
| 2 | No volunteer ↔ beneficiary | **Holds** (with the team-group caveat) | `casevolchat` is retired to a single read-only counter: `backend/internal/casevolchat/casevolchat.go:1-13, 51` — the package exposes only `MessageCountForSignup`, no thread create, no post, no list. It is registered nowhere in `backend/cmd/server/main.go` (grep for `casevolchat` there returns no route). App side: no code remains, only four dead translation strings at `humanitarian/lib/localization/app_translations.dart:31-32, 385, 3280-3281`. |
| 3 | Donor contacted only by staff | **Partial** | The only donor-initiated channel the app can open is staff-terminated: `/chats/support` resolves the recipient from `app_settings.support_user_id` (`backend/internal/handlers/chat.go:207-236`), and `/chat-groups/connect-requests` goes to a staff inbox (`backend/internal/handlers/chat_group_connect.go:34-51`). Same residual legacy-thread exposure as rule 1. |
| 4 | Volunteer can contact staff | **Holds** | `POST /chats/support` (`backend/cmd/server/main.go:739`) is open to any non-guest account with no role restriction; it opens ACTIVE, not pending, so the first message actually sends (`backend/internal/chat/chat.go:112-127`). App entry: `humanitarian/lib/modules/chat/screens/messages_screen.dart:145-150`. |
| 5 | Volunteer groups created by staff | **Holds** | Group creation exists only on the admin group behind `messages:add` — `backend/cmd/server/main.go:1027`, `:1038` (add member), `:1039` (remove). There is **no** participant-facing create route: participants get only list/messages/read/connect-request (`backend/cmd/server/main.go:839-846`). `CreateGroup` refuses any kind but `masked`/`team` (`backend/internal/chatgroups/chatgroups.go:154-156`). |
| 6 | Masked group hides real identity | **Holds — structurally** | The type non-staff responses are built from cannot carry identity: `GroupMessage` has `SenderMemberID`, `SenderLabel`, `IsMine`, `Body`, `CreatedAt` and nothing else (`backend/internal/chatgroups/chatgroups.go:122-129`) — no user id, no name, no phone. The masking is in SQL, not post-filtering: `backend/internal/chatgroups/chatgroups_reads.go:107-114` resolves the label as `CASE WHEN g.kind='masked' THEN (staff → 'Support', else masked_label) ELSE full_name END`. `masked` is derived from the group's kind and never accepted from the caller (`backend/internal/chatgroups/chatgroups_members.go:232, 253`). Real identities live in a separately named type reachable only from admin routes: `AdminGroupMessage` (`chatgroups.go:135-141`), `AdminListMessages` (`chatgroups_reads.go:151`). Staff-typed labels are scanned for contact details (`chatgroups_members.go:59-64`, `refuseContactInLabel`), and message bodies carrying a phone/email are refused and recorded (`backend/internal/chatgroups/chatgroups_admin.go:171-189`). |
| 7 | Marriage: staff open a masked chat | **Holds** | A thread exists only after staff approve a meeting request: `backend/cmd/server/main.go:1089` (`marriage:edit`) → `ApproveMeetingRequest`. There is no participant route that creates a thread (`main.go:825-830` is list/accept/decline/messages only). Masking is structural: the mobile `ThreadView` carries `OtherLabel` and no id/name/phone (`backend/internal/marriagechat/marriagechat.go:337-346`), filled with the profile's own public `profile_code` or the literal `"interested_member"` (`marriagechat.go:389-393`); `Message` carries `SenderRole` only (`marriagechat.go:400-406`). Real names appear only on the `Admin*` types (`marriagechat.go:510-519`). |
| 8 | Pause / resume / archive / export / delete | **Holds** | One implementation for all five systems: `backend/internal/chatlifecycle/chatlifecycle.go:53-59` defines end/pause/resume/archive/unarchive; `apply.go:74` applies them. Routes, staff-only by construction (admin group): `backend/cmd/server/main.go:1064-1071` — lifecycle + DELETE for donor, staff, marriage and group kinds. Sending is gated in every system: `refuseIfNotSendable` at `handlers/chat.go:411,554`, `chat_group.go:274`, `chat_group_admin.go:265`, `marriage_chat.go:309,394`, `staff_chat.go:201`. **Export** is a dashboard-side file download, not a server route: `admin-web/src/lib/chatExport.ts:1-30`, wired per system at `MessagesPage.tsx:345`, `StaffChatPage.tsx:65-73`, `MarriageChatsPage.tsx:255`, `components/chatGroups/GroupHeader.tsx:57-64` — each behind a PIN step-up (`components/ExportCsvButton.tsx:116-128`). Chat groups included. |

---

## What does not hold

### V1 — Legacy direct donor↔owner threads stay live until an operator runs a script

**Severity: the main finding.** Rules 1 and 3.

Origination is dead (`chat.go:104-107`), but nothing in the *code* stops a
message on a `chat_threads` row that already exists and is still
`lifecycle='open'`, `status='active'`:

- `backend/internal/handlers/chat.go:387-411` — `PostMessage` checks the caller
  is a party, that `status='active'`, and `refuseIfNotSendable`. It never asks
  whether the thread is a retired direct donor↔owner thread.
- `backend/internal/chatlifecycle/retire.go:10-13` states this outright: *"Left
  paused, staff could resume one into a working direct chat: sending checks
  lifecycle, never kind."*
- The closure is a one-off command, `backend/cmd/retire-direct-chats`, with a
  production runbook (`docs/runbooks/retire-direct-chats.md`). There is no
  migration under `backend/migrations/` that ends or archives these rows —
  the newest migrations are 121–124 and none touches `chat_threads.lifecycle`.

So conformance depends on a human having run the script on each environment,
and on no staff member later resuming one of those threads. A resumed thread
is fully functional donor↔beneficiary messaging.

Secondary leak on the same rows: `GET /chats` returns the counterpart's
`other_user_id` and `other_name` for a peer thread — only the **phone** is
withheld peer-to-peer (`backend/internal/chat/chat.go:412-416`,
`withholdPeerPhone`), while the name passes through only the counterpart's own
privacy setting (`chat.go:433-442`). The retire run archives the threads, and
`chat.go:389` filters `archived_at IS NULL`, so they disappear — again, only
once the script has run.

**Who can reach it:** any donor or beneficiary who was already party to an
`active` thread, from `humanitarian/lib/modules/chat/widgets/chat_thread_tiles.dart:102`.
Also reachable by accepting an old pending invite:
`humanitarian/lib/modules/notifications/widgets/chat_request_actions.dart:47,93`
(the in-app notification tile) → `POST /chats/:id/accept` (`main.go:754`).

**Smallest fix:** make the refusal structural rather than operational. Add a
kind check to the donor-chat send and accept paths — refuse
`POST /chats/:id/messages` and `POST /chats/:id/accept` for any thread that is
not the support thread, mirroring `ErrDirectChatRetired`. One predicate in
`handlers/chat.go` next to the existing `status='active'` check closes both the
un-run-script case and the resumed-thread case. A backfill migration ending
`lifecycle='open'` direct threads would close the data side, but the code gate
is the smaller and more durable change.

### V2 — A `team` group accepts any role, so staff can build a real-name donor+beneficiary room

Rules 1, 2 and 5.

`role_in_group` is a free-form string all the way down, and `kind='team'` has
no role restriction:

- `backend/internal/handlers/chat_group_admin.go:122` — `RoleInGroup string` is
  taken verbatim from the request body; `:144-152` validates only that `kind`
  is non-empty and there is at least one member.
- `backend/internal/chatgroups/chatgroups.go:153-182` — `CreateGroup` validates
  the *kind* only. `insertMembers` (`chatgroups_members.go:228-262`) sets
  `masked = kind == KindMasked` and, for a team group, stores no label at all
  (`:243`).
- `backend/internal/chatgroups/chatgroups_reads.go:112-113` — in a non-masked
  group, every member reads every sender's `up.full_name`.
- The repo's own test creates exactly this shape: a `KindTeam` group whose sole
  member has `RoleInGroup: "donor"` —
  `backend/internal/chatgroups/chatgroups_admin_kind_test.go:24-32`.
- The dashboard offers it: the role select lists
  `['donor','beneficiary','volunteer','staff']`
  (`admin-web/src/lib/chatGroupForm.ts:40`,
  `components/chatGroups/MemberRowsEditor.tsx:149-163`) with no dependence on
  the chosen kind (`components/chatGroups/KindCards.tsx`).
- Team groups are also exempt from the `sensitive_data` step-up that masked
  groups require (`handlers/chat_group_admin.go:61-75`).

Rule 5 scopes team groups to volunteers ("field team, training team,
distribution team"); rule 6 scopes mixed-role rooms to *masked* groups. A team
group containing a donor and a beneficiary is real-name donor↔beneficiary
communication, which rule 1 forbids without exception.

**Who can reach it:** any staff member with `messages:add`
(`backend/cmd/server/main.go:1027`), through
`admin-web/src/components/chatGroups/CreateGroupDialog.tsx:90`, or by adding a
member later (`messages:edit`, `main.go:1038`). Not reachable by a participant.

**Ambiguity, stated rather than guessed:** this needs staff action, and rule 5
says staff choose the members. Whether the client intends "staff may put
whoever they like in a team group" or "team groups are volunteers-only" is not
settled by the rules as written. I did not find a decision record fixing it.

**Smallest fix:** restrict `role_in_group` for `kind='team'` to
`volunteer` and `staff` in `insertMembers`
(`backend/internal/chatgroups/chatgroups_members.go:228`), returning
`ErrInvalidInput` — one place, covering `CreateGroup`, `AddMember` and
`ApproveConnectRequest`, since all three route through it. Mirror it in the
dashboard by filtering the role options on the selected kind
(`admin-web/src/lib/chatGroupForm.ts:40`). Confirm the intent with the client
before changing behaviour.

### V3 — Stale app copy pointing at retired flows (cosmetic, not a policy breach)

- `humanitarian/lib/modules/chat/screens/messages_screen.dart:135` still says
  support chat "and case chats" are reachable; case chats no longer exist.
- `messages_screen.dart:217-218` — the empty state tells the user to "Start a
  chat from a donation (donor) or from your campaign donations (owner)", which
  is the retired `startChat` flow (`modules/chat/chat_actions.dart:14-16`).
  A user following that instruction finds no such control.

**Smallest fix:** reword both to point at the connect-request flow. Copy only;
no logic.

---

## Every chat entry point in the app, and who sees it

Gating is guest-vs-full-account throughout. **There is no donor / beneficiary /
volunteer role gate anywhere in the client** — every role separation is
delegated to the server.

| Entry point | File:line | Who sees it | Endpoint | Peer reach |
|---|---|---|---|---|
| Messages tab button | `modules/dashboard/screens/dashboard_screen.dart:734-740`, `:830-834` | Everyone, guests included (guest sees an unbadged door) | — | — |
| Bot navigation → Messages | `modules/bot/bot_navigation.dart:66` | Everyone incl. guest, ungated | — | — |
| Messages screen | `modules/chat/screens/messages_screen.dart:105`, guest gate `:117` | All full accounts; guest gets `GuestMessagesPrompt` | `GET /chats` | — |
| Support chat tile | `modules/chat/screens/messages_screen.dart:145-150` | All full accounts | `POST /chats/support` | **No** — staff only |
| "Message the staff team" (events) | `modules/marriage/screens/marriage_event_group_screen.dart:236-240`, guest gate `chat_actions.dart:39` | Full accounts | `POST /chats/support` | **No** |
| Existing 1:1 thread tile | `modules/chat/widgets/chat_thread_tiles.dart:102` | Parties of an existing thread | `GET/POST /chats/:id/messages` | **Yes — V1** |
| Incoming chat-request card | `modules/chat/widgets/chat_request_card.dart:36` | Invited party | `POST /chats/:id/accept` | **Yes — V1** |
| Notification tile accept/decline | `modules/notifications/widgets/chat_request_actions.dart:47,93`; gate `notification_tile.dart:231-236` | Non-guest, `chat_request` notifications | `POST /chats/:id/accept` | **Yes — V1** |
| Marriage hub → Chats | `modules/marriage/screens/marriage_event_group_screen.dart:231` (inside `if (!guest)` `:206`) | Any full account | `GET /marriage/chats` | Masked, staff-mediated |
| Marriage "Request meeting" | `modules/marriage/screens/marriage_search_screen.dart:534`, gate `:138` | Any full account | `POST /marriage/:id/request-meeting` | Via staff approval only |
| Chat-groups section | `modules/chatgroups/widgets/chat_groups_section.dart:70`; gate `messages_screen.dart:255` | Full accounts who are members | `GET /chat-groups` | Masked, or team (V2) |
| Group conversation | `modules/chatgroups/screens/chat_group_conversation_screen.dart:40` | Active members | `GET/POST /chat-groups/:id/messages` | As above |
| Connect request — donation | `modules/donations/screens/my_donations_page.dart:324-328` | Donor; hidden for guests (`connect_request_button.dart:80`) | `POST /chat-groups/connect-requests` | **No** — goes to staff |
| Connect request — case | `modules/proposal/screens/beneficiary_case_detail_screen.dart:190-194` | Anyone who can open a case | same | **No** |
| Connect request — campaign donations | `modules/sponsorship/screens/beneficiary_campaign_donations_screen.dart:462-465` | Campaign owner / beneficiary | same | **No** |
| My connect requests | `modules/chatgroups/screens/my_connect_requests_screen.dart:52`, `:187` | Requester | `GET /chat-groups/connect-requests/mine` | **No** |
| AI assistant card | `modules/chat/screens/messages_screen.dart:141` | Everyone incl. guest | `POST /assistant/chat` | **No** |

Two structural facts worth recording, both verified:

- **No deep links reach a chat.** The app navigates exclusively with
  `Get.to(() => Widget())`; there is no named-route table and no link handler.
- **No push notification opens a conversation.**
  `humanitarian/lib/main.dart:114-118` — `onMessageOpenedApp` only
  `debugPrint`s. The sole notification-driven chat entry is the in-app tile in
  the table above.

---

## Dashboard chat surfaces (staff)

| Surface | Route | Permission gate |
|---|---|---|
| Donor/owner + support chats | `admin-web/src/App.tsx:168`, `:179` | module `messages` (`lib/navLayout.ts:62`) |
| Staff ↔ staff chat | `App.tsx:169` | **None** — any staff tier (`navLayout.ts:63`); enforced server-side at `backend/internal/staffchat/staffchat.go:69` (`staff_tier <> 'user'` for both parties) |
| Marriage chats | `App.tsx:161` | module `marriage` (`navLayout.ts:44`) |
| Chat groups list / detail | `App.tsx:170`, `:172` | `messages:view`; masked groups additionally require `sensitive_data` (`handlers/chat_group_admin.go:61-75`, 403 rendered at `ChatGroupDetailPage.tsx:132-148`) |
| Connect requests inbox | `App.tsx:171` | `messages:view`; deciding needs `messages:edit` (`ConnectRequestPanel.tsx:137`) |

Lifecycle controls are one shared component,
`admin-web/src/components/ChatLifecycleControls.tsx` — pause `:161-165`,
resume `:166-170`, end `:171-175`, archive/unarchive toggle `:177-185`, delete
`:189-193` (hidden without `<deleteModule>:delete`, `:70`). Mounted on all
four systems. For chat groups the whole strip is hidden without
`messages:edit` (`GroupHeader.tsx:68-72`), leaving view-only staff with export
but no lifecycle — correct, not a defect.

Staff see real identities by design: `GroupRoster.tsx:144` (real name beside
the masked label), `GroupMessages.tsx:167` (`sender_name`),
`UserPicker.tsx:177-182` (name and phone). Exports carry `sender_name`
(`chatExport.ts:172`) and thread-list exports carry phone columns
(`MessagesPage.tsx:94,97`). All of this is behind staff permissions and the
export PIN, and is what rule 6's "staff always see real identities" requires.

---

## What a tester should try

Each of these **should be refused**. The expected refusal is given so a silent
success is unmistakable.

**Rule 1 / 3 — donor or beneficiary reaching a peer directly**

1. As a donor, `POST /api/chats/request` with any `owner_user_id`.
   → **410 Gone**, message *"direct donor-owner chat has been retired; use a
   staff-mediated connect request instead"*
   (`backend/internal/chat/chat.go:104-107`). Confirm no `chat_threads` row was
   written.
2. **The V1 probe.** Find an existing `chat_threads` row with
   `lifecycle='open'` and `status='active'` whose two parties are a donor and a
   beneficiary. `POST /api/chats/:id/messages` as either party.
   → Today this **succeeds (200)** on an environment where
   `cmd/retire-direct-chats` has not been run. That success is the violation.
   After the run it answers **409** with
   `code: chat_lifecycle_refused`, `lifecycle: "ended"` and
   `lifecycle_reason: "OPOS #25284 Phase 4 — direct donor-owner chat retired"`.
3. Same thread, as staff: pause it, then resume it, then post as a participant.
   → Currently **succeeds**. This is the resumed-thread half of V1 and is not
   fixed by running the script.
4. `POST /api/chats/:id/messages` as a user who is *not* a party.
   → **403**, *"you are not a participant in this chat"*
   (`chat.ErrNotParty`, `chat.go:34`).

**Rule 2 — volunteer ↔ beneficiary**

5. Probe every plausible case-volunteer route:
   `GET /api/case-chats`, `/api/volunteer-chats`,
   `/api/volunteer-missions/:id/chat`, `POST` to each.
   → **404** from the router. No handler is registered; `casevolchat` exposes
   only `MessageCountForSignup`.

**Rule 5 / 6 — group creation and masking**

6. As a donor/beneficiary/volunteer, `POST /api/admin/chat-groups`.
   → **401/403** — the route is on the admin group behind `messages:add`
   (`main.go:1027`); a mobile session is not a dashboard session.
7. As a non-staff member of a **masked** group, `GET /api/chat-groups/:id/messages`.
   → **200**, and every `sender_label` is either `"Support"` or a staff-assigned
   label. Assert the JSON contains **no** `sender_user_id`, `sender_name`,
   `phone` or `full_name` key anywhere. Have a staff member post, and confirm
   the staff bubble reads `"Support"`, not the staff member's name.
8. As a non-member, `GET /api/chat-groups/:id/messages` for a group you are not
   in. → **403**, `chatgroups.ErrNotMember`.
9. As staff, create a masked group with a label containing a phone number
   (`"Donor 0770 123 4567"`).
   → Refused before the group is written — `ErrLabelContact`
   (`chatgroups_members.go:59-64`); the transaction rolls back, so no group and
   no members exist afterwards.
10. As a participant in a masked group, send a message containing your phone
    number. → Refused, and the attempt appears in the dashboard's contact-block
    panel with the number rendered as `•••`
    (`admin-web/src/components/chatGroups/GroupContactBlocks.tsx:114`).
11. As staff, try to add a **guest** account to any group.
    → Refused, `ErrGuestMember` (`chatgroups_members.go:145-148, 182-186`).
12. **The V2 probe.** As staff with `messages:add`, create a group with
    `kind: "team"` and two members, `role_in_group: "donor"` and
    `role_in_group: "beneficiary"`. Open it as each member.
    → Today this **succeeds**, and each sees the other's real full name
    (`chatgroups_reads.go:113`). That success is the finding. It should be
    refused with an invalid-input error naming the role.

**Rule 7 — marriage**

13. As a user, try to create a marriage chat thread directly (any
    `POST /api/marriage/chats`, `/api/marriage/chats/start`).
    → **404**; no such route exists (`main.go:825-830`).
14. As the requester in an active marriage thread, read the thread list and
    messages. → `other_label` is the profile's public `profile_code`; as the
    owner it is the literal `"interested_member"`. No `other_user_id`,
    `other_name` or `other_phone` key in the payload
    (`marriagechat.go:337-346`).
15. As a non-owner, `POST /api/marriage/chats/:id/accept`.
    → **403**, *"only the profile owner can accept or decline"*
    (`marriagechat.ErrNotOwner`).

**Rule 8 — lifecycle**

16. As a participant (mobile session), `POST /api/admin/chats/:id/lifecycle`
    with `{"action":"pause"}`, and `DELETE /api/admin/chats/:id`.
    → **401/403**. The mobile API exposes no lifecycle route at all
    (`chatlifecycle/chatlifecycle.go:26-31`).
17. As staff, pause a chat in each of the four systems, then post as a
    participant. → **409**, `code: chat_lifecycle_refused`, with
    `lifecycle: "paused"` and the reason staff typed
    (`handlers/chat_lifecycle_gate.go:46-52`). The participant must still be
    able to **read** the full history.
18. As staff, end a chat, then try to resume it.
    → **409**, *"this chat has been ended and cannot be reopened"*
    (`chatlifecycle.ErrEnded`).
19. As staff, archive a chat. → It disappears from the participant's list
    (`chat.go:389`, `marriagechat.go:371`) and stays visible to staff.
    Unarchive restores it in the same state.
20. As staff, export each of the four conversation types and a chat group.
    → A PIN step-up, then a file. Confirm the per-conversation file contains no
    phone or email column (`chatExport.ts:24-27`).
21. As staff **without** the relevant `:delete` permission, look for the delete
    button. → Absent (`ChatLifecycleControls.tsx:70`). Call
    `DELETE /api/admin/chats/:id` directly → **403**.

---

## Not determined

- Whether `cmd/retire-direct-chats` has been run on production or staging. That
  is an operational fact this audit cannot read from the code, and rules 1 and
  3 currently depend on it. It should be confirmed against
  `docs/runbooks/retire-direct-chats.md`'s post-check queries before this audit
  is treated as a clean bill.
- Whether the client intends team groups to be volunteers-only (V2). The rules
  as written do not settle it.

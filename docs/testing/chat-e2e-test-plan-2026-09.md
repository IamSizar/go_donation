# Chat system — end-to-end test plan (September 2026)

**Who this is for:** the person doing the testing, on a real phone and on the
dashboard, against the Railway deployment. You do not need to read code.

**What it covers:** every rule the chat system enforces — who may talk to whom,
connect requests, masked and team groups, invites, the lifecycle, export,
sensitive data, guests, and Arabic.

**How it was written:** every button label, message and rule below was read out
of the code on `main` (commit `fcc5b10`). Where the code could not tell us
something, this plan says so instead of guessing. Those spots are marked
**[NOT CONFIRMED]**.

---

## Before you start — read this first

**Three things will surprise you if nobody warns you.**

1. **One-to-one chat between members no longer exists.** A donor can no longer
   start a chat with a campaign owner, and nobody can start one with anybody.
   The server refuses every attempt. The replacement is the *connect request*:
   the member asks our team, and our team opens a supervised group. So most of
   this plan is about groups, not one-to-one chats.

2. **Old direct chats have not been cleaned up yet.** There is a one-off
   maintenance job that closes the direct chats that existed before the change.
   It has **not been run on production**. So if an old account already has a
   direct chat, it will still be open and still work. That is expected. Do not
   report it as a bug.

3. **Kurdish is English on these screens.** This is deliberate, not a fault.
   See Part 3.

**Check the deployment is current.** Before testing, confirm the Railway
backend and the dashboard are both running the latest `main`. Everything in
this plan landed between PR #100 and PR #135. If the deployment is older, half
of this will fail for the wrong reason.

---

# Part 1 — The accounts you need

## 1.1 The three member roles

Every member account is one of three kinds. The kind is chosen once, during
sign-up, and the app calls it "account type".

| Role number | English label | Arabic label | Code prefix |
|---|---|---|---|
| 1 | **Grantor** (the app also says "Donor") | **مانح** | `GR-` |
| 2 | **Eligible Recipient** (the app also says "Beneficiary") | **مستحق** | `ER-` |
| 3 | **Volunteer** | **متطوع** | `VL-` |

*Where this comes from:* `backend/internal/handlers/registration.go:196` rejects
anything outside 1–3 with "Please select a valid role." The branches are at
`:253` (recipient), `:321` (grantor) and `:332` (volunteer). The English and
Arabic labels are at `humanitarian/lib/localization/app_translations.dart:812`
and `:3904`.

A fourth state exists: **no role yet**. A brand-new phone account has no role
until the registration form is submitted.

## 1.2 Staff tiers

Staff are not a separate kind of account. A staff member is an ordinary account
that has been **promoted**. The tier is stored on the account.

| Tier | English label | Arabic label | What it can do by default |
|---|---|---|---|
| `super_admin` | Super Admin | المدير الرئيسي | Everything, always. Cannot be restricted. |
| `admin` | Administrator | مسؤول | Everything, by default. |
| `supervisor` | Supervisor | مشرف | Everything **except delete**. |
| `employee` | Employee | موظف | **View and edit only.** No add, no delete, no export, no archive. |
| `user` | User | مستخدم | No dashboard at all. This is the default for every account. |

*Where this comes from:* the tier names are at
`backend/internal/permissions/permissions.go:31-35`. The default table is
`defaultAllowed` at `:68-91`. Only these four tiers can open the dashboard
(`:60`).

**"Admin-level" means super_admin or admin, and nothing else.** A supervisor is
not admin-level. This matters for restoring things from the Trash. If you are
refused, the dashboard says **"Admin-level access required for this action."**
(`backend/internal/auth/middleware.go:47` and `:351`.)

## 1.3 The permissions that matter for chat

Permissions are set per *module* and per *action*. There are six actions:
view, add, edit, archive, delete, export.

Here is what each tier gets **by default** on the modules chat uses:

| Module | super_admin | admin | supervisor | employee |
|---|---|---|---|---|
| **messages** — view | yes | yes | yes | yes |
| **messages** — add (create a group, post a message) | yes | yes | yes | **no** |
| **messages** — edit (pause, resume, end, archive, add/remove members, decide connect requests) | yes | yes | yes | yes |
| **messages** — delete (delete a chat) | yes | yes | **no** | **no** |
| **sensitive_data** — view (see real names behind masked labels) | yes | yes | **no** | **no** |
| **users** — view | yes | yes | yes | yes |
| **marriage** — view / edit | yes | yes | yes | yes |
| **marriage** — delete | yes | yes | **no** | **no** |
| **trash** — view | yes | yes | yes | yes |

**The one that catches people out is `sensitive_data`.** Every other module
gives "view" to everybody by default. This one gives it to admins only. A
supervisor or an employee must be **granted it by name** on the Permissions
page. That is deliberate — it is the switch that decides who can see real
identities behind masked labels
(`backend/internal/permissions/permissions.go:139-145`).

**Two extra rules that are not in the table:**

- **Restoring from the Trash** needs admin-level, regardless of the `trash`
  module (`backend/cmd/server/main.go:1176`).
- **Permanently deleting from the Trash** needs super_admin (`:1179`).

## 1.4 How to grant a permission to one person

Dashboard → **Permissions**. The page has two halves.

- The **top half** is the tier matrix. Changing it changes *everyone* on that
  tier. Saving it asks for a one-time code **and** your password.
- The **bottom half** is the per-person card. Pick a staff member, tick the box,
  save. Only that person changes. A ↺ button next to a box resets it to the
  tier default. The tooltip reads **"Reset to tier default"**.

You can only pick real staff here. Plain users and the Super Admin are not
listed (`admin-web/src/pages/PermissionsPage.tsx:198`).

## 1.5 How each kind of account is actually made

| Account | How you make it | What is required |
|---|---|---|
| **Member (donor / beneficiary / volunteer)** | In the app. Enter a phone number, get an OTP code, then fill in the registration form. | The form needs **full name**, **address** and **account type**. Date of birth is optional but must be `YYYY-MM-DD` if given. The account then waits for staff approval. |
| **Guest** | In the app, "continue as guest". | A username only. No phone number. The account is approved immediately and has no role. |
| **Member, created by staff** | Dashboard → Users → create. | **Phone number only.** Username and password are optional, but if you set one you must set both. This account skips the approval queue and is active at once. |
| **Staff** | Dashboard → **Staff** → "Promote to staff". You give an *existing* account a tier, by phone number. | Only the Super Admin can change a tier. |
| **The first Super Admin** | Not creatable through any screen. It comes from the database. | — |

**A phone number can only be on one account.** This is enforced now on the
dashboard as well as in the app (PR #134). If you try to reuse a number, the
dashboard says:

> **English:** "Another account already uses this phone number. A number can
> only be on one account, so open that account instead, or enter a different
> number."
>
> **Arabic:** «هذا الرقم مستخدم في حساب آخر. لا يمكن أن يكون الرقم على أكثر من
> حساب واحد، فافتح ذلك الحساب أو أدخل رقماً مختلفاً.»

This also holds when the number is *spelled* differently. `0750 858 2031` and
`9647508582031` are the same number and the second one will be refused. Test
that — it is the whole point of the fix.

## 1.6 The minimum set of accounts

Nine accounts, and you can test everything below. Give each a phone number you
can actually receive an OTP on, or create them from the dashboard where the
table above allows it.

| Name | What it is | Why it exists |
|---|---|---|
| **SA** | Super Admin (you already have this) | Creates everything. Sees real names. Is the only account that can grant permissions and permanently delete. |
| **E1** | Employee, **without** sensitive_data | The star of step 8. Can open a team group but must be refused a masked one. Also proves an employee cannot create a group or delete a chat. |
| **SUP** | Supervisor | Proves the middle tier: can do everything except delete. *Optional — skip it if you are short of time; E1 covers the important refusals.* |
| **D** | Donor (role 1) | Sends a connect request from a donation. Sits in the masked group. Also the person who requests a marriage meeting, for the invite tests. |
| **B** | Beneficiary (role 2) | Sends a connect request from a case. Sits in the masked group opposite D. Also owns the marriage profile, so she is the one who accepts or declines the invite. |
| **V1** | Volunteer (role 3) | Member of the team group. |
| **V2** | Volunteer (role 3) | The other member of the team group — you need two to prove they see each other's real names. |
| **G** | Guest | Step 9. |
| **D2** | Second donor (role 1) | Only needed for step 1's "a donor cannot reach another member" attempt, so that you have someone D is *not* in a group with. *You can reuse B for this if you prefer.* |

**Why there is no separate "staff member with sensitive_data" account:** SA
already has it. E1 is the one who lacks it, and you grant it to E1 during
step 8 and watch the screen change.

---

# Part 2 — The test script

Do these in order. Later steps reuse what earlier steps created.

---

## Step 1 — The policy itself: members cannot reach each other

**What you are proving:** no member can start a conversation with another
member, whatever their roles. Not donor to beneficiary, not beneficiary to
donor, not either to a volunteer. The only route is through our team.

### 1a. A donor tries to message another member directly

1. Sign in on the phone as **D**.
2. Go to **Messages**.
3. Look for any control that starts a new conversation with a person.

**Expected:** there is none. The Messages tab lists conversations you are
already in, plus your connect requests, plus support. There is no "new chat"
button pointing at another member.

### 1b. The server refuses it too

You cannot do this by tapping, because the button is gone. If you (or a
developer) send the request directly, the server answers **410** with:

> "Direct messaging has been retired. Ask staff to connect you instead."

*(`backend/internal/handlers/chat.go:176`.)*

**Note:** this refusal is plain English and is **not translated**. An Arabic
user would see English here. It is unreachable by tapping, so it should never
appear — but if you ever see it, that is worth reporting.

### 1c. A member tries to open a group they are not in

1. Still as **D**, after step 3 has created the masked group, note the group's
   number from the dashboard.
2. Sign in as **D2** (or **V1**) — somebody who is not in that group.
3. Try to open that group.

**Expected:** **D2** never sees it in their list at all. If the app is forced to
open it anyway, the server refuses with **403** and the app shows:

> **English:** "This conversation is no longer available" — "It may have been
> closed by our team, or you are no longer part of it. Go back to see your
> other conversations."
>
> **Arabic:** «هذه المحادثة لم تعد متاحة» — «ربما أغلقها فريقنا، أو لم تعد
> مشاركاً فيها. ارجع لرؤية محادثاتك الأخرى.»

*(`humanitarian/lib/localization/app_translations.dart:504` and `:3687`.)*

**The refusals that should happen, in one list:**

| What you try | What should happen |
|---|---|
| Start a chat with another member | No button. Server would say 410, retired. |
| Open a group you are not a member of | Not in your list. Forced: "This conversation is no longer available." |
| Send into a group you were removed from | Same message. |
| Send into a paused or ended group | Composer replaced by a notice — see step 6. |

---

## Step 2 — Connect requests

### 2a. The donor asks, from a donation

1. On the phone as **D**, go to **My Donations**.
2. Open one of your donations.
3. Tap **"Ask our team to connect me"** / **«اطلب التواصل عبر فريقنا»**.
4. A sheet opens, titled **"Ask our team to connect you"** /
   **«طلب تواصل عبر فريقنا»**, explaining: "Our team will review your request.
   If they approve it, they will open a supervised chat for you here in the
   app."
5. Leave the message box empty and tap **"Send request"** / **«إرسال الطلب»**.

**Expected:** it refuses, under the field: **"Please describe what you need."**
/ **«يرجى وصف ما تحتاجه.»**

6. Type a real message and send.

**Expected:** the sheet itself changes to a success view:
**"Request sent"** / **«تم إرسال الطلب»**, with the body "Our team will review
it shortly. You can follow it in My Connect Requests on the Messages tab." Tap
**Done**.

*(If you closed the sheet before the answer arrived, you get a toast instead:
"Request sent. Our team will review it shortly." That is the same outcome.)*

7. Go to **Messages** → **"My connect requests"** /
   **«طلبات التواصل الخاصة بي»**. Your request is listed as
   **"Pending"** / **«قيد المراجعة»**, with the hint **"Our team is reviewing
   your request."**

### 2b. The beneficiary asks, from a case

1. Sign in as **B**.
2. Open one of her cases.
3. Same button, same sheet. Send a request.

**Expected:** identical behaviour. The only difference is what staff see: the
request is labelled **Case** rather than **Donation**.

### 2c. Staff approve D's request

1. On the dashboard as **SA**, go to **Connect requests**.
   The page reads: "Members ask to be put in touch about a donation or a case.
   Approve a request by opening a supervised group, or decline it with a reason
   the member will read."
2. Filter to **Pending**. Click D's request.
3. The detail panel shows **About** (the donation), **Message**, and **Sent**.
4. Click **Approve**.
5. The dialog is titled **"Approve request"**: "Approving opens a supervised
   group for this request. The person who sent it is already the first member;
   add anyone else they should talk to."
6. Choose group type **Masked group**. Add **B** as a second member, with role
   Beneficiary.
7. Click **"Approve and open group"**.

**Expected:** a toast, **"Request approved. The group is open."** The request
moves to the Approved filter and gains a link, **"Open the group #N"**.

**If you try to approve without filling everything in,** the submit button is
gated and the hint reads: "To approve, choose a group type, name a team group,
and give every member a person and a role."

### 2d. Staff decline B's request

1. Back on **Connect requests**, Pending filter. Click B's request.
2. Click **Decline**. The dialog says: **"A declined request cannot be
   reopened."**
3. Leave the reason blank and submit.

**Expected:** refused — **"Enter a reason for the member."**

4. Type a reason and click **"Decline request"**.

**Expected:** toast **"Request declined"**. It moves to the Declined filter.

### 2e. Both members see the result

1. On the phone as **D**: Messages → My connect requests. The request now reads
   **"Approved"** / **«تمت الموافقة»**, and the new group appears in your
   group-chat list. Open it and send a message.
2. As **B**: the request reads **"Declined"** / **«مرفوض»**, and underneath,
   **"Reason from our team"** / **«سبب من فريقنا»**, showing exactly the text
   the staff member typed.

**Important:** the member never learns *which* staff member decided. That is
deliberate (`backend/internal/handlers/chat_group_connect.go:53-71`). If a
staff name appears on the member's screen, that is a bug.

### 2f. Two staff decide the same request

1. Open the same pending request in two browser tabs as **SA**.
2. Approve it in one tab. Then approve it in the other.

**Expected:** the second tab is refused with:

> **English:** "Another staff member has already decided this request. Refresh
> the list to see the outcome."
>
> **Arabic:** «اتخذ موظف آخر قراراً بشأن هذا الطلب بالفعل. حدّث القائمة لرؤية
> النتيجة.»

---

## Step 3 — A masked group

Use the group step 2c created: **D** and **B**, masked.

### 3a. Members see labels, not names

1. On the phone as **D**, open the group.

**Expected:** B's messages are signed **"Beneficiary 1"** / **«مستحق 1»**. D's
own are signed **"Donor 1"** / **«مانح 1»**. Any staff message is signed
**"Support"** / **«فريق الدعم»**. No real name appears anywhere — not in the
bubbles, not in the header, not in the push notification.

2. As **B**, the same group shows D as **"Donor 1"** / **«مانح 1»**.

### 3b. Staff see real names

1. On the dashboard as **SA**, open the group.

**Expected:** the roster lists real names. The page carries the note:

> **English:** "Members see each other only by their labels. Staff see real
> names."
>
> **Arabic:** «يرى الأعضاء بعضهم بالأسماء الظاهرة فقط، أما الفريق فيرى الأسماء
> الحقيقية.»

### 3c. Sending a phone number is blocked

1. On the phone as **D**, in the group, type a message containing an Iraqi
   phone number — for example `07508582031` — and send.

**Expected:** it is **not** sent. The app shows:

> **English:** "Phone numbers and email addresses cannot be shared in this
> chat. It is supervised for your safety — please keep the conversation here,
> and ask our team if you need to arrange contact."
>
> **Arabic:** «لا يمكن مشاركة أرقام الهواتف أو عناوين البريد الإلكتروني في هذه
> المحادثة. المحادثة تحت إشراف فريقنا حفاظاً على سلامتك — يُرجى إبقاء التواصل
> هنا، واطلب من فريقنا إن احتجت إلى ترتيب وسيلة تواصل.»

2. Try these variants. **All should be blocked:**
   - An email address.
   - `9647508582031` and `009647508582031`.
   - The number with spaces or dashes: `0750 858 2031`, `0750-858-2031`.
   - The number written in **Arabic-Indic digits**: `٠٧٥٠٨٥٨٢٠٣١`.

*(The rules are in `backend/internal/moderation/contactfilter.go:135`. It
accepts up to three separator characters between digits, so heavy spacing may
slip through — see Part 3.)*

3. **Now check it is only masked groups.** Send the same phone number in the
   **team** group from step 4.

**Expected:** it goes through. The block applies to masked groups only
(`backend/internal/handlers/chat_group_contact_block.go:32`). A staff member is
also exempt and can send a number into a masked group.

4. On the dashboard, open the group and look at the contact-blocks panel.

**Expected:** the blocked attempt is listed, with the number already hidden
behind `•••`.

### 3d. A label cannot contain a phone number

1. On the dashboard, try to add a member whose label is `Donor 07508582031`.

**Expected:** refused —

> **English:** "A label contains a phone number or email address. Other members
> see labels, so remove the contact detail."

---

## Step 4 — A team group

1. On the dashboard as **SA**, go to **Chat groups** → **New group**.
2. Choose **Team group**: "A named working group. Members see each other's real
   names."
3. Give it a name, and add **V1** and **V2**.
4. Create it.
5. On the phone as **V1**, open the group and send a message. Then as **V2**.

**Expected:** each volunteer sees the other's **real name** on the message, and
the group's **name** in the header — not "Masked group #N". No labels anywhere.

---

## Step 5 — Chat invites: accept, decline, and the refusals

**Read this before you start.** Invites no longer exist for donor chats,
because donor chats cannot be created any more (step 1). The only place you can
still produce a live invite is the **Marriage / "My Engagement"** flow. So this
step needs a marriage profile.

**Setup:** **B** creates a marriage profile. **D** searches, finds it, and taps
"request a meeting". Staff (**SA**) then approve the meeting request on the
dashboard, at **Marriage → meeting requests**. Approving creates the chat and
sends **B** an invite.

*(Confirmed at `backend/internal/handlers/marriage_chat.go:99`. The exact
wording of the app's own marriage search and meeting-request screens was
**[NOT CONFIRMED]** — read them off the screen as you go.)*

### 5a. Accept

1. As **B**, open the notification or the Messages tab. The invite offers
   **Accept** and **Decline**.
2. Tap **Accept**.

**Expected:** the chat opens and both sides can write.

### 5b. Decline

1. Repeat the setup for a second invite (staff approve another meeting
   request).
2. As **B**, tap **Decline**.

**Expected:** the invite disappears and no chat opens.

### 5c. The three refusals

| What you do | What should happen |
|---|---|
| **Accept an invite you already declined.** Get back to a stale invite row — for example, leave the notification open on a second device while you decline on the first, then tap Accept on the stale one. | **English:** "You declined this invitation." · **Arabic:** «لقد رفضتَ هذه الدعوة.» The row then settles and the buttons go away. |
| **Decline a chat that is already active.** Accept on one device, then tap Decline on a stale row on the other. | **English:** "This chat is already active, so it can no longer be declined." · **Arabic:** «هذه المحادثة نشطة بالفعل، لذا لم يعد بالإمكان رفضها.» |
| **Accept an invite after staff paused or ended the chat.** Have SA pause the chat from the dashboard, then tap Accept on the stale invite. | The Accept button should not be offered at all on a closed chat. If it is reached, the refusal explains the chat is paused or closed — the same wording as the step 6 notice. |

**After a decline, staff can re-invite.** Approve the meeting request again and
**B** gets a fresh invite that can be accepted. *(See Part 3 — the re-invite's
push notification may be swallowed.)*

---

## Step 6 — Lifecycle: pause, resume, end, archive, delete

All of these are done by staff, on the dashboard. There is no member-facing
equivalent. Do them on the masked group from step 3, and watch **D**'s phone at
the same time.

### 6a. Pause

1. Dashboard as **SA**, open the group. Click **"Pause"** / **«إيقاف مؤقت»**.
2. It asks for a reason: "Why? Both participants will be shown this in place of
   their message box. You can leave it blank." Type something — for example
   "Under review by our team".

**Expected on the phone:** the message box is gone. In its place:

> **English:** "This conversation has been paused by our team." — "You can still
> read it. New messages can't be sent while it is paused." — **Reason:** *your
> text*.
>
> **Arabic:** «تم إيقاف هذه المحادثة مؤقتًا من قِبل فريقنا.» — «لا يزال بإمكانك
> قراءتها. لا يمكن إرسال رسائل جديدة أثناء الإيقاف المؤقت.» — **السبب**.

The history is still readable. The notice is amber.

### 6b. Resume

1. Click **"Resume"** / **«استئناف»**.

**Expected:** the message box comes back on the phone and sending works again.

2. Now click **Resume** on a chat that is *not* paused.

**Expected:** refused — "This chat is not paused, so it cannot be resumed."

### 6c. End

1. Click **"End chat"** / **«إنهاء المحادثة»**.
2. The confirmation says: **"Ending is final — the chat becomes read-only for
   everyone and cannot be reopened. The history is kept."** /
   **«الإنهاء نهائي — تصبح المحادثة للقراءة فقط للجميع ولا يمكن إعادة فتحها.
   يُحفظ السجل كاملًا.»**

**Expected on the phone:** the notice changes to grey:

> **English:** "This conversation has been closed by our team." — "You can still
> read the whole conversation, but no new messages can be sent."
>
> **Arabic:** «تم إغلاق هذه المحادثة من قِبل فريقنا.» — «لا يزال بإمكانك قراءة
> المحادثة كاملة، لكن لا يمكن إرسال رسائل جديدة.»

3. Now try to **Pause** or **Resume** the ended chat.

**Expected:** refused — "This chat has been ended. Ending is final — start a new
conversation instead." **Ending really is one-way. Do this last on any group you
still want to use.**

### 6d. Archive

1. Click **"Archive"** / **«أرشفة»**. The hint reads: "Hidden from the
   participants. Staff can still see it here."

**Expected on the phone:** the conversation **disappears from the member's
list entirely**. If they somehow open it, they are told it is no longer
available — the same message as step 1c. They are *not* told it was archived.

2. Click **"Un-archive"** / **«إلغاء الأرشفة»**.

**Expected:** it comes back on the phone.

### 6e. Delete

1. Click **"Delete chat"** / **«حذف المحادثة»**.
2. The confirmation says: **"Move this chat and all of its messages to the
   Trash? An administrator can restore it, and a Super-Admin can delete it
   permanently."**
3. You will also be asked for your **password** — this is the standard
   dashboard delete check.

**Expected:** the chat leaves the list and appears in **Trash**.

4. From Trash, **Restore** it. *(Needs admin-level. A supervisor is refused with
   "Admin-level access required for this action.")*

**Expected:** it comes back. **If it was a donor one-to-one chat, it comes back
closed and archived, never open.** That is deliberate.

5. From Trash, **permanently delete** it. *(Super Admin only.)*

### 6f. Who is allowed to do what

Sign in as **E1** (employee) and try each button on a chat.

| Action | E1 (employee) | SUP (supervisor) |
|---|---|---|
| Open / read | allowed | allowed |
| Pause, resume, end, archive | allowed | allowed |
| Create a group | **refused** | allowed |
| Post a staff message | **refused** | allowed |
| Delete a chat | **refused** | **refused** |
| Restore from Trash | **refused** | **refused** |

**Note a known mismatch:** on the chat-group detail page the Delete button is
shown to anyone with *edit*, but the server requires *delete*. So E1 and SUP may
**see** a Delete button and then be refused when they press it. That is a real
rough edge, recorded in `HANDOFF.md`, not a new bug.

---

## Step 7 — Export one conversation of each type

Each chat page has its own **"Export conversation"** / **«تصدير المحادثة»**
button, in the chat's header. It is separate from the list-level Export.

Do this for each of these:

1. **A donor / support chat** — Messages page.
2. **A marriage chat** — Marriage chats page.
3. **A staff-to-staff chat** — Staff chat page.
4. **A group chat** — open the group from step 3 or 4 and use the button in the
   group header.

**For each one:**

1. Click **Export conversation**.
2. You are asked for your password: **"Enter your password to confirm this
   action:"** / **«أدخل كلمة المرور لتأكيد هذا الإجراء:»**
3. Enter it wrong once.

**Expected:** **"Incorrect password — cancelled."** / **«كلمة مرور غير صحيحة —
تم الإلغاء.»** Nothing downloads.

4. Enter it correctly and pick a format: **CSV**, **Excel**, **PDF** or
   **Word**.

**Expected:** a file downloads. Open it and check:
- Every message is there, with its time and its sender.
- The document title names the chat type and number — for example "Group chat
  #12" / «محادثة جماعية ‎#12».
- **No phone numbers or email addresses appear in the file.** A row is built
  field by field and contact details are never included.
- For a **group** export, each sender's masked label and their role in the
  group are columns.

**Important for group exports:** the export reads through the same permission as
the page. So an account that cannot open a masked group also cannot export it —
see step 8.

---

## Step 8 — Sensitive data

**What you are proving:** a staff member without "sensitive data" cannot open a
masked group, and granting it to that one person fixes it — without changing
anyone else.

1. Sign in on the dashboard as **E1** (employee, nothing granted).
2. Go to **Chat groups**. The list loads, and the masked group from step 3 is
   visible with a **Masked** badge.
3. Click into it.

**Expected:** the group will not open. Instead:

> **English:** "Sensitive-data access needed" — "This is a masked group, so
> opening it shows the real identities behind the labels. Your access level does
> not include sensitive data. Ask the Primary Administrator for it if your work
> needs this group."
>
> **Arabic:** «تحتاج إلى صلاحية البيانات الحساسة» — «هذه مجموعة بأسماء مستعارة،
> وفتحها يكشف الهويات الحقيقية خلف الأسماء الظاهرة. مستوى صلاحيتك لا يشمل
> البيانات الحساسة. اطلبها من المشرف الرئيسي إذا كان عملك يتطلب هذه المجموعة.»

4. Still as **E1**, open the **team** group from step 4.

**Expected:** it opens normally. The gate is for masked groups only.

5. Still as **E1**, open the **Connect requests** page.

**Expected:** it loads, but the requester's real name and the donation or case
name are hidden. E1 can read and **decline** a request, but cannot choose members
to approve one.

6. Now, as **SA**, go to **Permissions** → the per-person card → pick **E1** →
   tick **sensitive_data / view** → save.

7. Sign back in as **E1** and open the masked group again.

**Expected:** it opens. Real names are in the roster and next to every message.
The **Export conversation** button now works for it too.

8. **Check nobody else changed.** Sign in as **SUP** and open the same masked
   group.

**Expected:** still refused. Granting E1 must not grant the whole employee tier,
and certainly not the supervisor tier. If SUP can now open it, that is a serious
bug — report it immediately.

9. As **SA**, click the **↺** next to E1's box to reset it, and confirm E1 is
   refused again.

---

## Step 9 — Guests

Sign in on the phone as **G**.

| What you try | What should happen |
|---|---|
| Open the **Messages** tab | It loads, but shows a sign-in prompt: **"Sign in to use Messages"** / **«سجّل الدخول لاستخدام الرسائل»** — "Your conversations will appear here once you have a full account." with a **Sign in** button. No chat list, no polling. |
| Look for **"Ask our team to connect me"** on a donation or a case | **The button is not there at all.** It is hidden for guests, not shown-and-refused. |
| Open **Notifications** | It loads. **No chat notifications of any kind appear** — not chat requests, not new messages, not group messages, not marriage chat ones. Not even their preview text. |
| Wait for a chat **push notification** | None arrives. A guest's phone is never sent a chat push. |
| Open **Technical Support** | **It loads.** The screen works and shows the guest's own tickets. |
| Try to **send** a support ticket, or open a support chat | **Refused.** A guest can read the support screen but cannot create a ticket or start a support chat. |
| Any other blocked action | **English:** "This action requires a full account. Please upgrade your account." |

**Also test from the staff side:** as **SA**, try to add **G** to a chat group.

**Expected:** refused —

> **English:** "Guest accounts cannot join a chat group. Remove the guest
> account from the members and try again."

**And:** a guest can never have an approved connect request, because the guest is
blocked from sending one in the first place.

**Finally, upgrade G.** Add a phone number and verify it with an OTP. **G**
becomes a full member, the Messages tab starts working, and chat notifications
begin to arrive.

---

## Step 10 — Arabic

Switch the phone **and** the dashboard to Arabic and walk through **every step
above again**. You are checking two different things.

### 10a. The wording is Arabic

Every label, every button, every error, every empty state. **No English words
should appear anywhere in the interface** — the only exceptions are data values
and the format names `CSV`, `Excel`, `PDF`, `Word`.

Pay particular attention to these, which have been fixed recently and are the
most likely to regress:

- A staff reply in a one-to-one chat should say **«فريق الدعم»**, never
  "Support".
- Masked labels should read **«مانح 1»**, **«مستحق 1»**, **«متطوع 1»**,
  **«عضو 1»** — never "Donor 1".
- **The push notification title too.** A masked group push must read «رسالة من
  مانح 1», not «رسالة من Donor 1». Check this on the lock screen, not just in
  the app.
- An unnamed person in a chat should not read "User #12".

**One known English leak to expect:** on the app's **Profile** and **Pending
approval** screens, the account type for a **volunteer** is shown as the English
word **"Volunteer"** even in Arabic. Donor and Beneficiary are translated;
volunteer is not, because the code does not look up the translation
(`humanitarian/lib/modules/auth/screens/profile.dart:180` and
`pending_approval.dart:74`). The Arabic word «متطوع» exists but is never
reached. Report it if you want it fixed, but it is not a new fault.

### 10b. The layout is right-to-left

- Text starts on the **right**.
- Back arrows point the **right** way.
- The message box, send button, and the pause/end notices all mirror.
- Numbers stay readable: a group titled «محادثة جماعية ‎#12» must not render as
  «12# …». The code isolates the number for exactly this reason — check it.
- Nothing is cut off, and nothing overlaps, with long Arabic wording.
- Check the connect-request sheet, the group chat, the lifecycle notice, the
  Permissions page, the Connect requests inbox and the chat-group detail page.

### 10c. Kurdish

Switch to Sorani and to Badini. **Expect English on all the chat screens.** See
Part 3 — this is deliberate.

---

# Part 3 — What to watch for

These are known and deliberate. **Do not raise them as bugs.** They are listed
so you are not surprised.

### Kurdish falls back to English

The app has four languages: English, Arabic, Sorani and Badini. On the chat
screens, both Kurdish languages currently show **English**.

This is a standing decision, not an oversight: **invented Kurdish is worse than a
visible English fallback.** Both Kurdish languages are written in Arabic script,
so "it looks Arabic" is not evidence a string is right — that mistake was made
on this project once and had to be undone. The missing strings are listed in
`TRANSLATION_REQUEST.md` at the repository root: **621 keys** are waiting for a
native speaker.

Specifically, in the chat area, Kurdish is English for: the whole chat-groups
dashboard (68 keys), the connect-request screens, the chat-invite refusals, the
word for the support team, the masked labels "Member N", and the export column
headers.

**One inconsistency worth knowing:** for a masked group, a Kurdish reader may see
the *push notification* with Kurdish words for Donor / Beneficiary / Volunteer,
but the *message bubble inside the app* in English. The two were fixed on
different branches.

### Other deliberately unfinished things

| Thing | What you will see |
|---|---|
| **The old direct-chat cleanup has not been run on production.** | Direct chats that existed before the change are still open and still work. New ones cannot be created. This is a one-off job waiting for an explicit go-ahead. |
| **Some server refusals are still plain English.** | A handful of chat-group refusals carry no translation key: "Unauthorized.", "Invalid JSON.", "Database error.", "A decline reason is required." If one of these appears in the Arabic dashboard, it is a known gap. |
| **The guest-upgrade refusal is English.** | If you try to upgrade a guest to a phone number that is already taken, the app shows English prose. Fixing it needs an app release. |
| **Delete button shown where delete is refused.** | On the chat-group detail page, the Delete button appears for anyone who can edit, but the server requires delete permission. See step 6f. |
| **A re-invite's push may not arrive.** | If a marriage invite is declined and staff approve the meeting again, the new invite appears correctly in the app, but the *push notification* can be swallowed as a duplicate, because its title and body are identical to the first one. |
| **The contact filter tolerates spacing.** | It allows up to three separator characters between digits. A phone number written with very heavy spacing may get through. Worth probing; not a regression. |
| **Old notification rows keep their old wording.** | Notifications created before the Arabic fix still read «رسالة من Support». They are not rewritten. Only new ones are correct. |
| **Volunteer account type shows in English.** | See step 10a. |
| **The export file's own header comment is out of date.** | It says group-chat export is not built. It **is** built and works — the comment was never updated. Ignore it. |

### Things this plan could not confirm from the code

- **The exact wording of the marriage search and "request a meeting" screens** in
  step 5. Read them off the screen.
- **Whether the Railway deployment is actually running the latest `main`.** Check
  before you start; everything here assumes PR #135 or later.
- **How the app behaves when the network drops mid-action.** Not covered here.
- **Whether any production account already holds one phone number in two
  spellings.** The fix stops new ones; it does not merge existing pairs, and
  nobody has counted them.

---

## A short checklist

- [ ] 1 — Members cannot reach each other
- [ ] 2 — Connect request: sent, approved, declined, seen by the member
- [ ] 3 — Masked group: labels, real names for staff, phone number blocked
- [ ] 4 — Team group: real names
- [ ] 5 — Invites: accept, decline, three refusals
- [ ] 6 — Pause, resume, end, archive, delete, restore
- [ ] 7 — Export: donor, marriage, staff, group
- [ ] 8 — Sensitive data: refused, granted, refused again
- [ ] 9 — Guests: no chats, no chat notifications, no pushes, support reads
- [ ] 10 — Arabic wording and right-to-left layout on all of the above

# TERMINOLOGY — canonical vocabulary for BalanceNex / توازن

One row per concept, reconciling the two client rename passes against **what the
code actually says today**. Written 2026-08-15.

> **This file changes nothing.** It is a specification awaiting the owner's
> sign-off. No rename was applied to the app, the dashboard, the API or the
> database while writing it. Several of the renames the client asks for turn out
> to be **already shipped** — that is recorded here so nobody pays for them twice.

## Where the two rename passes came from

| Source | Says | Framing |
|---|---|---|
| **Dashboard PDF p9** `[D p9]` — "تعديل المصطلحات لتوافق بوابات الدفع والمنظمات الدولية" | Donations/التبرعات → **Back Us / ادعمنا** (alt. Contributions/المساهمات) · Beneficiary/المستفيد → **Recipients/المستحقين** (alt. Target Groups/الفئات المستهدفة) · Sponsorships/الكفالات → **Assistance/المعونات** · Volunteers/المتطوعين → **unchanged** | Claimed to be required for **payment-gateway and international-organisation compliance**, and to apply to "لوحة التحكم وتطبيق الموبايل وكود الـ API" |
| **App PDF p1** `[A p1]` — "ثانياً: التعديلات العامة داخل التطبيق" | حساب المتبرع → **مانح** · متعفف → **مستحق** (مستحقين plural) | No compliance framing; app-only wording cleanup |
| **HANDOFF.md §3.5** — already shipped | Donor → **Grantor / المانح** · Recipient/Beneficiary → **Eligible / مستحق** · with carve-outs | An earlier pass, already on `main` |

Two things the client said that materially change how these are read:

1. The dashboard PDF ends the section with **"كما يمكن إضافة الكلمات المقترحة من
   قبلكم والتي تكون مقبولة دوليا"** — we are explicitly invited to propose our own
   internationally-acceptable wording. The shipped vocabulary is therefore a legal
   counter-proposal, not a deviation.
2. The app PDF's **own body text still uses the old words** it is replacing —
   the same page 1 asks for a stats slider counting "عدد المتبرعين، عدد المستفيدين"
   and describes the status colours with "تم إيصال التبرعات بالكامل إلى المستفيدين".
   The app PDF was written **before, or independently of**, the dashboard PDF's
   global rename. It is not a rejection of it.

## How to read the table

**Status**

- `SETTLED` — unambiguous, safe to apply. Either both sources agree, only one
  source speaks and it is unambiguous, or it is already done.
- `CONFLICT` — the two passes disagree. **Both options are shown; no pick is made
  here.** The tradeoff is in the row note.
- `NEEDS OWNER` — needs a compliance answer or a product judgement we cannot make
  from the documents. Includes every row whose only justification is the
  **unverified** payment-gateway claim.

**Blast radius** (in *Where it appears*)

- `app` — Flutter only · `dash` — admin dashboard only · `both` — both clients
- `+API` — **also renames API JSON fields, route paths and/or DB columns/tables.**
  A `+API` rename is a different order of risk from a label change: it breaks
  every deployed app build that has not been updated, needs a reversible
  migration, and cannot be rolled back by editing a locale file.

`ALREADY DONE` in the *Status* cell means the code already carries the requested
change. `ckb`/`kmr` are **deliberately empty** — see the Kurdish section.

---

## The table

| Concept | Current en | Current ar | Proposed en | Proposed ar | ckb | kmr | Where it appears | Source | Status |
|---|---|---|---|---|---|---|---|---|---|
| **T1** The money-giving record and its section | `Contributions` | `المساهمات` | `Contributions` (keep) | `المساهمات` (keep) | — | — | both, labels only | `[D p9]` I1 | **SETTLED — ALREADY DONE** (4 residual keys, note T1) |
| **T2** "Back Us / ادعمنا" as the primary user-facing brand for giving | `Contributions` | `المساهمات` | `Back Us` | `ادعمنا` | — | — | both, labels only | `[D p9]` I1 | **NEEDS OWNER** (note T2) |
| **T3** `donation*` identifiers — API fields, routes, DB tables | `donation`, `donations`, `donation_kind`… | n/a (code) | `contribution*` | n/a | — | — | **both +API +DB** | `[D p9]` I1 ("وكود الـ API") | **NEEDS OWNER** — highest blast radius (note T3) |
| **T4** The person receiving aid — **Arabic word** | — | app `مستحق` · dash `المستفيدون` | — | `مستحق` / `المستحقين` | — | — | both, labels only | `[D p9]` I2 + `[A p1]` I6 + §3.5 | **SETTLED** — app ALREADY DONE, dashboard AR outstanding (note T4) |
| **T5** The person receiving aid — **English word** | app `Eligible` / `Eligible Recipient` · dash `Recipient` | as T4 | **Option A** `Recipient(s)` · **Option B** `Eligible(s)` | as T4 | — | — | both, labels only | `[D p9]` I2 vs §3.5 | **CONFLICT** (note T5) |
| **T6** "Target Groups / الفئات المستهدفة" as the alternative for T4/T5 | absent (0 hits) | absent (0 hits) | `Target Groups` | `الفئات المستهدفة` | — | — | both, labels only | `[D p9]` I2 alt. | **NEEDS OWNER** (note T6) |
| **T7** `beneficiary*` identifiers — API fields, routes, DB tables | `beneficiary_cases`, `beneficiary_user_id`… | n/a (code) | `recipient*` or `eligible*` (follows T5) | n/a | — | — | **both +API +DB** | `[D p9]` I2 | **NEEDS OWNER** (note T7) |
| **T8** Recurring aid commitment — **English word** | dash `Assistance` · app `Support` | `الدعم` | `Assistance` | see T9 | — | — | both, labels only | `[D p9]` I3 | **SETTLED** — dashboard ALREADY DONE, app outstanding (note T8) |
| **T9** Recurring aid commitment — **Arabic word** | see T8 | `الدعم` (was `الكفالات`) | `Assistance` | `المعونات` | — | — | both, labels only | `[D p9]` I3 | **NEEDS OWNER** (note T9) |
| **T10** `الدعم` label collision — Sponsorships and Support are the same string | app: both `Support` | app + dash: both `الدعم` | must differ | must differ | — | — | both, labels only | defect found in audit | **SETTLED** — fix regardless of T8/T9 (note T10) |
| **T11** `sponsorship*` identifiers — API fields, routes, DB tables | `sponsorships`, `sponsorship_schedule`… | n/a (code) | `assistance*` | n/a | — | — | **both +API +DB** | `[D p9]` I3 | **NEEDS OWNER** (note T11) |
| **T12** The giving account holder | `Grantor` | `مانح` / `المانحون` | `Grantor` (keep) | `مانح` (keep) | — | — | both, labels only | `[A p1]` I5 + §3.5 | **SETTLED — ALREADY DONE** (1 residual, note T12) |
| **T13** `متعفف` (the word the client wants gone) | — | **absent — 0 occurrences** | — | `مستحق` (= T4) | — | — | app | `[A p1]` I6 | **SETTLED — ALREADY DONE** (note T13) |
| **T14** In-kind giving | `In-kind contribution` | app `مساهمة عيني` · dash `مساهمات عينية` | keep | `مساهمة عينية` (fix agreement) | — | — | both, labels only | follows T1 | **SETTLED — ALREADY DONE** (1 grammar slip, note T14) |
| **T15** Volunteers | `Volunteer(s)` | `متطوع` / `المتطوعون` | **DO NOT RENAME** | **DO NOT RENAME** | — | — | both +API | `[D p9]` I4 (explicit) | **SETTLED** — verified unchanged (note T15) |
| **T16** The **act** of giving (the verb) | `Donate` → `Contribute` · `Contribute` → `Contribute` | `Donate` → `مساهمة` · `Contribute` → `تبرّع` | **DO NOT RENAME** the verb | **DO NOT RENAME** the verb | — | — | app, labels only | §3.5 carve-out | **NEEDS OWNER** — carve-out already crossed (note T16) |
| **T17** Partner / الشركاء | `Partners` | `الشركاء` | **DO NOT RENAME** | **DO NOT RENAME** | — | — | both +API | §3.5 carve-out | **SETTLED** — verified unchanged (note T17) |
| **T18** Generic receiving / usefulness words | `receive`, `useful` | `مستلمة` (5) | **DO NOT RENAME** | **DO NOT RENAME** | — | — | both | §3.5 carve-out | **SETTLED** — verified intact (note T18) |
| **T19** `كفالة` inside aid **product** names (كفالة يتيم، كفالة أرملة…) | `Orphan Sponsorship`, `Widow Support`… | `كفالة يتيم`, `كفالة أرملة`… | tied to T8 | **DO NOT RENAME** without T9 | — | — | both +DB data rows | `[A p17]` M5, `[A p21]` K2 vs `[D p9]` I3 | **NEEDS OWNER** (note T19) |
| **T20** Role labels shown to admins | `Grantor` / `Recipient` / `Volunteer` | `المانحون` / `المستفيدون` / `المتطوعون` | follows T5 | `المستحقون` (follows T4) | — | — | dash, labels only | follows T4/T5 | **CONFLICT** — inherits T5 (note T20) |

**Tally: 10 SETTLED · 2 CONFLICT · 8 NEEDS OWNER.**

---

## Row notes

Every claim below was read out of the committed tree (`HEAD`, branch `main`) on
2026-08-15. Line numbers are for `humanitarian/lib/localization/app_translations.dart`
unless stated.

### T1 — Donations → Contributions: already shipped, both clients, both languages

Not a pending rename. It is live:

| Where | Key | Value |
|---|---|---|
| App `_en` L457 | `'Donations'` | `'Contributions'` |
| App `_ar` L2847 | `'Donations'` | `'المساهمات'` |
| App `_en` L2402 | `'Contributions'` | `'Contributions'` |
| Dashboard `en.ts` | `nav.donations` | `'Contributions'` |
| Dashboard `ar.ts` | `nav.donations` | `'المساهمات'` |

`المساهم*` now outnumbers `التبرع*` 35:4 in the app's `_ar` map and 14:4 in the
dashboard's `ar.ts`. The Arabic form the client offered as the "internationally
accepted alternative" is the one that shipped.

**Residual work if the owner confirms T1 as final** — four label keys still carry
the old word and should be finished in the same pass:

- App `_en` L1752 / `_ar` L4097: `'Donation'` → `'Donation'` / `'تبرع'` (the
  singular record was missed while the plural was renamed).
- Dashboard `en.ts` L1315 `score_donations: 'Value of donations (1-5)'`,
  L1463 `thank_you_tagline: 'Donor appreciation'`, L155 and L16
  (`'…the payment methods donors see…'`, `'…shown to donors on the donate screen.'`).

These are user-visible English strings inside the Arabic-capable dashboard, so
they also fall under the standing "Arabic = NO English" rule (checklist B6).

**Grammar damage the rename left behind in the dashboard Arabic** — `مساهمة` is
feminine where `تبرع` was masculine, and the adjectives were not updated with it:

| `ar.ts` | Current | Should be |
|---|---|---|
| L713 | `new: '+ مساهمة جديد'` | `+ مساهمة جديدة` |
| L793 | `new: '+ مساهمة جديد'` | `+ مساهمة جديدة` |
| L716 | `new: '+ دعم جديدة'` | `+ دعم جديد` |
| L1017 | `'لا توجد دعم مطابقة.'` | `'لا يوجد دعم مطابق.'` |

Same class of defect as T14. Worth fixing in whichever pass finishes T1 — an
Arabic reader sees these immediately.

### T2 — "Back Us / ادعمنا" is a branding decision, not a translation

`Back Us` and `ادعمنا` appear **nowhere** in the codebase (0 hits across
`humanitarian/lib`, `admin-web/src`, `backend`). The dashboard PDF presents it as
the *proposed* word (`الكلمة المقترحة`) and Contributions/المساهمات as the
*internationally accepted alternative* (`بديلة معتمدة دولياً`) — and the shipped
code already implements the alternative.

Adopting "Back Us" would be a **brand voice change**, not a compliance fix: it is
an imperative call-to-action ("back us"), not a category noun, so it does not
substitute cleanly everywhere `Contributions` currently appears (a table column
headed "Back Us" does not read). The owner should decide whether "Back Us" is
wanted as a **button/CTA label only** while `Contributions` stays as the category
noun, or not at all. Blast radius if adopted as a CTA only: small, labels only.

### T3 — Renaming `donation*` in the API is the single highest-risk item here

Measured on `HEAD`, case-insensitive occurrences of `donation`:

| | backend | admin-web | Flutter | total |
|---|---|---|---|---|
| `donation` | 917 | 296 | 791 | **2,004** |

Plus **3 database tables** (`donations`, `donation_section_codes`,
`in_kind_donations`), **17 distinct API route paths** (25 route registrations in
`backend/cmd/server/main.go`), and **11 JSON field names** on the wire
(`donation_id`, `donation_kind`, `donation_type`, `donations`, `donations_amount`,
`donations_count`, `donor_full_name`, `donor_name`, `donor_phone`,
`donor_user_id`, `score_donations`).

Why this is different from a label change: renaming a JSON field or a route
**breaks every already-installed copy of the mobile app** until users update, and
the table rename needs a reversible migration against live donation records —
i.e. financial data. The repo convention is no foreign keys
(HANDOFF §3.1), so referential breakage would surface at runtime, not at migration
time.

**What the owner must answer before this can be planned:** *which* payment gateway
imposed this requirement, and in writing. A gateway integrates over an API
contract we define; it does not normally read our internal column names. Until
that is produced, the honest position is that the UI-label rename (T1, already
done) satisfies what a gateway or an international donor actually sees, and the
identifier rename is unjustified cost. **This document does not assert the
compliance requirement is real — only that the client claimed it.**

### T4 — The Arabic word is settled: `مستحق`. The dashboard has not caught up.

Both PDFs agree on the Arabic. `[D p9]` says المستحقين; `[A p1]` says
"استبدال كلمة متعفف … بكلمة مستحق للمفرد و مستحقين للجمع". The already-shipped
pass (§3.5) chose the same word. There is **no Arabic conflict** here.

State today:

| Client | `المستحق*` | `المستفيد*` | Verdict |
|---|---|---|---|
| App `_ar` map | 16 | 2 | done |
| Dashboard `ar.ts` | 1 | 15 | **not done** |

The dashboard Arabic is where the client's complaint still lands. `nav.beneficiary`
is `'المستفيدون'` — literally the word `[D p9]` asks to replace — while the English
next to it already says `Recipient`. Concrete dashboard `ar.ts` sites: L42, L172,
L191, L198, L280, L717, L802, L827, L834, L921, L972, L1289, L1344, L1360.

App residuals (3 keys where the old word survived inside a compound):
`'Beneficiary'` → `'مستفيد مؤهل'` (L2731), `'Beneficiaries'` → `'المستفيدون المؤهلون'`
(L4331), `'Beneficiary dashboard'` → `'لوحة المستفيد المؤهل'` (L4388).

### T5 — CONFLICT: `Recipient` vs `Eligible`. Both are already shipped, in different clients.

This is the real conflict, and it is in **English**, not Arabic:

| | App (Flutter) | Dashboard (admin-web) |
|---|---|---|
| The noun | `Eligible Recipient` / `Eligibles` | `Recipient` |
| Source | shipped pass, HANDOFF §3.5 | shipped pass — and it happens to match `[D p9]` |

So the product currently calls the same person two different things depending on
which client you open, and the dashboard PDF's request is already satisfied on one
of them.

**Option A — `Recipient(s)` everywhere.** Matches `[D p9]` verbatim. Plain,
widely understood by international donors and auditors. Cost: changes the app's
existing `Eligible*` strings; `Eligible` currently appears 18 times in the app's
`_en` map. Risk: "Recipient" is also the natural English word for the *generic*
act of receiving, which the §3.5 carve-out deliberately protects (T18) — adopting
it as the role noun makes that boundary harder to police in future greps.

**Option B — `Eligible(s)` everywhere.** Matches what shipped and what the
dashboard's own Arabic will say (`مستحق` literally means "eligible/entitled", so
Option B is the tighter en↔ar pair). Cost: changes the dashboard's `Recipient*`
strings, and requires telling the client we chose a different English word from
the one they proposed — which `[D p9]`'s closing sentence explicitly permits.
Risk: "Eligibles" as a plural noun is slightly unnatural English.

**Not picked here.** Whichever wins must also settle T7 and T20.

Note for whoever applies it: `Recipient` is already used in the dashboard for an
**unrelated** meaning — `receipts.recipient_id` / `recipient_name` in the aid-receipt
module (`en.ts` L218–219) means "the person this delivery went to". Option A
collides with that; Option B does not.

### T6 — "Target Groups / الفئات المستهدفة" is a different concept, not a synonym

Absent from the codebase (0 hits). "Target group" is a *cohort* (widows, orphans,
displaced families) — a many. `المستحق` is *one person with a case file*. The
system's data model is per-person (`beneficiary_cases` rows, one per case, with an
identity code per H23). Substituting a cohort word for a person word would make
strings like "حالة المستحق" (this eligible person's case) read as "this target
group's case".

Recommend to the owner: adopt it later as a **separate new concept** for
segmentation/reporting if wanted, not as a rename of T4/T5.

### T7 — `beneficiary*` identifiers: second-highest blast radius

`beneficiar` occurrences on `HEAD`: backend 734 · admin-web 232 · Flutter 329 =
**1,295**. Plus **5 database tables** (`beneficiary_cases`,
`beneficiary_case_documents`, `beneficiary_project_requests`,
`beneficiary_project_request_comments`, `beneficiary_project_request_likes`),
**15 distinct route paths**, and **12 JSON field names** (`beneficiary`,
`beneficiary_case_code`, `beneficiary_case_id`, `beneficiary_case_title`,
`beneficiary_cases`, `beneficiary_community_name` + its `_ar`/`_sorani`/`_badini`
variants, `beneficiary_name`, `beneficiary_phone`, `beneficiary_user_id`).

Same reasoning as T3: same unverified compliance claim, same wire-breaking
consequence. Additionally, this rename **cannot start** until T5 is decided, since
the identifier would become either `recipient*` or `eligible*`.

### T8 / T9 — Sponsorships: English already done, Arabic is a judgement call

English: `nav.sponsorships` is already `'Assistance'` in the dashboard
(`en.ts` L41), and `sponsorship_types` is already `'Assistance types'` (L83).
`[D p9]`'s English request is satisfied on the dashboard. The **app** still says
`Support` (`'Sponsorships'` → `'Support'`, L2194) and should be brought in line —
that part is SETTLED.

Arabic is **not** settled, and the reason is semantic rather than clerical.
`الكفالة` is a specific, culturally load-bearing term — it is the word in
`كفالة يتيم` (orphan sponsorship) and `كفالة أرملة` (widow sponsorship), which are
**named products in this system** (checklist M5 lists four of them among the 22
donation projects; K2 repeats them as أعمالنا categories). `المعونة` means aid/relief
generically and does not carry the ongoing-guardianship sense.

Renaming the *section* to `المعونات` while the *things inside it* stay `كفالة يتيم`
produces a UI that reads "المعونات > كفالة يتيم" — which may be exactly what the
client wants (a neutral umbrella over specific products), or may be an accident.
**Ask.** Current Arabic is neither word: both clients say `الدعم` (see T10).

### T10 — Defect: two different sidebar entries render as `الدعم`

Found while auditing, independent of any rename, and it should be fixed whichever
way T8/T9 goes:

- Dashboard `ar.ts`: `nav.sponsorships` = `'الدعم'` **and** `nav.support` = `'الدعم'`.
  Two distinct sidebar destinations with an identical Arabic label.
- App: `'Sponsorships'` → EN `'Support'` / AR `'الدعم'`, and `'Support'` → EN
  `'Support'` / AR `'الدعم'`. Identical in **both** languages — so the sponsorship
  section and the technical-support section are indistinguishable by label alone.

The dashboard's English does not collide (`Assistance` vs `Support`), which is why
this was invisible to an English-only review. It is a direct instance of the
client's "الرسائل / الدعم" confusion in checklist B16.

### T11 — `sponsorship*` identifiers

`sponsorship` occurrences: backend 542 · admin-web 200 · Flutter 448 = **1,190**.
Plus **3 tables** (`sponsorships`, `sponsorship_schedule`, `sponsorship_types`),
**12 route paths**, **3 JSON fields** (`sponsorship_id`, `sponsorship_type`,
`sponsorships`). `sponsorship_schedule` is the table behind the reminder cron
(HANDOFF §5 #20) — renaming it touches scheduled jobs, not just request handling.
Blocked on T9.

### T12 — حساب المتبرع → مانح: already shipped

`'Donor'` → `'Grantor'` (L340) / `'مانح'` (L2730); `'Donors'` → `'Grantors'` /
`'المانحون'`; `reg_grantor_section` → `'Grantor details'` / `'بيانات المانح'`;
dashboard `role_donor: 'Grantor'`, `donor_full_name: 'Grantor name'`,
`donor_user_id: 'Grantor user ID'`. `المانح*` outnumbers `المتبرع*` 10:2 in the
app's `_ar` map and 11:2 in the dashboard's `ar.ts`.

The two app residuals are **not both** errors:

- L2536 `'عندما يكفلك أحد المتبرعين ستظهر هنا.'` — a genuine miss; should read
  `أحد المانحين`.
- L4057 `'Total donated'` → `'إجمالي المتبرع به'` — **leave it.** This is the *act*
  of giving ("the total that was donated"), not the person, and is protected by
  the T16 carve-out.

### T13 — متعفف: already gone

**Zero occurrences** of `متعفف` anywhere in `humanitarian/lib`, `admin-web/src`
or `backend`. Checklist item I6 is complete. Nothing to do; the row exists so the
finding is not lost and the item can be closed.

### T14 — In-kind

Already `In-kind contribution` / `مساهمات عينية` (dashboard `nav.in_kind`,
`page.in_kind.title`). One defect: the app's `'In-kind donation'` → `'مساهمة عيني'`
has an **adjective agreement error** — `مساهمة` is feminine, so it must be
`مساهمة عينية`. Introduced by the rename (the old `تبرع عيني` was masculine and
correct). Cheap fix, one key.

### T15 — Volunteers: DO NOT RENAME (client's own instruction)

`[D p9]` is explicit: "الكلمة الحالية Volunteers المتطوعين تترك كما هي باللغتين
العربية والإنجليزية دون تغيير لكونها مقبولة محلياً ودولياً."

**Verified unchanged:** `'Volunteer'` → `'Volunteer'` / `'متطوع'` (L342, L2732);
`'Volunteers'` → `'Volunteers'` / `'المتطوعون'`; dashboard `nav.volunteers` =
`'Volunteers'` / `'المتطوعون'`. 2,116 `volunteer` identifier occurrences across
the three codebases, 4 DB tables and 16 route paths stay exactly as they are.
Checklist I4 can be marked verified.

### T16 — Carve-out already crossed: the verb `تبرّع` vs the noun

HANDOFF §3.5 says: *"Do NOT rename the act of donating."* The intent is that
`المتبرع` (the person) becomes `المانح`, while `تبرّع` (to give) survives, because
Arabic speakers still *donate* to a *contributions* page.

The code has partly crossed that line, and inconsistently:

| Key | EN | AR |
|---|---|---|
| `'Donate'` | `'Contribute'` | `'مساهمة'` |
| `'Contribute'` | `'Contribute'` | `'تبرّع'` |

The two are **inverted**: the key that means "donate" renders the contribution
word, and the key that means "contribute" renders the donation word. Whatever the
owner decides, these two should agree with each other. Also note
`'Total donated'` → `'إجمالي المتبرع به'` (correct under the carve-out) and
`'Your contributions will appear here once you give.'` →
`'ستظهر مساهماتك هنا بعد أول تبرع.'` (mixes both deliberately, and reads well).

**Owner question:** does the verb move to `ساهم/مساهمة`, or does `تبرّع` stay as the
verb under a `المساهمات` heading? Losing this carve-out would be a regression the
last pass specifically avoided.

### T17 — Carve-out: Partner / الشركاء

Untouched and must stay untouched: `'Partners'` → `'Partners'` / `'الشركاء'`,
dashboard `nav.partners` = `'Partners'` / `'الشركاء'`. 14 partner keys in the app
translation file. Reason: a partner organisation is not a giver of money in this
model — checklist K6 defines partners as rated collaborating organisations with
their own profiles. Renaming them into the donor/grantor vocabulary would merge
two distinct entities.

### T18 — Carve-out: generic receiving and usefulness words

**Do not sweep these into the T4 rename.** They are ordinary vocabulary that
merely *looks* like the target word to a grep:

| Word | Language | Means | Occurrences |
|---|---|---|---|
| `مستلمة` | Arabic | "received" (a delivered item) | 5 |
| `وەرگرتن` | Kurdish | "to receive" (the verb) | 31 |
| `سوودمەند` | Kurdish | **"useful"** — not "beneficiary" | 37 |

`سوودمەند` is the dangerous one: it is a plausible dictionary rendering of
"beneficiary" and a previous pass had to be stopped from renaming it. It is used
in this codebase to mean *useful*. Any future rename script must exclude all three
explicitly.

### T19 — `كفالة` inside product names is data, not a label

`كفالة يتيم`، `كفالة أرملة`، `كفالة مستفيد`، `كفالة طالب` are **rows** in the
`project_categories` / `sponsorship_types` / `case_categories` CMS tables
(admin-editable, 4-language, per HANDOFF §3.2) — not translation keys. They also
appear in the client's own requested project list (`[A p17]`, checklist M5) and
أعمالنا categories (`[A p21]`, K2), written in the app PDF *after* the dashboard
PDF's Sponsorships rename request.

So the client is simultaneously asking to remove `الكفالات` as a section name and
to ship four products whose names begin with `كفالة`. That is not necessarily a
contradiction — but it must be resolved deliberately, and it is **content-editable
by the admin**, so it needs no code change either way. Blocked on T9.

### T20 — Role labels inherit T5

Dashboard `en.ts` L707–709: `role_donor: 'Grantor'`, `role_beneficiary: 'Recipient'`,
`role_volunteer: 'Volunteer'`. Dashboard `ar.ts` L834: `role_1: 'المانحون'`,
`role_2: 'المستفيدون'`, `role_3: 'المتطوعون'`.

The Arabic `role_2` is a T4 residual (settled direction: `المستحقون`). The English
cannot be finalised until T5 is. Note that `role_id` values themselves
(`'1'`=grantor, `'2'`=eligible — HANDOFF §3.4) are **numeric** and unaffected by
any rename, which is fortunate: the role identity survives the vocabulary change.

---

## Kurdish (ckb / kmr) — deliberately empty

**No Kurdish is proposed in this document, and none should be invented.** This
matches the standing decision recorded in the code itself
(`app_translations.dart` L2572–2580, restated at L2638): *writing invented Kurdish
is worse than a visible English fallback* — issue **#21431**, awaiting a native
speaker.

Two traps, both already sprung on this project once:

1. **Both Kurdish locales are written in ARABIC SCRIPT.** "It looks Arabic" is not
   a test for which map a string belongs in. The code comment at L2578–2580 exists
   because that mistake was made before.
2. **The Arabic word `مستحق` is already sitting inside Kurdish strings** — measured
   today: **16 occurrences in `_sorani`, 17 in `_badini`**, e.g.
   `'Beneficiary cases'` → `'کەیسەکانی مستحق'` (Sorani) and
   `"حالەتێن مستحق"` (Badini). The Arabic term was pasted into the Kurdish maps
   during the last pass. The dashboard `kmr.ts` has 2 instances of `مساهم`.
   **These are not translations — they are untranslated Arabic and must be part of
   the native-speaker review, not of any rename script.**

### Measured coverage gap (correcting the working assumption)

The brief for this document assumed Badini is "~540 keys behind". **That figure is
not reproducible against the code today.** Actual measurement, `HEAD`, 2026-08-15:

| Map | Keys | Missing vs source of truth |
|---|---|---|
| App `_en` (`static const`) | 1,967 | — (source) |
| App `_ar` (`static const`) | 1,967 | **0** |
| App `_sorani` (`static final`) | 1,896 | **71** |
| App `_badini` (`static final`) | 1,896 | **74** |
| Dashboard `en.ts` / `ar.ts` | 1,306 leaf strings | — / 0 |
| Dashboard `ckb.ts` / `kmr.ts` | 1,254 leaf strings | **52** each |

So the real gap is roughly **74 app keys + 52 dashboard keys ≈ 126**, not 540 —
*plus* the ~33 Arabic-token contaminations above, which are worse than a missing
key because they render as wrong-language text rather than falling back to English.
`_badini` also carries **3 keys that do not exist in `_en`** (stale strings:
`"Ask me anything — I'll guide you through the app"`, `"Don't have an account?"`,
and an impact-milestone sentence), which the double-quote/single-quote duplicate
trap in HANDOFF §3.4 makes easy to create.

**Whoever adds Kurdish keys: grep BOTH `'key':` and `"key":` in `_badini` first.**

---

## Blast-radius reference

Occurrences are case-insensitive matches on `HEAD`, branch `main`, counted per
identifier stem across all file types (code, SQL, locale files).

| Stem | backend | admin-web | Flutter | Total | DB tables | Route paths | JSON fields | Rename risk |
|---|---|---|---|---|---|---|---|---|
| `donation` | 917 | 296 | 791 | **2,004** | 3 | 17 | 11 | **Highest** — touches financial records |
| `beneficiar` | 734 | 232 | 329 | **1,295** | 5 | 15 | 12 | High — blocked on T5 |
| `sponsorship` | 542 | 200 | 448 | **1,190** | 3 | 12 | 3 | High — includes the reminder cron |
| `donor` | 418 | 124 | 162 | **704** | 0 (columns only) | 0 | 4 | Medium — already renamed at label level |
| `volunteer` | 895 | 415 | 806 | **2,116** | 4 | 16 | — | **None — DO NOT RENAME (T15)** |

A **label-only** rename (T1, T4, T8, T10, T12, T14, T20) touches
`humanitarian/lib/localization/app_translations.dart` and
`admin-web/src/lib/locales/*.ts` and nothing else. It is reversible in one commit,
ships with the next build, and needs no migration.

An **identifier** rename (T3, T7, T11) touches Go handlers and stores, SQL
migrations, the live database, `admin-web` API call sites, `humanitarian/lib/api/links.dart`
(21 endpoint constants carry these stems) and every model that parses the JSON.
It breaks installed app builds until users update, and needs a reversible
migration against live financial data. **These three should be quoted and
scheduled separately from the label work, and not started until the compliance
claim is substantiated in writing.**

---

## What the owner has to decide

Ordered so one sitting can clear them. Nothing in group I should be applied until
1–4 are answered.

1. **T5 — the English word: `Recipient` or `Eligible`?** Both already ship, in
   different clients. This blocks T7 and T20.
2. **T3 / T7 / T11 — is the payment-gateway compliance claim real?** Which gateway,
   and does it actually constrain our internal API field and table names, or only
   what a donor sees? If it is only the visible labels, T1's shipped rename already
   satisfies it and roughly 4,500 identifier occurrences stay untouched.
3. **T9 / T19 — does `الكفالات` become `المعونات`,** given that four *products*
   named `كفالة …` sit inside that section and the client asked for them by name?
4. **T16 — does the Arabic verb `تبرّع` survive** under a `المساهمات` heading, or
   does the act of giving become `ساهم` too? (The carve-out says it survives; the
   code has already crossed the line in two keys and inverted them.)
5. **T2 — is "Back Us / ادعمنا" wanted as a CTA button label,** with
   `Contributions / المساهمات` kept as the category noun? Or dropped?
6. **T6 — should `الفئات المستهدفة` be added later as a separate cohort concept,**
   rather than as a rename of the per-person `مستحق`?

Answering 1–4 converts 8 NEEDS OWNER rows and 2 CONFLICT rows into a single
schedulable rename pass. Answering none of them still leaves the 10 SETTLED rows
safe to apply — including the T10 `الدعم` collision, which is a defect in its own
right.

---

*Cross-references: checklist group **I** (I1–I6) and **N7**. HANDOFF.md §2
(standing rules: 4 languages, Kurdish = Badini by default, Arabic = no English),
§3.4 (the `_badini` quote-style trap), §3.5 (shipped renames and carve-outs).*

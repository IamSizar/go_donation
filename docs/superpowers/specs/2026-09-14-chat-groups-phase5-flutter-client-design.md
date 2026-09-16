# OPOS #25284 Phase 5 — Flutter Client Design Addendum

**Status:** Approved design, ready for implementation planning.
**Date:** 2026-09-14
**Extends:** §11 of `docs/superpowers/specs/2026-09-12-masked-group-chats-design.md` (the original spec's Flutter section, which gave the shape but not screen-by-screen detail).

## 1. Why an addendum, not a from-scratch design

§11 already settled the architecture: "My Connections"/"My Team Groups" in the Messages tab, a conversation screen (label-only for masked, real identity for team), a "Request to connect" entry point, removal of the old direct-chat UI (done in Phase 4). What's missing is which existing screens/widgets this maps onto and the handful of placement decisions §11 left open. This addendum answers those by directly modeling on this codebase's own closest existing analogs — `marriagechat`'s Flutter screens (already solve "masked, label-only identity") and `chat`'s (already solve "real identity, GetX-controller-backed, polling") — per this project's own "follow existing patterns" rule, not a new invention.

## 2. Concrete decisions

**One conversation screen serves both `kind='masked'` and `kind='team'`.** The backend's `GroupMessage.SenderLabel` already resolves to the correct display text server-side for both kinds (masked label or real name) — the client never branches on kind to decide what text to show, it just renders `sender_label`. No avatar is rendered for either kind (the current `GroupMessage` struct carries no avatar-URL field to render one from, unlike §11's original text which mentioned team-group avatars as a future nicety — out of scope here since the API doesn't provide it yet; this can be added later without a client-side redesign, it's purely additive).

**Where "Request to connect" lives:** the two spots Phase 4 removed the old buttons from (`my_donations_page.dart`'s `_DonationDetailSheet`, `beneficiary_campaign_donations_screen.dart`'s donor row) get a NEW button in the same place, opening a small form (message text) that calls `POST /chat-groups/connect-requests` with `context_type='donation'`. This directly closes the gap Phase 4's own final review flagged: the 410 error copy already tells users to "ask staff to connect you instead," but nothing did that yet.

**Case-context connect requests:** casevolchat's automatic thread-opening (on signup/check-in status change) had no explicit "button" anywhere — it just happened. Its replacement needs an explicit ask now (masked groups are staff-approved, not automatic). Rather than hunting for a specific case/signup detail screen to retrofit (higher risk, more files to touch correctly under time pressure), this phase adds ONE generic entry point in the Messages tab itself: a "Request help with a case" tile (visible to non-guest users) that opens the same connect-request form with `context_type='case'` and a `context_id` field the user fills from their own case reference — the simplest correct implementation that satisfies the acceptance criteria without guessing at an unconfirmed screen's layout. A tighter integration into a specific case-detail screen is a reasonable follow-up, not required to close this phase.

**Section styling matches the existing incoming/active/outgoing groups already in `messages_screen.dart`** (private `_SectionLabel`, not the separate reusable `AppSectionHeader` used elsewhere) — visual consistency with the screen the new sections are joining outweighs cross-screen widget reuse here.

**Polling intervals match existing conventions exactly:** 5s for the groups list (mirrors `ChatController`), 3s for an open conversation (mirrors `ChatThreadController`/marriage's `Timer.periodic`).

**A new "My Connect Requests" screen** (reusing `AppAsync`/`AppEmpty`, modeled on the existing incoming/outgoing tile patterns already in `messages_screen.dart`) shows the requester's own request history (`GET /chat-groups/connect-requests/mine`) — pending/approved (with a link into the resulting group)/declined (with `decline_reason` shown, matching how `marriage_chat_conversation_screen.dart` already surfaces a decline reason). Reachable via a tile in the Messages tab, next to the new "My Connections"/"My Team Groups" sections.

## 3. Explicitly out of scope

- Real avatars for team groups (API doesn't provide the data yet).
- A dedicated case-detail-screen integration for the case connect-request entry point (see above — a generic form now, a nicer integration later).
- Admin-web (Phase 6).
- Anything already shipped in Phases 1-4.

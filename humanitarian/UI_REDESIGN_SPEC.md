# Tawazon / BalanceNex — Full App UI Documentation (for Redesign)

> This document describes **every screen, section, button, tab, menu, and form field** in the current Flutter app, screen by screen, based on a direct read of the source code (not guesswork). It's meant to be handed to a designer who will **redesign the interface** with these goals:
> - Clean, simple, friendly interface
> - No duplicated buttons — one clear way to do each thing
> - Everything that's related should be visually grouped together
>
> Each screen section follows the same format: **Purpose**, **How you get here**, **Layout/sections**, **Every button**, **Tabs/menus**, **Form fields**, **States**, and **Notes for a redesigner** (concrete problems found in the current code that relate to the three goals above).
>
> User roles referenced throughout: **Donor/Grantor** (role 1), **Beneficiary/Eligible** (role 2), **Volunteer** (role 3), and **Guest** (no role / limited account).

---

## ⚠️ Read this first — the biggest "duplicated button" problems found

Before diving into individual screens, here is a consolidated list of the clearest duplication/clutter issues found while documenting every screen. This is the highest-value section for a redesign kickoff:

1. **Welcome screen: "Sign in" and "Create account" are literally the same button.** Both navigate to the exact same Login screen — there is no separate signup flow. → Merge into one "Continue" / "Get started" button.
2. **The dedicated Register screen (email/password) doesn't actually register anyone.** It's a dead-end form that fakes a delay and forwards to Verification. The real signup path is the phone/OTP flow on Login. → Remove this screen entirely.
3. **Home dashboard has 3 redundant paths to the same destinations**, stacked in one long scroll: hero CTA "Make donation", quick-action "Contribute", and multiple "See all"/stat taps all open the same Donations screen; similarly "History" quick action + "My history" hero button + every activity-tile tap all open the same History screen.
4. **"Give Now" and "Comprehensive Giving"** on the Donations screen are two different-looking buttons/cards that do the exact same thing (clear campaign selection, scroll to amount).
5. **Profile screen has 3 dead tiles** ("Privacy & Security", "Payment Methods", "App Settings") — they look tappable but have no action wired at all — while a separate, working "Control Settings" screen already covers the same ground. Two competing settings hubs exist simultaneously.
6. **Edit Profile: the camera icon on the avatar and the separate "Choose image" button do the exact same thing.**
7. **Settings drawer: "Volunteer With Us" and "Volunteer Attendance and Absence System" are two menu rows that open the exact same screen.** Same for "Our Partners" vs. "Supporting Organizations" (same screen, just a filter flag).
8. **Beneficiary "My help requests" and "Pending projects for help" are near-duplicate screens** built from the same controller/data, one just client-side-filtered from the other — two menu items and two files for what should be one screen with a status filter.
9. **Three parallel "get help" channels are all surfaced at once**: an AI chatbot, a human "Contact support" chat, and (mid-AI-conversation) a WhatsApp hand-off offer — all reachable from the same Messages screen.
10. **City Guide has three different ways to see the same list of places**: the map's pin bottom-sheet, a horizontal place-card strip under the map, and a fully separate "Services Directory" list screen — each leading to overlapping/duplicate destinations.
11. **Marriage hub: "Create/edit my profile" and "My profile" are two separate tiles/screens** for what is conceptually one "my profile" concept (edit-form vs. status-view).
12. **Several fields look editable but are actually locked** (read-only Full name/Phone in donation checkout, read-only Currency field in the beneficiary case form) — styled identically to real inputs, which is confusing.
13. **Status is often shown 2–3 times per card** (icon color + text pill + repeated in a detail sheet) — could be a single consistent status badge used everywhere.
14. **The Services hub repeats the same 4–5 tiles** ("Partners", "News and activities", "Technical support", "Marriage posts") across all three role variants, mixed flatly with role-specific actions — could be hoisted into one shared "Community & Support" section.

---

## Table of Contents

1. [App Navigation Structure](#1-app-navigation-structure)
2. [Splash & Onboarding / Auth](#2-splash--onboarding--auth)
3. [Dashboard, Drawer & Shared Navigation Widgets](#3-dashboard-drawer--shared-navigation-widgets)
4. [Donations & Sponsorship (Kafala)](#4-donations--sponsorship-kafala)
5. [Services Hub (Beneficiary Cases, Sponsorship Form, In-Kind, Support, Reports)](#5-services-hub)
6. [News & Activities, Partners, Beneficiary Case Detail](#6-news--activities-partners-beneficiary-case-detail)
7. [City Guide (Map & Directory) + Add an Activity](#7-city-guide)
8. [Marketplace & Cart](#8-marketplace--cart)
9. [Aid Receipts](#9-aid-receipts)
10. [Marriage Module](#10-marriage-module)
11. [Chat, Support Bot, Notifications, Search, History, Legal Pages](#11-chat-support-bot-notifications-search-history-legal-pages)
12. [Volunteer Hub (Support Section)](#12-volunteer-hub)

---

## 1. App Navigation Structure

### Bottom navigation tabs

Fixed at **4 tabs**, identical for every role (donor, beneficiary, volunteer, guest all see the same 4 — there is no per-role tab hiding anymore):

| # | Label | Screen shown | Role restriction |
|---|-------|--------------|-------------------|
| 0 | Home | Guest Home (guest) or role-adaptive Dashboard Home | None |
| 1 | Store | Marketplace | None |
| 2 | Marriage | Marriage Hub | None |
| 3 | City Guide | City Guide map | **Guests blocked** — tapping shows an "Upgrade Account" dialog instead of switching tabs |

Everything that used to be its own tab (Kafala/Sponsorship, Contribute, Volunteer, Services) now lives inside Home's quick-action tiles and the Profile drawer, not as separate top-level tabs — though in practice the app also has dedicated "Sponsorship" and "Services" section screens reached via menu/quick-action, described in sections 4–5 below.

Tab bar is a frosted-glass, pill-shaped, floating bar pinned to the bottom. Android back button: returns to Home from any other tab; on Home, shows an "Exit App?" confirm dialog.

### Top app bar (persistent, on every tab)

- **Left:** profile avatar → opens the Settings drawer (shows a red dot if profile incomplete).
- **Right:** Search icon → Global Search. Notification bell (unread badge) → Notifications. Messages icon (unread badge) → Messages.
- **Home tab only, extra header row:** Technical support icon → Support Ticket form. Refresh icon → re-fetch dashboard summary.

### Settings / Profile Drawer (opened via avatar)

In order:
1. Account header (avatar, name, phone/username, edit pencil icon)
2. **Control Settings and Preferences** (hidden for guests) → sub-page with Account Info, Payment Methods, Privacy & Security
3. **Language** → bottom-sheet picker (English / Arabic / Kurdish Sorani / Kurdish Badini)
4. **Dark mode** → inline switch
5. *(divider)*
6. **Volunteer With Us** (volunteers only) → Support/Volunteer section
7. **Volunteer Attendance and Absence System** (volunteers only) → *same destination as #6* (duplicate)
8. **Task Verification** → Task Verification screen
9. **Our Partners** → Partners screen
10. **Supporting Organizations** → Partners screen, filtered (duplicate destination component)
11. **Receipts** → Aid Receipts screen
12. **Services** → Services hub
13. **Share app** → native share sheet
14. *(divider)*
15. **Terms & Conditions**, **About Us**, **Our Humanitarian Work**, **Contact Us** → content pages
16. **Clear cache** → confirm dialog, clears image cache
17. *(bottom, pinned)* **Sign in** (guest) or **Log out** (signed-in)

### Impact stats slider (Home)

Auto-rotating cards (every 4s) of: Total given (IQD), Completed works, Grantors, Volunteers, Eligibles — each dropped if zero; whole widget hides if all are zero or on error.

---

## 2. Splash & Onboarding / Auth

### Splash Screen (`modules/splash/screens/splash_screen.dart`)
**Purpose:** Launch screen shown to everyone for ~2.4s while the app restores session/registration status and decides where to route.
**How you get here:** Always first on cold app start.
**Layout / sections:** Animated gradient background with drifting color orbs; centered rotating-ring glass badge with the BalanceNex logo; app name below in gradient text; thin shimmering loading bar at the bottom.
**Every button / tappable control:** None — fully automatic.
**Tabs / menus / dropdowns:** None.
**Form fields / inputs:** None.
**States:** Single loading state; no visible error state (failures silently clear stored identity and route to Welcome).
**Notes for a redesigner:** Purely decorative, safe to simplify. The shimmer bar runs on a fixed timer independent of actual load completion — consider tying it to real load state.

### Welcome Screen (`modules/auth/screens/welcome.dart`)
**Purpose:** First screen for a logged-out user; identical for every role.
**How you get here:** From Splash, when no session/guest exists.
**Layout / sections:** Centered glass card; top-right language pill; circular badge/logo; headline "Balance and Stability for a Better Life!"; two stacked buttons.
**Every button / tappable control:** "Sign in" → Login. "Create account" → **also Login** (same screen, no separate flow). Language pill → popup menu (EN/AR/CKB/Badini).
**Tabs / menus / dropdowns:** Language popup menu (4 options).
**Form fields / inputs:** None.
**States:** Static.
**Notes for a redesigner:** **Confirmed duplicate** — both primary buttons do the same thing. Merge into one "Get started" action, or make the second button meaningfully different (or remove it).

### Login Screen (`modules/auth/screens/login.dart`)
**Purpose:** Phone+OTP sign-in (and de-facto registration) plus Google sign-in and guest access, for any role.
**How you get here:** From Welcome, or Register's "Sign in" link.
**Layout / sections:** Glass card, "Secure sign in" badge, phone input with country-code picker, OTP-mode 2-segment picker (Real OTP vs Demo OTP), "Send OTP" button, divider, "Continue with Google" button, "Continue as guest" text button, "Create one" link, guest-access bottom sheet.
**Every button / tappable control:**
- Country-code picker → searchable 200+ country dialog.
- "Send OTP" → validates phone, sends code, goes to Verification.
- Real/Demo OTP segment toggle.
- "Continue with Google" → Google sign-in, logs in directly (no OTP).
- "Continue as guest" → opens guest sheet (username + password; "Continue as guest" primary button; if username taken, a "That's me — log in instead" button appears).
- "Create one" → Register screen.
**Tabs / menus / dropdowns:** OTP delivery mode (Real/Demo) segmented control; country-code picker dialog.
**Form fields / inputs:** Phone (required, validated per country); guest sheet: Username (required, 3–32 chars), Password (required, 6+ chars, show/hide toggle).
**States:** Loading spinners on Send OTP / Google buttons; inline error text on failure; guest sheet has its own error + "username taken" state.
**Notes for a redesigner:** "Demo OTP · Code: 123456" is a developer/testing toggle that exposes an internal code in the UI — should not ship in a customer-facing redesign. The guest sheet is effectively a second, parallel signup system (username/password) alongside the main phone/OTP flow — consider unifying.

### Register Screen (`modules/auth/screens/register.dart`)
**Purpose:** Per the code's own comments, this screen **does not actually create an account** — it fakes a delay and forwards to Verification.
**How you get here:** "Create one" link on Login.
**Layout / sections:** Glass card, "Create your account" badge, Email/Password/Confirm-password fields, "Create account" button, "Already have an account? Sign in" link.
**Every button / tappable control:** Password show/hide toggle; "Create account" → fake ~650ms delay, then Verification regardless of backend; "Sign in" link → back to Login.
**Form fields / inputs:** Email (required, must contain "@"), Password (required, 6+ chars), Confirm password (must match).
**States:** Loading spinner on submit; no real error state (never calls a backend).
**Notes for a redesigner:** **Recommend removing this screen entirely** — it's vestigial and misleading; the real signup path is Login's phone/OTP flow.

### Registration Form / "Complete your registration" (`modules/auth/screens/registration_form.dart`)
**Purpose:** The real onboarding form after phone verification — collects identity + role and submits for admin approval.
**How you get here:** Auto-routed after OTP verification (or guest upgrade) for new/incomplete accounts; also from Pending Approval's "Edit and resubmit."
**Layout / sections:** "Complete your registration" header (no back button); Panel 1 — Full name, Date of birth, Address, Gender (optional), City (optional), Occupation (optional); Role tiles — Donor / Beneficiary / Volunteer (mutually exclusive, icon+color+tagline); Conditional Panel 2 (Beneficiary only) — Family size, Housing status, Monthly income; Conditional Panel 3 (Volunteer only) — Skills, Availability, Experience; Terms & Conditions checkbox + link; "Submit for approval" button; full-screen loading overlay while submitting.
**Every button / tappable control:** Date picker; Gender/Housing-status/Experience dropdowns; 3 role tiles; Terms checkbox; Terms link → Terms screen; "Submit for approval" → validates and submits, then routes by resulting status.
**Tabs / menus / dropdowns:** Gender (Male/Female/Other); Housing status (Owned/Rented/Hosted/Displaced); Experience (None/<1yr/1–3yrs/>3yrs).
**Form fields / inputs:** Full name*, Date of birth*, Address*, Gender, City, Occupation, Role*, (if Beneficiary) Family size/Housing status/Monthly income, (if Volunteer) Skills/Availability/Experience, Terms checkbox* (* = required; some optional fields can be made required by admin config, but the UI doesn't visually mark which ones without triggering an error first).
**States:** Full-screen overlay + spinner while submitting; inline red error text for validation failures.
**Notes for a redesigner:** Long single-scroll form mixing identity + role selection + role-specific extras + legal consent — strong candidate for a multi-step wizard. Required fields aren't visually marked until an error appears — add always-visible required indicators (e.g. asterisks).

### Verification / OTP Screen (`modules/auth/screens/verification.dart`)
**Purpose:** Enter the 6-digit code sent during Login.
**How you get here:** After "Send OTP" on Login.
**Layout / sections:** "Secure Verification" header; phone-number confirmation text; 6-digit code field; "Verify OTP" button; a secondary button that is either "Resend OTP" or "Back to login" depending on state.
**Every button / tappable control:** "Verify OTP" → submits code, routes to home/registration/pending-approval as appropriate. Secondary button — dual-purpose (resend vs. back), label changes based on state.
**Form fields / inputs:** 6-digit code (required, numeric).
**States:** Loading spinner replacing button label; inline error text on failure.
**Notes for a redesigner:** The bottom button's label silently swapping between "Resend OTP" and "Back to login" is confusing — split into two always-visible, distinct actions.

### Guest Upgrade Screen (`modules/auth/screens/guest_upgrade.dart`)
**Purpose:** Lets a guest attach a verified phone number, upgrading into a normal phone account, then proceeding into the registration form.
**How you get here:** From an "upgrade account" prompt elsewhere (e.g. tapping City Guide as a guest).
**Layout / sections:** Two-step flow — Step 1: phone entry + country picker + "Send code"; Step 2: 6-digit OTP entry + "Verify & Continue" + "Use a different number" link.
**Every button / tappable control:** Country picker (same as Login); "Send code"; "Verify & Continue" → routes into registration form; "Use a different number" → resets to step 1.
**Form fields / inputs:** Phone (required), OTP code (required, 6 digits).
**States:** Loading spinners; inline error text.
**Notes for a redesigner:** Near-identical UI/flow to Login's phone+OTP portion — consider one shared "phone verification" component used by both Login and Guest Upgrade instead of two implementations.

### Pending Approval Screen (`modules/auth/screens/pending_approval.dart`)
**Purpose:** Holding screen while registration is under review, or shows rejection reason.
**How you get here:** Auto-routed after registration submission (pending), or on relogin while still pending/rejected.
**Layout / sections:** Large icon badge (hourglass = pending, error icon = rejected); headline + subtitle; (rejected only) "Rejection reason" panel; "Your details" read-only summary (Name/Address/Role); (rejected only) "Edit and resubmit" button; "Check status" button; "Log out" link.
**Every button / tappable control:** "Edit and resubmit" (rejected only) → Registration Form. "Check status" → re-polls status, auto-enters app if approved, else shows a "still waiting" snackbar. "Log out" → immediate logout to Login.
**States:** Auto-checks status silently once on open; manual "Check status" shows its own spinner + snackbar feedback.
**Notes for a redesigner:** Clean and single-purpose; only suggestion is replacing manual polling with pull-to-refresh for a more modern feel.

### Profile & Settings Screen (`modules/auth/screens/profile.dart`)
**Purpose:** Main "Profile & Settings" tab — profile summary plus every account/service/preference/legal option in one long list.
**How you get here:** A bottom-nav-adjacent tab (Profile tab, accessible any time while logged in) — **note:** in the current shell described in Section 1, Profile is opened via the drawer, but this dedicated Profile screen file also exists as its own tab-like destination; the two overlap significantly (see notes).
**Layout / sections:** Gradient hero card (avatar, name, role pill, Edit button); conditional "Complete your profile" reminder banner; **Account** section (Privacy & Security, Field privacy, Payment Methods, App Settings, Clear cache); **Services** section (Search, Aid receipts, Share the app, Services); **Preferences** section (Language rows shown inline, Dark mode, Notifications, Mute sounds toggle); **Legal** section (Terms, About Us, Contact Us); "Log out" at the bottom.
**Every button / tappable control:**
- Edit button / "Finish now" banner → Edit Profile.
- **"Privacy & Security" tile → dead, no action wired.**
- "Field privacy" tile → Field Privacy screen (works).
- **"Payment Methods" tile → dead, no action wired.**
- **"App Settings" tile → dead, no action wired.**
- "Clear cache" → confirm dialog, clears cache.
- "Search" → Global Search. "Aid receipts" → Aid Receipts. "Share the app" → share sheet. "Services" → Services hub.
- Language rows (4, inline) → switch locale directly.
- Dark mode / Notifications / Mute — switches.
- Terms / About Us / Contact Us tiles → content pages.
- "Log out" → confirm dialog, logs out.
**States:** Avatar loads local file → remote URL → placeholder; completeness banner shows/hides based on computed profile state; each preference toggle loads its saved value and reverts on save failure.
**Notes for a redesigner:** **Highest-priority screen to fix.** Three tiles are dead code that look identical to working tiles. A separate, fully-working "Control Settings" screen (see Section 3) duplicates Account/Payment/Privacy destinations. Recommend picking ONE settings hierarchy — Control Settings' clean 3-tile grouped pattern is the better template — and removing the dead/duplicate tiles here.

### Edit Profile Screen (`modules/auth/screens/edit_profile.dart`)
**Purpose:** Update name, address, gender, and profile picture.
**How you get here:** "Edit" button / "Finish now" banner on Profile; Control Settings' "Account Information and Editing" tile.
**Layout / sections:** Photo card (avatar with camera-icon overlay, "Choose image" button, conditional "Remove image" button, completion banner); Identity card (read-only Phone, Full name, Address); Gender card (3 choice chips); "Save profile" button.
**Every button / tappable control:** Camera icon on avatar and "Choose image" button — **both do the exact same thing** (open gallery picker); "Remove image"; Gender chips (Male/Female/Other); "Save profile" → validates and saves.
**Form fields / inputs:** Phone (read-only), Full name*, Address* (multiline), Gender* (chips), Profile picture (optional).
**States:** "Saving…" label while saving; success/failure snackbar.
**Notes for a redesigner:** **Confirmed duplicate** — camera icon and "Choose image" button do the same thing; keep only one (the avatar-overlay camera icon is the more standard pattern).

### Control Settings and Preferences (`modules/auth/screens/control_settings_screen.dart`)
**Purpose:** A cleaner settings sub-hub grouping account editing, payments, and privacy.
**How you get here:** A settings/drawer entry point.
**Layout / sections:** Three stacked option tiles: "Account Information and Editing", "Payment Methods and Payment Gateways", "Privacy and Security".
**Every button / tappable control:** Each tile → Edit Profile / Payment Methods / Privacy & Security screens (all working).
**States:** Static list.
**Notes for a redesigner:** This 3-tile grouped pattern is clean and should be the **single** settings entry point — see notes on the Profile screen above about consolidating.

### Field Privacy Screen (`modules/auth/screens/field_privacy_screen.dart`)
**Purpose:** Choose which profile fields are visible to others.
**How you get here:** "Field privacy" tile (Profile screen or Privacy & Security screen).
**Layout / sections:** 6 toggle rows, one per field, each in its own panel.
**Every button / tappable control:** Switch per field (Full name, Phone number, Gender, Address, Date of birth, Profile picture) — saves immediately, reverts silently on failure.
**States:** Full-screen spinner on initial load; caption "Visible to others"/"Hidden" per row.
**Notes for a redesigner:** Clean already. Consider a save-failure toast since it currently reverts silently with no feedback.

### Privacy and Security Screen (`modules/auth/screens/privacy_security_screen.dart`)
**Purpose:** Thin wrapper explaining the only privacy control that exists (field-level privacy) plus a note that there's no password to manage (phone+OTP auth).
**How you get here:** Control Settings' "Privacy and Security" tile.
**Layout / sections:** One tile ("Field privacy") + an info note.
**Every button / tappable control:** "Field privacy" tile → Field Privacy screen.
**Notes for a redesigner:** Deliberately minimal (good practice — avoid shipping dead buttons for features the backend doesn't support). Reconcile with Profile screen's dead "Privacy & Security" tile — only one should exist.

### Payment Methods Screen (`modules/auth/screens/payment_methods_screen.dart`)
**Purpose:** Shows wallet balance, transaction history, and admin-configured ways to pay — entirely read-only, no "add payment method."
**How you get here:** Control Settings' "Payment Methods and Payment Gateways" tile.
**Layout / sections:** "My wallet" balance card; "Wallet activity" transaction list (empty state if none); "Ways to pay" info cards (empty state if none configured).
**Every button / tappable control:** Pull-to-refresh only — no other actions.
**States:** Spinner on load; two independent empty states.
**Notes for a redesigner:** Well-grouped already. Consider whether a "Top up wallet" CTA belongs here if that capability is planned.

### Task Verification Screen (`modules/auth/screens/task_verification_screen.dart`)
**Purpose:** Shows tasks assigned to the user (mainly relevant to volunteers) with self-report completion.
**How you get here:** Drawer/menu entry point.
**Layout / sections:** Empty-state tile if none; "Pending" section + cards; "Completed" section + cards. Each pending card has a "Mark as done" button.
**Every button / tappable control:** Pull-to-refresh; "Mark as done" per pending task (spinner while in-flight).
**States:** Spinner on load; empty state; per-task busy spinner; error snackbar on failure.
**Notes for a redesigner:** Clean, well-grouped (Pending vs Completed), no notable issues.

---

## 3. Dashboard, Drawer & Shared Navigation Widgets

### Dashboard Shell (`modules/dashboard/screens/dashboard_screen.dart`)
**Purpose:** Root authenticated/guest screen hosting the persistent top bar, 4 tabs, and bottom nav.
**Layout / sections:** Persistent top bar; `IndexedStack` body (Home/Store/Marriage/City Guide); floating bottom nav; side Settings drawer.
**Every button / tappable control:** Profile avatar → drawer; Search/Notifications/Messages icons (see Section 1); 4 bottom-nav tabs (City Guide blocked for guests → upgrade dialog); Exit dialog Cancel/Exit.
**Notes for a redesigner:** Bottom nav is intentionally minimal (4 tabs) — good pattern to keep. Three separate "chrome" treatments currently stack (blurred nav, plain top row, gradient page headers) — could be unified into one consistent visual system.

### Role-adaptive Home Dashboard (`widgets/dashboard.dart`)
**Purpose:** Role-specific home feed — stats, quick actions, and public content, styled differently for donor/beneficiary/volunteer.
**Layout / sections (donor variant):** Page header with Support + Refresh icons; Hero gradient card ("Make donation" primary + "My history" secondary + 2 hero stats); Wallet card; Impact Stats Slider; 2×2 stat grid; "Quick actions" (Contribute/History/Support); "Explore" (Assistant); category capsules; "Featured campaigns" strip; "Latest news" strip; "Our partners" strip; "Recent donations" list.
**Beneficiary variant differences:** Hero CTA "Submit request"; stat grid differs (Approved cases/Needs changes/Approved requests/Open tickets); Quick actions (Submit/My requests/Pending); no wallet card.
**Volunteer variant differences:** Hero CTA "Open missions"; stat grid (Available/Completed missions/Application status/city); Quick actions (Missions/Apply/History); no wallet card.
**Every button / tappable control:** Primary hero CTA (role-dependent); "My history"; hero stat tiles (some tappable); Wallet info icon (dialog); Support/Refresh header icons; 3 quick-action tiles; Assistant tile; category capsules; "See all" links (4 of them); individual cards throughout; "Retry" on error.
**States:** Loading spinner, error + Retry, per-list empty-state text, promotional strips silently hide if empty.
**Notes for a redesigner:** **Most cluttered screen in the app** — 10+ stacked sections in one scroll. Confirmed duplicates: "Contribute" quick action = "Make donation" hero CTA (same destination); "History" quick action = "My history" hero button = every activity-tile tap (same destination, 3 paths); "Support" quick action = "Active sponsorships" hero stat (same destination). Strongly recommend one clear primary CTA + one quick-actions row (not duplicated elsewhere) + collapsing the 3 promotional strips into a single carousel/"Discover" section.

### Settings & Profile Drawer (`widgets/settings_drawer.dart`)
See full ordered list in Section 1. **Notes for a redesigner:** "Our Partners"/"Supporting Organizations" and "Volunteer With Us"/"Volunteer Attendance..." are confirmed duplicate destinations. The 20-row flat list mixes account settings, content pages, and operational tools — group into headed sections (Account / Preferences / My Activity / Organization Info / Support).

### Profile Menu Button (`widgets/profile_menu.dart`)
**Purpose:** Top-bar avatar control that opens the Settings drawer.
**Every button / tappable control:** The avatar itself — opens the drawer (despite the name, it's not a popup menu).
**Notes for a redesigner:** Naming is misleading internally, but harmless for the redesign — useful context if you want a true popover menu instead of a drawer.

### Impact Stats Slider (`widgets/impact_stats_slider.dart`)
Passive, auto-rotating, non-interactive — hides itself completely when empty/loading/error. **Notes for a redesigner:** Could be visually merged with the Featured Campaigns strip right below it on Home to reduce "carousel fatigue" (two back-to-back auto-rotating card carousels).

### Notifications widget / screen (`widgets/notification.dart`, `modules/notifications/screens/notifications_screen.dart`)
**Purpose:** Unread/read notifications list.
**Layout / sections:** Hero summary card (unread count, animated bell, "Mark all" pill); 3 stat pills (All/Unread/Read); Filter by status chips (All/Unread/Read); Filter by category chips (All/Urgent/Payment/Campaign/System/Reminder/Normal); Filter by type dropdown; notification tile list.
**Every button / tappable control:** "Mark all" pill; status chips; category chips; type dropdown; each tile (tap to open, swipe to mark read); pull-to-refresh.
**States:** Loading, error, empty ("No notifications match the selected filters.").
**Notes for a redesigner:** Three separate stacked filter mechanisms (status chips + category chips + type dropdown) before any content is visible — consolidate into one filter sheet or one combined chip row. "Mark all" pill and the "Unread" chip both relate to the same concept and sit apart — group visually.

### Auth UI shared components (`widgets/auth_ui.dart`) & Shared glass UI kit (`shared/widgets/glass_ui.dart`)
Two parallel "glass card" design systems exist — one used only by auth screens, one (`GradientScreen`/`GlassPanel`/`SectionScaffold`/`SectionTile`/`InfoChip`) used by nearly every other pushed screen. **Notes for a redesigner:** Unify into a single design-system component set; `SectionScaffold`'s header pattern is used almost everywhere, so redesigning it once cascades cleanly app-wide.

### Cached Profile Avatar (`widgets/cached_profile_avatar.dart`)
Shared building block (local file → network → initial letter → icon fallback chain), used by drawer header and top-bar button. No issues — redesign it once, it updates everywhere.

---

## 4. Donations & Sponsorship (Kafala)

### Contribute / Give Now hub (`modules/donations/screens/donations_section.dart`)
**Purpose:** Main donation screen for donors — pick a campaign or give unrestricted support, choose an amount, proceed to checkout. Guests are prompted to upgrade before donating.
**Layout / sections:** Header + "See all" (→ donation history); **"Give Now" hero card** (teal gradient, tappable); "Featured campaigns" list (each with progress bar + "Donate to this campaign" button); "Quick amount" chips (10k/20k/50k/100k IQD); "Selected donation" summary card + "Continue donation" button; **"Comprehensive Giving" option card** (its own "Choose option" button); static "Why people choose this" info card.
**Every button / tappable control:** "See all"; "Give Now" hero card; campaign card tap → Campaign Detail; "Donate to this campaign" button per card; amount chips; "Continue donation"; "Choose option"/"Selected option" on the Comprehensive Giving card; Retry on error.
**States:** Loading, error+Retry, empty ("No campaigns available.").
**Notes for a redesigner:** **Confirmed — "Give Now" and "Comprehensive Giving" do the exact same thing** (clear campaign selection + scroll to amount). Merge into one persistent "give without a specific campaign" affordance. The "Continue donation" button's visibility logic appears inverted in the code (shows only when donor name is *empty*) — flag to engineering, not just a design fix. The bottom "Why people choose this" card is pure marketing filler with no function — consider dropping for a cleaner screen.

### Contributions list (`modules/donations/screens/donations_screen.dart`)
Appears to be legacy/dead code — a bare `ListView` of donation cards not clearly wired into current navigation. **Notes for a redesigner:** Confirm with engineering whether this is still routed to anywhere; if not, don't design it — a much richer version already exists (My Contributions, below).

### Campaign Details (`modules/donations/screens/campaign_detail_screen.dart`)
**Purpose:** Full detail of one campaign; browsable by anyone, "Donate" is donor-only.
**Layout / sections:** Hero summary; conditional "About this project"; Funding card (goal/raised/progress bar); conditional Location & community, Volunteers, Timeline, Contact, Notes cards; Status & activity card; bottom fixed "Donate to this campaign" button.
**Notes for a redesigner:** Many small optional detail cards create a long page — consider tabs (Overview/Location/Contact) for a more compact feel. "Organizer user ID" (a raw internal ID) is shown to end users and should be removed from a consumer-facing redesign.

### Continue Donation / Checkout (`modules/donations/screens/continue_donation_screen.dart`)
**Purpose:** Checkout form — amount, donation type, payment method, confirm.
**Layout / sections:** Checkout hero card; Donor details (read-only Name/Phone, editable Amount, optional Message); Donation type selector (General/Zakat/Sadaqah); Payment method cards (App Wallet + admin-configured methods, Cash/FIB fallback); conditional Account/transfer details card with Copy button; Contribution summary; "Confirm [amount] IQD donation" button; success dialog.
**Notes for a redesigner:** Two disabled fields (Name, Phone) are styled identically to editable ones — should look visibly locked, not like fillable inputs. Amount is re-editable here despite already being chosen via chips on the previous screen — pick one source of truth. "Contribution summary" duplicates the same single line as both "Contribution amount" and "Total."

### Contribution Details — placeholder (`modules/donations/screens/donation_details_screen.dart`)
Unused stub screen (just static text "Contribution details screen"). **Notes for a redesigner:** Dead code — the real detail view is the bottom sheet in My Contributions (below); don't design this file, confirm deletion with engineering.

### My Contributions / Donation history (`modules/donations/screens/my_donations_page.dart`)
**Purpose:** Full donation history with totals and per-donation detail/chat.
**Layout / sections:** Hero card (total + Campaigns/Success/Pending counts); "Contribution status" legend chips (Success/Pending/Failed — **decorative only, not real filters despite looking like filter chips**); "Recent donations" list with "View details" → bottom sheet (detail rows + "Chat with campaign owner" button if applicable).
**Notes for a redesigner:** The status legend chips look tappable but aren't — either make them real filters or restyle so they don't imply interactivity. Status is shown 3× per item (amount color, badge, repeated in the detail sheet) — simplify to one consistent indicator.

### Kafala Support / Eligible support hub (`modules/sponsorship/screens/sponsorship_section.dart`)
**Purpose:** Entry hub for Sponsorship — content differs entirely by role.
**Donor variant:** 3 tiles — "Overview", "Create monthly sponsorship", "Orphan & Family Profiles".
**Beneficiary variant:** 7 tiles — "Submit project for help", "My entitlements", "My campaign donations", "My help requests", "Pending projects for help", "Submit beneficiary case", "My beneficiary cases".
**Notes for a redesigner:** **Confirmed duplicate pair** — "My help requests" and "Pending projects for help" pull from the same controller/data, one just filtered from the other; merge into one screen with a status filter. The beneficiary variant's 7 flat tiles mix two parallel systems ("projects" vs. "cases") — group into two clearly labeled sections at minimum, or unify the underlying concepts.

### Sponsorship Overview (`modules/sponsorship/screens/sponsorship_overview_screen.dart`)
**Purpose:** Donor's view of active monthly sponsorships, with cancel action.
**Layout / sections:** Hero card; "My monthly sponsorships" list (each with due-date text + conditional "Cancel sponsorship" button); static "Focus areas" filler card.
**Notes for a redesigner:** Error state has no Retry button (inconsistent with the rest of the app) — only pull-to-refresh recovers, which isn't obvious. "Focus areas" is filler — consider folding into the hero card or removing.

### Beneficiary Entitlements / "My entitlements" (`modules/sponsorship/screens/beneficiary_entitlements_screen.dart`)
**Purpose:** Shows which sponsorships support the beneficiary, with a voice-readout accessibility feature.
**Layout / sections:** Voice header card ("Listen"/"Stop" buttons); entitlement cards (status chip, amount, recurrence, next-due date).
**Notes for a redesigner:** Auto-speaks a summary on first load with no opt-out beyond a Stop-after-the-fact button — consider making voice opt-in. Status color coding is inconsistent with other screens — unify a single app-wide status-color system.

### Beneficiary Campaign Donations (`modules/sponsorship/screens/beneficiary_campaign_donations_screen.dart`)
**Purpose:** For beneficiaries with published campaigns — see donations received per campaign, chat with donors.
**Layout / sections:** Summary band; per-campaign expandable cards; donation rows (donor, amount, delivery-status chip, tappable to start a chat).
**Notes for a redesigner:** The "start a chat" tap target is the whole row with only a subtle icon — make it a clearer button. Delivery-status vocabulary here (registered/under_review/received/delivered/cancelled) differs from the donor-side vocabulary (success/pending/failed) for what's conceptually the same donation — worth reconciling.

### Beneficiary My Projects / "My help requests" (`modules/sponsorship/screens/beneficiary_my_projects_screen.dart`)
Shows ALL submitted project requests regardless of status. **Notes for a redesigner:** See the confirmed duplicate note above (vs. Pending Projects). Also: like/comment counts appear on this private tracking view, which seems like leftover styling from a public feed — question whether that's needed here.

### Beneficiary Pending Projects (`modules/sponsorship/screens/beneficiary_pending_projects_screen.dart`)
Same data/controller as My Projects, client-side filtered to pending-only. **This is the clearest duplicate-screen case in the app** — recommend one "My requests" screen with a status filter chip row (All/Pending/Approved/Rejected) instead of two menu items and two files.

### Beneficiary Submit Project (`modules/sponsorship/screens/beneficiary_submit_project_screen.dart`)
**Purpose:** ~18-field form to submit a help-project request.
**Layout / sections:** Project panel (title/category/summary/description); Budget panel (amount+currency); "Where & who" panel (location, community name, optional headcount fields that reveal more fields, timeline); Contact panel (all optional); "Submit project request" button.
**Notes for a redesigner:** Very long single-scroll form — strong candidate for a multi-step wizard (Project → Budget → Location/People → Contact). The Currency field is read-only but styled like a real input — restyle as a static label. Consider splitting the conditional "people affected" volunteer-info fields into their own panel.

### Orphan & Family Profiles (`modules/sponsorship/screens/orphan_family_profiles_screen.dart`)
**Purpose:** Browsable directory for donors to choose someone to sponsor.
**Layout / sections:** Intro card; category filter capsules; profile cards (priority tag, needs note, "Sponsor" button; whole card also tappable → case detail).
**Notes for a redesigner:** The "Sponsor" button doesn't pass which profile was tapped into the sponsorship form — confirm with engineering whether this is intentional; if not, it's a functional gap that undermines the "sponsor this specific person" intent the button implies. Card-tap-for-detail vs. button-tap-for-action overlap — visually distinguish "Sponsor" as the strong primary CTA vs. the rest of the card as passive/navigable.

---

## 5. Services Hub

### Services Hub (`modules/proposal/screens/proposal_services_section.dart`)
**Purpose:** Central menu of giving/support tools + public-content shortcuts + reports, varying by role.
**Donor tiles:** Beneficiary cases, Create sponsorship, In-kind donation, Partners, News and activities, Technical support, Reports, Marriage posts.
**Beneficiary tiles:** Marriage posts, Partners, News and activities, Technical support.
**Volunteer tiles:** Reports, Partners, News and activities, Technical support, Marriage posts.
**Notes for a redesigner:** The same 4–5 tiles (Partners/News/Technical support/Marriage posts) repeat verbatim across all three role variants — hoist into a shared "Community & Support" section and keep only donation-specific actions role-varying. The flat list mixes "give/request," "read content," and "get help" actions — group into labeled sections.

### Beneficiary Cases — public list (`BeneficiaryCasesScreen`)
Read-only browse list of verified cases for donors. **Notes for a redesigner:** Subtitle is a raw dash-joined string (code-city-priority) — break into structured badges.

### My Beneficiary Cases (`MyBeneficiaryCasesScreen`)
Beneficiary's private status tracker for their own case(s). **Notes for a redesigner:** Status shown via both summary chips and per-row color — could consolidate.

### Submit Beneficiary Case (`BeneficiaryCaseFormScreen`)
14-field flat form (title, name, national ID, phone, city, district, address, family members, income, housing/work/health/education status, actual needs). **Notes for a redesigner:** No field grouping (identity vs. household vs. needs) and errors only via snackbar (no inline validation) — group into labeled sections and add inline errors.

### Create Sponsorship (`SponsorshipFormScreen`)
Campaign picker dropdown, auto-filled-but-editable "Support type" field, Monthly amount, Notes; a "My sponsorships" button floats at the top linking elsewhere. **Notes for a redesigner:** "My sponsorships" as an escape-hatch button on a creation form is an odd placement — likely belongs as its own nav entry or a tab in a unified Sponsorships screen. "Support type" being both auto-filled and freely editable is a confusing dual-source-of-truth — make it a label, not an input.

### In-Kind Donation (`InKindDonationFormScreen`)
Category (free text, pre-filled "Food"), Item name, Quantity (text, not numeric), Pickup address. **Notes for a redesigner:** Category should be a proper picker (Food/Clothing/Supplies/etc.), not free text; Quantity should use a numeric keyboard.

### Technical Support (`SupportTicketFormScreen`)
Subject + Message, "Send request" button. **Notes for a redesigner:** Fine as-is; consider adding a topic/category selector for triage and inline validation instead of snackbar-only errors.

### Reports (`ReportsScreen`)
Read-only stat tiles, role-varying (donor: Completed/Pending donations; volunteer: missions/attendance stats), plus shared "Project request groups"/"Expense groups" counts. **Notes for a redesigner:** No charts, no tap-through detail — a "dead end" reports screen; consider simple charts or tappable drill-downs. "Groups" counts need clearer labeling of what a "group" means.

---

## 6. News & Activities, Partners, Beneficiary Case Detail

### News and Activities (`modules/proposal/screens/news_activities_screen.dart`)
**Purpose:** Public social-style feed (news/articles/events/videos) for all roles.
**Layout / sections:** Category filter chip row ("All" + admin categories); post cards (hero image/video, optional gallery strip, metadata pills, title, body, "Watch video"/"Open media" button, Like/Comment/Share bar).
**Every button / tappable control:** Category chips; gallery thumbnails → full-screen viewer; media button (opens video or external link); Like (guests prompted to sign in); Comment → bottom sheet; Share → native share sheet + server count.
**States:** Loading, error+retry, empty; comments sheet has its own loading/empty/sending states.
**Notes for a redesigner:** The "Watch video"/"Open media" button AND a play-icon overlay on the hero image are two affordances for the same "play this" action — unify into one clear control. Category chips + type/date/location pills + the like/comment/share bar are three different "tag" idioms stacked on one card — consolidate chip/pill styling.

### Partners (`modules/proposal/screens/partners_screen.dart`)
**Purpose:** Directory of partner organizations, reused (with a filter flag) as "Supporting Organizations."
**Layout / sections:** Partner cards — logo, name, type pill, description, a `Wrap` of contact/social chips (phone/email/website/location + one per social link), 5-star rating row + "Rate" button.
**Notes for a redesigner:** Phone/email/website/location AND every social link all render as same-style pill chips in one big wrap — group "contact" info separately from "social" icons (as recognizable brand icons) for a cleaner card. "Supporting Organizations" relies on fragile free-text keyword matching (substring search on `partner_type`) rather than a real category field — flag to engineering as a backend improvement opportunity alongside the visual redesign.

### Beneficiary Case Detail (`modules/proposal/screens/beneficiary_case_detail_screen.dart`)
**Purpose:** Read-only detail of one verified case.
**Layout / sections:** Title (shown twice — top bar + card heading, redundant); detail lines (code, city, district, address, family members, housing/work/health/education status, priority, status); separate "Actual needs" card.
**Notes for a redesigner:** Zero calls-to-action on a screen meant to help a donor decide whether to help — no "Sponsor this case"/"Donate now" button links out from here; consider adding a direct action connecting case detail → sponsorship/donation flow.

---

## 7. City Guide

### City Guide (map) + Services Directory (list) (`modules/community/screens/community_services_section.dart`)
**Purpose:** Two-part local-services feature (map + directory list) for all roles including guests.
**Map screen layout:** Gradient header card with place count; "Add an Activity" button; sector filter chips; interactive map (custom pins, recenter button, empty-state overlay); horizontal place-card strip below the map; tapping a pin/card opens a bottom sheet (name, "Maps ↗", sector tags, phone/website rows, gallery strip, "View Full Details" button).
**Directory list layout:** Loading/error/empty states; vertical list of service cards (category-colored icon, name, category pill, address, city·phone line) — tapping opens the full Community Detail screen directly.
**Notes for a redesigner:** **Confirmed — three overlapping ways to see the same place info**: the map bottom-sheet, the horizontal place-card strip (opens the same bottom sheet), and the separate directory list (jumps straight to full detail). This is the most duplicated navigational pattern in the app — consolidate into one unified list/map toggle view. The bottom sheet's "View Full Details" button existing alongside a directory card that already jumps straight to detail is itself a duplicate path to the same destination. Category coloring is done via client-side keyword matching — should be a real backend category+color field.

### City Service / Community Detail (`modules/community/screens/community_detail_screen.dart`)
**Purpose:** Full detail page for one place.
**Layout / sections:** Detail lines (category, city, address, phone, email, website, coordinates, privacy note if approx-location, opening hours, sector tag chips); description card; photo gallery card; mini-map card with "Open in Maps" button.
**Notes for a redesigner:** Phone/email/website rows look tappable (colored icon) while Coordinates/Hours/Category rows look identical but are inert — inconsistent affordance cues; make tappable vs. informational visually distinct everywhere. The Coordinates text row duplicates the mini-map right below it — drop the raw numbers in favor of just the map + "Open in Maps" button.

### Add an Activity (`modules/community/screens/add_activity_screen.dart`)
**Purpose:** User-submitted place suggestion, goes into an admin approval queue.
**Layout / sections:** Place name*, Category* (free text), City, Address, Phone, Opening Hours, Latitude/Longitude (raw numeric fields), Sector multi-select chips, "Submit for review" button.
**Notes for a redesigner:** Category is free text here despite City Guide having a fixed, color-coded category system elsewhere — should be a picker matching that same set. Raw Latitude/Longitude number fields are poor mobile UX for "suggest a place" — a tap-to-drop-pin map picker (the app already has the map component) would be far friendlier.

---

## 8. Marketplace & Cart

### Marketplace (`modules/marketplace/screens/marketplace_section.dart`)
**Purpose:** Browse-and-buy storefront for any role; guest checkout is blocked.
**Layout / sections:** "Your orders" shortcut tile; infinite-scroll product list (image, name, category, label badges [new/sale/featured/used/in_stock], price, Add/quantity stepper); floating cart teaser bar (appears once cart has items).
**Every button / tappable control:** "Your orders" tile; product tile tap OR long-press → product-details bottom sheet (two entry points, slightly different close behavior); Add button → quantity stepper; cart teaser bar → Cart screen.
**Notes for a redesigner:** No category/label filter exists despite products having both a category and up to 5 label badges — an easy, missing win for filtering "on sale"/"new" items. Tap and long-press both open the same product-detail sheet with different dismiss behavior — unify to one interaction model.

### Cart (`modules/marketplace/screens/cart_screen.dart`)
**Purpose:** Review + checkout cart items.
**Layout / sections:** Line items with quantity steppers; Payment method (Cash vs. App Wallet cards); item count + total; "Clear" button; "Checkout" button; empty-cart state.
**Notes for a redesigner:** Good separation already (deliberately split out from an earlier cramped overlay per code comments) — keep checkout as its own full screen in the redesign. Add a visible error/toast for checkout failure (currently only success has explicit feedback).

### Marketplace Orders (`modules/marketplace/screens/marketplace_orders_screen.dart`)
Read-only order history (status icon + status pill — redundant, shown twice per card). **Notes for a redesigner:** No cancel/contact-support action on a pending order — likely a gap vs. user expectations for an order-history screen.

---

## 9. Aid Receipts

### Aid Receipts (`modules/receipts/screens/aid_receipts_screen.dart`)
**Purpose:** Beneficiary's read-only record of aid received, with reference codes and staff-uploaded proof photos.
**Layout / sections:** Receipt cards — masked code, delivered-at date, items text, "Delivered by [name]," notes, photo strip (tap → full-screen viewer).
**States:** Loading spinner; empty state ("You have no receipts yet.").
**Notes for a redesigner:** A failed fetch and "genuinely zero receipts" render identically (both show the same empty message) — add a distinct error+retry state, matching the pattern used elsewhere in the app (Marketplace, News). The masked receipt code is a good privacy touch worth keeping.

---

## 10. Marriage Module

### Marriage Hub (`modules/marriage/screens/marriage_hub_screen.dart`)
**Purpose:** Menu for the whole Marriage module, for everyone (guests see fewer tiles).
**Layout / sections:** Always visible — "Browse profiles", "Marriage posts". Signed-in only — "Create/edit my profile", "My profile", "Subscription", "Chats", "Message the staff team".
**Notes for a redesigner:** Two separate "message staff" entry points exist across the module (this hub's generic support chat vs. the mediated per-thread Chats) — clarify or merge. The flat 7-tile list could be grouped into "Discover" / "My Profile & Plan" / "Conversations."

### Create/edit marriage profile (`modules/marriage/screens/marriage_form_screen.dart`)
**Purpose:** Create/update a marriage/engagement profile for review.
**Layout / sections:** Photo picker; up to 10 admin-controlled optional/required fields (Gender, Age, City, About you, Private notes [staff-only], Marital status, Religion, Employment status, Weight, Height); "Who can see this profile" privacy dropdown (Private/Staff only/Matched users); "Submit profile" button.
**Notes for a redesigner:** "Private notes (staff only)" sits inline among public fields with just a lock icon marking it — visually separate public vs. staff-only fields into distinct groups. The single privacy dropdown's 3 options aren't explained (e.g., what exactly "Matched users (summary)" reveals) — add clarity, since privacy is a stated priority. Ten flat fields with no section headers — group into Basic info / About you / Physical / Privacy.

### My profile / status (`modules/marriage/screens/marriage_my_profile_screen.dart`)
Read-only status view (Submitted/Under review/Active/Paused/Matched/Rejected/Closed) of the user's own submitted profile(s). **Notes for a redesigner:** This screen and the hub's "Create/edit my profile" tile both relate to "my profile" but are two separate destinations (edit-form vs. status-view) — consider merging into one "My Profile" screen with an edit action.

### Browse profiles / Search (`modules/marriage/screens/marriage_search_screen.dart`)
**Purpose:** Search/filter profiles, bookmark, request a meeting.
**Layout / sections:** Search bar + optional gender dropdown + optional filter icon (only shown if admin-enabled); results list of profile cards (bookmark button, "Request meeting" button); Filters bottom sheet (age/marital-status/religion/employment/weight/height ranges + Clear/Apply).
**Notes for a redesigner:** Search errors and "no results" look identical (both show nothing / a generic message) — add a distinct error state. This screen's profile card and the Posts feed's card show nearly identical info with different visual treatments — consolidate into one shared card component.

### Marriage posts / profile feed (`modules/marriage/screens/marriage_posts_screen.dart`)
Infinite-scroll, photo-forward feed of active profiles — despite the "posts" name, every card is a real profile, not an article. **Notes for a redesigner:** Duplicates the Search screen's card/behavior (save + request meeting) with a different visual style — consolidate into one card component. The subtitle text ("Programs, stories, and updates...") doesn't match the actual content (profile cards) — reconsider the framing/naming since "Browse profiles" already covers nearly the same data.

### Subscription (`modules/marriage/screens/marriage_subscription_screen.dart`)
Package cards with "Subscribe" → payment-method bottom sheet (App Wallet or other methods) → result dialog (paid/pending). **Notes for a redesigner:** Failure snackbar shows the raw exception text — rewrite in friendly language. Otherwise clean and single-purpose.

### Marriage chats — thread list (`modules/marriage/screens/marriage_chats_screen.dart`)
Simple list of staff-mediated chat threads with status chips (Pending/Active/Declined). Clean, no notable issues.

### Marriage chat conversation (`modules/marriage/screens/marriage_chat_conversation_screen.dart`)
One-on-one staff-mediated chat about a meeting request. Persistent "Staff can view this chat" banner; conditional Accept/Decline banner (profile owner) or "waiting" notice (requester); composer only shown once active. **Notes for a redesigner:** Multiple stacked banners (privacy notice + accept/decline/waiting) can feel redundant when shown together — consider one adaptive status banner instead.

---

## 11. Chat, Support Bot, Notifications, Search, History, Legal Pages

### Messages (`modules/chat/screens/messages_screen.dart`)
**Purpose:** Inbox — donor↔campaign-owner threads, support, AI assistant shortcut, case-linked staff/volunteer/beneficiary chats.
**Layout / sections:** "Support Assistant" card (always pinned); "Contact support" card (always pinned); "Case chats" section (if any); "Chat requests" (Accept/Decline); "Conversations" list; "Waiting for accept" list; empty-state fallback.
**Notes for a redesigner:** The AI-assistant card and human-support card are both permanently pinned above everything in every state — two "get help" entry points always competing for the top of the screen; consider merging into one "Need help?" affordance with a sub-choice, or a persistent single button. Four different section labels (requests/conversations/waiting/case chats) in one flat list could become tabs instead.

### Chat conversation (`modules/chat/screens/chat_conversation_screen.dart`) & Case chat conversation (`modules/chat/screens/case_chat_conversation_screen.dart`)
Both are near-identical 1:1 chat UIs (same banner, same bubble styling, same composer) — the case-chat version just polls via a timer instead of a reactive controller. **Notes for a redesigner:** Merge into one screen/component with a mode flag — clear code/design duplication.

### Support / AI Assistant chat (`modules/bot/screens/bot_chat_screen.dart`)
**Purpose:** Role-aware AI assistant that can navigate the user to relevant screens; free-text restricted for guests.
**Layout / sections:** Welcome bubble; always-visible Suggestions panel; conversation bubbles (user/bot, with action buttons and structured "tool result" cards for wallet/donations/marriage/case/volunteer lookups); "Continue on WhatsApp" banner (appears after 3 messages); composer.
**Notes for a redesigner:** The suggestions panel stays visible for the whole conversation rather than collapsing after first use — can crowd a long chat. Between this bot, the human "Contact support" chat, and the mid-conversation WhatsApp offer, there are **three parallel "get help" channels** — consolidate into one entry point that branches.

### Global Search (`modules/search/screens/global_search_screen.dart`)
Single search box across campaigns/news/products/partners/city places, grouped by type with per-type "View more." **Notes for a redesigner:** Results are a flat list distinguished only by a small colored icon+label, not real section headers — add actual headers per type for clearer grouping.

### My History (`modules/history/screens/role_history_screen.dart`)
**Purpose:** Role-specific activity log (donations/missions/cases) with filters and a detail bottom sheet.
**Layout / sections:** Hero card with 4 role-specific metrics; Filters panel (Type/Status/Date chip groups); record list with detail bottom sheet.
**Notes for a redesigner:** Hero metrics + 3 filter groups + a record-count row all compete for top-of-screen space before any actual record appears — consider collapsing the hero into a compact stat strip or making filters expandable. The detail bottom sheet includes a raw key/value dump that may look unformatted/untranslated — design a proper structured layout per record kind.

### Terms & Conditions / Content pages (`modules/legal/screens/terms_screen.dart`, `content_page_screen.dart`)
Both are the same generic "static CMS content" template (title + body + retry-on-error), just pointed at different content slugs. **Notes for a redesigner:** Treat as one reusable template, not two separate designs; mainly needs typography treatment (heading hierarchy, readable margins).

---

## 12. Volunteer Hub

### Volunteer / "Volunteer With Us" (`modules/support/screens/support_section.dart`)
**Purpose:** Volunteer application, mission browsing/joining, and GPS+photo check-in/check-out — three flows in one screen.
**Layout / sections:** "Volunteer application" status tile; "My missions" section (joined); "Available Missions" section; Mission Detail screen (info chips, description, a status-dependent action button that changes label across 5+ states, Check-in/Check-out buttons with camera+GPS); Volunteer Application Form (name/phone/city, skill picker, availability picker, submit).
**Notes for a redesigner:** Conflates 3 distinct flows (apply / browse+join missions / check-in-out) in one scrolling page — split into clearer sections or tabs ("My Application," "My Missions," "Find Missions"). The join-mission button's label overloads 5+ different meanings (pending/approved/joined/completed/cancelled) — replace with a dedicated status badge instead of changing one button's text. Background status-change polling triggers transient snackbars that could be missed mid-task — consider a persistent/dismissible notification for important transitions like mission approval.

---

*Document generated from a direct code read of the Flutter app in `humanitarian/lib/` — every screen, button, and flag described above reflects the app's actual current behavior, not assumptions.*

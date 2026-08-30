# App small fixes — the owner's clarified points

Branch: feat/app-small-fixes. Three deployables in this repo; every task
below is in `humanitarian/` (the Flutter app) unless it says otherwise.

## Global Constraints

- Platform-adaptive: Cupertino on iOS, Material on Android, through the
  existing `shared/widgets/adaptive_dialog.dart` layer. Never `Platform.isIOS`
  inside a widget — use `Theme.of(context).platform`.
- Every user-facing string is localized in en + ar. Four locale maps exist
  (`_en`, `_soraniPublished`, `_badiniPublished`, `_ar`); Kurdish inherits
  English through the documented merge, so en + ar is the bar. Never add a
  raw literal to a widget — `translating_widget_literals_test.dart` fails the
  build for it.
- RTL is first-class: logical properties (start/end), never left/right.
- Spacing comes from the 4/8/12/16/24/32 scale. Colours come from
  `AppThemeConfig` tokens, never literals — `theme_contrast_guard_test.dart`
  and the WCAG suites measure 4.5:1 in BOTH themes.
- Tests ship in the same commit as the code. `flutter analyze` clean and the
  full `flutter test` suite green before a task is done. Run them; never
  claim "should work".
- Comment the why, not the what. Match the density of the file you are in —
  this codebase explains its decisions in the source.
- Touch only what the task requires. No drive-by refactors.

## Task 1: Reach the support form from Messages

The top bar's AI and support buttons are already removed (commit d33b2d7).
Messages already carries `_BotAssistantCard` (the assistant) and a
`chat_support` SectionTile (live chat with staff). What it does NOT carry is a
standing entry to `TechnicalSupportScreen` — the support REQUEST FORM with
ticket history. Today that screen only appears from Messages inside
`_SupportChatUnavailableNotice`, i.e. only when support chat is misconfigured.

Add a permanent SectionTile for it in `lib/modules/chat/screens/messages_screen.dart`,
directly beneath the existing `chat_support` tile, using the same SectionTile
shape and an existing icon (`Icons.support_agent_rounded` is already used by
the chat tile — pick a distinct one, e.g. `Icons.contact_support_outlined`).

Copy: reuse existing keys if they fit; otherwise add new en + ar entries. The
two tiles must read as different things: one reaches a human in a live chat,
the other files a tracked request.

Do not remove `_SupportChatUnavailableNotice` — it stays as the guidance for
the misconfigured case.

Test: extend or add a widget/source test proving Messages offers BOTH the chat
tile and the form tile.

## Task 2: One language for the country picker

In sign-up and login, tapping the country code opens a list where some
countries read in Arabic and some in English. Every name must follow the app's
own language (en / ar / ckb / kmr).

The picker is `CountryCodePicker` (package `country_code_picker`) in
`lib/modules/auth/screens/login.dart`. Investigate how it resolves names —
the package takes a `favorite`/`localize`/`showFlag` set of options and a
locale. Find why the list is mixed today before changing anything: it is
likely falling back to the device locale, or the package's own localization
lacks the app's locale codes (the app uses `ar_IQ`/`ar_TR` for Kurdish, which
no package will know).

Constraint: the dial-code chip beside the field must stay LTR. There is a
deliberate `Directionality` there — a phone number is a fixed left-to-right
digit group and the bidi algorithm mirrors it otherwise. Do not regress it.

If the package cannot serve Kurdish, the correct answer is to map the app's
locale to the nearest one the package supports and say so in a comment —
never to leave the list mixed.

Test: a widget test that opens the picker under `ar` and asserts no Latin
country name appears, and under `en` that none are Arabic.

## Task 3: Compact donation cards

The donation list items are too tall. The owner confirmed: keep the headline
and the amount/progress on the card; the description moves to the detail
screen.

Area: `lib/modules/donations/`. Find the card widget the list builds.

Keep: title, and the amount/progress figure a donor decides with.
Remove from the card: the body/description text.
The detail screen must still show everything — nothing may become unreachable.

Spacing from the scale; contrast still measured in both themes.

Test: a widget test that the card renders the title and the amount and does
NOT render the description, plus whatever the existing donation tests need
updating to match.

## Task 4: The blank overlay over Marketplace search

Reported: "when I tap on search and the keyboard opens, a blank box or overlay
covers everything on the screen."

Area: `lib/modules/marketplace/`.

Reproduce and diagnose FIRST — do not restyle blind. Likely candidates: a
suggestions/overlay panel sized to the full viewport, a `Stack` child painting
an opaque box, or a layout that collapses when `viewInsets.bottom` grows.
Identify the actual cause and say what it was in the commit message.

The results must stay visible and scrollable while typing, and the keyboard
must never cover the focused field (rule 5.6).

Test: a widget test that pumps the marketplace search with a simulated
keyboard inset and asserts the result list is still laid out and visible.

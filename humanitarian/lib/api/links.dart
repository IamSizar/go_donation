// API endpoints.
//
// Phase 6 cutover (2026-05-16): the backend was rewritten in Go and now lives
// on port 8080 with paths under /api/* (no /percentage/ prefix). This file is
// the single point of change — every other Dart file imports baseUrl/publicBaseUrl
// from here, so updating `baseUrl` below is what swaps the backend.
//
// Every run target — debug and release, simulator/emulator/real device —
// hits production. Nothing here depends on a local backend being up.
const String baseUrl = 'https://backend-production-59d2.up.railway.app/api/';

// Local dev (uncomment and swap the line above to test against your own
// backend instead of production; pick the host for your run target):
//   iOS Simulator: 'http://localhost:8081/api/'
//   Android emulator: 'http://10.0.2.2:8081/api/'
//   Real device on same Wi-Fi: 'http://<your-Mac-LAN-IP>:8081/api/'

/// Google OAuth Web/Server client ID (Phase 9 · B-09). Supplied at build time:
///   flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com
/// When empty, Google sign-in initializes without a server client ID (the
/// backend must then accept the platform client ID as an audience). The backend
/// separately validates the token against GOOGLE_OAUTH_CLIENT_IDS.
const String googleServerClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
);

/// Project root for uploaded/static files (sibling of `api/`, not inside it).
/// Must end with `/` so [Uri.resolve] appends paths like `images/...` correctly.
///
/// Go serves uploaded images at `/images/*` from the root of the same origin
/// as the API, so `publicBaseUrl` is the API host without the `/api/` segment.
String get publicBaseUrl {
  String root;
  if (baseUrl.endsWith('/api/')) {
    root = baseUrl.substring(0, baseUrl.length - 5);
  } else if (baseUrl.endsWith('api/')) {
    root = baseUrl.substring(0, baseUrl.length - 4);
  } else {
    root = baseUrl;
  }
  if (root.endsWith('/')) return root;
  return '$root/';
}

/// Phone + PASSWORD login. POST JSON: `phone` (or `number`) and `password`.
/// Returns `status`, `user_id`, `returning_user`, `has_role`, `role_id`,
/// `account`, `access_token`, `token_type`, `expires_at`, `expires_in`.
///
/// A16 — this endpoint no longer accepts a phone number on its own, and no
/// longer creates accounts. A number with no password on file is answered with
/// `401 {code: "otp_required"}`: phone-only sign-in and sign-up both go through
/// [otpRequestUrl] + [otpVerifyUrl], which verify a code before issuing a
/// token. (The companion `insertUserWithPhoneUrl` constant was deleted with the
/// silent session re-mint that used it — see api/auth_session.dart.)
const String loginUrl = '${baseUrl}auth/login/';

/// Phase 19 — OTP delivery (OTPIQ → WhatsApp first, SMS fallback).
///
/// `otpRequestUrl` — POST JSON: `{ "phone": "...", "mode": "real" | "demo" }`.
///   On success returns `{ status, mode, phone, expires_in, [sms_id], [demo_code] }`.
///   Demo mode is only allowed when the backend has OTP_DEMO_ENABLED=1, and the
///   server upgrades a "demo" request to real delivery once OTPIQ is configured.
///
/// `otpVerifyUrl` — POST JSON: `{ "phone": "...", "code": "123456" }`.
///
///   A16 — this NO LONGER RETURNS A SESSION. Under the owner's design a code
///   proves a number once, at account creation, and a password is what signs a
///   user in afterwards. So a correct code returns
///   `{ status: "password_setup_required", setup_ticket, expires_in,
///      min_password_length }` — the single-use permission to choose a first
///   password — and answers `409 {code: "password_required"}` for a number that
///   already HAS one, because a code must never stand in for a password.
const String otpRequestUrl = '${baseUrl}auth/otp/request/';
const String otpVerifyUrl = '${baseUrl}auth/otp/verify/';

/// A16 — finish sign-up (or rescue an account that has no password).
///
/// POST JSON: `{ "phone": "...", "setup_ticket": "...", "password": "..." }`
/// where `setup_ticket` came from [otpVerifyUrl]. Returns the SAME shape as
/// [loginUrl] (access_token + account + user_id + role_id + expires_at), so the
/// end of sign-up is a normal signed-in session.
///
/// It can only ever set a FIRST password: an account that already has one is
/// answered `409 {code: "password_already_set"}`. Refusals carry a translatable
/// `code` (`setup_ticket_invalid` / `setup_ticket_expired` /
/// `setup_ticket_exhausted` / `password_too_short` / `password_too_long`).
const String passwordSetUrl = '${baseUrl}auth/password/set';

/// Section 27.5 — POST (Bearer required) to revoke the current session token
/// server-side on logout, so it can never be reused. Best-effort: the client
/// still clears local state even if this call fails offline.
const String logoutUrl = '${baseUrl}auth/logout';

/// POST JSON: `user_id`, `role_id`. Returning users keep an existing role (`role_unchanged`).
const String chooseRoleUrl = '${baseUrl}choose_role/';

/// New-user registration approval flow (replaces the old choose-role screen).
///
/// `registrationSubmitUrl` — POST JSON: `{ full_name, date_of_birth (YYYY-MM-DD),
///   address, role_id }`. Bearer required. Returns `{ status, registration_status }`.
/// `registrationStatusUrl` — GET. Bearer required. Returns
///   `{ registration_status, reject_reason, role_id, has_role }`. Both are
///   reachable by not-yet-approved users (no approval gate).
const String registrationSubmitUrl = '${baseUrl}registration/submit';
const String registrationStatusUrl = '${baseUrl}registration/status';
// Grantor registration spec — optional personal/ID-card photo upload,
// multipart POST: [personal_photo], [id_photo]. Bearer required.
const String registrationPhotosUrl = '${baseUrl}registration/photos';

/// CSRF compat stub — the Go API doesn't use CSRF (Bearer-only), but this URL
/// returns a well-formed `{status, csrf_token, action, ttl}` so the existing
/// FeaturedCampaignsController works unchanged.
const String loginGetTokenUrl = '${baseUrl}auth/login/get_token.php';

/// Campaigns list: GET with `page`, `per_page`. The `csrf_token` query param
/// is harmlessly ignored by the Go endpoint.
const String featuredCampaignsUrl = '${baseUrl}campaigns/';
const String profileApiUrlSet = '${baseUrl}profile/set/';

/// GET `?user_id=` — returns `status`, `account` (`getUserAccountForClient`).
const String profileApiUrlGet = '${baseUrl}profile/get/';

/// Legacy alternate path the Flutter code falls back to. Go doesn't expose this
/// path; the primary `profileApiUrlGet` is the one that resolves.
const String accountGetUrlAlternate = '${baseUrl}get/';

/// POST: `campaigns_id`, `message`, `amount`, `payment_method` (form body).
/// Optional GET query: `user_id`.
const String insertDonationUsersUrl = '${baseUrl}donate/';

/// POST (preferred) or GET: `user_id`. Returns `success`, `summary`, `items`.
/// Go path doesn't use a .php suffix.
const String myDonationsHistoryUrl = '${baseUrl}donate/my_donations';

/// POST JSON: beneficiary project request.
/// Include `user_id` (int) when the client is logged in — from prefs key `id_user`.
const String submitBeneficiaryProjectUrl =
    '${baseUrl}beneficiary_project_requests/';

/// GET: admin-managed project categories for the submit-project dropdown (#17).
const String projectCategoriesUrl = '${baseUrl}project-categories';

/// GET: admin-managed in-kind donation categories (Donations Page spec,
/// "4. In-Kind Donations").
const String inkindCategoriesUrl = '${baseUrl}inkind-categories';

/// GET: donate-screen switches — whether the project list is shown and
/// whether the Comprehensive Grant option is offered. Both admin-controlled.
const String donationOptionsUrl = '${baseUrl}donation-options';

/// GET: admin-managed donation payment methods for the donate screen (#19).
const String paymentMethodsUrl = '${baseUrl}payment-methods';

/// GET: admin-managed donor-facing donation types — General / Zakat / Sadaqah
/// and anything staff add after them (M7, migration 103). The app used to keep
/// its own hardcoded copy of this list, so a type added from the dashboard was
/// accepted by the server and never offered to the donor.
const String donationTypesUrl = '${baseUrl}donation-types';

/// GET: admin-managed "Our Work" categories for the News & Activities filter (#22).
const String mediaCategoriesUrl = '${baseUrl}media-categories';

/// GET: admin-managed beneficiary-case categories for the Home Quick Filter
/// Capsules (Orphan Sponsorship, Widow Support, Food Baskets, etc).
const String caseCategoriesUrl = '${baseUrl}case-categories';

/// GET: admin-managed City Guide sectors for the directory filter chips (#29).
const String citySectorsUrl = '${baseUrl}city-sectors';

/// GET: admin-managed City Guide SUB-categories, the second half of the
/// spec's "Main and subcategory" (migration 101, 27 rows in four languages).
/// Public, like `citySectorsUrl`. K16 — the route and the data have existed
/// since migration 101; the app had never asked for either.
const String cityCategoriesUrl = '${baseUrl}city-categories';

/// POST: a user suggests a new City Guide place → admin approval queue (#30).
const String communitySubmitUrl = '${baseUrl}community/submit';

/// GET/POST: the current user's notification on/off switch (#31).
const String notificationSettingUrl = '${baseUrl}profile/notifications';

/// GET/POST: the switch above, refined — one per CATEGORY of alert (K7,
/// migration 108). GET answers `items[]` with this user's state already
/// applied; POST takes `{"disabled": [...]}` and replaces the whole set.
///
/// Category rather than raw notification type on purpose: there are 81 types
/// and the server derives a category from every one of them, so this is the
/// unit the Alerts tab's own filter chips already group by.
const String notificationCategoriesUrl =
    '${baseUrl}profile/notification-categories';

/// GET/POST: the current user's hidden profile fields (#32).
const String fieldPrivacyUrl = '${baseUrl}profile/privacy';

/// GET: the admin-managed catalogue of fields a user may show/hide in Privacy
/// Settings. Data-driven so new options need no app change (see migration
/// 083).
const String privacyOptionsUrl = '${baseUrl}profile/privacy-options';
// Privacy Settings spec — display-name choice (real name vs. alias) and
// optional social media links.
const String privacyExtrasUrl = '${baseUrl}profile/privacy-extras';

/// GET: app-wide global search across content tables (#33).
const String globalSearchUrl = '${baseUrl}search';

/// GET: support WhatsApp handoff number (#36); empty when disabled.
const String supportWhatsappUrl = '${baseUrl}support/whatsapp';

/// POST: create a marriage/engagement profile (#42). Eligible role only.
const String marriageSubmitUrl = '${baseUrl}marriage';

/// GET: the current user's own submitted marriage profile(s) + status
/// (Note #18). Unlike marriageProfilesUrl (public browse), this is never
/// status-filtered — a user needs to see their own profile even when it's
/// rejected/closed/paused.
const String myMarriageProfileUrl = '${baseUrl}marriage/mine';

/// GET: admin-configured required registration fields (#43).
const String fieldRulesUrl = '${baseUrl}registration/field-rules';

/// POST: open a direct chat with support/tech staff (#45).
const String chatSupportUrl = '${baseUrl}chats/support';

/// Note #40 — real (username + password) guest accounts.
/// POST {username, password}: create a new guest account.
const String guestRegisterUrl = '${baseUrl}auth/guest/register';

/// POST {username, password}: sign back into an existing guest account.
const String guestLoginUrl = '${baseUrl}auth/guest/login';

/// POST (Bearer, guest only) {phone, code}: consume the phone's OTP (sent via
/// the existing [otpRequestUrl]) and attach it to the current guest account,
/// converting it to a full account.
const String guestUpgradeVerifyUrl = '${baseUrl}auth/guest/upgrade/verify';

/// #49 — public link shared when sharing the app or a post (store / website).
/// Set this to the real download/website URL; empty = share text only (no link).
const String appShareUrl = '';

/// GET: the current user's digital aid-delivery receipts (#50).
const String aidReceiptsUrl = '${baseUrl}aid-receipts';

/// GET: admin-managed marketplace product categories (#28).
const String marketplaceCategoriesUrl = '${baseUrl}marketplace/categories';

/// #27 — rate a partner (authed).
String partnerRateUrl(int partnerId) => '${baseUrl}partners/$partnerId/rate';

/// GET: activities carried out in cooperation with a partner — the Partner
/// Page's history section ("Eleventh: Partners Section").
String partnerActivitiesUrl(int partnerId) =>
    '${baseUrl}partners/$partnerId/activities';

/// #24 — media post engagement endpoints (authed).
String mediaLikeUrl(int postId) => '${baseUrl}media/$postId/like';

/// POST: toggle "save for later" on a post. Returns {saved}.
String mediaSaveUrl(int postId) => '${baseUrl}media/$postId/save';
String mediaCommentsUrl(int postId) => '${baseUrl}media/$postId/comments';
String mediaShareUrl(int postId) => '${baseUrl}media/$postId/share';

const String communityDirectoryUrl = '${baseUrl}community/';
const String beneficiaryCampaignDonationsUrl =
    '${baseUrl}beneficiary/campaign-donations';

/// Donor ↔ campaign-owner chat (Phase 28).
const String chatsUrl = '${baseUrl}chats';
const String chatRequestUrl = '${baseUrl}chats/request';
String chatAcceptUrl(int threadId) => '${baseUrl}chats/$threadId/accept';
String chatDeclineUrl(int threadId) => '${baseUrl}chats/$threadId/decline';
String chatMessagesUrl(int threadId) => '${baseUrl}chats/$threadId/messages';

/// AI Support Assistant (Phase 29).
const String assistantChatUrl = '${baseUrl}assistant/chat';

/// Activity event log — the app POSTs analytics/audit events here (the Postgres
/// replacement for the old Firestore `events` collection).
const String eventsLogUrl = '${baseUrl}events';

const String marketplaceProductsUrl = '${baseUrl}marketplace/';
const String volunteerMissionsUrl = '${baseUrl}volunteer_hub/';
const String partnersUrl = '${baseUrl}partners/';
const String mediaPostsUrl = '${baseUrl}media/';
const String appNotificationsUrl = '${baseUrl}notifications/';
const String dashboardSummaryUrl = '${baseUrl}dashboard/';
const String roleHistoryUrl = '${baseUrl}history/';
const String beneficiaryCasesUrl = '${baseUrl}beneficiary_cases/';
const String sponsorshipsUrl = '${baseUrl}sponsorships/';

/// GET: the caller's sponsorship schedule occurrences — one row per due date
/// ("Eighth: Sponsorship Schedule and Calendar"). Optional ?status= filter:
/// upcoming | due | overdue | paid | skipped.
const String sponsorshipScheduleUrl = '${baseUrl}sponsorships/schedule';
const String inKindDonationsUrl = '${baseUrl}in_kind_donations/';
const String marriageProfilesUrl = '${baseUrl}marriage/';
// Note #35 — staff-mediated marriage chat.
const String marriageChatsUrl = '${baseUrl}marriage/chats';
// Note #36 — Staff↔Volunteer↔Beneficiary chat.
const String caseChatsUrl = '${baseUrl}case-chats';
// Note #37 — generic authed photo upload + volunteer self check-in/out.
const String uploadsUrl = '${baseUrl}uploads';
// Note #42 — test-phase internal app wallet (IQD).
const String walletUrl = '${baseUrl}wallet';
const String walletTransactionsUrl = '${baseUrl}wallet/transactions';
// Client note — "Task Verification".
const String tasksUrl = '${baseUrl}tasks';
const String volunteerMissionSignupsUrl = '${baseUrl}volunteer_mission_signups';
const String supportTicketsUrl = '${baseUrl}support/';
const String reportsUrl = '${baseUrl}reports/';

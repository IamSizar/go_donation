// API endpoints.
//
// Phase 6 cutover (2026-05-16): the backend was rewritten in Go and now lives
// on port 8080 with paths under /api/* (no /percentage/ prefix). This file is
// the single point of change — every other Dart file imports baseUrl/publicBaseUrl
// from here, so updating `baseUrl` below is what swaps the backend.
//
// Pick the right host for your run target:
//   - LAN device (real phone, same Wi-Fi): your Mac's LAN IP, e.g. 192.168.1.12
//   - iOS simulator / Flutter web on this Mac: localhost
//   - Android emulator: 10.0.2.2  (the magic loopback Android emulator uses)
// Production (Railway). For local dev, swap to 'http://localhost:8080/api/'
// (iOS Simulator shares the Mac's localhost; Android emulator uses 10.0.2.2).
const String baseUrl = 'https://backend-production-59d2.up.railway.app/api/';

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

/// Phone-only login. POST JSON: `phone` or `number`.
/// Returns `status`, `user_id`, `returning_user`, `has_role`, `role_id`, `account`,
/// `access_token`, `token_type`, `expires_at`, `expires_in`.
const String loginUrl = '${baseUrl}auth/login/';

/// After OTP is verified, POST JSON: `phone` or `number` only (`insertUserWithPhone`).
/// Same response shape as `loginUrl` — including the Bearer token in `access_token`.
const String insertUserWithPhoneUrl = '${baseUrl}auth/login/';

/// Phase 19 — OTP-based login (OTPIQ → WhatsApp first, SMS fallback).
///
/// `otpRequestUrl` — POST JSON: `{ "phone": "...", "mode": "real" | "demo" }`.
///   On success returns `{ status, mode, phone, expires_in, [sms_id], [demo_code] }`.
///   Demo mode is only allowed when the backend has OTP_DEMO_ENABLED=1.
///
/// `otpVerifyUrl` — POST JSON: `{ "phone": "...", "code": "123456" }`.
///   On success returns the SAME shape as `loginUrl` (access_token + account +
///   user_id + role_id + expires_at), so calling code can swap in transparently.
const String otpRequestUrl = '${baseUrl}auth/otp/request/';
const String otpVerifyUrl  = '${baseUrl}auth/otp/verify/';

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

/// GET: admin-managed donation payment methods for the donate screen (#19).
const String paymentMethodsUrl = '${baseUrl}payment-methods';

/// GET: admin-managed "Our Work" categories for the News & Activities filter (#22).
const String mediaCategoriesUrl = '${baseUrl}media-categories';

/// GET: admin-managed City Guide sectors for the directory filter chips (#29).
const String citySectorsUrl = '${baseUrl}city-sectors';

/// POST: a user suggests a new City Guide place → admin approval queue (#30).
const String communitySubmitUrl = '${baseUrl}community/submit';

/// GET/POST: the current user's notification on/off switch (#31).
const String notificationSettingUrl = '${baseUrl}profile/notifications';

/// GET/POST: the current user's hidden profile fields (#32).
const String fieldPrivacyUrl = '${baseUrl}profile/privacy';

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

/// #49 — public link shared when sharing the app or a post (store / website).
/// Set this to the real download/website URL; empty = share text only (no link).
const String appShareUrl = '';

/// GET: the current user's digital aid-delivery receipts (#50).
const String aidReceiptsUrl = '${baseUrl}aid-receipts';

/// GET: admin-managed marketplace product categories (#28).
const String marketplaceCategoriesUrl = '${baseUrl}marketplace/categories';

/// #27 — rate a partner (authed).
String partnerRateUrl(int partnerId) => '${baseUrl}partners/$partnerId/rate';

/// #24 — media post engagement endpoints (authed).
String mediaLikeUrl(int postId) => '${baseUrl}media/$postId/like';
String mediaCommentsUrl(int postId) => '${baseUrl}media/$postId/comments';
String mediaShareUrl(int postId) => '${baseUrl}media/$postId/share';

const String communityDirectoryUrl = '${baseUrl}community/';
const String beneficiaryCampaignDonationsUrl = '${baseUrl}beneficiary/campaign-donations';

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
const String inKindDonationsUrl = '${baseUrl}in_kind_donations/';
const String marriageProfilesUrl = '${baseUrl}marriage/';
// Note #35 — staff-mediated marriage chat.
const String marriageChatsUrl = '${baseUrl}marriage/chats';
// Note #36 — Staff↔Volunteer↔Beneficiary chat.
const String caseChatsUrl = '${baseUrl}case-chats';
// Note #37 — generic authed photo upload + volunteer self check-in/out.
const String uploadsUrl = '${baseUrl}uploads';
const String volunteerMissionSignupsUrl = '${baseUrl}volunteer_mission_signups';
const String supportTicketsUrl = '${baseUrl}support/';
const String reportsUrl = '${baseUrl}reports/';

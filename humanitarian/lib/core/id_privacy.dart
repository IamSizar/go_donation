/// #54 — ID-code privacy. Masks reference/ID codes shown in the UI so a full
/// code isn't exposed (screenshots, shoulder-surfing, other users' codes).
/// Keeps a short recognizable prefix + suffix and masks the unique middle.
String maskId(String? code, {int keepStart = 4, int keepEnd = 2}) {
  final s = (code ?? '').trim();
  if (s.length <= keepStart + keepEnd + 1) return s; // too short to mask usefully
  return '${s.substring(0, keepStart)}••••${s.substring(s.length - keepEnd)}';
}

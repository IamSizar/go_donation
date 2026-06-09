import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

/// SharedPreferences key for the rotating campaigns CSRF (action `campaigns`).
const String kCampaignsCsrfPrefsKey = 'csrf_token_campaigns';

/// Single [Dio] + [CookieJar] for `get_token.php?action=campaigns` and the campaigns list.
/// PHP CSRF is session-bound; both calls must share cookies.
class CampaignsApiClient {
  CampaignsApiClient._();

  static final CookieJar cookieJar = CookieJar();

  static final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: const {'Accept': 'application/json'},
      validateStatus: (code) => code != null && code < 600,
    ),
  )..interceptors.add(CookieManager(cookieJar));
}

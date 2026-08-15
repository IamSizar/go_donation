import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:get/get.dart';

class PartnersController extends GetxController {
  final partners = <Map<String, dynamic>>[].obs;
  final isLoading = false.obs;
  final errorMessage = RxnString();

  /// K24 — whether the organization currently publishes partner ratings.
  ///
  /// The client asked for the 1–5 star rating "with an option to hide it", and
  /// staff already have that switch in the dashboard. When it is off the
  /// server blanks every score before sending the rows, so the app has to stop
  /// offering the picker too: otherwise the user rates a partner, is told
  /// "Your rating was saved", and watches the stars empty again on the next
  /// refresh.
  ///
  /// Defaults to true so a failed or older response shows the feature rather
  /// than hiding it — the same default the server uses for an unset setting.
  /// It is deliberately NOT reset on failure: [fetchPartners] leaves the last
  /// known policy in place, because guessing "visible" after a dropped request
  /// would flash a picker that the previous, successful load had hidden.
  final ratingsVisible = true.obs;

  /// J8 — the in-list search term, sent to the server as `?q=`.
  ///
  /// It is NOT a filter over [partners]. `GET /api/partners` caps the list at
  /// 50 rows, so filtering what is loaded would answer "no such partner" about
  /// a register the app has never seen all of. The server matches name,
  /// name_ar and partner_type in SQL, so the answer covers every partner.
  final searchQuery = ''.obs;

  /// Whether a query is narrowing the list right now.
  ///
  /// The screen uses this to choose its empty copy: "no partners are listed
  /// yet" is a claim about the organization's register, and under a search the
  /// only true statement is "nothing matched".
  bool get hasActiveSearch => searchQuery.value.trim().isNotEmpty;

  int get _uid =>
      int.tryParse(sharedPreferences.getString('id_user') ?? '') ?? 0;

  /// Applies [query] and reloads from the server. A no-op when the term has
  /// not actually changed, so a debounce firing twice costs one request.
  Future<void> setSearchQuery(String query) async {
    final next = query.trim();
    if (next == searchQuery.value) return;
    searchQuery.value = next;
    await fetchPartners();
  }

  @override
  void onInit() {
    super.onInit();
    fetchPartners();
  }

  Future<void> fetchPartners() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final res = await const ModuleApi().partnersWithRatingPolicy(
        userId: _uid,
        q: searchQuery.value,
      );
      partners.assignAll(res.items);
      ratingsVisible.value = res.ratingsVisible;
    } catch (_) {
      partners.clear();
      errorMessage.value = 'Unable to load partners.'.tr;
    } finally {
      isLoading.value = false;
    }
  }

  /// #27 — submit a rating; reconciles the card with the server aggregate.
  ///
  /// Refuses outright while [ratingsVisible] is false (K24). The UI no longer
  /// offers the picker in that state, so this guard is for the method itself:
  /// it is public, and `POST /api/partners/:id/rate` has no visibility check of
  /// its own, so any future caller could otherwise write a score into a column
  /// the public API will strip on the very next read.
  Future<void> submitRating(Map<String, dynamic> partner, int stars) async {
    if (!ratingsVisible.value) return;
    final id = int.tryParse('${partner['id']}') ?? 0;
    if (id == 0) return;
    try {
      final res = await const ModuleApi().ratePartner(id, stars);
      partner['my_rating'] = (res['my_rating'] as num?)?.toInt() ?? stars;
      partner['avg_rating'] = (res['avg_rating'] as num?)?.toDouble();
      partner['rating_count'] = (res['rating_count'] as num?)?.toInt() ?? 0;
      partners.refresh();
      Get.snackbar('Thanks'.tr, 'Your rating was saved.'.tr);
    } catch (_) {
      Get.snackbar('Error'.tr, 'Could not save your rating.'.tr);
    }
  }
}

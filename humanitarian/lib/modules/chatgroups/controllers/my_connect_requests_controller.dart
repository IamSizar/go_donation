// MyConnectRequestsController — owns the signed-in member's own history of
// "ask staff to connect me" requests (OPOS #25284 Phase 5), shown on the
// My Connect Requests screen.
//
// No polling: this is a pull-to-refresh history, not a live conversation. An
// approved request also shows up as a new group in the Messages tab, which
// does poll.
import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/localization/failure_message.dart';
import 'package:get/get.dart';

import '../models/chat_group_models.dart';

/// Loads and holds the member's connect requests — pending, approved and
/// declined — in the order the server returns them.
class MyConnectRequestsController extends GetxController {
  /// [api] is injectable so tests can answer without a network; production
  /// code always uses the default.
  MyConnectRequestsController({ModuleApi api = const ModuleApi()})
    : _api = api;

  final ModuleApi _api;

  /// The member's requests in server order.
  final requests = <MyConnectRequest>[].obs;

  /// True while a load is in flight.
  final isLoading = false.obs;

  /// A localized "what failed, then what to do next" sentence, or null.
  final errorMessage = RxnString();

  @override
  void onInit() {
    super.onInit();
    fetchRequests();
  }

  /// Loads the requests. Returns normally on failure — the error is exposed
  /// through [errorMessage] — so it can be handed straight to a
  /// RefreshIndicator or a Retry button.
  Future<void> fetchRequests() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final rows = await _api.myConnectRequests();
      requests.assignAll(rows.map(MyConnectRequest.fromMap));
    } catch (e) {
      debugPrint('[chat-groups] loading connect requests failed: $e');
      errorMessage.value = failureMessage(
        e,
        'error_connect_requests_load_failed',
      );
    } finally {
      isLoading.value = false;
    }
  }
}

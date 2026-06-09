import 'package:get/get.dart';

import '../controllers/donations_controller.dart';

class DonationsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<DonationsController>(DonationsController.new);
  }
}

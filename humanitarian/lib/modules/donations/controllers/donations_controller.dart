import 'package:get/get.dart';

import '../models/donation_model.dart';

class DonationsController extends GetxController {
  final donations = <DonationModel>[
    const DonationModel(id: '1', title: 'Food Support', amount: 25),
    const DonationModel(id: '2', title: 'School Supplies', amount: 40),
  ].obs;
}

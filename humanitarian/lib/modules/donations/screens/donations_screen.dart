import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/donations_controller.dart';
import '../widgets/donation_card.dart';

class DonationsScreen extends GetView<DonationsController> {
  const DonationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contributions')),
      body: Obx(
        () => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: controller.donations.length,
          itemBuilder: (context, index) {
            return DonationCard(donation: controller.donations[index]);
          },
        ),
      ),
    );
  }
}

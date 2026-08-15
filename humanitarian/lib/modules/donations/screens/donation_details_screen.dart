import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/widgets/app_main_menu_button.dart';
import 'package:get/get.dart';

class DonationDetailsScreen extends StatelessWidget {
  const DonationDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Contribution Details'.tr),
        actions: const [AppMainMenuButton()],
      ),
      body: Center(child: Text('Contribution details screen'.tr)),
    );
  }
}

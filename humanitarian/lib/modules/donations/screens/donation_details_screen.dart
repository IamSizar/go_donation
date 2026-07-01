import 'package:flutter/material.dart';

class DonationDetailsScreen extends StatelessWidget {
  const DonationDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contribution Details')),
      body: const Center(
        child: Text('Contribution details screen'),
      ),
    );
  }
}

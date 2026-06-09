import 'package:flutter/material.dart';

class DonationDetailsScreen extends StatelessWidget {
  const DonationDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Donation Details')),
      body: const Center(
        child: Text('Donation details screen'),
      ),
    );
  }
}

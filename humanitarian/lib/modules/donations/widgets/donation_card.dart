import 'package:flutter/material.dart';

import '../models/donation_model.dart';

class DonationCard extends StatelessWidget {
  const DonationCard({
    super.key,
    required this.donation,
  });

  final DonationModel donation;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(donation.title),
        subtitle: Text('${donation.amount.toStringAsFixed(2)} IQD'),
      ),
    );
  }
}

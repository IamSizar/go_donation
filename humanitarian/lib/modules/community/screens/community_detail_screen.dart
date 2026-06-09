import 'package:flutter/material.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

class CommunityDetailScreen extends StatelessWidget {
  const CommunityDetailScreen({super.key, required this.entry});

  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final name = localizedContentFromMap(entry, 'name', fallback: 'Service');
    final description = localizedContentFromMap(entry, 'description');

    return GradientScreen(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: PageTopBar(title: name),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                children: [
                  GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.tr,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _DetailLine(
                          icon: Icons.category_rounded,
                          label: 'Category',
                          value: (entry['category'] ?? '').toString(),
                        ),
                        _DetailLine(
                          icon: Icons.location_city_rounded,
                          label: 'City',
                          value: (entry['city'] ?? '').toString(),
                        ),
                        _DetailLine(
                          icon: Icons.place_rounded,
                          label: 'Address',
                          value: (entry['address'] ?? '').toString(),
                        ),
                        _DetailLine(
                          icon: Icons.phone_rounded,
                          label: 'Phone',
                          value: (entry['phone'] ?? '').toString(),
                        ),
                        _DetailLine(
                          icon: Icons.email_rounded,
                          label: 'Email',
                          value: (entry['email'] ?? '').toString(),
                        ),
                        _DetailLine(
                          icon: Icons.public_rounded,
                          label: 'Website',
                          value: (entry['website'] ?? '').toString(),
                        ),
                        _DetailLine(
                          icon: Icons.my_location_rounded,
                          label: 'Location',
                          value: _locationText(entry),
                        ),
                      ],
                    ),
                  ),
                  if (description.trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    GlassPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Description'.tr,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(description.tr),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.tr,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(value.tr),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _locationText(Map<String, dynamic> entry) {
  final latitude = (entry['latitude'] ?? '').toString();
  final longitude = (entry['longitude'] ?? '').toString();
  if (latitude.trim().isEmpty || longitude.trim().isEmpty) return '';
  return '$latitude, $longitude';
}

import 'package:flutter/material.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

double? _parseCoord(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

class CommunityDetailScreen extends StatelessWidget {
  const CommunityDetailScreen({super.key, required this.entry});

  final Map<String, dynamic> entry;

  static Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final name = localizedContentFromMap(entry, 'name', fallback: 'Service');
    final description = localizedContentFromMap(entry, 'description');
    final phone = (entry['phone'] ?? '').toString().trim();
    final email = (entry['email'] ?? '').toString().trim();
    final website = (entry['website'] ?? '').toString().trim();
    final lat = _parseCoord(entry['latitude']);
    final lng = _parseCoord(entry['longitude']);

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
                  // ── Details card ──────────────────────────────────────────
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
                        // Tappable phone
                        if (phone.isNotEmpty)
                          _TappableDetailLine(
                            icon: Icons.phone_rounded,
                            label: 'Phone',
                            value: phone,
                            trailingIcon: Icons.call_rounded,
                            trailingColor: const Color(0xFF4CAF50),
                            onTap: () => _launch('tel:$phone'),
                          )
                        else
                          const _DetailLine(
                            icon: Icons.phone_rounded,
                            label: 'Phone',
                            value: '',
                          ),
                        // Email
                        if (email.isNotEmpty)
                          _TappableDetailLine(
                            icon: Icons.email_rounded,
                            label: 'Email',
                            value: email,
                            trailingIcon: Icons.mail_outline_rounded,
                            trailingColor: const Color(0xFFFF9800),
                            onTap: () => _launch('mailto:$email'),
                          )
                        else
                          const _DetailLine(
                            icon: Icons.email_rounded,
                            label: 'Email',
                            value: '',
                          ),
                        // Tappable website
                        if (website.isNotEmpty)
                          _TappableDetailLine(
                            icon: Icons.language_rounded,
                            label: 'Website',
                            value: website,
                            trailingIcon: Icons.open_in_new_rounded,
                            trailingColor: const Color(0xFF2196F3),
                            onTap: () => _launch(
                              website.startsWith('http')
                                  ? website
                                  : 'https://$website',
                            ),
                          )
                        else
                          const _DetailLine(
                            icon: Icons.language_rounded,
                            label: 'Website',
                            value: '',
                          ),
                        if (lat != null && lng != null)
                          _DetailLine(
                            icon: Icons.my_location_rounded,
                            label: 'Coordinates',
                            value:
                                '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                          ),
                      ],
                    ),
                  ),

                  // ── Description card ─────────────────────────────────────
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

                  // ── Mini-map (only when coordinates exist) ───────────────
                  if (lat != null && lng != null) ...[
                    const SizedBox(height: 14),
                    GlassPanel(
                      padding: EdgeInsets.zero,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: SizedBox(
                          height: 190,
                          child: Stack(
                            children: [
                              FlutterMap(
                                options: MapOptions(
                                  initialCenter: LatLng(lat, lng),
                                  initialZoom: 15.0,
                                  interactionOptions:
                                      const InteractionOptions(
                                    flags: InteractiveFlag.none,
                                  ),
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                                    subdomains: const ['a', 'b', 'c', 'd'],
                                    userAgentPackageName:
                                        'com.humanitarian.app',
                                  ),
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: LatLng(lat, lng),
                                        width: 48,
                                        height: 48,
                                        child: const DecoratedBox(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: LinearGradient(
                                              colors: [
                                                Color(0xFF667EEA),
                                                Color(0xFF64D8CB),
                                              ],
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Color(0x88667EEA),
                                                blurRadius: 12,
                                                spreadRadius: 2,
                                              ),
                                            ],
                                          ),
                                          child: Icon(
                                            Icons.place_rounded,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              // "Open in Maps" button
                              Positioned(
                                bottom: 10,
                                right: 10,
                                child: GestureDetector(
                                  onTap: () => _launch(
                                    'https://maps.google.com/?q=$lat,$lng',
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF667EEA),
                                          Color(0xFF64D8CB),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black38,
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.map_rounded,
                                          color: Colors.white,
                                          size: 13,
                                        ),
                                        SizedBox(width: 5),
                                        Text(
                                          'Open in Maps',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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

// ── Detail line widgets ───────────────────────────────────────────────────────

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

/// A detail row that's tappable — shows a coloured trailing icon action badge.
class _TappableDetailLine extends StatelessWidget {
  const _TappableDetailLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.trailingIcon,
    required this.trailingColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final IconData trailingIcon;
  final Color trailingColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GestureDetector(
        onTap: onTap,
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
                  Text(
                    value,
                    style: TextStyle(
                      color: trailingColor,
                      decoration: TextDecoration.underline,
                      decorationColor: trailingColor,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: trailingColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(trailingIcon, size: 14, color: trailingColor),
            ),
          ],
        ),
      ),
    );
  }
}

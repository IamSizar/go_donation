import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/community/controllers/community_controller.dart';
import 'package:flutter_application_1/modules/community/screens/add_activity_screen.dart';
import 'package:flutter_application_1/modules/community/screens/community_detail_screen.dart';
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

double _fitZoom(List<({LatLng pos, Map<String, dynamic> entry})> pins) {
  if (pins.length < 2) return 13.0;
  final lats = pins.map((p) => p.pos.latitude);
  final lngs = pins.map((p) => p.pos.longitude);
  final latSpan =
      lats.reduce((a, b) => a > b ? a : b) -
      lats.reduce((a, b) => a < b ? a : b);
  final lngSpan =
      lngs.reduce((a, b) => a > b ? a : b) -
      lngs.reduce((a, b) => a < b ? a : b);
  final maxSpan = latSpan > lngSpan ? latSpan : lngSpan;
  if (maxSpan < 0.02) return 14.0;
  if (maxSpan < 0.05) return 13.0;
  if (maxSpan < 0.15) return 12.0;
  if (maxSpan < 0.4) return 11.0;
  if (maxSpan < 1.0) return 9.5;
  if (maxSpan < 3.0) return 8.0;
  if (maxSpan < 8.0) return 7.0;
  return 6.0;
}

// ── Accent colours ────────────────────────────────────────────────────────────
const _kPinA = Color(0xFF45B8D1); // soft cyan — calmer, easier on the eyes
const _kPinB = Color(0xFF3C7CB0); // muted blue
const _kCardA = Color(0xFF0D1B2A); // header top
const _kCardB = Color(0xFF1A3349); // header bottom

class CommunityServicesSection extends StatelessWidget {
  const CommunityServicesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionScaffold(
      title: 'Community Services',
      subtitle:
          'Browse local support programs by category, region, and urgency.',
      child: _CommunityServicesList(),
    );
  }
}

// ── Services list + City Guide ────────────────────────────────────────────────

class _CommunityServicesList extends StatelessWidget {
  const _CommunityServicesList();

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<CommunityController>()
        ? Get.find<CommunityController>()
        : Get.put(CommunityController());

    return Obx(() {
      final items = controller.entries;
      final error = controller.errorMessage.value;
      final loading = controller.isLoading.value;

      return RefreshIndicator(
        onRefresh: controller.fetchEntries,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          children: [
            if (loading) const Center(child: CircularProgressIndicator()),
            if (error != null)
              SectionTile(
                icon: Icons.local_library_rounded,
                title: 'Services Directory',
                subtitle: error,
                color: Colors.indigo,
                onTap: controller.fetchEntries,
              ),
            if (error == null && !loading && items.isEmpty)
              const SectionTile(
                icon: Icons.local_library_rounded,
                title: 'Services Directory',
                subtitle: 'No approved city services are available yet.',
                color: Colors.indigo,
              ),
            for (final item in items) ...[
              _CityServiceCard(
                entry: item,
                onTap: () => Get.to(() => CommunityDetailScreen(entry: item)),
              ),
              const SizedBox(height: 12),
            ],
            // The City Guide map now lives on its own screen, opened from Home.
          ],
        ),
      );
    });
  }
}

// ── City Guide header card ────────────────────────────────────────────────────

class _CityGuideHeader extends StatelessWidget {
  const _CityGuideHeader({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [_kCardA, _kCardB],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _kPinA.withValues(alpha: 0.22), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: _kPinA.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon box
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kPinA, _kPinB],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _kPinA.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.explore_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          // Text
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'City Guide',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Mosul · Iraq',
                  style: TextStyle(
                    color: Color(0xFF8ECAE6),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          // Count badge
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_kPinA, _kPinB],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: _kPinA.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.place_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── City Guide screen (opened from Home) ──────────────────────────────────────

/// Full-screen City Guide: a redesigned map of local services with a place
/// strip below it. Moved here out of the Community list and opened from Home.
class CityGuideScreen extends StatefulWidget {
  const CityGuideScreen({super.key});

  @override
  State<CityGuideScreen> createState() => _CityGuideScreenState();
}

class _CityGuideScreenState extends State<CityGuideScreen> {
  late final CommunityController _controller;

  @override
  void initState() {
    super.initState();
    _controller = Get.isRegistered<CommunityController>()
        ? Get.find<CommunityController>()
        : Get.put(CommunityController());
    if (_controller.entries.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _controller.fetchEntries(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'City Guide',
      subtitle: 'Find local services on the map · Mosul, Iraq',
      child: Obx(() {
        final items = _controller.filteredEntries;
        final sectors = _controller.sectors.toList();
        final selected = _controller.selectedSector.value;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              _CityGuideHeader(count: items.length),
              // #30 — let users suggest a new place (goes to the admin queue).
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Get.to(() => const AddActivityScreen()),
                  icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                  label: Text('add_activity'.tr),
                  // Filled soft-cyan button: white-on-white was invisible in
                  // light mode; a solid accent reads clearly in both themes.
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPinB,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              // #29 — sector filter chips (admin-managed, 4-language).
              if (sectors.isNotEmpty) ...[
                const SizedBox(height: 12),
                _SectorFilterRow(
                  sectors: sectors,
                  selected: selected,
                  onSelect: _controller.selectSector,
                ),
              ],
              const SizedBox(height: 14),
              Expanded(child: _CityMap(entries: items)),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 14),
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => _PlaceCard(entry: items[i]),
                  ),
                ),
              ],
            ],
          ),
        );
      }),
    );
  }
}

void _showEntrySheet(BuildContext ctx, Map<String, dynamic> entry) {
  showModalBottomSheet(
    context: ctx,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _EntrySheet(entry: entry),
  );
}

// #29 — resolve a sector slug to its localized display name using the fetched
// sector list. Falls back to the slug if the sector is unknown.
String _sectorLabel(String slug, List<Map<String, dynamic>> sectors) {
  for (final s in sectors) {
    if ((s['slug'] ?? '').toString() == slug) {
      return localizedContentFromValues(
        base: (s['name_en'] ?? '').toString(),
        arabic: (s['name_ar'] ?? '').toString(),
        sorani: (s['name_ckb'] ?? '').toString(),
        badini: (s['name_kmr'] ?? '').toString(),
        fallback: slug,
      );
    }
  }
  return slug;
}

List<String> _entrySectors(Map<String, dynamic> entry) {
  final raw = entry['sectors'];
  if (raw is List) {
    return raw.map((s) => s.toString()).where((s) => s.isNotEmpty).toList();
  }
  return const [];
}

// #29 — horizontal "All + one-per-sector" filter chip row above the map.
class _SectorFilterRow extends StatelessWidget {
  const _SectorFilterRow({
    required this.sectors,
    required this.selected,
    required this.onSelect,
  });
  final List<Map<String, dynamic>> sectors;
  final String? selected;
  final void Function(String?) onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _SectorChip(
            label: 'city_all'.tr,
            active: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final s in sectors) ...[
            const SizedBox(width: 8),
            _SectorChip(
              label: _sectorLabel((s['slug'] ?? '').toString(), sectors),
              active: selected == (s['slug'] ?? '').toString(),
              onTap: () => onSelect((s['slug'] ?? '').toString()),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectorChip extends StatelessWidget {
  const _SectorChip({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(colors: [_kPinA, _kPinB])
              : null,
          color: active ? null : Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.18),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFF8ECAE6),
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// #29 — full-screen swipeable gallery viewer for a place's photos.
class _GalleryViewer extends StatelessWidget {
  const _GalleryViewer({required this.images, this.initialIndex = 0});
  final List<String> images;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: images.length,
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(
            child: Image.network(
              images[i],
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_rounded,
                color: Colors.white30,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Redesigned map ────────────────────────────────────────────────────────────

class _CityMap extends StatefulWidget {
  const _CityMap({required this.entries});
  final List<Map<String, dynamic>> entries;

  @override
  State<_CityMap> createState() => _CityMapState();
}

class _CityMapState extends State<_CityMap> {
  final MapController _map = MapController();
  int _selected = -1;

  List<({LatLng pos, Map<String, dynamic> entry})> get _pins {
    final result = <({LatLng pos, Map<String, dynamic> entry})>[];
    for (final e in widget.entries) {
      final lat = _parseCoord(e['latitude']);
      final lng = _parseCoord(e['longitude']);
      if (lat != null && lng != null) {
        result.add((pos: LatLng(lat, lng), entry: e));
      }
    }
    return result;
  }

  LatLng _center(List<({LatLng pos, Map<String, dynamic> entry})> pins) {
    if (pins.isEmpty) return const LatLng(36.3489, 43.1489); // Mosul
    if (pins.length == 1) return pins.first.pos;
    final avgLat =
        pins.map((p) => p.pos.latitude).reduce((a, b) => a + b) / pins.length;
    final avgLng =
        pins.map((p) => p.pos.longitude).reduce((a, b) => a + b) / pins.length;
    return LatLng(avgLat, avgLng);
  }

  void _recenter() {
    final pins = _pins;
    final z = pins.isEmpty ? 12.0 : (pins.length == 1 ? 14.0 : _fitZoom(pins));
    _map.move(_center(pins), z);
    setState(() => _selected = -1);
  }

  void _select(int i, LatLng pos, Map<String, dynamic> entry) {
    setState(() => _selected = i);
    _map.move(pos, 15.5);
    _showEntrySheet(context, entry);
  }

  @override
  Widget build(BuildContext context) {
    final pins = _pins;
    final center = _center(pins);
    final zoom = pins.isEmpty
        ? 12.0
        : (pins.length == 1 ? 14.0 : _fitZoom(pins));

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: center,
                initialZoom: zoom,
                maxZoom: 18.0,
                minZoom: 3.0,
                onTap: (_, __) {
                  if (_selected != -1) setState(() => _selected = -1);
                },
              ),
              children: [
                // Clean, colourful basemap (CartoDB Voyager) — far more legible
                // than the old neon-on-black style.
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.humanitarian.app',
                ),
                MarkerLayer(
                  markers: [
                    for (var i = 0; i < pins.length; i++)
                      Marker(
                        point: pins[i].pos,
                        width: 130,
                        height: 64,
                        child: GestureDetector(
                          onTap: () => _select(i, pins[i].pos, pins[i].entry),
                          child: _CityPin(
                            selected: i == _selected,
                            label: localizedContentFromMap(
                              pins[i].entry,
                              'name',
                              fallback: '',
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // Count + city chip.
            Positioned(
              top: 12,
              left: 12,
              child: _MapChip(
                icon: Icons.place_rounded,
                label: pins.isEmpty
                    ? 'Mosul · Iraq'
                    : '${pins.length} ${pins.length == 1 ? 'place' : 'places'} · Mosul',
              ),
            ),

            // Recenter / fit-all control.
            Positioned(
              right: 12,
              bottom: 12,
              child: _MapButton(
                icon: Icons.center_focus_strong_rounded,
                onTap: _recenter,
              ),
            ),

            // Empty state.
            if (pins.isEmpty)
              IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: const Text(
                      'No locations yet.\nAdd coordinates from the admin panel.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                        height: 1.55,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),

            // Attribution.
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '© CartoDB © OSM',
                  style: TextStyle(fontSize: 9, color: Colors.black45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _pinFill = Color(0xFF0F766E); // teal — strong on the light map
const _pinRing = Color(0xFF38BDF8); // sky — selected highlight

/// A clean circular map pin; grows and shows a label card when selected.
class _CityPin extends StatelessWidget {
  const _CityPin({required this.selected, required this.label});
  final bool selected;
  final String label;

  @override
  Widget build(BuildContext context) {
    final size = selected ? 38.0 : 28.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (selected && label.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label.length > 16 ? '${label.substring(0, 16)}…' : label,
              style: const TextStyle(
                color: _kCardA,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF14B8A6), _pinFill],
            ),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? _pinRing : Colors.white,
              width: selected ? 3.5 : 3,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 7,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            Icons.location_city_rounded,
            color: Colors.white,
            size: selected ? 19 : 15,
          ),
        ),
      ],
    );
  }
}

/// Floating circular control on the map (e.g. recenter).
class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: _pinFill, size: 22),
        ),
      ),
    );
  }
}

/// Small frosted chip overlay on the map.
class _MapChip extends StatelessWidget {
  const _MapChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _pinFill),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: _kCardA,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// A place card in the horizontal strip beneath the map.
// #29 — soft, eye-friendly accent colour per service category (was a single
// harsh indigo for everything). Muted tones so a long list stays calm to read.
Color _categoryColor(String category) {
  final c = category.toLowerCase();
  if (c.contains('health') ||
      c.contains('clinic') ||
      c.contains('hospital') ||
      c.contains('medical')) {
    return const Color(0xFF4CA97E); // soft green
  }
  if (c.contains('educat') ||
      c.contains('school') ||
      c.contains('library') ||
      c.contains('training')) {
    return const Color(0xFF5B8DEF); // soft blue
  }
  if (c.contains('water') || c.contains('sanit')) {
    return const Color(0xFF3FA9C4); // soft teal
  }
  if (c.contains('food') || c.contains('nutri')) {
    return const Color(0xFFD79A45); // soft amber
  }
  if (c.contains('shelter') || c.contains('hous')) {
    return const Color(0xFFC58457); // soft terracotta
  }
  if (c.contains('relief') || c.contains('emergen') || c.contains('aid')) {
    return const Color(0xFFCF6B6B); // soft rose
  }
  if (c.contains('women') || c.contains('coop') || c.contains('social')) {
    return const Color(0xFF9B72CF); // soft violet
  }
  return const Color(0xFF6D79C4); // soft indigo (default)
}

// #29 — City Guide service card: soft category colour, a category chip, the
// address, and a city · phone line. Replaces the old flat indigo tile.
class _CityServiceCard extends StatelessWidget {
  const _CityServiceCard({required this.entry, required this.onTap});

  final Map<String, dynamic> entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = localizedContentFromMap(entry, 'name', fallback: 'Service');
    final category = (entry['category'] ?? '').toString().trim();
    final city = (entry['city'] ?? '').toString().trim();
    final phone = (entry['phone'] ?? '').toString().trim();
    final address = (entry['address'] ?? '').toString().trim();
    final accent = _categoryColor(category);
    final meta = [city, phone].where((s) => s.isNotEmpty).join('   ·   ');

    return Material(
      color: AppThemeConfig.elevatedSurface(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppThemeConfig.border(context)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.location_city_rounded,
                  color: accent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppThemeConfig.text(context),
                      ),
                    ),
                    if (category.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          category,
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                    if (address.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 15,
                            color: AppThemeConfig.mutedText(context),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.3,
                                color: AppThemeConfig.text(context)
                                    .withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppThemeConfig.mutedText(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.entry});
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final name = localizedContentFromMap(entry, 'name', fallback: 'Place');
    final category = (entry['category'] ?? '').toString();
    final city = (entry['city'] ?? '').toString();
    final sub = [category, city].where((s) => s.isNotEmpty).join(' · ');

    return GestureDetector(
      onTap: () => _showEntrySheet(context, entry),
      child: Container(
        width: 210,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppThemeConfig.surface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppThemeConfig.border(context)),
          boxShadow: [
            BoxShadow(
              color: AppThemeConfig.shadow(context),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _pinFill.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.location_city_rounded, color: _pinFill),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: AppThemeConfig.text(context),
                    ),
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppThemeConfig.mutedText(context),
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

// ── Bottom sheet ──────────────────────────────────────────────────────────────

class _EntrySheet extends StatelessWidget {
  const _EntrySheet({required this.entry});
  final Map<String, dynamic> entry;

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final name = localizedContentFromMap(entry, 'name', fallback: 'Place');
    final category = (entry['category'] ?? '').toString();
    final city = (entry['city'] ?? '').toString();
    final phone = (entry['phone'] ?? '').toString().trim();
    final website = (entry['website'] ?? '').toString().trim();
    final lat = _parseCoord(entry['latitude']);
    final lng = _parseCoord(entry['longitude']);
    final subtitle = [category, city].where((s) => s.isNotEmpty).join(' • ');
    // #29 — opening hours (4-language), sector tags, and photo gallery.
    final hours = localizedContentFromMap(entry, 'opening_hours');
    final sectorSlugs = _entrySectors(entry);
    final allSectors = Get.isRegistered<CommunityController>()
        ? Get.find<CommunityController>().sectors.toList()
        : <Map<String, dynamic>>[];
    final gallery = (entry['gallery'] is List)
        ? (entry['gallery'] as List)
              .map((e) => e.toString())
              .where((s) => s.isNotEmpty)
              .toList()
        : <String>[];

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kCardA, Color(0xFF162032)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        14,
        24,
        MediaQuery.of(context).padding.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Header
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_kPinA, _kPinB]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: _kPinA.withValues(alpha: 0.4),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.place_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF8ECAE6),
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              if (lat != null && lng != null)
                GestureDetector(
                  onTap: () => _launch('https://maps.google.com/?q=$lat,$lng'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_kPinA, _kPinB]),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: _kPinA.withValues(alpha: 0.4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Text(
                      'Maps ↗',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // #29 — sector tags.
          if (sectorSlugs.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final slug in sectorSlugs)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _kPinA.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _kPinA.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      _sectorLabel(slug, allSectors),
                      style: const TextStyle(
                        color: Color(0xFF8ECAE6),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          if (phone.isNotEmpty) ...[
            _SheetRow(
              icon: Icons.phone_rounded,
              label: phone,
              iconColor: const Color(0xFF4CAF50),
              actionLabel: 'Call'.tr,
              onTap: () => _launch('tel:$phone'),
            ),
            const SizedBox(height: 10),
          ],
          // #29 — opening hours.
          if (hours.trim().isNotEmpty) ...[
            _SheetRow(
              icon: Icons.schedule_rounded,
              label: hours,
              iconColor: const Color(0xFFFFB74D),
            ),
            const SizedBox(height: 10),
          ],
          if (website.isNotEmpty) ...[
            _SheetRow(
              icon: Icons.language_rounded,
              label: website,
              iconColor: _kPinA,
              actionLabel: 'Open',
              onTap: () => _launch(
                website.startsWith('http') ? website : 'https://$website',
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (lat != null && lng != null) ...[
            _SheetRow(
              icon: Icons.my_location_rounded,
              label: '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
              iconColor: Colors.white38,
            ),
            const SizedBox(height: 10),
          ],
          // #29 — photo gallery strip; tap opens a full-screen viewer.
          if (gallery.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'city_photos'.tr,
              style: const TextStyle(
                color: Color(0xFF8ECAE6),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: gallery.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => Get.to(
                    () => _GalleryViewer(images: gallery, initialIndex: i),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      gallery[i],
                      width: 110,
                      height: 84,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 110,
                        height: 84,
                        color: Colors.white.withValues(alpha: 0.08),
                        child: const Icon(
                          Icons.broken_image_rounded,
                          color: Colors.white30,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                Navigator.pop(context);
                Get.to(() => CommunityDetailScreen(entry: entry));
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _kPinA.withValues(alpha: 0.4)),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('View Full Details'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.icon,
    required this.label,
    required this.iconColor,
    this.onTap,
    this.actionLabel,
  });
  final IconData icon;
  final String label;
  final Color iconColor;
  final VoidCallback? onTap;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (actionLabel != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  actionLabel!,
                  style: TextStyle(
                    color: iconColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

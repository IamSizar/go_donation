import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/id_privacy.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

// #50 — resolve a stored photo path to a full URL. Uploads are saved as
// relative paths (e.g. images/uploads/x.png); Image.network needs an absolute
// URL, so resolve those against the server host. Already-absolute URLs pass
// through unchanged.
String _receiptPhotoUrl(String path) {
  final p = path.trim();
  if (p.isEmpty) return p;
  final uri = Uri.tryParse(p);
  if (uri != null && uri.hasScheme) return p;
  return Uri.parse(publicBaseUrl)
      .resolve(p.replaceFirst(RegExp(r'^/+'), ''))
      .toString();
}

/// #50 — the current user's digital aid-delivery receipts (items + proof
/// photos + reference code). Read-only; recorded by staff.
class AidReceiptsScreen extends StatefulWidget {
  const AidReceiptsScreen({super.key});

  @override
  State<AidReceiptsScreen> createState() => _AidReceiptsScreenState();
}

class _AidReceiptsScreenState extends State<AidReceiptsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = const ModuleApi().myAidReceipts();
  }

  void _reload() => setState(() => _future = const ModuleApi().myAidReceipts());

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'receipts_title'.tr,
      subtitle: 'receipts_subtitle'.tr,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return Center(child: Text('receipts_empty'.tr));
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _ReceiptCard(receipt: items[i]),
            ),
          );
        },
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.receipt});
  final Map<String, dynamic> receipt;

  @override
  Widget build(BuildContext context) {
    final code = maskId((receipt['receipt_code'] ?? '').toString()); // #54
    final items = (receipt['items'] ?? '').toString();
    final deliveredAt = (receipt['delivered_at'] ?? '').toString();
    final deliveredBy = (receipt['delivered_by'] ?? '').toString();
    final notes = (receipt['notes'] ?? '').toString();
    final photos = (receipt['photos'] is List)
        ? (receipt['photos'] as List)
            .map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .map(_receiptPhotoUrl)
            .toList()
        : <String>[];

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: Colors.teal),
              const SizedBox(width: 8),
              Expanded(child: Text(code, style: const TextStyle(fontWeight: FontWeight.w800))),
              if (deliveredAt.isNotEmpty)
                Text(deliveredAt, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(items),
          ],
          if (deliveredBy.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('${'receipts_delivered_by'.tr}: $deliveredBy',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(notes, style: const TextStyle(fontSize: 13)),
          ],
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _openImage(context, photos, i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      photos[i],
                      width: 120,
                      height: 90,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 120,
                        height: 90,
                        color: Colors.white.withValues(alpha: 0.08),
                        child: const Icon(Icons.broken_image_rounded, color: Colors.white30),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openImage(BuildContext context, List<String> images, int initialIndex) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
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
              child: Image.network(images[i], fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.white30, size: 64)),
            ),
          ),
        ),
      ),
    ));
  }
}

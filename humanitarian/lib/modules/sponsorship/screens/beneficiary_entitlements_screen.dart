import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/app_voice.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/sponsorship/controllers/beneficiary_entitlements_controller.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

/// #21 — beneficiary "My Entitlements": the sponsorships supporting this user,
/// with next-support dates and a spoken (voice) summary for accessibility.
class BeneficiaryEntitlementsScreen extends StatefulWidget {
  const BeneficiaryEntitlementsScreen({super.key});

  @override
  State<BeneficiaryEntitlementsScreen> createState() =>
      _BeneficiaryEntitlementsScreenState();
}

class _BeneficiaryEntitlementsScreenState
    extends State<BeneficiaryEntitlementsScreen> {
  late final BeneficiaryEntitlementsController controller;
  Worker? _worker;
  bool _spoke = false;

  @override
  void initState() {
    super.initState();
    controller = Get.put(BeneficiaryEntitlementsController());
    // Auto-announce the summary once, after the first load settles.
    _worker = ever<bool>(controller.isLoading, (loading) {
      if (!loading && !_spoke) {
        _spoke = true;
        _announce();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!controller.isLoading.value && !_spoke) {
        _spoke = true;
        _announce();
      }
    });
  }

  @override
  void dispose() {
    _worker?.dispose();
    AppVoice.stop();
    super.dispose();
  }

  String _summaryText() {
    if (controller.entitlements.isEmpty) {
      return 'entitlements_voice_none'.tr;
    }
    final count = '${controller.activeCount}';
    final due = controller.nextDue;
    final date = (due?['next_due_date'] ?? '').toString();
    final shortDate = date.length >= 10 ? date.substring(0, 10) : date;
    if (shortDate.isNotEmpty) {
      return 'entitlements_voice_summary'.trParams({
        'count': count,
        'date': shortDate,
      });
    }
    return 'entitlements_voice_count'.trParams({'count': count});
  }

  void _announce() => AppVoice.speak(_summaryText());

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'My entitlements',
      subtitle: 'Sponsorships supporting you and your next support date.',
      child: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = controller.entitlements;
        return RefreshIndicator(
          onRefresh: () async {
            _spoke = false;
            await controller.fetch();
            _spoke = true;
            _announce();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            children: [
              if (controller.errorMessage.value != null)
                SectionTile(
                  icon: Icons.info_outline_rounded,
                  title: 'My entitlements',
                  subtitle: controller.errorMessage.value!,
                  color: Colors.orange,
                  onTap: controller.fetch,
                )
              else if (items.isEmpty)
                const SectionTile(
                  icon: Icons.card_giftcard_rounded,
                  title: 'No active entitlements yet.',
                  subtitle:
                      'When a sponsor supports your case, it will appear here.',
                  color: Colors.teal,
                )
              else ...[
                _VoiceHeader(
                  summary: _summaryText(),
                  onListen: _announce,
                  onStop: AppVoice.stop,
                ),
                const SizedBox(height: 14),
                for (final e in items) ...[
                  _EntitlementCard(item: e),
                  const SizedBox(height: 12),
                ],
              ],
            ],
          ),
        );
      }),
    );
  }
}

class _VoiceHeader extends StatelessWidget {
  const _VoiceHeader({
    required this.summary,
    required this.onListen,
    required this.onStop,
  });

  final String summary;
  final VoidCallback onListen;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.campaign_rounded, color: AppThemeConfig.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  summary,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppThemeConfig.text(context),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onListen,
                  icon: const Icon(Icons.volume_up_rounded),
                  label: Text('Listen'.tr),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => onStop(),
                icon: const Icon(Icons.stop_rounded),
                label: Text('Stop'.tr),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EntitlementCard extends StatelessWidget {
  const _EntitlementCard({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final title = localizedContentFromMap(
      item,
      'project_title',
      fallback: 'General support',
    );
    final amount = (item['amount'] ?? '').toString();
    final currency = (item['currency'] ?? '').toString();
    final interval = (item['schedule_interval'] ?? 'monthly').toString();
    final status = (item['status'] ?? '').toString();
    final due = (item['next_due_date'] ?? '').toString();
    final shortDue = due.length >= 10 ? due.substring(0, 10) : due;

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppThemeConfig.text(context),
                  ),
                ),
              ),
              _StatusChip(status: status),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (amount.isNotEmpty)
                InfoChip(
                  icon: Icons.payments_rounded,
                  label: '$amount $currency',
                ),
              InfoChip(
                icon: Icons.event_repeat_rounded,
                label: ('sponsorship_$interval').tr,
              ),
              if (shortDue.isNotEmpty)
                InfoChip(
                  icon: Icons.event_available_rounded,
                  label: '${'Next support due'.tr}: $shortDue',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'active':
        color = Colors.green;
        break;
      case 'delayed':
        color = Colors.orange;
        break;
      case 'paused':
        color = Colors.blueGrey;
        break;
      default:
        color = Colors.amber;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        ('sponsorship_status_$status').tr,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

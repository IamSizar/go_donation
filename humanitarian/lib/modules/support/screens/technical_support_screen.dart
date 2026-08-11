import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

/// Technical Support — send a message to the team and track the reply.
///
/// The Profile hub's "Technical Support" entry used to open SupportSection,
/// which is the volunteer-missions screen: a user tapping "الدعم الفني" landed
/// on a list of volunteering opportunities. There was no support screen at all,
/// and no way to read a ticket back — POST /api/support existed, nothing
/// returned the user their own tickets, and staff had no reply field.
///
/// Escalation: once the user has raised tickets on more than three distinct
/// days that are still unresolved, the backend flags it and a WhatsApp button
/// appears. Distinct DAYS is the rule the spec asks for — three messages fired
/// off in one frustrated sitting is a single attempt, not three, and should not
/// unlock a channel that bypasses the queue.
class TechnicalSupportScreen extends StatefulWidget {
  const TechnicalSupportScreen({super.key});

  @override
  State<TechnicalSupportScreen> createState() => _TechnicalSupportScreenState();
}

class _TechnicalSupportScreenState extends State<TechnicalSupportScreen> {
  final _subject = TextEditingController();
  final _message = TextEditingController();

  List<Map<String, dynamic>> _tickets = const [];
  bool _loading = true;
  bool _sending = false;
  bool _escalate = false;
  String? _whatsapp;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await const ModuleApi().getObject('${baseUrl}support/mine');
      final items = (res['items'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _tickets = items
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _escalate = res['escalate'] == true;
        _loading = false;
      });
      if (_escalate && _whatsapp == null) {
        final n = await const ModuleApi().supportWhatsapp();
        if (mounted) setState(() => _whatsapp = n);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final subject = _subject.text.trim();
    final message = _message.text.trim();
    if (subject.isEmpty || message.isEmpty) {
      Get.snackbar('Technical Support'.tr, 'support_fill_both'.tr);
      return;
    }
    setState(() => _sending = true);
    try {
      await const ModuleApi().postJson(supportTicketsUrl, {
        'subject': subject,
        'message': message,
      });
      _subject.clear();
      _message.clear();
      Get.snackbar('Technical Support'.tr, 'support_sent'.tr);
      await _load();
    } catch (_) {
      Get.snackbar('Technical Support'.tr, 'support_send_failed'.tr);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openWhatsApp() async {
    final number = (_whatsapp ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (number.isEmpty) return;
    final uri = Uri.parse('https://wa.me/$number');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: 'Technical Support'.tr,
      subtitle: '',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  if (_escalate && (_whatsapp ?? '').isNotEmpty) ...[
                    _EscalationCard(onTap: _openWhatsApp),
                    const SizedBox(height: 16),
                  ],
                  GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'support_new_message'.tr,
                          style: TextStyle(
                            color: AppThemeConfig.text(context),
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _subject,
                          decoration: InputDecoration(
                            labelText: 'support_subject'.tr,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _message,
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: 'support_message'.tr,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _sending ? null : _send,
                            child: Text(
                              _sending ? 'Sending...'.tr : 'support_send'.tr,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'support_my_requests'.tr,
                    style: TextStyle(
                      color: AppThemeConfig.text(context),
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_tickets.isEmpty)
                    Text(
                      'support_no_requests'.tr,
                      style: TextStyle(
                        color: AppThemeConfig.mutedText(context),
                        height: 1.5,
                      ),
                    )
                  else
                    for (final t in _tickets) ...[
                      _TicketCard(ticket: t),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
    );
  }
}

/// Shown only once the backend says the user has been waiting across more than
/// three separate days without resolution.
class _EscalationCard extends StatelessWidget {
  const _EscalationCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.support_agent_rounded, color: Color(0xFF25D366)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'support_escalate_title'.tr,
                  style: TextStyle(
                    color: AppThemeConfig.text(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'support_escalate_body'.tr,
            style: TextStyle(
              color: AppThemeConfig.mutedText(context),
              height: 1.5,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.chat_rounded, size: 18),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
              ),
              label: Text('support_escalate_cta'.tr),
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket});

  final Map<String, dynamic> ticket;

  @override
  Widget build(BuildContext context) {
    final status = (ticket['status'] ?? 'open').toString();
    final reply = (ticket['admin_reply'] ?? '').toString().trim();
    final created = (ticket['created_at'] ?? '').toString();
    final done = const {
      'closed',
      'resolved',
      'done',
    }.contains(status.toLowerCase());

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (ticket['subject'] ?? '').toString(),
                  style: TextStyle(
                    color: AppThemeConfig.text(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: (done ? Colors.green : Colors.orange).withValues(
                    alpha: 0.14,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'status_$status'.tr,
                  style: TextStyle(
                    color: done
                        ? Colors.green.shade700
                        : Colors.orange.shade800,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
          if (created.length >= 10) ...[
            const SizedBox(height: 4),
            Text(
              created.substring(0, 10),
              style: TextStyle(
                color: AppThemeConfig.mutedText(context),
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            (ticket['message'] ?? '').toString(),
            style: TextStyle(
              color: AppThemeConfig.mutedText(context),
              height: 1.5,
              fontSize: 13.5,
            ),
          ),
          if (reply.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppThemeConfig.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppThemeConfig.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'support_reply'.tr,
                    style: TextStyle(
                      color: AppThemeConfig.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    reply,
                    style: TextStyle(
                      color: AppThemeConfig.text(context),
                      height: 1.5,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
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
  String? _error;

  /// True once the user has tried to send, so the inline field errors appear
  /// on the first failed attempt rather than scolding an untouched form.
  bool _submitAttempted = false;

  /// True while both fields hold something. Drives the send button, so a
  /// doomed request can never fire (rule 5.6).
  bool get _canSend =>
      _subject.text.trim().isNotEmpty && _message.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Rebuild on every keystroke so the button ungates and the inline error
    // clears as soon as the field is valid, rather than only on submit.
    _subject.addListener(_onFieldChanged);
    _message.addListener(_onFieldChanged);
    _load();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _subject.removeListener(_onFieldChanged);
    _message.removeListener(_onFieldChanged);
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Clear the previous failure as the (re)load starts, so a retry is not
    // shown under the error it is trying to clear. `_loading` is NOT set back
    // to true here: it is a first-load flag, and a pull-to-refresh must not
    // tear the ticket list down to a spinner.
    if (mounted && _error != null) setState(() => _error = null);
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
        // Best-effort on purpose, and deliberately OUTSIDE the ticket load's
        // failure path: the WhatsApp number only decorates the escalation
        // card. Losing it must not claim the tickets failed to load.
        try {
          final n = await const ModuleApi().supportWhatsapp();
          if (mounted) setState(() => _whatsapp = n);
        } catch (e) {
          debugPrint('supportWhatsapp failed: $e');
        }
      }
    } catch (e) {
      // Was `catch (_) { _loading = false; }` — the failure was swallowed
      // whole, so an errored fetch fell through to the "no requests yet" copy.
      // That told a user their support tickets did not exist when the request
      // had failed, on the one screen they open BECAUSE something is wrong —
      // and offered no way to retry.
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your support requests.';
        _loading = false;
      });
      debugPrint('support/mine failed: $e');
    }
  }

  Future<void> _send() async {
    final subject = _subject.text.trim();
    final message = _message.text.trim();
    // The button is already gated on _canSend, so this only catches a send
    // racing the last keystroke. The inline messages under the fields, not a
    // snackbar, are what tell the user WHICH field is missing.
    if (subject.isEmpty || message.isEmpty) {
      setState(() => _submitAttempted = true);
      return;
    }
    // Dismiss the keyboard before the request: it must not hang over the
    // ticket list the send is about to refresh.
    FocusScope.of(context).unfocus();
    setState(() {
      _submitAttempted = false;
      _sending = true;
    });
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
      // Deliberate: sending is an action, not a data load, and the failure is
      // already told to the user by this snackbar — no false empty state can
      // come out of it.
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
      // The whole screen used to be replaced by a centred spinner on first
      // load, which took the compose form away for exactly as long as the
      // ticket fetch ran — on the screen a user opens BECAUSE something is
      // wrong. The page is now built immediately and only the ticket list
      // carries the loading state, which is the same region the error state
      // already occupies.
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          // Scrolling the page puts the keyboard away, so it can never end up
          // covering the ticket list the user scrolled down to read.
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                  // Inline, per-field validation. The error names the rule
                  // being broken and sits at the field it belongs to, rather
                  // than a snackbar that covers the form it is complaining
                  // about (rule 5.6). It appears only after a send attempt and
                  // clears the moment the field holds text.
                  TextField(
                    controller: _subject,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'support_subject'.tr,
                      errorText:
                          _submitAttempted && _subject.text.trim().isEmpty
                          ? 'support_subject_required'.tr
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _message,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'support_message'.tr,
                      errorText:
                          _submitAttempted && _message.text.trim().isEmpty
                          ? 'support_message_required'.tr
                          : null,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      // Disabled while incomplete or in flight: no doomed
                      // request, and no double submit.
                      onPressed: (_sending || !_canSend) ? null : _send,
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
            // Only the ticket LIST has the four states. The compose form
            // above stays reachable through a failed load — the user
            // came here to reach support, and a read failure must not
            // take away their way of doing it.
            //
            // Error stays first: a failure that happened while `_loading` was
            // still true must show the banner, not a skeleton that will never
            // resolve.
            if (_error != null)
              AppErrorState(message: _error!, onRetry: _load)
            else if (_loading)
              const _TicketListSkeleton()
            else if (_tickets.isEmpty)
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

/// First-load placeholder for the ticket list only.
///
/// A ticket is a [GlassPanel] carrying a subject, a status pill, a date and a
/// message paragraph, so the bones are card-shaped blocks at roughly that
/// height rather than [AppSkeleton.rows]' loose text bones — the cards then
/// fill the same footprint instead of shifting the page as they arrive.
/// Two blocks, not more: most users have raised one or two tickets, and a tall
/// placeholder would over-promise.
class _TicketListSkeleton extends StatelessWidget {
  const _TicketListSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppSkeleton(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _TicketBone(),
          const SizedBox(height: 12),
          const _TicketBone(),
        ],
      ),
    );
  }
}

/// One card-shaped bone at a ticket card's height, using GlassPanel's own
/// 28pt radius so it reads as a card rather than a bar.
class _TicketBone extends StatelessWidget {
  const _TicketBone();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 128,
      decoration: BoxDecoration(
        color: AppColors.of(context).groundSunken,
        borderRadius: BorderRadius.circular(28),
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

String _statusLabel(String status) {
  final key = 'status_$status';
  final translated = key.tr;
  // GetX hands back the key when there is no entry for it.
  if (translated != key) return translated;
  return localizedTag(status);
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
                  // A prefixed key first ('status_open'), falling back to
                  // localizedTag on the bare value. Without the fallback an
                  // untranslated status renders as the literal key — the app
                  // was showing "status_open" on a ticket card in the Arabic
                  // UI. GetX returns the key unchanged when it has no entry,
                  // so a missing translation is silent, which is exactly how
                  // this survived.
                  _statusLabel(status),
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

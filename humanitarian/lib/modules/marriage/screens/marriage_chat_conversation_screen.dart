import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

/// Note #35 — one staff-mediated marriage chat thread. Every bubble is
/// labeled only by role ("You" / the counterpart's masked label / "Staff")
/// — never a real name, matching the privacy design agreed for this feature.
class MarriageChatConversationScreen extends StatefulWidget {
  const MarriageChatConversationScreen({
    super.key,
    required this.threadId,
    required this.otherLabel,
    required this.myRole,
    required this.initialStatus,
  });

  final int threadId;
  final String otherLabel;
  final String myRole; // "requester" | "owner"
  final String initialStatus;

  @override
  State<MarriageChatConversationScreen> createState() =>
      _MarriageChatConversationScreenState();
}

class _MarriageChatConversationScreenState
    extends State<MarriageChatConversationScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;
  List<Map<String, dynamic>> _messages = [];
  late String _status;
  bool _loading = true;
  bool _sending = false;
  bool _deciding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    _load();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final res = await const ModuleApi().marriageChatMessages(widget.threadId);
      final items = (res['items'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      if (!mounted) return;
      setState(() {
        _messages = items;
        _status = (res['status'] ?? _status).toString();
        _error = null;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      if (!silent) setState(() => _error = e.toString());
    } finally {
      if (!silent && mounted) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _input.clear();
    try {
      await const ModuleApi().sendMarriageChatMessage(widget.threadId, text);
      await _load(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
        _input.text = text;
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _decide(bool accept) async {
    setState(() => _deciding = true);
    try {
      if (accept) {
        await const ModuleApi().acceptMarriageChat(widget.threadId);
      } else {
        await const ModuleApi().declineMarriageChat(widget.threadId);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _deciding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = widget.myRole == 'owner';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.otherLabel, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppThemeConfig.primary.withValues(alpha: 0.08),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_rounded, size: 14, color: AppThemeConfig.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'marriage_chat_mediated_notice'.tr,
                    style: TextStyle(fontSize: 11.5, color: AppThemeConfig.mutedText(context)),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          if (_status == 'pending' && isOwner)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Text('marriage_chat_pending_owner_notice'.tr,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _deciding ? null : () => _decide(false),
                    child: Text('marriage_chat_decline'.tr),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _deciding ? null : () => _decide(true),
                    child: Text('marriage_chat_accept'.tr),
                  ),
                ],
              ),
            )
          else if (_status == 'pending' && !isOwner)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text('marriage_chat_pending_requester_notice'.tr, textAlign: TextAlign.center),
            ),
          Expanded(
            child: _loading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _messages.isEmpty
                    ? Center(child: Text(_error!))
                    : _messages.isEmpty
                        ? Center(child: Text('marriage_chat_no_messages'.tr))
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                            itemCount: _messages.length,
                            itemBuilder: (context, i) => _Bubble(message: _messages[i]),
                          ),
          ),
          if (_status == 'active')
            _Composer(input: _input, sending: _sending, onSend: _send)
          else if (_status == 'declined')
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text('marriage_chat_declined_notice'.tr, textAlign: TextAlign.center),
            ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final Map<String, dynamic> message;

  @override
  Widget build(BuildContext context) {
    final mine = message['is_mine'] == true;
    final role = (message['sender_role'] ?? '').toString();
    final isStaff = role == 'staff';
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;
    final bg = isStaff
        ? Colors.blueGrey.withValues(alpha: 0.18)
        : mine
            ? AppThemeConfig.primary
            : AppThemeConfig.softSurface(context);
    final fg = mine && !isStaff ? Colors.white : AppThemeConfig.text(context);
    final createdAt = DateTime.tryParse((message['created_at'] ?? '').toString());

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 3, left: 4, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isStaff) Icon(Icons.shield_rounded, size: 12, color: Colors.blueGrey),
                  if (isStaff) const SizedBox(width: 4),
                  Text(
                    mine
                        ? 'marriage_chat_you'.tr
                        : isStaff
                            ? 'Support'.tr
                            : 'marriage_chat_other_party'.tr,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isStaff ? Colors.blueGrey : AppThemeConfig.mutedText(context),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(mine ? 16 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 16),
                ),
              ),
              child: Text(
                (message['body'] ?? '').toString(),
                style: TextStyle(color: fg, fontSize: 14.5, height: 1.35),
              ),
            ),
            if (createdAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
                child: Text(
                  DateFormat('MMM d · HH:mm').format(createdAt),
                  style: TextStyle(fontSize: 10, color: AppThemeConfig.mutedText(context)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.input, required this.sending, required this.onSend});
  final TextEditingController input;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: AppThemeConfig.softSurface(context),
          border: Border(top: BorderSide(color: AppThemeConfig.border(context))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: input,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Type a message…'.tr,
                  filled: true,
                  fillColor: AppThemeConfig.surface(context),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: AppThemeConfig.border(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: AppThemeConfig.border(context)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: sending ? null : onSend,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: AppThemeConfig.primary, shape: BoxShape.circle),
                child: sending
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

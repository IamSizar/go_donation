import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

/// Note #36 — one Staff↔Volunteer↔Beneficiary chat thread. Unlike the
/// marriage chat, identities are NOT masked — this is operational
/// coordination, so real names show. Always active (no accept/decline step:
/// staff already confirmed the pairing by approving the case-linked signup).
class CaseChatConversationScreen extends StatefulWidget {
  const CaseChatConversationScreen({
    super.key,
    required this.threadId,
    required this.title,
    this.subtitle,
  });

  final int threadId;
  final String title;
  final String? subtitle;

  @override
  State<CaseChatConversationScreen> createState() => _CaseChatConversationScreenState();
}

class _CaseChatConversationScreenState extends State<CaseChatConversationScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  int get _myUserId => int.tryParse(sharedPreferences.getString('id_user') ?? '') ?? 0;

  @override
  void initState() {
    super.initState();
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
      final res = await const ModuleApi().caseChatMessages(widget.threadId);
      final items = (res['items'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      if (!mounted) return;
      setState(() {
        _messages = items;
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
      await const ModuleApi().sendCaseChatMessage(widget.threadId, text);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            if (widget.subtitle != null && widget.subtitle!.trim().isNotEmpty)
              Text(widget.subtitle!, style: TextStyle(fontSize: 12, color: AppThemeConfig.mutedText(context))),
          ],
        ),
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
                Text(
                  'Support can view and help in this chat'.tr,
                  style: TextStyle(fontSize: 11.5, color: AppThemeConfig.mutedText(context)),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _messages.isEmpty
                    ? Center(child: Text(_error!))
                    : _messages.isEmpty
                        ? Center(child: Text('No messages yet. Say hello! 👋'.tr))
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                            itemCount: _messages.length,
                            itemBuilder: (context, i) => _Bubble(message: _messages[i], myUserId: _myUserId),
                          ),
          ),
          _Composer(input: _input, sending: _sending, onSend: _send),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.myUserId});
  final Map<String, dynamic> message;
  final int myUserId;

  @override
  Widget build(BuildContext context) {
    final senderId = int.tryParse('${message['sender_user_id']}') ?? 0;
    final mine = senderId == myUserId;
    final role = (message['sender_role'] ?? '').toString();
    final isStaff = role == 'staff';
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;
    final bg = isStaff
        ? Colors.blueGrey.withValues(alpha: 0.18)
        : mine
            ? AppThemeConfig.primary
            : AppThemeConfig.softSurface(context);
    final fg = mine && !isStaff ? Colors.white : AppThemeConfig.text(context);
    final senderName = (message['sender_name'] ?? '').toString();
    final createdAt = DateTime.tryParse((message['created_at'] ?? '').toString());

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!mine || isStaff)
              Padding(
                padding: const EdgeInsets.only(bottom: 3, left: 4, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isStaff) Icon(Icons.shield_rounded, size: 12, color: Colors.blueGrey),
                    if (isStaff) const SizedBox(width: 4),
                    Text(
                      isStaff ? (senderName.isNotEmpty ? senderName : 'Support'.tr) : senderName,
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

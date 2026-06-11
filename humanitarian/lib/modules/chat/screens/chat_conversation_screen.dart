import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/chat/controllers/chat_controller.dart';
import 'package:flutter_application_1/modules/chat/models/chat_models.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class ChatConversationScreen extends StatefulWidget {
  const ChatConversationScreen({
    super.key,
    required this.threadId,
    required this.title,
    this.subtitle,
  });

  final int threadId;
  final String title;
  final String? subtitle;

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  late final ChatThreadController ctrl;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  int get _myUserId =>
      int.tryParse(sharedPreferences.getString('id_user') ?? '') ?? 0;

  @override
  void initState() {
    super.initState();
    ctrl = Get.put(
      ChatThreadController(widget.threadId),
      tag: 'chat-${widget.threadId}',
    );
    ever(ctrl.messages, (_) => _scrollToBottom());
  }

  @override
  void dispose() {
    Get.delete<ChatThreadController>(tag: 'chat-${widget.threadId}');
    _input.dispose();
    _scroll.dispose();
    super.dispose();
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
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    final ok = await ctrl.send(text);
    if (!ok && mounted && ctrl.errorMessage.value != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ctrl.errorMessage.value!)),
      );
      _input.text = text; // restore so the user doesn't lose it
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
              Text(
                widget.subtitle!,
                style: TextStyle(fontSize: 12, color: AppThemeConfig.mutedText(context)),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Support-present banner.
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
            child: Obx(() {
              if (ctrl.isLoading.value && ctrl.messages.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (ctrl.messages.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.forum_outlined, size: 48, color: AppThemeConfig.mutedText(context)),
                        const SizedBox(height: 12),
                        Text(
                          'No messages yet. Say hello! 👋'.tr,
                          style: TextStyle(color: AppThemeConfig.mutedText(context)),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                itemCount: ctrl.messages.length,
                itemBuilder: (context, i) {
                  final m = ctrl.messages[i];
                  final mine = m.senderUserId == _myUserId;
                  return _MessageBubble(message: m, mine: mine);
                },
              );
            }),
          ),
          _Composer(input: _input, onSend: _send, controller: ctrl),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final isSupport = message.isSupport;
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;
    final bg = isSupport
        ? Colors.blueGrey.withValues(alpha: 0.18)
        : mine
            ? AppThemeConfig.primary
            : AppThemeConfig.softSurface(context);
    final fg = mine && !isSupport ? Colors.white : AppThemeConfig.text(context);

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Sender label (name for others / "Support" for admin).
            if (!mine || isSupport)
              Padding(
                padding: const EdgeInsets.only(bottom: 3, left: 4, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSupport)
                      Icon(Icons.shield_rounded, size: 12, color: Colors.blueGrey),
                    if (isSupport) const SizedBox(width: 4),
                    Text(
                      isSupport ? 'Support'.tr : message.senderName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isSupport ? Colors.blueGrey : AppThemeConfig.mutedText(context),
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
                message.body,
                style: TextStyle(color: fg, fontSize: 14.5, height: 1.35),
              ),
            ),
            if (message.createdAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
                child: Text(
                  DateFormat('MMM d · HH:mm').format(message.createdAt!),
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
  const _Composer({required this.input, required this.onSend, required this.controller});

  final TextEditingController input;
  final VoidCallback onSend;
  final ChatThreadController controller;

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
            Obx(
              () => GestureDetector(
                onTap: controller.isSending.value ? null : onSend,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppThemeConfig.primary,
                    shape: BoxShape.circle,
                  ),
                  child: controller.isSending.value
                      ? const Padding(
                          padding: EdgeInsets.all(13),
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ConnectRequestSheet — "Ask our team to connect me" (OPOS #25284 Phase 5
// Task 5, OPOS #26046). The member-facing copy says "our team", never "staff"
// (OPOS #26351); these comments still say staff for the people who act.
//
// WHY THIS EXISTS
// Donors, beneficiaries and volunteers may not contact each other directly in
// this app. What they can do is ask staff: the member writes what they need,
// staff review it, and an approval opens a supervised group chat. This sheet
// is where that request is written and sent; ConnectRequestButton is how a
// screen offers it.
//
// THE CONTRACT — POST /api/chat-groups/connect-requests
// (backend/internal/handlers/chat_group_connect.go, chatgroups_connect.go):
//   * context_type must be "donation" or "case"; context_id names the row.
//   * A blank message is refused (400), so Send is disabled while the trimmed
//     message is blank (rule 5.6: never let a doomed request fire). There is
//     NO maximum length, so the field sets none either.
//   * Resubmitting while an earlier request for the same context is pending
//     replaces its message, so sending twice is harmless — but one tap still
//     sends one request, because the button is disabled while it is in flight.
//   * A failure arrives as a plain Exception carrying an English server
//     sentence and no machine code, so the member is shown failureMessage's
//     localized "what failed, what to do next" and the detail goes to the log.
//
// THE CONFIRMATION (OPOS #26331)
// When the request is accepted while the sheet is still open, the form is
// replaced IN PLACE by ConnectRequestSentView, whose Done button closes the
// sheet. It used to be a SnackBar on the screen underneath, which the member
// often never saw: on My Donations the donation's detail sheet stays open over
// that screen and covers it, and on the Messages route toasts were found not
// to paint at all (messages_screen.dart).
//
// The SnackBar survives only for a member who dismissed the sheet before the
// answer arrived, when there is no sheet left to confirm in. It goes through
// the ScaffoldMessenger captured from the CALLER's context before the sheet
// opens: the sheet's own context is deactivated once the sheet pops, and using
// it then throws.
//
// NEVER POP A ROUTE THAT IS NOT CURRENT
// A dismissed sheet stays mounted for its ~200 ms exit animation. Anything
// here that pops checks first that the sheet's route is still on top; popping
// otherwise removes the screen or sheet UNDERNEATH it.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/design/motion.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/failure_message.dart';
import 'package:flutter_application_1/modules/chatgroups/widgets/connect_request_sent_view.dart';
import 'package:flutter_application_1/modules/chatgroups/widgets/connect_request_submit_button.dart';

/// `context_type` for a request about one donation.
const String kConnectContextDonation = 'donation';

/// `context_type` for a request about one beneficiary case.
const String kConnectContextCase = 'case';

/// The fewest lines the message field shows, so it reads as "write a few
/// sentences" rather than as a one-line search box.
const int _messageMinLines = 3;

/// The most lines the field grows to before it scrolls inside itself, so a
/// long message never pushes the send button off the sheet.
const int _messageMaxLines = 6;

/// A failure sentence is two clauses and must not be cut off with an ellipsis.
const int _errorMaxLines = 4;

/// Opens the sheet asking staff to connect the member about [contextId] of
/// [contextType] ([kConnectContextDonation] or [kConnectContextCase]).
///
/// Completes when the sheet closes, however it closed. When the request was
/// sent the sheet itself says so; a member who closed it before the answer
/// arrived is told on the screen underneath instead. [api] is a seam for
/// tests; production uses the real client.
Future<void> showConnectRequestSheet(
  BuildContext context, {
  required String contextType,
  required int contextId,
  ModuleApi api = const ModuleApi(),
}) async {
  // Captured now, while [context] is certainly mounted. The fallback toast is
  // shown after the sheet has gone, when neither the sheet's context nor — if
  // the caller was itself a sheet — the caller's may still be usable.
  final messenger = ScaffoldMessenger.maybeOf(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppThemeConfig.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
    ),
    builder: (_) => ConnectRequestSheet(
      contextType: contextType,
      contextId: contextId,
      api: api,
      onSentAfterDismiss: () => _confirmSent(messenger),
      onFailedAfterDismiss: (message) => _tellFailed(messenger, message),
    ),
  );
}

/// Tells a member who closed the sheet early that their request still went
/// through, on the screen underneath.
void _confirmSent(ScaffoldMessengerState? messenger) {
  if (messenger == null || !messenger.mounted) return;
  messenger.showSnackBar(SnackBar(content: Text('connect_request_sent'.tr)));
}

/// Tells a member who closed the sheet early that their request did NOT go
/// through, with the already-localized [message], on the screen underneath —
/// left untold, they would reasonably believe it was sent (OPOS #26345).
void _tellFailed(ScaffoldMessengerState? messenger, String message) {
  if (messenger == null || !messenger.mounted) return;
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

/// The sheet's content: what happens next, the message field, and the button
/// — then, once the request is accepted, the success view in their place.
class ConnectRequestSheet extends StatefulWidget {
  /// Builds the sheet for one donation or case. Prefer
  /// [showConnectRequestSheet], which also wires the fallback confirmation.
  const ConnectRequestSheet({
    super.key,
    required this.contextType,
    required this.contextId,
    required this.api,
    required this.onSentAfterDismiss,
    required this.onFailedAfterDismiss,
  }) : assert(
         contextType == kConnectContextDonation ||
             contextType == kConnectContextCase,
         'the server accepts only "donation" or "case"',
       );

  /// [kConnectContextDonation] or [kConnectContextCase].
  final String contextType;

  /// The id of the donation or case the request is about.
  final int contextId;

  /// Where the request is sent.
  final ModuleApi api;

  /// Called when the server accepts a request whose sheet the member had
  /// already dismissed. It was still sent, and with no sheet left to show the
  /// success view in, the caller has to confirm it instead.
  final VoidCallback onSentAfterDismiss;

  /// Called with the localized failure sentence when a request fails after
  /// the member dismissed its sheet: no sheet is left to show the error on, so
  /// the caller has to tell them instead.
  final ValueChanged<String> onFailedAfterDismiss;

  @override
  State<ConnectRequestSheet> createState() => _ConnectRequestSheetState();
}

class _ConnectRequestSheetState extends State<ConnectRequestSheet> {
  /// Holds the member's message. Never cleared on failure.
  final _message = TextEditingController();

  /// The line under the field — the validation refusal or the failure. Null
  /// when there is nothing to say.
  String? _error;

  /// True while the request is in flight; the button is disabled meanwhile.
  bool _isSending = false;

  /// True once the request was accepted while the sheet was still open; the
  /// form is replaced by the success view from then on.
  bool _isSent = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  // ─── Validation ───────────────────────────────────────────────────────────

  /// The refusal to show for [text], or null when it may be sent.
  ///
  /// Blank is refused because the server refuses it (400). Send is already
  /// disabled while the message is blank, so this is the defence behind that:
  /// if a tap ever reaches [_submit] with nothing to send, the doomed request
  /// still never fires and the member is told at the field. It is judged after
  /// trimming because the server trims before it checks, so a message of
  /// spaces and new lines is blank to both.
  ///
  /// There is deliberately no maximum: the server enforces none, and a limit
  /// invented here would cut off the members with the most to explain.
  static String? _validate(String text) =>
      text.trim().isEmpty ? 'connect_request_message_required'.tr : null;

  /// Re-checks as the member types once something is showing: a refusal goes
  /// the moment it no longer applies, and a failure clears when they edit.
  void _onChanged(String text) {
    if (_error == null) return;
    setState(() => _error = _validate(text));
  }

  // ─── Sending ──────────────────────────────────────────────────────────────

  /// Validates, then sends the trimmed message once.
  Future<void> _submit() async {
    if (_isSending) return;
    final refusal = _validate(_message.text);
    if (refusal != null) {
      AppHaptics.error();
      setState(() => _error = refusal);
      return;
    }
    // Read before the await: the sheet may be dismissed while in flight.
    final api = widget.api;
    final onSentAfterDismiss = widget.onSentAfterDismiss;
    final onFailedAfterDismiss = widget.onFailedAfterDismiss;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSending = true;
      _error = null;
    });
    try {
      await api.submitConnectRequest(
        contextType: widget.contextType,
        contextId: widget.contextId,
        message: _message.text.trim(),
      );
    } catch (e) {
      _showFailure(e, onFailedAfterDismiss);
      return;
    }
    AppHaptics.success();
    if (!_isCurrentRoute) {
      onSentAfterDismiss();
      return;
    }
    setState(() {
      _isSending = false;
      _isSent = true;
    });
  }

  /// True while this sheet is still the route on top — false once the member
  /// has dismissed it, even though its state stays mounted for the ~200 ms
  /// exit animation. `mounted` alone is not enough: popping then would remove
  /// the screen or sheet UNDERNEATH instead.
  bool get _isCurrentRoute =>
      mounted && (ModalRoute.of(context)?.isCurrent ?? true);

  /// Closes the sheet from the success view's Done button, guarded like every
  /// pop here so it can never remove the route underneath.
  void _closeSheet() {
    if (_isCurrentRoute) Navigator.of(context).pop();
  }

  /// Logs [error] for support and tells the member in a localized sentence
  /// instead: on the sheet, where the typed text stays and the button works
  /// again — or, when the member already dismissed the sheet, through
  /// [onFailedAfterDismiss] on the screen underneath.
  void _showFailure(Object error, ValueChanged<String> onFailedAfterDismiss) {
    debugPrint(
      '[chat-groups] connect request for ${widget.contextType} '
      '${widget.contextId} failed: $error',
    );
    final message =
        failureMessage(error, 'error_connect_request_submit_failed');
    AppHaptics.error();
    // Dismissed while in flight — gone, or still mounted for its ~200 ms exit
    // animation: an error set on the sheet would never be read, and staying
    // silent would leave the member believing the request was sent.
    if (!_isCurrentRoute) {
      onFailedAfterDismiss(message);
      return;
    }
    setState(() {
      _isSending = false;
      _error = message;
    });
  }

  // ─── Layout ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final motion = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.settleDuration;
    return Padding(
      // Lifts the sheet above the keyboard so it never covers the field or
      // the button (rule 5.6).
      padding: EdgeInsetsDirectional.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpace.lg,
            0,
            AppSpace.lg,
            AppSpace.lg,
          ),
          // The form cross-fades into the success view and the sheet eases to
          // its new height, rather than either jumping (rule 5.4).
          child: AnimatedSize(
            duration: motion,
            child: AnimatedSwitcher(
              duration: motion,
              child: _isSent
                  ? ConnectRequestSentView(onDone: _closeSheet)
                  : _buildForm(),
            ),
          ),
        ),
      ),
    );
  }

  /// The heading, the message field and the send button.
  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SheetHeading(),
        const SizedBox(height: AppSpace.lg),
        _MessageField(
          controller: _message,
          errorText: _error,
          onChanged: _onChanged,
        ),
        const SizedBox(height: AppSpace.md),
        ConnectRequestSubmitButton(
          message: _message,
          isSending: _isSending,
          onTap: _submit,
        ),
      ],
    );
  }
}

/// The title, and the one line saying what happens after sending — the
/// guidance a member needs to know this is a request, not a message.
class _SheetHeading extends StatelessWidget {
  const _SheetHeading();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'connect_request_title'.tr,
          style: TextStyle(
            fontSize: AppType.heading,
            fontWeight: AppType.wLabel,
            color: AppThemeConfig.text(context),
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          'connect_request_explainer'.tr,
          style: TextStyle(
            fontSize: AppType.body,
            height: AppType.leadBody,
            color: AppThemeConfig.mutedText(context),
          ),
        ),
      ],
    );
  }
}

/// The multi-line message. Return inserts a new line; sending is the button's
/// job. The error line animates in and out with Material's own transition.
class _MessageField extends StatelessWidget {
  const _MessageField({
    required this.controller,
    required this.errorText,
    required this.onChanged,
  });

  /// Holds the message.
  final TextEditingController controller;

  /// The refusal or failure to show under the field, if any.
  final String? errorText;

  /// Called on every edit.
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      minLines: _messageMinLines,
      maxLines: _messageMaxLines,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: 'connect_request_message_label'.tr,
        hintText: 'connect_request_message_hint'.tr,
        alignLabelWithHint: true,
        errorText: errorText,
        errorMaxLines: _errorMaxLines,
        filled: true,
        fillColor: AppThemeConfig.softSurface(context),
        border: OutlineInputBorder(borderRadius: AppRadius.smAll),
      ),
    );
  }
}

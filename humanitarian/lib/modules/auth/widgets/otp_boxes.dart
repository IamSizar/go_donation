import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme_config.dart';

/// R2 #31 — the 6-digit code as six separate boxes.
///
/// One real (invisible) TextField sits on top of six painted boxes. Keeping a
/// single field is what makes the platform features work for free:
///   * SMS auto-fill — `AutofillHints.oneTimeCode` (iOS offers the code from
///     the incoming message above the keyboard; Android's autofill too),
///   * paste — long-press the boxes → Paste (a code copied from WhatsApp),
///   * backspace across boxes — it is one string, not six fields.
/// When all six digits are in, [onCompleted] fires so the user doesn't have to
/// press anything.
class OtpBoxes extends StatefulWidget {
  const OtpBoxes({
    super.key,
    required this.controller,
    required this.onCompleted,
    this.enabled = true,
    this.length = 6,
  });

  final TextEditingController controller;
  final ValueChanged<String> onCompleted;
  final bool enabled;
  final int length;

  @override
  State<OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<OtpBoxes> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {});
    final code = widget.controller.text;
    if (code.length == widget.length) widget.onCompleted(code);
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.controller.text;
    final accent = AppThemeConfig.accent(context);
    final border = AppThemeConfig.border(context);

    final boxes = Row(
      // Digits are read left-to-right in every language.
      textDirection: TextDirection.ltr,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < widget.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: AspectRatio(
              aspectRatio: 0.85,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppThemeConfig.surface(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        _focus.hasFocus &&
                            i == code.length.clamp(0, widget.length - 1)
                        ? accent
                        : border,
                    width:
                        _focus.hasFocus &&
                            i == code.length.clamp(0, widget.length - 1)
                        ? 2
                        : 1,
                  ),
                ),
                child: Text(
                  i < code.length ? code[i] : '',
                  style: TextStyle(
                    color: AppThemeConfig.text(context),
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );

    return Stack(
      children: [
        boxes,
        Positioned.fill(
          child: Opacity(
            // Invisible but hit-testable: taps focus it, long-press pastes.
            opacity: 0.011,
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              enabled: widget.enabled,
              autofocus: widget.enabled,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.oneTimeCode],
              showCursor: false,
              enableInteractiveSelection: true,
              maxLength: widget.length,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(widget.length),
              ],
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(color: Colors.transparent, height: 3),
            ),
          ),
        ),
      ],
    );
  }
}

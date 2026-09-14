// ConnectRequestButton — how a screen offers "Ask staff to connect me"
// (OPOS #25284 Phase 5 Task 5, OPOS #26046).
//
// One widget for every entry point, so the rules for WHEN the action is
// offered live in one place:
//   * never to a guest — the server refuses guests on this route
//     (auth.RequireNotGuest in backend/cmd/server/main.go), so the button could
//     only ever fail for them;
//   * never without an id — a request must name the donation or case it is
//     about, and some rows arrive without one (DonationHistoryEntry.id is
//     nullable).
// In both cases it renders nothing at all, rather than a control the member
// can do nothing with.
//
// Two shapes: a labelled outline button for detail screens and sheets, and an
// icon-only action for a dense list row, which carries the same label as its
// tooltip and screen-reader name.
//
// ICONS: a Material glyph, like every other icon on the three host screens.
// The app has no SF Symbols layer yet (it uses no CupertinoIcons at all), and a
// lone iOS glyph among Material ones would be the inconsistency, not the fix.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';
import 'package:flutter_application_1/modules/chatgroups/widgets/connect_request_sheet.dart';

/// The action's glyph: a person at a help desk — staff, not the other member.
const IconData _actionIcon = Icons.support_agent_rounded;

/// The labelled button's height — above the 44pt minimum touch target.
const double _buttonHeight = 48;

/// Offers the "Ask staff to connect me" sheet for one donation or case, or
/// renders nothing when the member cannot use it.
class ConnectRequestButton extends StatelessWidget {
  /// A full-width labelled outline button, for detail screens and sheets.
  const ConnectRequestButton({
    super.key,
    required this.contextType,
    required this.contextId,
    this.api = const ModuleApi(),
    this.padding = EdgeInsetsDirectional.zero,
  }) : _isIconOnly = false;

  /// An icon-only action for a dense row. Its label is its tooltip and its
  /// screen-reader name, since there is no visible text to read.
  const ConnectRequestButton.iconOnly({
    super.key,
    required this.contextType,
    required this.contextId,
    this.api = const ModuleApi(),
    this.padding = EdgeInsetsDirectional.zero,
  }) : _isIconOnly = true;

  /// [kConnectContextDonation] or [kConnectContextCase].
  final String contextType;

  /// The donation's or case's id. Null hides the button: a request must name
  /// what it is about.
  final int? contextId;

  /// Where the request is sent. A seam for tests.
  final ModuleApi api;

  /// Space around the button, applied only when it renders — so a hidden
  /// button leaves no gap behind in its host's layout.
  final EdgeInsetsGeometry padding;

  /// Which of the two shapes to draw; set by the constructor chosen.
  final bool _isIconOnly;

  @override
  Widget build(BuildContext context) {
    final id = contextId;
    if (id == null || isGuestMode()) return const SizedBox.shrink();
    final label = 'connect_request_action'.tr;
    void open() => showConnectRequestSheet(
      context,
      contextType: contextType,
      contextId: id,
      api: api,
    );
    return Padding(
      padding: padding,
      child: _isIconOnly
          ? _IconAction(label: label, onTap: open)
          : _LabelledAction(label: label, onTap: open),
    );
  }
}

/// The labelled shape: an outline button, the secondary style — the host
/// screen's own content stays the primary thing on it.
class _LabelledAction extends StatelessWidget {
  const _LabelledAction({required this.label, required this.onTap});

  /// The already-translated label.
  final String label;

  /// Opens the sheet.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppThemeConfig.accent(context);
    return AppPressable(
      onTap: onTap,
      semanticLabel: label,
      expand: true,
      child: Container(
        height: _buttonHeight,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpace.md),
        decoration: BoxDecoration(
          border: Border.all(color: accent),
          borderRadius: AppRadius.mdAll,
        ),
        // Excluded because the button already announces [label].
        child: ExcludeSemantics(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_actionIcon, size: AppSpace.lg, color: accent),
              const SizedBox(width: AppSpace.xs),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppType.body,
                    fontWeight: AppType.wAction,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The icon-only shape, for a row. AppPressable gives it a 44pt touch target.
class _IconAction extends StatelessWidget {
  const _IconAction({required this.label, required this.onTap});

  /// The already-translated label, used as tooltip and screen-reader name.
  final String label;

  /// Opens the sheet.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      // AppPressable already announces [label]; a tooltip-sourced
      // announcement as well would read the name twice.
      excludeFromSemantics: true,
      child: AppPressable(
        onTap: onTap,
        semanticLabel: label,
        child: Icon(
          _actionIcon,
          size: AppSpace.lg,
          color: AppThemeConfig.accent(context),
        ),
      ),
    );
  }
}

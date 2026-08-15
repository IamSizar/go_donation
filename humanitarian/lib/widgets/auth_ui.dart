import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';

/// Shared chrome for the sign-in / sign-up screens.
///
/// These four screens (login, register, welcome, guest upgrade) were the last
/// place still painting the old navy→teal gradient with decorative blur orbs
/// and white-on-glass text. The rest of the app moved to the flat themed
/// background some time ago — see the client note in AppThemeConfig — so the
/// auth flow was the odd one out, and it read as dated next to every screen
/// that follows it.
///
/// Everything here now delegates to the app's own components (GradientScreen,
/// GlassPanel, the themed InputDecoration) rather than styling itself, so the
/// sign-in screen looks like the app the user is about to enter, and it
/// follows light/dark automatically instead of assuming a dark ground.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child, this.maxWidth = 460});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return GradientScreen(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // #39 — free navigation: only shown when there's actually
                  // somewhere to go back to.
                  Builder(
                    builder: (context) => Navigator.of(context).canPop()
                        ? const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: _AuthBackButton(),
                          )
                        : const SizedBox.shrink(),
                  ),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Plain themed back arrow. Mirrors direction for RTL locales rather than
/// relying on the (non-directional) arrow_back glyph.
class _AuthBackButton extends StatelessWidget {
  const _AuthBackButton();

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => Navigator.of(context).maybePop(),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: authFieldFill(context),
            shape: BoxShape.circle,
            border: Border.all(color: authFieldBorder(context)),
          ),
          child: Icon(
            isRtl ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
            color: AppThemeConfig.text(context),
            size: 20,
          ),
        ),
      ),
    );
  }
}

/// The card the auth forms sit in. Kept under its old name because four
/// screens reference it; it is the app's standard panel now, not a
/// translucent glass sheet floating over a gradient.
class AuthGlassCard extends StatelessWidget {
  const AuthGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) =>
      GlassPanel(padding: padding, child: child);
}

/// Small pill above the form title ("Secure sign in"). Tinted with the brand
/// colour instead of translucent white, so it reads on a light ground.
class AuthBadge extends StatelessWidget {
  const AuthBadge({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppThemeConfig.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppThemeConfig.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppThemeConfig.primary),
          const SizedBox(width: 7),
          Text(
            label.tr,
            style: TextStyle(
              color: AppThemeConfig.primary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Neutral pill used on the welcome screen to list what the app offers.
class AuthFeatureChip extends StatelessWidget {
  const AuthFeatureChip({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: authFieldFill(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: authFieldBorder(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppThemeConfig.primary),
          const SizedBox(width: 7),
          Text(
            label.tr,
            style: TextStyle(
              color: AppThemeConfig.text(context),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Field colours for the auth forms.
///
/// AppThemeConfig.border() is `white @ 80%` in light mode and surface() is
/// `white @ 78%` — both inherited from the old gradient background, where a
/// translucent white edge read as glass. On the flat white page they are
/// invisible, which left the phone field and the Google button looking like
/// plain text rather than controls. These are the real edges those inputs
/// need; the app-wide tokens are left alone because other screens still draw
/// on tinted surfaces where the translucent versions are correct.
Color authFieldFill(BuildContext context) => AppThemeConfig.isDark(context)
    ? const Color(0xFF16263A)
    : const Color(0xFFF3F5F9);

Color authFieldBorder(BuildContext context) => AppThemeConfig.isDark(context)
    ? Colors.white.withValues(alpha: 0.14)
    : const Color(0xFFD3DBE6);

/// Field styling for the auth forms.
///
/// Takes [context] so it can follow the theme; the old version hardcoded
/// white-on-transparent, which is invisible on the app's light background.
InputDecoration authInputDecoration(
  BuildContext context, {
  required String label,
  required String hintText,
  required IconData icon,
  Widget? suffixIcon,
}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: c, width: w),
  );

  final muted = AppThemeConfig.mutedText(context);
  const danger = Color(0xFFDC2626);

  return InputDecoration(
    labelText: label.tr,
    hintText: hintText.tr,
    labelStyle: TextStyle(color: muted),
    floatingLabelStyle: TextStyle(color: AppThemeConfig.primary),
    hintStyle: TextStyle(color: muted.withValues(alpha: 0.7)),
    prefixIcon: Icon(icon, color: muted, size: 20),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: authFieldFill(context),
    enabledBorder: border(authFieldBorder(context)),
    focusedBorder: border(AppThemeConfig.primary, 1.6),
    errorBorder: border(danger),
    focusedErrorBorder: border(danger, 1.6),
    errorStyle: const TextStyle(color: danger, fontWeight: FontWeight.w600),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';
import 'package:flutter_application_1/routes/app_routes.dart';
import 'package:get/get.dart';

/// Section 27 — guest-facing versions of the Home and Account tabs, and of the
/// Messages tab's conversation list (OPOS #26423). They make no authenticated
/// calls, so a signed-out guest gets a clean browse landing and a clear path
/// to sign in (instead of an auth-error placeholder).

void _goSignIn() {
  exitGuestMode();
  Get.offAllNamed(AppRoutes.authLogin);
}

/// Guest Home — a welcome hero and a sign-in call-to-action.
///
/// Note #41 — the "Browse" shortcut tiles this used to show (Marketplace,
/// Marriage, a locked City Directory tile) were dropped: Store, Marriage,
/// and City Guide are now real bottom-nav tabs reachable directly (the same
/// 4 fixed tabs every role sees), so duplicating them here as in-page tiles
/// was a second, confusing path to the exact same place.
class GuestHomeSection extends StatelessWidget {
  const GuestHomeSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome'.tr,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppThemeConfig.text(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'You are browsing as a guest.'.tr,
              style: TextStyle(
                fontSize: 14,
                color: AppThemeConfig.mutedText(context),
              ),
            ),
            const SizedBox(height: 20),

            // Hero card.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppThemeConfig.accent(context),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.explore_rounded,
                    color: AppThemeConfig.onAccent(context),
                    size: 30,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Explore freely'.tr,
                    style: TextStyle(
                      color: AppThemeConfig.onAccent(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Browse campaigns, stories, and updates from our community. Sign in to donate, volunteer, or create requests and make an impact.'
                        .tr,
                    style: TextStyle(
                      color: AppThemeConfig.onAccent(
                        context,
                      ).withValues(alpha: 0.9),
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _goSignIn,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppThemeConfig.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Sign in'.tr,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Guest Account tab — a friendly sign-in prompt shown where a signed-in user
/// would see their profile.
class GuestAccountSection extends StatelessWidget {
  const GuestAccountSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: AppThemeConfig.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_outline_rounded,
                  size: 44,
                  color: AppThemeConfig.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'You are a guest'.tr,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppThemeConfig.text(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in to access your profile, donations, volunteering, and messages.'
                    .tr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: AppThemeConfig.mutedText(context),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _goSignIn,
                  icon: const Icon(Icons.login_rounded),
                  label: Text(
                    'Sign in'.tr,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppThemeConfig.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  // There is no separate registration screen: the phone/OTP
                  // login flow both signs in existing users and creates new
                  // accounts. (A RegisterPage used to exist but registered
                  // nobody — it waited 650ms and forwarded to /verify — and
                  // has since been deleted.)
                  onPressed: _goSignIn,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppThemeConfig.primary,
                    side: BorderSide(color: AppThemeConfig.border(context)),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Create an account'.tr,
                    style: const TextStyle(fontWeight: FontWeight.w600),
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

/// OPOS #26423 — what a guest sees on the Messages tab in place of the
/// conversation list.
///
/// WHY A PROMPT AND NOT THE LIST
/// The server gives a guest session an empty GET /api/chats and GET
/// /api/marriage/chats, and refuses thread messages with 403
/// guest_restricted (OPOS #26354). A guest has no conversations and cannot
/// start one. Showing them the list meant polling for an answer that is always
/// empty, then drawing "no conversations yet" or "could not load your chats",
/// as if something were missing rather than simply not open to a guest. This
/// says what the tab is for and how to get it.
///
/// WHAT IT REUSES
///   * The shape and tone of [GuestAccountSection]: a mark, a heading, one
///     explanatory sentence and a "Sign in" button.
///   * [_goSignIn], so this button leaves guest mode exactly as the guest Home
///     and Account tabs do.
///   * [AppEmpty] to draw it. The Messages tab already uses AppEmpty in this
///     same slot for a member with no conversations, so both states share one
///     layout, whose padding is directional and whose text is centred, and so
///     reads the same right to left.
///
/// Support is deliberately NOT in this widget: the support doors sit above it
/// on the Messages tab, for guests and members alike.
class GuestMessagesPrompt extends StatelessWidget {
  const GuestMessagesPrompt({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppEmpty(
      // The same mark as the Messages door in the dashboard's top bar, so the
      // prompt visibly belongs to the button that opened it.
      icon: Icons.forum_outlined,
      title: 'messages_guest_title',
      message: 'messages_guest_body',
      actionLabel: 'Sign in',
      onAction: _goSignIn,
    );
  }
}

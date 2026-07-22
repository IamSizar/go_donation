import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/chat/controllers/chat_controller.dart';
import 'package:flutter_application_1/modules/chat/screens/messages_screen.dart';
import 'package:flutter_application_1/modules/community/screens/community_services_section.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/featured_campaigns_controller.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/role_dashboard_controller.dart';
import 'package:flutter_application_1/modules/dashboard/screens/guest_sections.dart';
import 'package:flutter_application_1/modules/marketplace/screens/marketplace_section.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_hub_screen.dart';
import 'package:flutter_application_1/modules/notifications/controllers/notifications_controller.dart';
import 'package:flutter_application_1/modules/notifications/screens/notifications_screen.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:flutter_application_1/widgets/dashboard.dart';
import 'package:flutter_application_1/widgets/profile_menu.dart';
import 'package:get/get.dart';

/// Note #41 — "Complete Restructuring and Distribution of the Application
/// Interfaces". The bottom nav is now fixed at exactly 4 tabs, identical for
/// every role (no scrolling, no per-role tab set): Home, Store, Marriage,
/// City Guide. Everything that used to be a separate tab (Kafala, Contribute,
/// Volunteer, Services) is now reached from Home's existing quick-action
/// tiles/hero buttons (widgets/dashboard.dart), which now push those screens
/// directly instead of switching to a tab index that no longer exists.
/// Alerts and Messages moved to a persistent top bar shown on every tab;
/// Profile moved into the same top bar's avatar menu
/// (widgets/profile_menu.dart).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  static const List<NavDestination> _destinations = [
    NavDestination(
      label: 'Home',
      icon: Icons.dashboard_customize_rounded,
      activeIcon: Icons.dashboard_rounded,
      color: Colors.teal,
    ),
    NavDestination(
      label: 'Store',
      icon: Icons.storefront_outlined,
      activeIcon: Icons.storefront_rounded,
      color: Colors.deepOrangeAccent,
    ),
    NavDestination(
      label: 'Marriage',
      icon: Icons.favorite_outline_rounded,
      activeIcon: Icons.favorite_rounded,
      color: Colors.pinkAccent,
    ),
    NavDestination(
      label: 'City Guide',
      icon: Icons.map_outlined,
      activeIcon: Icons.map_rounded,
      color: Colors.indigo,
    ),
  ];

  static const int _cityGuideIndex = 3;

  // Non-const on purpose: GuestHomeSection reads the guest config (which
  // loads async), so it must rebuild when setState fires after the fetch.
  List<Widget> get _sections => [
    isGuestMode() ? GuestHomeSection() : const DashboardHomeSection(),
    const MarketplaceSection(),
    const MarriageHubScreen(),
    const CityGuideScreen(),
  ];

  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<FeaturedCampaignsController>()) {
      Get.put(FeaturedCampaignsController());
    }
    if (!Get.isRegistered<RoleDashboardController>()) {
      Get.put(RoleDashboardController());
    }
    // Guests have no phone-based session to summarize — skip the auth-gated
    // summary (it would 401 and show "Please sign in again"); the
    // GuestHomeSection replaces that tab anyway.
    if (!isGuestMode()) {
      Get.find<RoleDashboardController>().fetchSummary();
    }
    if (!Get.isRegistered<NotificationsController>()) {
      Get.put(NotificationsController());
    }
    // Note #41 — Messages moved to the persistent top bar (shown on every
    // tab, not just its own screen), so its unread badge needs the
    // controller registered up-front here too, same as Notifications.
    if (!Get.isRegistered<ChatController>()) {
      Get.put(ChatController());
    }
    _currentIndex = dashboardTabNotifier.value.clamp(0, _sections.length - 1);
    dashboardTabNotifier.addListener(_handleDashboardTabChange);
  }

  @override
  void dispose() {
    dashboardTabNotifier.removeListener(_handleDashboardTabChange);
    super.dispose();
  }

  void _handleDashboardTabChange() {
    final nextIndex = dashboardTabNotifier.value.clamp(0, _sections.length - 1);
    if (nextIndex == _currentIndex || !mounted) return;
    setState(() => _currentIndex = nextIndex);
  }

  Future<bool> _confirmExit() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Exit App?'.tr),
            content: Text('Do you want to close the app?'.tr),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('Cancel'.tr),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('Exit'.tr),
              ),
            ],
          ),
        ) ??
        false;
  }

  // 27.3 — the phone Back button on the main screen must NOT log the user out
  // and must NOT pop the root route (popping it left an empty navigator = black
  // screen). Instead: from any non-Home tab, Back returns to Home; from Home,
  // Back asks to exit and — if confirmed — backgrounds/closes the app.
  Future<void> _handleBack() async {
    const homeIndex = 0; // Home is always the first destination.
    if (_currentIndex != homeIndex) {
      setState(() => _currentIndex = homeIndex);
      if (dashboardTabNotifier.value != homeIndex) {
        dashboardTabNotifier.value = homeIndex;
      }
      return;
    }
    final shouldExit = await _confirmExit();
    if (shouldExit) {
      // Android: sends the app to the background (like the Home button). iOS:
      // no-op (Apple disallows programmatic exit) — the dialog just closes.
      await SystemNavigator.pop();
    }
  }

  void _onTabSelected(int index) {
    // Note #40 — City Directory (this tab) is a hard block for guests: show
    // the upgrade prompt instead of ever switching to it.
    if (index == _cityGuideIndex && isGuestMode()) {
      requireUpgrade(
        context,
        reason: 'Full registration is required to view the City Directory.',
      );
      return;
    }
    if (index == _currentIndex) return;
    AppHaptics.selection();
    dashboardTabNotifier.value = index;
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        extendBody: true,
        body: Column(
          children: [
            const _DashboardTopBar(),
            Expanded(
              // The top bar above already reserves the status-bar inset via
              // its own SafeArea; each tab's screen also wraps itself in a
              // SafeArea (since it's reused elsewhere as a standalone pushed
              // route). Left alone, that's the status-bar gap applied
              // twice. Stripping the top MediaQuery padding here makes the
              // tab's own SafeArea compute zero top inset, so the gap only
              // ever appears once, right under the top bar.
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: IndexedStack(
                  index: _currentIndex,
                  children: _sections,
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: AppThemeConfig.navBarSurface(context),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: AppThemeConfig.border(context)),
                  boxShadow: [
                    BoxShadow(
                      color: AppThemeConfig.shadow(context),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: ModernBottomNavigator(
                  currentIndex: _currentIndex,
                  destinations: _destinations,
                  onSelected: _onTabSelected,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Note #41 — persistent header shown above every tab: the profile avatar
/// (with a dot when the profile is incomplete, previously shown on the
/// now-removed Profile tab icon), an Alerts bell (unread badge), and a
/// Messages icon (unread badge). Kept intentionally minimal — each tab's own
/// SectionScaffold still carries its own title/subtitle underneath.
class _DashboardTopBar extends StatelessWidget {
  const _DashboardTopBar();

  @override
  Widget build(BuildContext context) {
    final notifications = Get.find<NotificationsController>();
    final chats = Get.find<ChatController>();
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: profileIncompleteNotifier,
              builder: (context, incomplete, _) =>
                  ProfileMenuButton(showIndicatorDot: incomplete),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Obx(
                  () => _TopBarIconButton(
                    icon: Icons.notifications_none_rounded,
                    badgeCount: notifications.unreadCount,
                    tooltip: 'Notifications'.tr,
                    onTap: () => Get.to(() => const NotificationsScreen()),
                  ),
                ),
                const SizedBox(width: 8),
                Obx(
                  () => _TopBarIconButton(
                    icon: Icons.forum_outlined,
                    badgeCount: chats.totalUnread,
                    tooltip: 'Messages'.tr,
                    onTap: () => Get.to(() => const MessagesScreen()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBarIconButton extends StatelessWidget {
  const _TopBarIconButton({
    required this.icon,
    required this.badgeCount,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final int badgeCount;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: AppThemeConfig.surface(context),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            AppHaptics.selection();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 22, color: AppThemeConfig.text(context)),
                if (badgeCount > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(minWidth: 16),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                      child: Text(
                        badgeCount > 99 ? '99+' : '$badgeCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

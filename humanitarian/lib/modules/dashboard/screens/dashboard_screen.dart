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
import 'package:flutter_application_1/modules/auth/screens/profile_menu_screen.dart';
import 'package:flutter_application_1/modules/search/screens/global_search_screen.dart';
import 'package:flutter_application_1/widgets/cached_profile_avatar.dart';
import 'package:flutter_application_1/api/profile_api.dart';
import 'dart:io';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:flutter_application_1/widgets/dashboard.dart';
import 'package:flutter_application_1/widgets/settings_section.dart';
import 'package:get/get.dart';

/// Note #41 — "Complete Restructuring and Distribution of the Application
/// Interfaces". The bottom nav is now fixed at 5 tabs, identical for every
/// role (no scrolling, no per-role tab set): Home, Store, Marriage, City
/// Guide, Settings. Everything that used to be a separate tab (Kafala,
/// Contribute, Volunteer, Services) is now reached from Home's existing
/// quick-action tiles/hero buttons (widgets/dashboard.dart), which now push
/// those screens directly instead of switching to a tab index that no
/// longer exists. Alerts and Messages moved to a persistent top bar shown on
/// every tab. Settings — previously a side drawer opened by tapping the
/// profile avatar — is its own tab (widgets/settings_section.dart).
///
/// "Ninth: Improve the Home Interface Design" then reinstated a profile
/// photo in the top-right, but it now opens the account hub
/// (ProfileMenuScreen) rather than switching to the Settings tab. The two
/// don't overlap: the hub owns the account items (profile, notifications,
/// community services, language, dark mode, support, legal/contact, log
/// out) and the Settings tab keeps the organizational content.
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
      label: 'Events',
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
    NavDestination(
      label: 'Settings',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      color: Colors.blueGrey,
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
    const SettingsSection(),
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
        body: Column(
          children: [
            _DashboardTopBar(tabIndex: _currentIndex),
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
                child: IndexedStack(index: _currentIndex, children: _sections),
              ),
            ),
          ],
        ),
        // Stock BottomNavigationBar has no way to override its total
        // height — its ~56pt base is hardcoded internally with no
        // constructor param to shrink it, so a custom bar is used instead
        // to get a smaller background block. The home-indicator safe area
        // is still handled correctly (added below via SafeArea), same as
        // the stock widget would.
        bottomNavigationBar: _CompactBottomNavBar(
          currentIndex: _currentIndex,
          destinations: _destinations,
          onSelected: _onTabSelected,
        ),
      ),
    );
  }
}

/// Replaces the stock BottomNavigationBar — that widget hardcodes a ~56pt
/// base height internally with no constructor param to shrink it. This
/// mirrors its plain icon+label look (no Material 3 selection pill) at a
/// smaller, fully-controlled height.
class _CompactBottomNavBar extends StatelessWidget {
  const _CompactBottomNavBar({
    required this.currentIndex,
    required this.destinations,
    required this.onSelected,
  });

  final int currentIndex;
  final List<NavDestination> destinations;
  final ValueChanged<int> onSelected;

  // Sized to hug the icon+label content tightly (see _CompactNavItem) — the
  // lever for "make the bar smaller" is this height, not the icon/font
  // sizes below, which stay at their normal, comfortable size.
  //
  // Budget at 40: icon 24 + gap 2 + label line box 12 (fontSize 11 with an
  // explicit height of 1.1) = 38, leaving 1pt of slack top and bottom. The
  // label needs that explicit line height — the locale fonts default to
  // roughly 1.45, which makes the content 42 and overflows this bar by 2.
  static const double _barHeight = 40;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppThemeConfig.backgroundTop(context),
      // Full SafeArea, i.e. the device's standard home-indicator gap below the
      // labels — the same spacing other iOS apps use. The bar is kept short by
      // _barHeight hugging the icon+label stack, not by trimming this gap.
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _barHeight,
          child: Row(
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: _CompactNavItem(
                    destination: destinations[i],
                    selected: i == currentIndex,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactNavItem extends StatelessWidget {
  const _CompactNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? AppThemeConfig.primary
        : AppThemeConfig.mutedText(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? destination.activeIcon : destination.icon,
              color: color,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              destination.label.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                // Explicit line height so the label box is 12pt rather than
                // the locale font's default (~16pt) — see _barHeight.
                height: 1.1,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Note #41 — persistent header shown above every tab: the current tab's
/// title (top-left, same row as the icons — role-based dashboard title on
/// Home, a fixed title on every other tab), an Alerts bell (unread badge),
/// and a Messages icon (unread badge). Each tab's own in-page header no
/// longer repeats the title (see each tab's `title: ''` in its
/// SectionScaffold call). Kept intentionally minimal.
class _DashboardTopBar extends StatelessWidget {
  const _DashboardTopBar({required this.tabIndex});

  final int tabIndex;

  static const int _homeIndex = 0;
  static const int _storeIndex = 1;
  static const int _marriageIndex = 2;
  static const int _cityGuideIndex = 3;
  static const int _settingsIndex = 4;

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
            if (tabIndex == _homeIndex)
              Expanded(
                child: Obx(() {
                  final controller = Get.find<RoleDashboardController>();
                  final roleKey = controller.roleKey.value.trim().isNotEmpty
                      ? controller.roleKey.value.trim()
                      : switch (sharedPreferences.getString('role_id')) {
                          '1' => 'donor',
                          '2' => 'beneficiary',
                          '3' => 'volunteer',
                          _ => 'guest',
                        };
                  return _TopBarTitle(dashboardTitleForRole(roleKey));
                }),
              )
            else if (tabIndex == _storeIndex)
              const Expanded(child: _TopBarTitle('Marketplace'))
            else if (tabIndex == _marriageIndex)
              const Expanded(child: _TopBarTitle('Events'))
            else if (tabIndex == _cityGuideIndex)
              const Expanded(child: _TopBarTitle('City Guide'))
            else if (tabIndex == _settingsIndex)
              const Expanded(child: _TopBarTitle('Settings'))
            else
              const Spacer(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Note #43 — grouped with Notifications/Messages at the top,
                // matching the client's requested layout (was inside the side
                // drawer only). The profile avatar sits at the end of this row
                // and opens the account hub — see _TopBarProfileAvatar.
                _TopBarIconButton(
                  icon: Icons.search_rounded,
                  badgeCount: 0,
                  tooltip: 'search_title'.tr,
                  onTap: () => Get.to(() => const GlobalSearchScreen()),
                ),
                const SizedBox(width: 8),
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
                const SizedBox(width: 8),
                // "Ninth: Improve the Home Interface Design" — the profile photo
                // sits top-right and opens the account hub.
                const _TopBarProfileAvatar(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBarTitle extends StatelessWidget {
  const _TopBarTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.tr,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: AppThemeConfig.text(context),
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

/// "Ninth: Improve the Home Interface Design" — the user's circular profile
/// photo in the top-right corner. Tapping it opens the account hub
/// (ProfileMenuScreen). Falls back to a person glyph when no photo is set.
class _TopBarProfileAvatar extends StatelessWidget {
  const _TopBarProfileAvatar();

  String? _localImagePath() {
    final path = sharedPreferences.getString('profile_image_path');
    if (path == null || path.isEmpty) return null;
    return File(path).existsSync() ? path : null;
  }

  String? _remoteImageUrl() => normalizeProfilePictureUrl(
    sharedPreferences.getString('profile_picture_url'),
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Profile'.tr,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            AppHaptics.selection();
            Get.to(() => const ProfileMenuScreen());
          },
          child: CachedProfileAvatar(
            localPath: _localImagePath(),
            imageUrl: _remoteImageUrl(),
            radius: 19,
            backgroundColor: AppThemeConfig.primary,
            placeholder: const Icon(
              Icons.person,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

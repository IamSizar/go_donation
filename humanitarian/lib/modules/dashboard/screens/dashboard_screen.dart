import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/modules/auth/screens/profile.dart';
import 'package:flutter_application_1/modules/chat/screens/messages_screen.dart';
import 'package:flutter_application_1/modules/community/screens/community_services_section.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/featured_campaigns_controller.dart';
import 'package:flutter_application_1/modules/dashboard/controllers/role_dashboard_controller.dart';
import 'package:flutter_application_1/modules/dashboard/screens/guest_sections.dart';
import 'package:flutter_application_1/modules/donations/screens/donations_section.dart';
import 'package:flutter_application_1/modules/marketplace/screens/marketplace_section.dart';
import 'package:flutter_application_1/modules/notifications/controllers/notifications_controller.dart';
import 'package:flutter_application_1/modules/proposal/screens/proposal_services_section.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/sponsorship_section.dart';
import 'package:flutter_application_1/modules/support/screens/support_section.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:flutter_application_1/widgets/dashboard.dart';
import 'package:flutter_application_1/widgets/notification.dart';
import 'package:get/get.dart';

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
      label: 'Kafala',
      icon: Icons.favorite_outline_rounded,
      activeIcon: Icons.favorite_rounded,
      color: Colors.pinkAccent,
    ),
    NavDestination(
      label: 'Market',
      icon: Icons.storefront_outlined,
      activeIcon: Icons.storefront_rounded,
      color: Colors.deepOrangeAccent,
    ),
    NavDestination(
      label: 'Community',
      icon: Icons.groups_outlined,
      activeIcon: Icons.groups_rounded,
      color: Colors.indigo,
    ),
    NavDestination(
      label: 'Contribute',
      icon: Icons.volunteer_activism_outlined,
      activeIcon: Icons.volunteer_activism_rounded,
      color: Colors.green,
    ),
    NavDestination(
      label: 'Alerts',
      icon: Icons.notifications_none_rounded,
      activeIcon: Icons.notifications_active_rounded,
      color: Colors.amber,
    ),
    NavDestination(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      color: Colors.blueAccent,
    ),
    NavDestination(
      label: 'Volunteer',
      icon: Icons.front_hand_outlined,
      activeIcon: Icons.front_hand_rounded,
      color: Colors.cyan,
    ),
    NavDestination(
      label: 'Services',
      icon: Icons.apps_rounded,
      activeIcon: Icons.apps,
      color: Colors.deepPurple,
    ),
    NavDestination(
      label: 'Messages',
      icon: Icons.forum_outlined,
      activeIcon: Icons.forum_rounded,
      color: Colors.teal,
    ),
  ];

  // Section 27 — for a guest, swap the auth-gated Home + Profile tabs for
  // guest-friendly browse/sign-in screens (instance getter so it can read the
  // live guest flag).
  List<Widget> get _sections => [
    // Non-const on purpose: GuestHomeSection reads the guest config (which
    // loads async), so it must rebuild when setState fires after the fetch.
    isGuestMode() ? GuestHomeSection() : const DashboardHomeSection(),
    const SponsorshipSection(),
    const MarketplaceSection(),
    const CommunityServicesSection(),
    const DonationsSection(),
    const NotificationsSection(),
    isGuestMode() ? GuestAccountSection() : const ProfileSection(),
    const SupportSection(),
    const ProposalServicesSection(),
    const MessagesScreen(),
  ];

  /// Services (ProposalServicesSection) lives at this section index. Backlog #6:
  /// it's reachable from the Profile "Services" entry + bot deep-links, but it is
  /// intentionally NOT a bottom-nav tab. It stays in the allowed set below so
  /// navigation to it isn't bounced; it's only excluded from the VISIBLE bar.
  static const int _servicesTabIndex = 8;

  /// Tabs each role may open from the bottom navigator (others are not their flow).
  static List<int> _navigatorSourceIndices() {
    // Section 27 — Guest Mode: a signed-out guest sees only the Super-Admin-
    // enabled browse screens (Home is always the landing). All account tabs
    // (Kafala, Contribute, Alerts, Profile, Volunteer, Messages) are hidden.
    if (isGuestMode()) {
      final tabs = <int>[0]; // Home
      if (guestCanSee('marketplace')) tabs.add(2); // Market
      if (guestCanSee('city_directory')) tabs.add(3); // Community
      tabs.add(6); // Profile — always available so a guest can sign in
      return tabs;
    }
    switch (sharedPreferences.getString('role_id')) {
      case '1': // Donor — giving, market, messages; not kafala/volunteer shells
        return const [0, 2, 3, 4, 9, 5, 6, 8];
      case '2': // Beneficiary — aid/kafala, community, messages, alerts, profile
        return const [0, 1, 3, 9, 5, 6, 8];
      case '3': // Volunteer — volunteer hub, community, alerts, profile
        return const [0, 7, 3, 5, 6, 8];
      default:
        return List<int>.generate(_destinations.length, (i) => i);
    }
  }

  /// #13 — indices kept in the allowed source set (so navigation to them isn't
  /// bounced) but hidden from the VISIBLE bottom bar for a given role. For a
  /// beneficiary, Community services (3) and Messages (9) move into the profile
  /// menu, so they're dropped from the bar — same rationale as Services (8).
  static Set<int> _hiddenNavIndices() {
    if (!isGuestMode() && sharedPreferences.getString('role_id') == '2') {
      return const {3, 9};
    }
    return const {};
  }

  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<FeaturedCampaignsController>()) {
      Get.put(FeaturedCampaignsController());
    }
    if (!Get.isRegistered<RoleDashboardController>()) {
      Get.put(RoleDashboardController());
    }
    // Guests have no token — skip the auth-gated summary (it would 401 and show
    // "Please sign in again"); the GuestHomeSection replaces that tab anyway.
    if (!isGuestMode()) {
      Get.find<RoleDashboardController>().fetchSummary();
    }
    if (!Get.isRegistered<NotificationsController>()) {
      Get.put(NotificationsController());
    }
    _currentIndex = dashboardTabNotifier.value.clamp(0, _sections.length - 1);
    _ensureCurrentTabVisibleForRole();
    dashboardTabNotifier.addListener(_handleDashboardTabChange);

    // Section 27 — refresh the guest whitelist on a fresh launch (the in-memory
    // map is empty after a restart), then rebuild so the nav shows the right
    // browse tabs.
    if (isGuestMode() && guestScreenConfig.isEmpty) {
      fetchGuestConfig().then((_) {
        if (mounted) setState(_ensureCurrentTabVisibleForRole);
      });
    }
  }

  @override
  void dispose() {
    dashboardTabNotifier.removeListener(_handleDashboardTabChange);
    super.dispose();
  }

  void _ensureCurrentTabVisibleForRole() {
    final allowed = _navigatorSourceIndices();
    if (!allowed.contains(_currentIndex)) {
      final fallback = allowed.first;
      _currentIndex = fallback;
      if (dashboardTabNotifier.value != fallback) {
        dashboardTabNotifier.value = fallback;
      }
    }
  }

  void _handleDashboardTabChange() {
    var nextIndex = dashboardTabNotifier.value.clamp(0, _sections.length - 1);
    final allowed = _navigatorSourceIndices();
    if (!allowed.contains(nextIndex)) {
      nextIndex = allowed.first;
      if (dashboardTabNotifier.value != nextIndex) {
        dashboardTabNotifier.value = nextIndex;
        return;
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final sourceIndices = _navigatorSourceIndices();
    // #6 — Services (index 8) stays reachable (Profile entry + bot deep-links) but
    // is no longer a bottom-nav tab: keep it allowed above, exclude it here.
    final hiddenIndices = _hiddenNavIndices();
    final navIndices = [
      for (final i in sourceIndices)
        if (i != _servicesTabIndex && !hiddenIndices.contains(i)) i,
    ];
    final visibleDestinations = [
      for (final i in navIndices) _destinations[i],
    ];
    final navigatorSelectedIndex = navIndices.indexOf(_currentIndex);
    final safeNavIndex = navigatorSelectedIndex >= 0
        ? navigatorSelectedIndex
        : 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(index: _currentIndex, children: _sections),
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
                child: ValueListenableBuilder<bool>(
                  valueListenable: profileIncompleteNotifier,
                  builder: (context, profileIncomplete, _) {
                    return Obx(() {
                      final notifications = Get.find<NotificationsController>();
                      // Always read the observable so this Obx has something to
                      // watch even when the Alerts tab is hidden (e.g. a guest),
                      // otherwise GetX throws "improper use of GetX".
                      final unread = notifications.unreadCount;
                      final alertsIndex = navIndices.indexOf(5);
                      final profileIndex = navIndices.indexOf(6);
                      return ModernBottomNavigator(
                        currentIndex: safeNavIndex,
                        destinations: visibleDestinations,
                        badgeCounts: {
                          if (alertsIndex >= 0) alertsIndex: unread,
                        },
                        dotIndicators: {
                          if (profileIncomplete && profileIndex >= 0)
                            profileIndex,
                        },
                        onSelected: (visibleIndex) {
                          final actualIndex = navIndices[visibleIndex];
                          if (actualIndex == _currentIndex) return;
                          AppHaptics.selection();
                          dashboardTabNotifier.value = actualIndex;
                          setState(() => _currentIndex = actualIndex);
                        },
                      );
                    });
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:flutter_application_1/shared/widgets/adaptive_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/design/motion.dart';
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
    return showAdaptiveConfirm(
      context,
      title: 'Exit App?'.tr,
      message: 'Do you want to close the app?'.tr,
      confirmLabel: 'Exit'.tr,
      cancelLabel: 'Cancel'.tr,
    );
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
            DashboardTopBar(tabIndex: _currentIndex),
            Expanded(
              // Each tab's screen wraps itself in a SafeArea, because each is
              // also reachable as a standalone pushed route. Inside this
              // Column both of its insets are already accounted for, so both
              // must be stripped or they get applied twice:
              //
              //   TOP — the DashboardTopBar above reserves the status bar.
              //   Without removeTop the gap appears twice, once under the
              //   status bar and again under the top bar.
              //
              //   BOTTOM — the nav bar below reserves the home indicator.
              //   Without removeBottom the section pads itself by the full
              //   ~34pt inset, which paints as a band of page background
              //   sitting on top of the nav bar and reads as a second, empty
              //   bar. This only started mattering when the nav moved out of
              //   Scaffold's bottomNavigationBar slot and into this Column —
              //   the slot used to consume that inset on the body's behalf.
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                removeBottom: true,
                child: IndexedStack(index: _currentIndex, children: _sections),
              ),
            ),
            // The nav bar lives in the BODY, not in Scaffold's
            // bottomNavigationBar slot.
            //
            // The slot reserves the bottom safe-area inset OUTSIDE whatever
            // widget you give it and fills that strip with the Scaffold's own
            // background. The result was two stacked bars: our surface on top,
            // and a strip of scaffold background beneath it that no amount of
            // padding inside our widget could reach or colour.
            //
            // As the last child of the body Column it sits flush against the
            // physical bottom edge, so its own decoration paints all the way
            // down and there is nothing behind it.
            _CompactBottomNavBar(
              currentIndex: _currentIndex,
              destinations: _destinations,
              onSelected: _onTabSelected,
            ),
          ],
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

  // Content budget: icon 21 + gap 1 + label line box 11 (fontSize 10 with an
  // explicit height of 1.1) = 33pt.
  //
  // The bar is 52, not 33, on purpose. Sizing it to hug the content exactly
  // left the icons pressed against the top hairline with a single point of
  // slack, so the row read as crammed into the edge of the bar rather than
  // sitting in it. The extra 19pt distributes as ~9pt above and below, which
  // is what makes the content look seated in the bar.
  //
  // The label needs its explicit line height — the locale fonts default to
  // roughly 1.45, which would grow the content past even this and overflow.
  static const double _barHeight = 52;

  /// Clearance below the labels, clamped between [_minClearance] and
  /// [_maxClearance].
  ///
  /// Two different things constrain this, and getting it wrong in either
  /// direction is visible:
  ///
  ///   * Using the device's FULL bottom inset (~34pt here) leaves the labels
  ///     floating well above the screen edge. The bar reads as too tall and
  ///     too high up, because most of its height is empty colour.
  ///
  ///   * Using a small flat value (10pt was tried) pushes the labels into the
  ///     region the display's ROUNDED CORNERS mask. The centre tabs survive,
  ///     but the outermost ones — leftmost under RTL — get their descenders
  ///     clipped by the corner radius. The home indicator is not the binding
  ///     constraint; the corner is, and it only bites at the ends of the row,
  ///     which is why the clipping looks asymmetric.
  ///
  /// 20pt clears both the indicator and the corner mask while still sitting
  /// 14pt lower than the full inset.
  static const double _minClearance = 6;
  static const double _maxClearance = 20;

  /// The device's real bottom inset, clamped.
  ///
  /// Read from [View], not from MediaQuery: an ancestor can legitimately
  /// consume the padding (Scaffold does), after which MediaQuery reports 0
  /// and any calculation based on it silently produces a bar that looks fine
  /// in code and wrong on screen. The view is the ground truth.
  static double _clearanceFor(BuildContext context) {
    final view = View.of(context);
    final inset = view.viewPadding.bottom / view.devicePixelRatio;
    return inset <= 0
        ? _minClearance
        : inset.clamp(_minClearance, _maxClearance);
  }

  @override
  Widget build(BuildContext context) {
    // The decoration sits OUTSIDE the padding on purpose: the bar's surface
    // must reach the physical bottom edge so it reads as anchored chrome,
    // while its content stops short of the unsafe region.
    //
    // The surface is `card`, NOT `ground`. Painting the bar in the page's own
    // background colour gives it no edge, so every neutral pixel above it —
    // the body's bottom gutter, the gap under the last card — merges into it
    // and the bar appears to extend far up the screen. It was never taller
    // than its 54pt; there was simply no boundary to see. A distinct surface
    // plus a hairline is what makes chrome read as chrome.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppThemeConfig.navBarSurface(context),
        // The SEPARATOR carries the separation, not the fill.
        //
        // Measured from a device screenshot: the bar's white (#FFFFFF) against
        // the sand page (#F7F4EE) is a ~3% luminance step — technically a
        // different colour, visually no edge at all. The `line` hairline
        // (#E4DFD4) on white was equally faint. So the bar rendered correctly
        // and still could not be found on screen.
        //
        // lineStrong (#CFC8B9) is the quietest value that actually reads as an
        // edge here. Anything subtler and the chrome dissolves into the page.
        border: Border(
          top: BorderSide(
            color: AppThemeConfig.borderStrong(context),
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: _clearanceFor(context)),
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
        ? AppThemeConfig.accent(context)
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
              size: 21,
            ),
            const SizedBox(height: 1),
            Text(
              destination.label.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                // Explicit line height so the label box is 11pt rather than
                // the locale font's default (~15pt) — see _barHeight.
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
class DashboardTopBar extends StatefulWidget {
  const DashboardTopBar({super.key, required this.tabIndex});

  final int tabIndex;

  static const int _homeIndex = 0;
  static const int _storeIndex = 1;
  static const int _marriageIndex = 2;
  static const int _cityGuideIndex = 3;
  static const int _settingsIndex = 4;

  /// Space between the trailing controls.
  ///
  /// Was 8 with five controls; J9 makes it six, so it is 6. The arithmetic on
  /// the narrowest phone Android still ships (320dp): 32dp of bar padding
  /// leaves 288, and the six controls occupy 34 + 42×4 + 38 + 5×6 = 270 — the
  /// title keeps 18dp there and 78dp on a 360dp screen. It cannot overflow
  /// whatever the numbers do, because the title is Expanded and ellipsised
  /// (see _TopBarTitle): a crowded bar truncates the title, it never breaks
  /// the layout.
  static const double _gap = 6;

  @override
  State<DashboardTopBar> createState() => _DashboardTopBarState();
}

class _DashboardTopBarState extends State<DashboardTopBar> {
  /// Whether the action cluster is open.
  ///
  /// Lives here rather than inside _TopBarActions because the TITLE has to
  /// react to it too: expanded, the six controls take the width the title was
  /// using, and an Expanded title simply ellipsised to "لوحة…". A truncated
  /// heading is worse than none — it is the same clutter the collapse was
  /// meant to remove, with a broken word on top. The title steps aside while
  /// the cluster is open and comes back when it closes.
  bool _actionsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final tabIndex = widget.tabIndex;
    // The unread counts moved with the buttons into _TopBarActions, which is
    // the only thing that reads them now.
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (_actionsExpanded)
              // No Spacer while open: the cluster is entitled to the whole bar,
              // and a Spacer would hold width it needs on a narrow screen.
              const SizedBox.shrink()
            else if (tabIndex == DashboardTopBar._homeIndex)
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
            else if (tabIndex == DashboardTopBar._storeIndex)
              const Expanded(child: _TopBarTitle('Marketplace'))
            else if (tabIndex == DashboardTopBar._marriageIndex)
              const Expanded(child: _TopBarTitle('Events'))
            else if (tabIndex == DashboardTopBar._cityGuideIndex)
              const Expanded(child: _TopBarTitle('City Guide'))
            else if (tabIndex == DashboardTopBar._settingsIndex)
              const Expanded(child: _TopBarTitle('Settings'))
            else
              const Spacer(),
            // Flexible, not a bare child: seven controls (six plus the toggle)
            // are 27px wider than a 320dp bar, which a fixed-width Row answers
            // with a RenderFlex overflow. Bounded here and scrollable inside,
            // so the cluster degrades to a swipe instead of striped paint.
            Flexible(
              child: _TopBarActions(
                tabIndex: tabIndex,
                expanded: _actionsExpanded,
                onToggle: () =>
                    setState(() => _actionsExpanded = !_actionsExpanded),
              ),
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

/// The top bar's actions, collapsed behind one button.
///
/// WHY THIS EXISTS
/// This row had grown to six controls — assistant, support, search,
/// notifications, messages, profile — drawn above every tab, next to the
/// screen title. Six tap targets and two badges is more chrome than content on
/// a narrow phone, and it competes with the thing the user actually came to
/// read.
///
/// Collapsed, it is a single button. Expanded, the six unfurl beside it.
///
/// DIRECTION
/// The toggle is the FIRST child, so it keeps the position nearest the title
/// and the group grows away from it: leftwards in Arabic, rightwards in
/// English, with no `Platform`/`isRTL` branch anywhere. `Row` lays children
/// start-to-end and `AlignmentDirectional.centerStart` pins the growing box by
/// its start edge, so both come from the ambient `Directionality` and mirror
/// on their own.
///
/// THE BADGE IS THE POINT
/// Notifications and messages carry unread counts. Hiding them behind a
/// collapsed button would hide the one thing in this bar that is time-
/// sensitive, so the toggle carries their SUM while collapsed and drops it
/// once expanded, where the real per-item badges are visible again.
class _TopBarActions extends StatelessWidget {
  const _TopBarActions({
    required this.tabIndex,
    required this.expanded,
    required this.onToggle,
  });

  final int tabIndex;

  /// Owned by _DashboardTopBarState, because the title reacts to it too.
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final notifications = Get.find<NotificationsController>();
    final chats = Get.find<ChatController>();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Obx(() {
          // Summed, not "any unread": a single dot would say something is
          // waiting without saying how much, and both counts are already
          // rendered as numbers when expanded.
          final pending = notifications.unreadCount + chats.totalUnread;
          return _TopBarIconButton(
            icon: expanded ? Icons.close_rounded : Icons.more_horiz_rounded,
            badgeCount: expanded ? 0 : pending,
            tooltip: expanded ? 'Close'.tr : 'Quick actions'.tr,
            onTap: () {
              AppHaptics.gentle();
              onToggle();
            },
          );
        }),
        // Flexible so the scrollable half receives a BOUNDED width. Without
        // it the AnimatedSize hands its child unbounded constraints, the row
        // inside takes its full intrinsic width, and this Row overflows by the
        // 27px the toggle added — a scroll view cannot scroll if nothing ever
        // told it how much room it has.
        Flexible(
          child: ClipRect(
            child: AnimatedSize(
              duration: AppMotion.resolve(context, AppMotion.settleDuration),
              curve: AppMotion.resolveCurve(context, Curves.easeOutCubic),
              alignment: AlignmentDirectional.centerStart,
              child: expanded
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: DashboardTopBar._gap),

                          // K28's per-section AI icon and J9's support
                          // button both used to live here. The owner asked for
                          // both to come off this bar and be reached from
                          // الرسائل instead, which already carries the
                          // assistant card and the support-chat tile and now
                          // carries the technical-support form as well.
                          //
                          // What that trades away, recorded so it is a
                          // decision and not an accident: the assistant no
                          // longer opens pre-asking about the tab the user is
                          // standing on (AssistantHintButton seeded it from
                          // the tab's route). From الرسائل it opens on its
                          // normal welcome, whose suggestion chips are the
                          // role's real FAQs.
                          // Note #43 — grouped with Notifications/Messages at the top,
                          // matching the client's requested layout (was inside the side
                          // drawer only). The profile avatar sits at the end of this row
                          // and opens the account hub — see _TopBarProfileAvatar.
                          _TopBarIconButton(
                            icon: Icons.search_rounded,
                            badgeCount: 0,
                            tooltip: 'search_title'.tr,
                            onTap: () =>
                                Get.to(() => const GlobalSearchScreen()),
                          ),
                          const SizedBox(width: DashboardTopBar._gap),
                          Obx(
                            () => _TopBarIconButton(
                              icon: Icons.notifications_none_rounded,
                              badgeCount: notifications.unreadCount,
                              tooltip: 'Notifications'.tr,
                              onTap: () =>
                                  Get.to(() => const NotificationsScreen()),
                            ),
                          ),
                          const SizedBox(width: DashboardTopBar._gap),
                          Obx(
                            () => _TopBarIconButton(
                              icon: Icons.forum_outlined,
                              badgeCount: chats.totalUnread,
                              tooltip: 'Messages'.tr,
                              onTap: () => Get.to(() => const MessagesScreen()),
                            ),
                          ),
                          const SizedBox(width: DashboardTopBar._gap),
                          // "Ninth: Improve the Home Interface Design" — the profile photo
                          // sits top-right and opens the account hub.
                          const _TopBarProfileAvatar(),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

import 'dart:ui';

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
import 'package:flutter_application_1/modules/dashboard/screens/keyboard_safe_tab_body.dart';
import 'package:flutter_application_1/modules/marketplace/screens/marketplace_section.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_hub_screen.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_saved_screen.dart';
import 'package:flutter_application_1/modules/notifications/controllers/notifications_controller.dart';
import 'package:flutter_application_1/modules/notifications/screens/notifications_screen.dart';
import 'package:flutter_application_1/modules/auth/screens/profile_menu_screen.dart';
import 'package:flutter_application_1/modules/search/screens/global_search_screen.dart';
import 'package:flutter_application_1/widgets/cached_profile_avatar.dart';
import 'package:flutter_application_1/api/profile_api.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'dart:io';
import 'package:flutter_application_1/modules/profile/required_fields_prompt.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:flutter_application_1/widgets/dashboard.dart';
import 'package:get/get.dart';

/// Note #41 — "Complete Restructuring and Distribution of the Application
/// Interfaces". The bottom nav was fixed at 5 tabs, identical for every
/// role (no scrolling, no per-role tab set): Home, Store, Marriage, City
/// Guide, Settings. Everything that used to be a separate tab (Kafala,
/// Contribute, Volunteer, Services) is reached from Home's existing
/// quick-action tiles/hero buttons (widgets/dashboard.dart), which push
/// those screens directly instead of switching to a tab index that no
/// longer exists. Alerts and Messages moved to a persistent top bar shown on
/// every tab.
///
/// "Ninth: Improve the Home Interface Design" then reinstated a profile
/// photo in the top-right, opening the account hub (ProfileMenuScreen)
/// rather than a tab.
///
/// The owner's later ask — "remove settings tab and move them to profile" —
/// removed the 5th tab entirely: the bottom nav is now 4 tabs (Home, Store,
/// Marriage, City Guide) and every destination the Settings tab offered
/// (Control Settings and Preferences, Volunteer With Us, Task Verification,
/// Our Partners, receipts, share, Our Humanitarian Work, clear cache) moved
/// into ProfileMenuScreen alongside the account items it already owned. See
/// profile_menu_screen.dart and widgets/settings_section.dart (now a shared
/// widget toolkit, not a tab) for the destinations themselves.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;

  // Drives the tab-switch fade (see [_animateTabSwitch]). One controller,
  // reused across every switch — a fresh AnimationController per tap would
  // work too, but this way there is nothing to create or dispose beyond the
  // one instance this State already owns for its whole lifetime.
  late final AnimationController _tabFadeController = AnimationController(
    vsync: this,
    duration: AppMotion.snapDuration,
    value: 1, // starts fully visible — nothing to fade in on first build.
  );
  late final Animation<double> _tabFadeAnimation = CurvedAnimation(
    parent: _tabFadeController,
    curve: Curves.easeOut,
  );

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
    //
    // OPOS #26423 — except for a guest. The server gives a guest session an
    // empty chat list and refuses thread messages (OPOS #26354), so a guest's
    // ChatController would fetch /chats on start and poll it every 5 seconds
    // for the whole session, for a badge that can never show anything. The
    // top bar shows a guest's Messages door with no badge instead (see
    // _TopBarActions), and Messages shows a guest a sign-in prompt.
    if (!isGuestMode() && !Get.isRegistered<ChatController>()) {
      Get.put(ChatController());
    }
    _currentIndex = dashboardTabNotifier.value.clamp(0, _sections.length - 1);
    dashboardTabNotifier.addListener(_handleDashboardTabChange);
  }

  @override
  void dispose() {
    dashboardTabNotifier.removeListener(_handleDashboardTabChange);
    _tabFadeController.dispose();
    super.dispose();
  }

  /// Replays the tab-switch fade from the top, unless Reduce Motion is on —
  /// in which case it jumps straight to fully visible instead of animating.
  void _animateTabSwitch() {
    if (AppMotion.reduced(context)) {
      _tabFadeController.value = 1;
      return;
    }
    _tabFadeController
      ..value = 0
      ..forward();
  }

  void _handleDashboardTabChange() {
    final nextIndex = dashboardTabNotifier.value.clamp(0, _sections.length - 1);
    if (nextIndex == _currentIndex || !mounted) return;
    setState(() => _currentIndex = nextIndex);
    _animateTabSwitch();
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
      _animateTabSwitch();
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
    _animateTabSwitch();
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
            // Owner #16 — when staff make a registration field required, the
            // people who already signed up are PROMPTED, never blocked. This
            // renders literally nothing (SizedBox.shrink) unless this account
            // is actually missing a newly-required field and has not already
            // dismissed that exact prompt, so it costs the layout nothing on
            // every other launch. It sits ABOVE the tab body rather than
            // inside a tab because the fields are account-wide, not the
            // business of whichever tab happens to be open.
            const RequiredFieldsPrompt(),
            Expanded(
              // The nav bar used to be a sequential Column child below this
              // Expanded — flow layout, never overlapping content. The
              // floating-glass redesign needs it to float ON TOP of the tab
              // content instead: its BackdropFilter blurs whatever is
              // directly behind it, and with the old flow layout that was
              // always just the Scaffold's flat background, never the
              // scrolled content — so the "glass" never actually showed
              // anything through itself. A Stack is what makes the blur
              // real.
              child: Stack(
                children: [
                  // Each tab's screen wraps itself in a SafeArea, because
                  // each is also reachable as a standalone pushed route.
                  // Inside this Stack both of its insets are already
                  // accounted for, so both must be stripped or they get
                  // applied twice:
                  //
                  //   TOP — the DashboardTopBar above reserves the status
                  //   bar. Without removeTop the gap appears twice, once
                  //   under the status bar and again under the top bar.
                  //
                  //   BOTTOM — now that the nav bar floats over the content
                  //   instead of reserving space for itself, the content
                  //   fills the FULL remaining height on purpose (that's
                  //   what lets it scroll under the glass and show through
                  //   it) — removeBottom just strips the device's own
                  //   home-indicator/gesture-bar inset, which the floating
                  //   pill already clears itself via its own clearance
                  //   calculation, independent of MediaQuery.
                  //
                  //   Delegated to KeyboardSafeTabBody rather than an inline
                  //   `MediaQuery.removePadding(context: context, ...)`:
                  //   that inline form used to read `context` from THIS
                  //   build method — which sits ABOVE the Scaffold being
                  //   built here — so `MediaQuery.of` resolved to the
                  //   app-root MediaQuery instead of this Scaffold body's
                  //   own (already `viewInsets`-stripped) one. The raw,
                  //   un-stripped keyboard inset then rode through to every
                  //   tab, whose own nested Scaffold (kept for standalone-
                  //   route reuse) subtracted it a SECOND time — crushing
                  //   the active tab to a sliver the moment its keyboard
                  //   opened. On Marketplace this read as a blank box
                  //   covering the screen. See keyboard_safe_tab_body.dart
                  //   for the full account.
                  Positioned.fill(
                    child: KeyboardSafeTabBody(
                      child: FadeTransition(
                        // One controller, reused for every switch, fading
                        // the CURRENTLY shown tab in — not an AnimatedSwitcher
                        // keyed per tab, which would remount (and lose the
                        // state of) whichever section it swapped away from.
                        // IndexedStack keeps every section resident on
                        // purpose; this only animates what's already
                        // painted.
                        opacity: _tabFadeAnimation,
                        child: IndexedStack(
                          index: _currentIndex,
                          children: _sections,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _CompactBottomNavBar(
                      currentIndex: _currentIndex,
                      destinations: _destinations,
                      onSelected: _onTabSelected,
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

/// A floating "glass" pill tab bar — chosen from three previewed concepts
/// (floating glass / soft capsule / minimal dot) over the stock
/// BottomNavigationBar, which hardcodes a ~56pt base height with no
/// constructor param to shrink it.
///
/// The active tab renders as a solid accent-filled capsule with icon+label;
/// the rest are icon-only in muted colour, so the row reads as one floating
/// object rather than a bar spanning the screen edge to edge.
class _CompactBottomNavBar extends StatelessWidget {
  const _CompactBottomNavBar({
    required this.currentIndex,
    required this.destinations,
    required this.onSelected,
  });

  final int currentIndex;
  final List<NavDestination> destinations;
  final ValueChanged<int> onSelected;

  // Taller than the old flat bar (52) — the active capsule needs room for
  // its own vertical padding around icon+label without the pill touching the
  // rounded ends of the outer shape.
  static const double _barHeight = 64;
  static const double _horizontalMargin = 16;
  static const double _radius = 32;

  /// Floor for the gap below the pill on a device that reports no bottom
  /// inset at all (most Android phones with 3-button nav).
  static const double _minClearance = 6;

  /// The pill floats clear of the edge on every platform — unlike the old
  /// flush bar, it never sits directly on the home indicator / gesture pill,
  /// so there is no corner-mask clipping risk to guard against here (that
  /// risk only applied to labels pinned flush against the screen's rounded
  /// corners). A flat clearance on top of the device's own inset, read from
  /// [View] rather than MediaQuery — an ancestor Scaffold can consume the
  /// padding, after which MediaQuery reports 0 — is enough on both
  /// platforms; Android's opaque nav bar and iOS's translucent indicator are
  /// both cleared by their own real inset plus the same 8pt margin.
  static double _clearanceFor(BuildContext context) {
    final view = View.of(context);
    final inset = view.viewPadding.bottom / view.devicePixelRatio;
    return (inset <= 0 ? _minClearance : inset) + 8;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _horizontalMargin,
        0,
        _horizontalMargin,
        _clearanceFor(context),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: _barHeight,
            decoration: BoxDecoration(
              // Translucent over the blur, not opaque — that's what reads as
              // "glass" rather than just a rounded flat bar. `navBarSurface`
              // already adapts to light/dark; a low alpha is what makes the
              // page's own content show through the blur behind it — this
              // only reads as GLASS now that the bar floats over the tab
              // content in a Stack instead of sitting below it in normal
              // flow (see the build method's Positioned.fill/Positioned
              // split). At the old 0.72 there was nothing to see through in
              // either layout; 0.45 is low enough for scrolled content to
              // stay visible, softened by the blur, without the icons and
              // the active pill losing contrast against busy content.
              color: AppThemeConfig.navBarSurface(context).withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(_radius),
              border: Border.all(
                color: AppThemeConfig.borderStrong(context).withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppThemeConfig.shadow(context),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _SlidingPillNavRow(
              currentIndex: currentIndex,
              destinations: destinations,
              onSelected: onSelected,
            ),
          ),
        ),
      ),
    );
  }
}

/// The row inside the glass bar: one accent pill that TRAVELS between tabs
/// rather than each tab drawing its own, plus the icon/label row on top of
/// it.
///
/// Requested explicitly over the previous per-tab pop-in pill: switching
/// tabs should read as the same pill sliding to its new spot (with a slight
/// overshoot before it settles), not as one pill disappearing while a new
/// one appears elsewhere.
class _SlidingPillNavRow extends StatefulWidget {
  const _SlidingPillNavRow({
    required this.currentIndex,
    required this.destinations,
    required this.onSelected,
  });

  final int currentIndex;
  final List<NavDestination> destinations;
  final ValueChanged<int> onSelected;

  @override
  State<_SlidingPillNavRow> createState() => _SlidingPillNavRowState();
}

class _SlidingPillNavRowState extends State<_SlidingPillNavRow>
    with SingleTickerProviderStateMixin {
  // A dedicated spring, not AppMotion.snap/settle/carry: those three are
  // deliberately curated so overshoot ([AppMotion.carry]) only ever
  // represents a gesture's own carried momentum, never a tap. This pill's
  // bounce was asked for explicitly as its own signature motion, so it gets
  // its own token instead of overloading `carry`'s meaning. Damping just
  // under 1 for a bounce small enough to read as "settling into place", not
  // a wobble.
  static final AppSpring _pillSpring = AppSpring(
    name: 'navPillSlide',
    dampingRatio: 0.86,
    response: 0.38,
  );

  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
    value: widget.currentIndex.toDouble(),
  );

  @override
  void didUpdateWidget(covariant _SlidingPillNavRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _slideTo(widget.currentIndex.toDouble());
    }
  }

  void _slideTo(double target) {
    if (AppMotion.reduced(context)) {
      _controller.value = target;
      return;
    }
    // Carries whatever velocity the controller already has — if a second
    // tap lands mid-slide, the pill re-targets from where it actually is
    // instead of snapping back to a standstill first.
    _controller.animateWith(
      _pillSpring.simulate(
        from: _controller.value,
        to: target,
        velocity: _controller.velocity,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final slotWidth = constraints.maxWidth / widget.destinations.length;
            final clampedValue = _controller.value.clamp(
              0.0,
              (widget.destinations.length - 1).toDouble(),
            );
            // THE BUG THIS FIXES: this was `Positioned(left: ...)` — a raw
            // physical-LTR offset computed from the tab's INDEX. The icon
            // Row below already reverses itself for RTL for free (Flutter's
            // own Directionality-aware layout), so under Arabic Home (index
            // 0) actually renders on the right — but the pill, still
            // measuring "index 0" as physical pixel 0 from the left, kept
            // landing under whichever tab RTL had pushed to that physical
            // spot instead (City Guide, the last index). The pill and the
            // tab it was supposed to be sitting on were on OPPOSITE sides of
            // the bar. `PositionedDirectional`'s `start` resolves against
            // the same ambient Directionality the Row uses, so index 0 is
            // "start" in both — they can't disagree again.
            final pillStart = clampedValue * slotWidth;
            return Stack(
              children: [
                PositionedDirectional(
                  start: pillStart + 4,
                  top: 4,
                  bottom: 4,
                  width: slotWidth - 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppThemeConfig.accent(context),
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < widget.destinations.length; i++)
                      Expanded(
                        child: _NavTapTarget(
                          destination: widget.destinations[i],
                          // How close the travelling pill currently is to
                          // THIS tab — 0 when it's sitting right on it, 1+
                          // once it's a full slot away. Driving color/label
                          // off this (rather than a plain selected bool)
                          // is what makes the icon and label cross-fade in
                          // step with the pill's own motion instead of
                          // popping the instant a tap lands.
                          distance: (_controller.value - i).abs(),
                          onTap: () => widget.onSelected(i),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _NavTapTarget extends StatefulWidget {
  const _NavTapTarget({
    required this.destination,
    required this.distance,
    required this.onTap,
  });

  final NavDestination destination;
  final double distance;
  final VoidCallback onTap;

  @override
  State<_NavTapTarget> createState() => _NavTapTargetState();
}

class _NavTapTargetState extends State<_NavTapTarget> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    // A continuous blend, not a selected/unselected switch — see the
    // `distance` doc on _SlidingPillNavRow. Clamped because the spring can
    // briefly overshoot past the target tab (that's the bounce), which
    // would otherwise push these past their 0..1 range.
    final onPill = (1 - widget.distance).clamp(0.0, 1.0);
    final color = Color.lerp(
      AppThemeConfig.mutedText(context),
      AppThemeConfig.onAccent(context),
      onPill,
    )!;
    // Client report — a tab's name used to only exist once the pill had
    // (mostly) arrived on it; every other tab was an icon with no label at
    // all, so the bar only ever named the ONE tab you were already on. The
    // label is now always on screen for every tab — this just grows and
    // brightens as the pill approaches instead of appearing from nothing,
    // so the pill still reads as "arriving" without the bar going mute for
    // the other three tabs.
    final labelFontSize = 9.0 + onPill * 3.0;

    // GestureDetector, not InkWell/Material — a ripple spreading from the
    // tap point reads as generic Material chrome against a custom glass
    // pill that already moves and bounces on its own; this tab bar's own
    // feedback is the icon dipping under the finger instead.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      child: Center(
        child: AnimatedScale(
          scale: _pressed ? 0.86 : 1.0,
          duration: AppMotion.resolve(context, AppMotion.snapDuration),
          curve: AppMotion.resolveCurve(context, Curves.easeOut),
          child: Padding(
            // Fixed padding on every side now that every tab always carries
            // a label below its icon — there's no icon-only slot left to
            // give the extra room to, unlike the old horizontal layout.
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 6,
              vertical: 8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The outline and filled glyphs are two different SVG-ish
                // paths, not one shape with a colour change — swapping them
                // outright at the distance<0.5 cutoff popped visibly.
                // Stacking both and cross-fading their opacity is what
                // makes the swap read as one icon morphing weight, not two
                // icons taking turns.
                SizedBox(
                  width: 21,
                  height: 21,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: (1 - onPill).clamp(0.0, 1.0),
                        child: Icon(
                          widget.destination.icon,
                          color: color,
                          size: 21,
                        ),
                      ),
                      Opacity(
                        opacity: onPill,
                        child: Icon(
                          widget.destination.activeIcon,
                          color: color,
                          size: 21,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.destination.label.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: labelFontSize,
                    fontWeight: FontWeight.w700,
                    color: color,
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
    // THE BUG THIS FIXES (round 2): the previous fix correctly sized the
    // inner Stack to the full 42px padded circle, so `Positioned(top: -4,
    // right: -4)` now measures the badge against the real circle edge — but
    // that Stack was still the DIRECT child of `Material(shape:
    // CircleBorder(), clipBehavior: Clip.antiAlias)`, which clips everything
    // painted inside it to that same circle. A badge deliberately sitting
    // AT the edge is half outside the circle by design (that's what "on the
    // edge" means), so the circular clip mask cut away most of it — only
    // the sliver still inside the circle survived. The clip has to stop at
    // the button's own surface (icon + ripple), so the badge now lives in
    // an OUTER Stack, as a sibling of the clipped Material rather than a
    // descendant of it.
    return Semantics(
      button: true,
      label: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
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
                child: Icon(
                  icon,
                  size: 22,
                  color: AppThemeConfig.text(context),
                ),
              ),
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              top: -4,
              right: -4,
              child: IgnorePointer(
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
            ),
        ],
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

  /// The Messages door, badged with [unread] conversations needing attention.
  Widget _messagesButton({required int unread}) => _TopBarIconButton(
    icon: Icons.forum_outlined,
    badgeCount: unread,
    tooltip: 'Messages'.tr,
    onTap: () => Get.to(() => const MessagesScreen()),
  );

  @override
  Widget build(BuildContext context) {
    final notifications = Get.find<NotificationsController>();
    // Null for a guest: DashboardScreen registers no ChatController for one
    // (OPOS #26423), so there is no chat unread count and Get.find would
    // throw. The registration is checked rather than assumed.
    final chats = Get.isRegistered<ChatController>()
        ? Get.find<ChatController>()
        : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // THE BUG THIS FIXES: only the EXPANDED row got the `top: 6`
        // padding below (added so the icons' badges have headroom to
        // overhang without being clipped). The collapsed toggle button
        // never got that same padding, so it was 6px SHORTER than the
        // expanded state. AnimatedSize below reports its real height either
        // way, and this whole Row sits inside DashboardTopBar's own Row —
        // so opening the cluster grew this Row's height by that 6px, which
        // grew the WHOLE top bar, which pushed the tab body (title and
        // everything in it) down by the same 6px; closing it shrank
        // everything back up. Reported live as "the title moves down and
        // back up when I open/close the ⋯ menu." Giving the toggle the
        // identical top padding means both states measure the same height
        // and the bar never resizes at all.
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Obx(() {
            // Summed, not "any unread": a single dot would say something is
            // waiting without saying how much, and both counts are already
            // rendered as numbers when expanded.
            final pending =
                notifications.unreadCount + (chats?.totalUnread ?? 0);
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
        ),
        // Events tab's Saved door — client feedback: it was rendered by
        // the tab's OWN AppScreen header (marriage_hub_screen.dart's
        // `trailing:`), one row below this bar, since a tab's in-page
        // header is a SEPARATE widget from this persistent one. Moved
        // here, beside the ⋯ toggle rather than into the toggle's own
        // collapsible cluster, so it reads as a peer of ⋯ and stays
        // visible whether or not that cluster is open — matching "next to
        // the three dots, not below it." Same top: 6 padding as the toggle
        // for the same reason (see the comment above it): a control this
        // bar always shows must measure the same height as the toggle, or
        // opening/closing the cluster would resize the whole bar again.
        if (tabIndex == DashboardTopBar._marriageIndex) ...[
          const SizedBox(width: DashboardTopBar._gap),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _TopBarIconButton(
              icon: Icons.bookmark_rounded,
              badgeCount: 0,
              tooltip: 'Saved'.tr,
              onTap: () =>
                  Get.to(() => const MarriageSavedScreen(api: ModuleApi())),
            ),
          ),
        ],
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
                      // THE BUG THIS FIXES: this ClipRect clips exactly to
                      // AnimatedSize's measured content — the Row below, at
                      // its own natural height. _TopBarIconButton's badge
                      // deliberately sits partway OUTSIDE its button's
                      // circle (top: -4) so it lands on the circle's edge,
                      // same as the already-fixed "•••" button. That badge
                      // was fine standing alone, but here it is a child of
                      // this Row, whose own top edge sits at y=0 of exactly
                      // what ClipRect clips to — so the badge's -4px
                      // overhang above that had nowhere to go and was cut
                      // off. A few points of top padding gives the clipped
                      // region that headroom back; `crossAxisAlignment:
                      // start` keeps every icon pinned to the padded top
                      // instead of drifting if one child is ever taller.
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                            // Kept for a guest too, because Messages is where
                            // support is reached from. A guest's door has no
                            // badge and no Obx: without a ChatController there is
                            // nothing to observe, and GetX throws on an Obx that
                            // reads no observable.
                            if (chats == null)
                              _messagesButton(unread: 0)
                            else
                              Obx(
                                () =>
                                    _messagesButton(unread: chats.totalUnread),
                              ),
                            const SizedBox(width: DashboardTopBar._gap),
                            // "Ninth: Improve the Home Interface Design" — the profile photo
                            // sits top-right and opens the account hub.
                            const _TopBarProfileAvatar(),
                          ],
                        ),
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

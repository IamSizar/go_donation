// AppMainMenuButton — the way back to the main menu, from anywhere.
//
// WHY THIS WIDGET EXISTS (J7)
// The client asked for "a Menu button on every app page and a Back button on
// every page and section — بحيث يمكن للمستخدم الوصول إلى القائمة الرئيسية في
// أي وقت". Back was already unified: AppScreen draws one whenever the route can
// pop. The menu half existed nowhere at all — `openDrawer`, `endDrawer` and
// `Drawer(` returned zero hits across the entire app — so from a screen three
// pushes deep, returning to the main menu meant pressing Back three times and
// hoping you had counted right.
//
// WHAT "THE MAIN MENU" IS IN THIS APP
// There is no drawer, and adding one would fight the design: the main menu here
// is the dashboard — AppRoutes.home, the five-tab screen that everything else
// is pushed on top of. So this button unwinds the stack back to it instead of
// sliding a panel out. The glyph is still the familiar ☰, because that is what
// "زر القائمة" means to the person holding the phone; what changes is that it
// takes you to the menu rather than overlaying one.
//
// WHY IT POPS RATHER THAN PUSHING OR REPLACING
// `Get.offAllNamed(home)` would also land on the dashboard, but it DESTROYS the
// stack — including any route the user might reasonably expect Back to return
// them to, and including routes that are not the dashboard at all (the sign-in
// and registration flows are their own roots). Popping to the first route is
// the honest operation: it goes as far up as the current flow actually goes and
// can never leave the navigator empty or invent a destination that was not
// already there.
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/core/widgets/app_pressable.dart';

/// Unwinds to the root of the current navigation stack and selects the Home
/// tab, so the user lands on the main menu rather than on whichever tab they
/// happened to leave selected.
///
/// Safe on any route: `popUntil(isFirst)` stops at the root instead of emptying
/// the navigator, so calling it from a screen whose root is NOT the dashboard
/// (registration, sign-in) returns the user to the top of that flow rather than
/// throwing them somewhere they never were.
void goToMainMenu(BuildContext context) {
  // Set the tab BEFORE popping: DashboardScreen listens to this notifier, so
  // by the time it is on screen again it is already showing Home.
  dashboardTabNotifier.value = 0;
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// The ☰ control. Sized and coloured to sit next to [AppScreen]'s back arrow,
/// and usable inside a stock `AppBar`'s `actions:` for the handful of screens
/// that still build their own chrome.
class AppMainMenuButton extends StatelessWidget {
  const AppMainMenuButton({super.key, this.color});

  /// Overrides the glyph colour. Needed by screens whose own AppBar sits on a
  /// coloured or transparent background; null takes the theme's ink.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final label = 'Main menu'.tr;
    return AppPressable(
      onTap: () => goToMainMenu(context),
      semanticLabel: label,
      child: Tooltip(
        message: label,
        child: Padding(
          // Keeps the glyph off the screen edge inside an AppBar's actions
          // list, where there is no gutter of its own.
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpace.xs,
          ),
          child: Icon(
            Icons.menu_rounded,
            size: 20,
            color: color ?? AppColors.of(context).ink,
          ),
        ),
      ),
    );
  }
}

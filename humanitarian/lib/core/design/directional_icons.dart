// Direction-aware icons.
//
// WHAT THIS FILE IS FOR — AND THE MISTAKE IT NOW EXISTS TO PREVENT
//
// This file originally branched on Directionality and swapped each arrow by
// hand, on the belief that Flutter does not mirror Material's directional
// glyphs. That belief is WRONG. Every arrow and chevron this app uses carries
// `matchTextDirection: true`, so Flutter already flips them under RTL:
//
//   arrow_forward_ios_rounded    true      arrow_forward_rounded   true
//   arrow_back_ios_rounded       true      arrow_back_rounded      true
//   arrow_back_ios_new_rounded   true      arrow_forward           true
//   chevron_right_rounded        true      arrow_back              true
//   chevron_left_rounded         true
//
// (Read off the real IconData at runtime, not from the SDK source — the
// declarations are easy to misread.)
//
// Swapping a self-mirroring icon by hand DOUBLE-mirrors it, so it points the
// wrong way. That is strictly worse than doing nothing, and it is invisible in
// the LTR build most development happens in. Three of this app's four
// languages are right-to-left, so it lands on the majority of its users.
//
// So this file no longer branches at all. It survives as a naming layer: call
// sites say "forward" rather than naming a physical direction, which is what
// makes the intent reviewable — and this header records why adding a
// Directionality check back in would be a regression.
//
// test/design/directional_icons_test.dart asserts both halves: that each icon
// still self-mirrors, and that these accessors return the SAME glyph in both
// directions. If the SDK ever drops matchTextDirection from one of them, the
// first assertion fails and tells you to start branching for that icon only.
//
// USAGE
//   Icon(AppIcons.forward(context))    // "next", disclosure, continue
//   Icon(AppIcons.back(context))       // "previous", dismiss
import 'package:flutter/material.dart';

abstract final class AppIcons {
  /// Points the way navigation advances: right in LTR, left in RTL.
  ///
  /// Use for disclosure chevrons on list rows, "see all" affordances, and
  /// continue/next buttons. Flutter mirrors it; do not branch here.
  static IconData forward(BuildContext context) =>
      Icons.arrow_forward_ios_rounded;

  /// The chunkier non-iOS-style variant of [forward], for buttons rather than
  /// list rows.
  static IconData forwardSolid(BuildContext context) =>
      Icons.arrow_forward_rounded;

  /// Points the way navigation retreats: left in LTR, right in RTL.
  static IconData back(BuildContext context) =>
      Icons.arrow_back_ios_new_rounded;

  /// The chunkier variant of [back].
  static IconData backSolid(BuildContext context) => Icons.arrow_back_rounded;

  /// A large disclosure chevron, as used at the end of a tappable row.
  static IconData chevronForward(BuildContext context) =>
      Icons.chevron_right_rounded;
}

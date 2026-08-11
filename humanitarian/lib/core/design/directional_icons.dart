// Direction-aware icons.
//
// WHY THIS FILE EXISTS
// Flutter does not mirror `Icons.arrow_forward` under RTL. The icon font has a
// `matchTextDirection` flag, but the Material arrow and chevron glyphs are not
// declared with it, so a right-pointing chevron keeps pointing right in Arabic
// — where "forward" is to the LEFT. An audit of this app found 27 arrow and
// chevron usages and only 3 that checked direction.
//
// That matters more here than in most apps: three of the four supported
// languages (ar, ckb, kmr) are right-to-left, so the un-mirrored case is the
// majority case, not the edge case.
//
// Use these instead of naming a physical direction:
//
//   Icon(AppIcons.forward(context))    // "next", disclosure, continue
//   Icon(AppIcons.back(context))       // "previous", dismiss
import 'package:flutter/material.dart';

abstract final class AppIcons {
  /// Points the way navigation advances: right in LTR, left in RTL.
  ///
  /// Use for disclosure chevrons on list rows, "see all" affordances, and
  /// continue/next buttons.
  static IconData forward(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl
      ? Icons.arrow_back_ios_rounded
      : Icons.arrow_forward_ios_rounded;

  /// The chunkier non-iOS-style variant of [forward], for buttons rather than
  /// list rows.
  static IconData forwardSolid(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl
      ? Icons.arrow_back_rounded
      : Icons.arrow_forward_rounded;

  /// Points the way navigation retreats: left in LTR, right in RTL.
  static IconData back(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl
      ? Icons.arrow_forward_ios_rounded
      : Icons.arrow_back_ios_new_rounded;

  /// The chunkier variant of [back].
  static IconData backSolid(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl
      ? Icons.arrow_forward_rounded
      : Icons.arrow_back_rounded;

  /// A large disclosure chevron, as used at the end of a tappable row.
  static IconData chevronForward(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl
      ? Icons.chevron_left_rounded
      : Icons.chevron_right_rounded;
}

// Reads properties off a tree that has actually been PAINTED, not off tokens.
//
// WHY THIS FILE EXISTS
// Three of this project's guards measure the design system from the outside:
// test/design/contrast_test.dart measures the token pairs, and
// test/localization/arabic_map_purity_test.dart measures the translation maps.
// Both are property tests over data, and both are blind to the same mistake —
// a correct token used on the wrong surface, or a correct map that a screen
// never asks. Every contrast defect found on this app so far (1.04:1, 1.2:1,
// 2.25:1) was made of individually-valid palette colours, and every English
// leak was a `.tr` on a key nobody had added.
//
// So this file walks the RENDERED tree instead. It answers three questions
// about whatever a test has just pumped:
//
//   • [collectTexts] / [collectIcons] — what is on screen, in what colour, on
//     what background (composited through every translucent layer above it).
//   • [latinResidue] — is there English on the Arabic screen.
//   • [contrastFailures] — is any pair below its WCAG floor.
//
// It is deliberately screen-agnostic: the beneficiary and volunteer roles are
// its first callers, but nothing here knows about them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/core/design/contrast.dart';

// ─── What was on screen ───

/// One [Text] as it was actually rendered.
class RenderedText {
  const RenderedText({
    required this.data,
    required this.color,
    required this.background,
    required this.fontSize,
    required this.fontWeight,
  });

  /// The exact string the user reads.
  final String data;

  /// The ink, already composited onto [background] if it was translucent.
  final Color color;

  /// Every painted layer above this text, flattened to one opaque colour.
  final Color background;

  final double fontSize;
  final FontWeight fontWeight;

  /// WCAG's floor for THIS text: 3.0 once it is large, 4.5 otherwise.
  ///
  /// "Large" is 18.66px bold or 24px regular — WCAG states it in points
  /// (14pt/18pt) and Flutter's logical pixels are the CSS px those convert to.
  /// Getting this wrong in either direction matters: a blanket 4.5 would fail
  /// the hero headline that WCAG passes, and a blanket 3.0 would let a 12px
  /// caption through at a ratio nobody can read.
  double get floor {
    final isBold = fontWeight.value >= FontWeight.w700.value;
    if (fontSize >= 24 || (isBold && fontSize >= 18.66)) return 3.0;
    return 4.5;
  }

  @override
  String toString() =>
      '"$data" ${_hex(color)} on ${_hex(background)} '
      '(${fontSize.toStringAsFixed(1)}px w${fontWeight.value})';
}

/// One [Icon] as it was actually rendered.
class RenderedIcon {
  const RenderedIcon({
    required this.icon,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final Color color;
  final Color background;

  @override
  String toString() =>
      'icon ${icon.codePoint} ${_hex(color)} on ${_hex(background)}';
}

String _hex(Color c) =>
    '#${(c.a * 255).round().toRadixString(16).padLeft(2, '0')}'
            '${(c.r * 255).round().toRadixString(16).padLeft(2, '0')}'
            '${(c.g * 255).round().toRadixString(16).padLeft(2, '0')}'
            '${(c.b * 255).round().toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();

/// The colour a widget PAINTS behind its children, or null when it paints none.
///
/// Only the four that actually appear under this app's text. `Container` is not
/// listed because it is a composition: with `color:` it builds a [ColoredBox]
/// and with `decoration:` a [DecoratedBox], and both of those are caught here.
Color? _paintedColor(Widget widget) {
  if (widget is ColoredBox) return widget.color;
  if (widget is DecoratedBox) {
    final decoration = widget.decoration;
    if (decoration is BoxDecoration) return decoration.color;
    if (decoration is ShapeDecoration) return decoration.color;
    return null;
  }
  if (widget is Material) return widget.color;
  if (widget is Card) return widget.color;
  return null;
}

/// Every painted layer between [element] and the window, flattened to one
/// opaque colour.
///
/// Walks UP collecting fills, stopping at the first opaque one — anything above
/// that is hidden by definition — then composites back DOWN so translucent
/// washes land on what is really under them. This is the whole reason the file
/// exists: `onAccent.withValues(alpha: 0.14)` is not a colour anyone can
/// measure until it is composited onto the accent it sits on.
Color effectiveBackground(Element element, Color fallback) {
  final layers = <Color>[]; // nearest first
  element.visitAncestorElements((ancestor) {
    final color = _paintedColor(ancestor.widget);
    if (color == null || color.a == 0) return true;
    layers.add(color);
    return color.a < 1.0; // keep climbing only while still see-through
  });

  var composited = layers.isNotEmpty && layers.last.a == 1.0
      ? layers.removeLast()
      : fallback;
  for (final layer in layers.reversed) {
    composited = Color.alphaBlend(layer, composited);
  }
  return composited;
}

/// Every [Text] currently in the tree, with its ink and background resolved.
///
/// [fallback] is the colour the window itself paints — used only when nothing
/// in the ancestry is opaque, which on a real screen means the scaffold.
List<RenderedText> collectTexts(
  WidgetTester tester, {
  required Color fallback,
}) {
  final out = <RenderedText>[];
  for (final element in find.byType(Text).evaluate()) {
    final widget = element.widget as Text;
    final data = widget.data;
    // `Text.rich` carries its string in `textSpan` instead; none of the screens
    // under test use it, and silently measuring nothing would be worse than
    // skipping it visibly, so it is skipped here and asserted nowhere.
    if (data == null || data.trim().isEmpty) continue;

    final inherited = DefaultTextStyle.of(element).style;
    final style = widget.style?.inherit ?? true
        ? inherited.merge(widget.style)
        : widget.style!;

    final background = effectiveBackground(element, fallback);
    final ink = style.color ?? inherited.color ?? const Color(0xFF000000);
    out.add(
      RenderedText(
        data: data,
        // A translucent ink is not measurable either — composite it first.
        color: ink.a >= 1.0 ? ink : Color.alphaBlend(ink, background),
        background: background,
        fontSize: style.fontSize ?? 14,
        fontWeight: style.fontWeight ?? FontWeight.w400,
      ),
    );
  }
  return out;
}

/// Every [Icon] currently in the tree that is carrying INFORMATION.
///
/// Glyphs painted at under 50% opacity are excluded, deliberately. WCAG 1.4.11
/// applies to non-text content that conveys meaning and exempts what is purely
/// decorative, and on this app the two are told apart by exactly that: the
/// hero's 170px watermark is drawn at alpha 0.07 precisely so it reads as
/// texture. Measuring it would report a "failure" whose only fix is to make the
/// decoration louder than the text on top of it.
List<RenderedIcon> collectIcons(
  WidgetTester tester, {
  required Color fallback,
}) {
  final out = <RenderedIcon>[];
  for (final element in find.byType(Icon).evaluate()) {
    final widget = element.widget as Icon;
    final icon = widget.icon;
    if (icon == null) continue;

    final theme = IconTheme.of(element);
    final color = widget.color ?? theme.color ?? const Color(0xFF000000);
    final opacity = color.a * (widget.color == null ? (theme.opacity ?? 1) : 1);
    if (opacity < 0.5) continue;

    final background = effectiveBackground(element, fallback);
    out.add(
      RenderedIcon(
        icon: icon,
        color: color.a >= 1.0 ? color : Color.alphaBlend(color, background),
        background: background,
      ),
    );
  }
  return out;
}

// ─── Is there English on the Arabic screen ───

/// Latin tokens that are correct INSIDE an Arabic string.
///
/// Mirrors `latinIsIntended` in test/localization/arabic_map_purity_test.dart,
/// which guards the same property one layer down (the map, rather than the
/// screen). Kept as its own list rather than imported because the screen can
/// legitimately show things the map never contains — a governorate name that
/// arrived from the server, for instance — and merging the two lists would let
/// a screen-only exception silently widen the map's guard.
const kLatinIsIntendedOnScreen = <String>[
  'Google', // brand — the sign-in button reads "المتابعة باستخدام Google"
  'Firebase', // brand
  'IQD', // ISO 4217 code, printed beside the Arabic د.ع
  'GPS', // used as an initialism in Arabic too
  'FIB', // First Iraqi Bank's own Latin initialism
  'VIP', // marriage subscription tier
];

/// The Latin letters left in [value] once every allowed token is removed.
///
/// An empty result means the string is clean; anything left is English that
/// reached an Arabic reader.
///
/// Keeping ONLY the Latin letters, rather than deleting everything that is
/// permitted, is what makes this robust. The alternative — strip the digits,
/// then the punctuation, then the bidi marks, then the Arabic comma — is a list
/// that is wrong the first time a screen prints a character nobody enumerated,
/// and it needs zero-width control characters written into a regex where no
/// reviewer can see them. Arabic script, digits in any numeral system,
/// punctuation and invisible marks are all, definitionally, not English.
///
/// The allowlist pass must come FIRST, while the brand tokens are still whole —
/// the same ordering bug arabic_map_purity_test hit and documents.
String latinResidue(String value) {
  var out = value;
  for (final token in kLatinIsIntendedOnScreen) {
    out = out.replaceAll(token, '');
  }
  return out.replaceAll(RegExp('[^A-Za-z]'), '');
}

/// True when [value] still contains Latin letters after [latinResidue].
bool leaksEnglish(String value) => latinResidue(value).isNotEmpty;

/// Rendered strings that look like an UNRESOLVED translation key.
///
/// GetX returns the key unchanged when no entry exists, silently, so a missing
/// entry does not fail anywhere — it just renders. In English that is invisible
/// unless the key happens to be a machine token, which most of this app's are:
/// `reg_volunteer_section`, `needs_changes`, `case_status_open`. Those shapes
/// are what this looks for, so an English pump catches the same missing entry
/// that an Arabic pump catches as a leak.
///
/// Deliberately narrow: `snake_case` or a bare `lowercase_word` with no space.
/// A missing entry whose key is an ordinary English sentence is invisible here
/// and is caught by the Arabic pump instead — the two checks cover each other.
List<String> unresolvedKeyShapes(Iterable<String> rendered) {
  final tokenish = RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+)+$');
  return rendered.where((s) => tokenish.hasMatch(s.trim())).toSet().toList()
    ..sort();
}

// ─── Is any pair below its floor ───

/// WCAG floor for meaningful non-text content (1.4.11).
const double kNonTextFloor = 3.0;

/// Every text whose ink misses its own [RenderedText.floor], described.
List<String> contrastFailures(Iterable<RenderedText> texts) {
  final out = <String>[];
  for (final text in texts) {
    final ratio = contrastRatio(text.color, text.background);
    if (ratio + 0.005 < text.floor) {
      out.add('${ratio.toStringAsFixed(2)}:1 (needs ${text.floor}) — $text');
    }
  }
  return out;
}

/// Every meaningful icon below [kNonTextFloor], described.
List<String> iconContrastFailures(Iterable<RenderedIcon> icons) {
  final out = <String>[];
  for (final icon in icons) {
    final ratio = contrastRatio(icon.color, icon.background);
    if (ratio + 0.005 < kNonTextFloor) {
      out.add('${ratio.toStringAsFixed(2)}:1 (needs $kNonTextFloor) — $icon');
    }
  }
  return out;
}

// ─── Driving the pump ───

/// Scrolls [tester]'s first scrollable to the end, running [onStep] at each
/// resting position INCLUDING the first.
///
/// Both role dashboards are `ListView`s, so everything below the fold is never
/// built — a test that only pumps measures the top ~870px and reports the rest
/// as clean. Dragging is upward only: the list sits under a [RefreshIndicator],
/// and a downward drag would trigger a refresh instead of scrolling.
/// Runs [body] with Flutter's error channel diverted, and returns the widget
/// CREATION LOCATIONS of every layout overflow it reported.
///
/// A location looks like `Row:file:///…/dashboard.dart:2337:17` — the identity
/// of the widget that overflowed, not the pixel count, because the count is a
/// property of the font and the identity is a property of the layout.
///
/// WHY THE ERROR CHANNEL HAS TO BE DIVERTED
/// `tester.takeException()` hands back the exception object, whose `toString`
/// is "A RenderFlex overflowed by 20 pixels on the right." — the same sentence
/// for every widget on the screen, which cannot be compared against anything.
/// The creation location lives on the FlutterErrorDetails, and the only way to
/// reach that is to be the handler.
///
/// The diversion is restored in a `finally`, and the reported errors are
/// returned rather than swallowed — a caller that ignores the result has hidden
/// a failure, so callers must assert on it.
Future<List<String>> captureOverflowLocations(
  Future<void> Function() body,
) async {
  final locations = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.toString();
    if (!text.contains('overflowed by')) {
      // Not a layout overflow. Hand it back to whoever was listening — usually
      // the test binding, which will fail the test, which is correct.
      previous?.call(details);
      return;
    }
    final match = RegExp(r'[A-Za-z_]+:file:///[^\s]+').firstMatch(text);
    locations.add(match?.group(0) ?? text.split('\n').first);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return locations;
}

/// The trailing `file.dart:line:col` of a creation location, for comparison
/// between two pumps of the same build.
String overflowSite(String location) => location.split('/').last;

Future<void> sweepScroll(
  WidgetTester tester,
  Future<void> Function() onStep, {
  double step = 400,
  int maxSteps = 40,
}) async {
  await onStep();
  final scrollable = find.byType(Scrollable).first;
  var previous = -1.0;
  for (var i = 0; i < maxSteps; i++) {
    final position = tester.state<ScrollableState>(scrollable).position;
    if (!position.hasContentDimensions ||
        position.pixels >= position.maxScrollExtent ||
        position.pixels == previous) {
      break;
    }
    previous = position.pixels;
    await tester.drag(scrollable, Offset(0, -step));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await onStep();
  }
}

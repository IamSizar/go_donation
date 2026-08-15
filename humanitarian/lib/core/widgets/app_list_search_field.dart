// A search box that belongs to ONE list.
//
// WHY THIS FILE EXISTS (J8)
// The client asked for in-app search "in the main menu, all sub-sections, and
// every page holding data or lists". The app had a global search box in the
// top bar and, of 44 list-bearing screens, exactly one list with a search of
// its own (the marriage profile search). Open الشركاء, أعمالنا, المتجر, دليل
// المدينة or مساهماتي and there was no way to look for a single row.
//
// WHAT THIS WIDGET IS AND IS NOT
// It is the INPUT only. It never filters anything itself, because the honest
// answer to "what does this search cover?" is different per list:
//
//   * Lists the server can search (`?q=`) hand the text back to their loader,
//     which re-fetches. The search then covers the whole table.
//   * Lists whose full set is genuinely already in memory filter locally.
//
// Deciding that per call site is deliberate. A search box that filters only
// the rows a paginated list happens to have loaded reads as a search of the
// catalogue and is not one — the user types a product they own and is told it
// does not exist. So this widget refuses to make that choice for anyone; each
// list wires [onChanged] to whichever of the two it can honestly do.
//
// DESIGN
//   * Debounced, so a server-backed list makes one request per pause rather
//     than one per keystroke.
//   * The clear button is part of the field, not a separate control: a filter
//     the user cannot see how to undo is how a list ends up looking empty.
//   * The return key reads "search" and dismisses the keyboard, and the
//     app-wide DismissKeyboardOnTap covers taps outside. Scrollables using
//     this field also set keyboardDismissBehavior: onDrag, so scrolling the
//     results puts the keyboard away.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/app_haptics.dart';
import 'package:flutter_application_1/core/design/tokens.dart';

class AppListSearchField extends StatefulWidget {
  const AppListSearchField({
    super.key,
    required this.onChanged,
    this.hintKey = 'search_title',
    this.debounce = const Duration(milliseconds: 350),
  });

  /// Called with the trimmed query after [debounce] of quiet, and immediately
  /// on submit or clear. An empty string means "no filter".
  final ValueChanged<String> onChanged;

  /// Translation key for the placeholder. Defaults to `search_title`, which
  /// exists in all four locales — en/ar/ckb/kmr — so no screen using this
  /// widget can render an English word on an Arabic page.
  final String hintKey;

  final Duration debounce;

  @override
  State<AppListSearchField> createState() => _AppListSearchFieldState();
}

class _AppListSearchFieldState extends State<AppListSearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;

  /// The last query actually emitted, so a debounce that fires on unchanged
  /// text (e.g. type a space, delete it) does not trigger a second request.
  String _emitted = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Emits [raw] trimmed, at most once per distinct value.
  void _emit(String raw) {
    final query = raw.trim();
    if (query == _emitted) return;
    _emitted = query;
    widget.onChanged(query);
  }

  void _onChanged(String raw) {
    _debounce?.cancel();
    _debounce = Timer(widget.debounce, () => _emit(raw));
    // Rebuild for the clear button, which only exists while there is text.
    setState(() {});
  }

  /// The return key: run it now rather than waiting out the debounce, and put
  /// the keyboard away so the results are not hidden behind it.
  void _onSubmitted(String raw) {
    _debounce?.cancel();
    FocusScope.of(context).unfocus();
    AppHaptics.selection();
    _emit(raw);
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    AppHaptics.selection();
    _emit('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final hasText = _controller.text.isNotEmpty;

    return TextField(
      controller: _controller,
      onChanged: _onChanged,
      onSubmitted: _onSubmitted,
      // A search box is free text, so the plain keyboard is the correct one —
      // and `search` is the right action label because there is nothing after
      // this field to move to.
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.search,
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      // Client-side rule: a query is a filter, not stored data, so the only
      // thing worth enforcing is a sane length. 80 characters is longer than
      // any name in the catalogue and stops a pasted wall of text becoming a
      // URL the server has to parse. The SERVER side of this input is the
      // parameterized bind every `?q=` handler already uses (`ILIKE $n`), so
      // no query — however long or however punctuated — can reach the SQL.
      maxLength: 80,
      style: TextStyle(fontSize: AppType.body, color: c.ink),
      decoration: InputDecoration(
        // maxLength draws a "0/80" counter by default; on a search box that
        // reads as a form field with a quota rather than as a filter.
        counterText: '',
        isDense: true,
        hintText: widget.hintKey.tr,
        prefixIcon: Icon(Icons.search_rounded, size: 20, color: c.inkTertiary),
        prefixIconConstraints: const BoxConstraints(minWidth: 34),
        suffixIcon: hasText
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: c.inkSecondary,
                // Named so a screen reader announces what the ✕ does rather
                // than reading out the icon.
                tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                onPressed: _clear,
                visualDensity: VisualDensity.compact,
              )
            : null,
      ),
      inputFormatters: [
        // Newlines cannot be typed into a single-line field but CAN be pasted,
        // and a pasted newline would travel into the query string.
        FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
      ],
    );
  }
}

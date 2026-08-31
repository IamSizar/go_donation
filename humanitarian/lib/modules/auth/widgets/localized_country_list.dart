// Shared country-list localization for CountryCodePicker.
//
// `CountryCodePicker` resolves each entry's name through its own
// `CountryLocalizations`, which reads the ambient `Localizations` locale in
// its BuildContext. Two things break that in this app: (1) the app never
// registers `CountryLocalizations.delegate` in `main.dart`, so the lookup
// always misses; and (2) even if it were registered, the picker opens its
// list via `showDialog(useRootNavigator: true)`, which mounts the dialog on
// the app's root Overlay — a sibling of the calling widget's position, not
// a descendant — so a local `Localizations.override` around the picker
// would never reach it. With the lookup missing, every name falls back to
// the package's raw data, which stores each country's own endonym
// ("Österreich", "中国大陆", "افغانستان", "Deutschland") rather than one
// consistent language — a mixed list in every locale, not just Arabic.
//
// The fix builds the list ourselves instead of trusting the ambient locale:
// start from the package's default `codes` and overlay every name from the
// ONE i18n file matching the app's current language, so the dialog always
// renders in a single language regardless of where it mounts. Resolved once
// per language and cached in [_localizedCountryListCache] (shared across
// every screen that mixes this in), so re-opening the picker — on any
// screen — never re-reads the asset.
//
// Extracted from `_LoginFormState` (login.dart) so guest_upgrade.dart could
// share the exact same fix instead of shipping its own copy with the bug
// still open.
import 'dart:convert'; // jsonDecode for the country picker's i18n files

import 'package:country_code_picker/country_code_picker.dart';
import 'package:flutter/material.dart'; // Icon/Icons/Colors/BoxDecoration for the shared dialog chrome
import 'package:flutter/services.dart'; // rootBundle
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:flutter_application_1/widgets/auth_ui.dart'; // authFieldBorder
import 'package:get/get.dart';

/// Mixin for any `State` that shows a `CountryCodePicker` and needs its
/// country names in one consistent language. Gives the mixing State:
///   - [countryList] to pass as `CountryCodePicker.countryList`
///   - [countryPickerKey] to pass as the picker's `key` (forces a rebuild
///     once the localized list resolves — see the comment on that getter)
///   - [loadCountryList] to call once from `initState`
mixin LocalizedCountryList<T extends StatefulWidget> on State<T> {
  /// Cached per language code ('en' | 'ar' | 'ku'), shared by every screen
  /// that mixes this in — resolved once per language for the whole app.
  static final Map<String, List<Map<String, String>>>
  _localizedCountryListCache = {};

  /// The country list overlaid onto the app's current language. Null until
  /// [loadCountryList] resolves at least once, in which case the picker
  /// falls back to the package's own (mixed-language) default for the one
  /// frame before it's ready.
  List<Map<String, String>>? countryList;

  /// The country list to pass to `CountryCodePicker.countryList` right now
  /// — the resolved one once loaded, the package default until then.
  List<Map<String, String>> get countryListOrDefault => countryList ?? codes;

  /// Maps the app's own language (see [AppLocaleService.contentVariant]) to
  /// the closest locale file `country_code_picker` ships. Kurdish has no
  /// dedicated file for either dialect the app distinguishes: the
  /// package's only Kurdish set is `ku.json` (Kurmanji, Latin script), so
  /// both Sorani (`ar_IQ`) and Badini (`ar_TR`) map to it — the closest
  /// available option, rather than leaving Kurdish users reading Arabic or
  /// English country names.
  String countryPickerLangCode() {
    return switch (AppLocaleService.contentVariant(Get.locale)) {
      'ar' => 'ar',
      'sorani' || 'badini' => 'ku',
      _ => 'en',
    };
  }

  /// `CountryCodePickerState` builds its `elements` (and the favourites
  /// shown in the dialog) once, inside `createState()`, from whatever
  /// `countryList` the widget was FIRST created with — it never recomputes
  /// them on `didUpdateWidget`. So swapping `countryList` in a later build
  /// (once [loadCountryList] resolves) would silently do nothing without a
  /// key: a keyed widget that changes key is torn down and rebuilt fresh,
  /// which is what actually gets the localized names into `elements`.
  Key get countryPickerKey => ValueKey(
    'country_picker_${countryList == null ? 'loading' : countryPickerLangCode()}',
  );

  /// Called inside the SAME `setState` that assigns the newly-loaded
  /// [countryList]. The keyed rebuild this triggers (see
  /// [countryPickerKey]) tears down and recreates the `CountryCodePicker`
  /// at its `initialSelection` — visually snapping the chip back to that
  /// default. If the mixing State keeps its own "currently selected dial
  /// code" field for building the outgoing phone number, a country picked
  /// in the ~1 frame before this rebuild would leave that field holding the
  /// user's real pick while the chip shows the default flag, silently
  /// prefixing the submitted number with the wrong country code. Override
  /// this to reset that field to its default in the same setState call, so
  /// the chip and the field can never disagree.
  void onCountryListLoaded() {}

  /// Loads (or reuses the cached) localized country list for the app's
  /// current language and stores it in [countryList] via `setState`.
  Future<void> loadCountryList() async {
    final lang = countryPickerLangCode();
    final cached = _localizedCountryListCache[lang];
    if (cached != null) {
      if (mounted) {
        setState(() {
          countryList = cached;
          onCountryListLoaded();
        });
      }
      return;
    }
    try {
      final jsonString = await rootBundle.loadString(
        'packages/country_code_picker/src/i18n/$lang.json',
      );
      final Map<String, dynamic> rawNames = jsonDecode(jsonString);
      // A handful of entries (US, GB, RU, PS…) map to a JSON array of
      // aliases ("United States of America", "USA") instead of one string;
      // the first alias is the country's ordinary name.
      final names = rawNames.map(
        (code, value) => MapEntry(
          code,
          value is List ? value.first as String : value as String,
        ),
      );
      final localized = codes
          .map((entry) {
            final name = names[entry['code']];
            return name == null
                ? entry
                : <String, String>{...entry, 'name': name};
          })
          .toList(growable: false);
      _localizedCountryListCache[lang] = localized;
      if (mounted) {
        setState(() {
          countryList = localized;
          onCountryListLoaded();
        });
      }
    } catch (e) {
      // The asset ships inside the package itself, so this should never
      // fail — but a missing/renamed file on a future package upgrade
      // should degrade to the package's default (mixed-language) list,
      // never crash sign-in. Logged so a future package upgrade that does
      // break this isn't silent.
      debugPrint(
        'LocalizedCountryList: failed to load "$lang.json", falling back '
        'to the package default list: $e',
      );
    }
  }

  /// Builds the `CountryCodePicker` with the dialog CHROME every screen
  /// must share — the header text (localized), header/dialog/search text
  /// styles, dialog box decoration, barrier, and close icon — so it can
  /// never again be forgotten by a caller the way guest_upgrade.dart
  /// forgot it (F5): that screen passed only `key`/`countryList` and fell
  /// back to the package's own hardcoded English "Select Country" heading
  /// on an otherwise-Arabic screen, even though the country NAMES were
  /// already fixed by [countryList] above. The list of names being shared
  /// did nothing to guarantee the dialog's own chrome was shared too — so
  /// that chrome now lives in exactly one place, and every caller that
  /// wants a country picker goes through this method instead of
  /// constructing `CountryCodePicker` directly.
  ///
  /// Only the handful of properties that legitimately differ per-screen
  /// (row size, padding, chip text style, favourites) are parameters;
  /// everything else — including `headerText`, which MUST resolve through
  /// `.tr` — is fixed here.
  Widget buildLocalizedCountryCodePicker(
    BuildContext context, {
    required ValueChanged<CountryCode> onChanged,
    String initialSelection = 'IQ',
    List<String> favorite = const ['+964', 'IQ'],
    EdgeInsetsGeometry padding = const EdgeInsetsDirectional.only(
      start: 12,
      end: 2,
    ),
    double flagWidth = 24,
    required TextStyle textStyle,
    bool showCountryOnly = false,
    bool showOnlyCountryWhenClosed = false,
    bool alignLeft = false,
  }) {
    return CountryCodePicker(
      // See [countryPickerKey] — forces a rebuild once the localized
      // names resolve, since the package never recomputes them on its own.
      key: countryPickerKey,
      countryList: countryListOrDefault,
      onChanged: onChanged,
      initialSelection: initialSelection,
      favorite: favorite,
      showCountryOnly: showCountryOnly,
      showOnlyCountryWhenClosed: showOnlyCountryWhenClosed,
      alignLeft: alignLeft,
      padding: padding,
      flagWidth: flagWidth,
      showDropDownButton: true,
      textStyle: textStyle,
      flagDecoration: BoxDecoration(borderRadius: BorderRadius.circular(3)),
      dialogSize: const Size(360, 520),
      boxDecoration: BoxDecoration(
        color: AppThemeConfig.elevatedSurface(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: authFieldBorder(context)),
      ),
      barrierColor: Colors.black.withValues(alpha: 0.45),
      closeIcon: Icon(
        Icons.close_rounded,
        color: AppThemeConfig.mutedText(context),
      ),
      // Reuses the ONE existing translation key (both `_en` and `_ar` maps
      // in app_translations.dart) rather than inventing a second — this
      // heading must always resolve through `.tr` so it matches the
      // screen's language instead of the package's hardcoded English.
      headerText: 'Select your country · 200+ available'.tr,
      headerTextStyle: TextStyle(
        color: AppThemeConfig.text(context),
        fontWeight: FontWeight.w700,
        fontSize: 15,
      ),
      dialogTextStyle: TextStyle(
        color: AppThemeConfig.text(context),
        fontWeight: FontWeight.w500,
      ),
      searchStyle: TextStyle(color: AppThemeConfig.text(context)),
      dialogItemPadding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 12,
      ),
    );
  }
}

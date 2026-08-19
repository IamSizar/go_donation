// Fails when a screen renders a city or a currency without the helper.
//
// WHY THIS EXISTS
// Two fixes were shipped for exactly these defects — «duhok» in English beside
// Arabic, and «IQD» on an Arabic screen — and BOTH were incomplete. Each was
// made against the one call site visible on screen at the time, verified there,
// and declared done. Eleven city call sites existed; one of them was correct.
//
// A fix verified on one screen is not a fix, and no amount of care at review
// time reliably catches the twelfth call site added next month. So the rule is
// enforced mechanically here instead.
//
// This is a SOURCE test, not a widget test, and deliberately so: the defect is
// "somebody wrote the raw form somewhere", which no amount of pumping widgets
// can enumerate.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files exempt from the city rule, each for a stated reason.
const _cityAllowlist = <String, String>{
  // Builds request payloads — sends the stored value to the server, which is
  // correct. Localising here would send Arabic to a column holding keys.
  'lib/api/module_api.dart': 'API payload construction, not display',
  // The helper itself.
  'lib/localization/content_localizer.dart': 'defines localizedCity',
  'lib/data/iraq_governorates.dart': 'defines the governorate list',
};

/// Files exempt from the currency rule, each for a stated reason.
const _currencyAllowlist = <String, String>{
  'lib/localization/money.dart': 'defines formatMoney/localizedCurrency',
  'lib/localization/app_translations.dart': 'holds the IQD translations',
  // Field and column names (balanceIQD, amount_iqd), never rendered raw.
  'lib/api/wallet_api.dart': 'API field names, not display strings',
};

/// Individual LINES exempt from the currency rule.
///
/// Allowed per line rather than per file on purpose: exempting a whole file
/// would hide the next real offender added to it. Each entry states why the
/// line is not a defect, and each was checked rather than assumed.
///
/// The blind spot these cover: this guard cannot see that a string is passed
/// to a widget which applies `.tr` itself (_ProposalTextField does
/// `labelText: label.tr`, _FieldNote likewise). Such a string IS a translation
/// key and its Arabic value already reads «الدينار العراقي».
const _currencyLineAllowlist = <String, String>{
  "_ProposalTextField(controller: _amount, label: 'Monthly amount IQD'),":
      'key translated by _ProposalTextField; ar = المبلغ الشهري بالدينار العراقي',
  "'Projects are funded in Iraqi dinar (IQD), so the '":
      'key translated by _FieldNote, which applies .tr to its text',
  "final _currencyController = TextEditingController(text: 'IQD');":
      'EDITABLE input holding the code sent to the server; must stay raw',
  "_currencyController.text = 'IQD';":
      'resets that same input to the wire value',
};

/// Every .dart file under lib/, with its repo-relative path.
Iterable<({String path, String source})> _libSources() sync* {
  final lib = Directory('lib');
  for (final entity in lib.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    yield (path: entity.path, source: entity.readAsStringSync());
  }
}

void main() {
  test('a city is never rendered without localizedCity', () {
    // Reads a 'city' value out of a map — the shape every offender had.
    final reads = RegExp(r"""\[\s*['"]city['"]\s*\]""");
    final offenders = <String>[];

    for (final file in _libSources()) {
      if (_cityAllowlist.containsKey(file.path)) continue;
      final lines = file.source.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!reads.hasMatch(line)) continue;
        // A map-literal KEY ('city': value) is writing, not reading.
        if (RegExp(r"""['"]city['"]\s*:""").hasMatch(line)) continue;
        // The read itself must go through the helper, on this line.
        //
        // An earlier version of this guard also exempted any file that
        // mentioned localizedCity ANYWHERE, which was a hole big enough to let
        // the original bug back in: dashboard.dart localises one city and
        // rendered another raw, and a file-level check called that fine. Found
        // by mutation-testing this guard rather than by reading it.
        if (line.contains('localizedCity')) continue;
        offenders.add('${file.path}:${i + 1}  ${line.trim()}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These render a city without localizedCity, so an Arabic reader sees '
          'the raw stored value:\n${offenders.join('\n')}\n\n'
          'Wrap the value in localizedCity(). If the site is an EDITABLE '
          'input, it must keep the raw value — localising an input writes the '
          'localised string back on save — so add it to _cityAllowlist with '
          'that reason instead.',
    );
  });

  test('a currency code is never written as a display literal', () {
    // A literal 'IQD' inside a Dart string, which is how every offender read.
    final literal = RegExp(r"""['"][^'"]*\bIQD\b[^'"]*['"]""");
    final offenders = <String>[];

    for (final file in _libSources()) {
      if (_currencyAllowlist.containsKey(file.path)) continue;
      final lines = file.source.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!literal.hasMatch(line)) continue;
        // A comment explaining the currency is not a rendered string.
        if (line.trimLeft().startsWith('//')) continue;
        // Passing 'IQD' INTO the helper as a fallback code is the correct use.
        if (line.contains('localizedCurrency') || line.contains('formatMoney')) {
          continue;
        }
        // A TRANSLATION KEY that happens to contain "IQD" is not a defect: the
        // Arabic value behind it already reads «د.ع». Only an interpolated or
        // untranslated literal actually reaches the reader as written.
        // Checked, not assumed — 'Confirm @amount IQD donation' resolves to
        // «تأكيد مساهمة @amount د.ع».
        if (RegExp(r"""['"][^'"]*\bIQD\b[^'"]*['"]\s*\.tr""").hasMatch(line)) {
          continue;
        }
        // Same for a key split across lines: the .tr sits on the NEXT line.
        if (i + 1 < lines.length && lines[i + 1].trimLeft().startsWith('.tr')) {
          continue;
        }
        // A DEFAULT CODE is not a display string. `?? 'IQD'`, `currency: 'IQD'`
        // and `return 'IQD'` all supply a code that formatMoney/
        // localizedCurrency translates further down. Flagging these would make
        // the guard cry wolf, and a guard that cries wolf gets deleted.
        if (RegExp(r"""\?\?\s*['"]IQD['"]""").hasMatch(line)) continue;
        if (RegExp(r"""currency:\s*['"]IQD['"]""").hasMatch(line)) continue;
        if (RegExp(r"""return\s*['"]IQD['"]\s*;""").hasMatch(line)) continue;
        if (RegExp(r"""['"]currency['"]\s*:\s*['"]IQD['"]""").hasMatch(line)) {
          continue;
        }
        if (_currencyLineAllowlist.containsKey(line.trim())) continue;
        offenders.add('${file.path}:${i + 1}  ${line.trim()}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These put a raw currency code in a display string, so an Arabic '
          'reader sees «IQD» instead of «د.ع»:\n${offenders.join('\n')}\n\n'
          'Use formatMoney() for an amount, or localizedCurrency() for a bare '
          'code.',
    );
  });
}

// ─── Why content FIELDS are not guarded here ───────────────────────────────
//
// The same "one site fixed, N sites unfixed" risk applies to translatable
// content (mission titles, category names, notification bodies). It was
// audited by hand rather than mechanised, deliberately.
//
// A rule over base keys like ['title'] cannot be made precise. The same key is
// read legitimately for a PERSON's name, a chat message body, and nested JSON
// objects — none of which are translatable content. The rule would fire
// constantly on correct code, and a guard that cries wolf gets deleted, which
// is worse than no guard because it also removes the ones that work.
//
// The audit behind that decision (2026-08-19), so it is not repeated blindly:
//   - api/ parses all four language columns into typed models exposing a
//     localised getter — correct.
//   - Screens reading name_en/_ar/_ckb/_kmr pass ALL FOUR into a localising
//     helper — correct.
//   - catalogue_facets and media_posts_controller select the reader's language
//     first and fall back to English only when it is empty — correct.
//   - Notifications parse every variant into a model with localizedTitle —
//     correct.
//   - Five sites read a base key directly and were fixed: the mission title in
//     the dashboard card and in the status-change snackbar, two history record
//     titles, and two bot listings.
//
// If this class does recur, the tractable rule is probably at the API boundary
// (assert that a payload carrying title_ar is never read as title) rather than
// over every call site.

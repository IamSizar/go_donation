// Pins that backend tags never reach the user as machine output.
//
// WHY THIS FILE EXISTS
// Found by walking the running app: marketplace product cards showed
// "beauty_care" and news cards showed "event" — raw English snake_case in a
// right-to-left Arabic UI, which breaks the project's hard rule that the
// Arabic interface contains no English.
//
// The values come from two different backend fields (a legacy free-text
// `category` and a `post_type` enum), so the fix is one shared helper rather
// than three patched call sites. These tests cover both halves of it: a
// translated tag wins, and an UNKNOWN tag still degrades to something
// readable — because new tags will appear server-side before anyone
// translates them, and that case must not regress to snake_case.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:flutter_application_1/core/design/tokens.dart';
import 'package:flutter_application_1/localization/app_translations.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/modules/notifications/models/app_notification_model.dart';
import 'package:flutter_application_1/modules/notifications/widgets/notification_detail_dialog.dart';

/// Every notification_type the backend can write, as one list.
///
/// Sourced by reading `backend/internal/notify/templates.go` rather than by
/// sampling the running app: the fixed values are the `Type:` field of every
/// LocalizedMessage, and the three interpolated families
/// (`volunteer_application_<status>`, `volunteer_mission_<status>`,
/// `support_ticket_<status>`) are expanded from the `switch` that builds them.
/// `system_test` is a legacy row still present in production data.
const notificationTypes = <String>[
  'admin_announcement',
  'admin_new_beneficiary_case',
  'admin_new_guest_account',
  'admin_new_marriage_profile',
  'admin_new_project_request',
  'beneficiary_case_approved',
  'beneficiary_case_rejected',
  'beneficiary_case_submitted',
  'case_volunteer_chat_message',
  'case_volunteer_chat_opened',
  'chat_accepted',
  'chat_message',
  'chat_request',
  'donation_approved',
  'donation_cancelled_by_donor',
  'donation_payment_confirmed',
  'donation_payment_failed',
  'donation_received_on_project',
  'donation_rejected',
  'donation_submitted',
  'in_kind_donation_cancelled',
  'in_kind_donation_delivered',
  'in_kind_donation_received',
  'in_kind_donation_scheduled',
  'in_kind_donation_submitted',
  'marketplace_order_approved',
  'marketplace_order_cancelled',
  'marketplace_order_completed',
  'marketplace_order_submitted',
  'marriage_approved',
  'marriage_chat_accepted',
  'marriage_chat_message',
  'marriage_chat_request',
  'marriage_meeting_declined',
  'marriage_profile_submitted',
  'marriage_rejected',
  'marriage_status_changed',
  'marriage_subscription_activated',
  'marriage_subscription_pending',
  'marriage_subscription_pending_admin',
  'marriage_subscription_rejected',
  'new_campaign',
  'new_media_post',
  'new_partner',
  'new_volunteer_mission',
  'post_comment_received',
  'project_request_approved',
  'project_request_rejected',
  'project_request_status_changed',
  'project_request_submitted',
  'registration_approved',
  'registration_rejected',
  'sponsorship_accepted',
  'sponsorship_cancelled',
  'sponsorship_due_grantor',
  'sponsorship_due_recipient',
  'sponsorship_payment_due_reminder',
  'sponsorship_status_changed',
  'sponsorship_submitted',
  'staff_chat_message',
  'support_request_submitted',
  'support_ticket_replied',
  'system_test',
  'task_assigned',
  'wallet_topup',
  // volunteer_application_<status>
  'volunteer_application_approved',
  'volunteer_application_inactive',
  'volunteer_application_rejected',
  'volunteer_application_submitted',
  // volunteer_mission_<status>
  'volunteer_mission_absent',
  'volunteer_mission_approved',
  'volunteer_mission_cancelled',
  'volunteer_mission_completed',
  'volunteer_mission_completion_requested',
  'volunteer_mission_join_submitted',
  'volunteer_mission_joined',
  'volunteer_mission_no_show',
  'volunteer_mission_rejected',
  // support_ticket_<status>
  'support_ticket_closed',
  'support_ticket_in_progress',
  'support_ticket_resolved',
];

/// Wraps a widget in just enough app chrome for the design tokens and GetX
/// translations to resolve. Mirrors `test/widgets/app_states_test.dart`.
Widget _host(Widget child, {TextDirection direction = TextDirection.rtl}) {
  return MaterialApp(
    theme: ThemeData(extensions: <ThemeExtension<dynamic>>[AppColors.light]),
    home: Directionality(
      textDirection: direction,
      child: Scaffold(body: child),
    ),
  );
}

/// A notification whose category resolves to `urgent` — the one the client's
/// screenshot showed disagreeing between the list and the dialog.
AppNotificationModel _urgentNotification() {
  return AppNotificationModel(
    id: '1',
    title: 'Support request',
    titleAr: 'طلب دعم',
    titleSorani: '',
    titleBadini: '',
    message: 'A message',
    messageAr: 'رسالة',
    messageSorani: '',
    messageBadini: '',
    notificationType: 'support_request_submitted',
    notificationCategory: 'urgent',
    priority: 1,
    isRead: false,
    createdAt: DateTime.utc(2026, 8, 15, 12),
  );
}

void main() {
  setUp(() {
    Get.addTranslations(AppTranslations().keys);
    Get.locale = const Locale('en', 'US');
    Get.fallbackLocale = const Locale('en', 'US');
  });

  group('localizedTag', () {
    test('a known tag resolves to its translated label', () {
      expect(localizedTag('beauty_care'), 'Beauty care');
      expect(localizedTag('event'), 'Event');
    });

    test('an UNKNOWN tag is humanised, never left as snake_case', () {
      // The regression that matters: a tag added server-side tomorrow must
      // not appear on a product card as "garden_tools".
      expect(localizedTag('garden_tools'), 'Garden tools');
      expect(localizedTag('some-new-kind'), 'Some new kind');
    });

    test('no tag renders nothing, so callers can hide the chip', () {
      // An empty pill is worse than no pill.
      expect(localizedTag(null), '');
      expect(localizedTag(''), '');
      expect(localizedTag('   '), '');
    });

    test('Arabic resolves the Arabic label, not the English one', () {
      Get.locale = const Locale('ar', 'SA');
      final label = localizedTag('beauty_care');

      expect(label, isNot('beauty_care'));
      expect(label, isNot('Beauty care'));
      // The whole point: no Latin letters reach an Arabic screen.
      expect(RegExp(r'[A-Za-z]').hasMatch(label), isFalse);
    });

    test('a snake_case token never survives to the screen, in any language', () {
      // The humanising branch must run for EVERY locale, not just English.
      // A Kurdish reader seeing "garden_tools" is the same defect as an Arabic
      // one seeing it.
      for (final locale in const [
        Locale('en', 'US'),
        Locale('ar', 'SA'),
        Locale('ar', 'IQ'),
        Locale('ar', 'TR'),
      ]) {
        Get.locale = locale;
        expect(
          localizedTag('garden_tools'),
          isNot(contains('_')),
          reason: 'raw token leaked in $locale',
        );
      }
    });

    test(
      'a tag translated only in English degrades to English, not Kurdish',
      () {
        // Kurdish is deliberately incomplete. `beauty_care` has no Sorani entry,
        // so a Sorani reader must get the ENGLISH label — not the Badini one,
        // which is what GetX's language-only fallback used to hand back.
        Get.locale = const Locale('ar', 'IQ');
        final sorani = localizedTag('beauty_care');
        Get.locale = const Locale('en', 'US');
        final english = localizedTag('beauty_care');

        expect(sorani, isNotEmpty);
        expect(sorani, isNot('beauty_care'));
        // Either a real Sorani label exists, or it falls back to English. What
        // it must NEVER be is Arabic or Badini text picked up by accident.
        final soraniEntry = AppTranslations.soraniForTest['beauty_care'];
        if (soraniEntry == null) {
          expect(
            sorani,
            english,
            reason: 'no Sorani entry, so English is the required fallback',
          );
        }
      },
    );
  });

  group('the backend tags actually rendered by the app', () {
    // These are the values that reach localizedTag call sites today:
    //   marketplace_controller.dart:366  product['category']  (legacy free text)
    //   news_activities_screen.dart:307  item['post_type']    (enum)
    //   dashboard.dart:1925              post['post_type']    (enum)
    //   dashboard.dart:95                any status token
    //   technical_support_screen.dart:342 ticket status
    const postTypes = ['activity', 'event', 'news', 'article'];
    const supportStatuses = ['open', 'in_progress', 'resolved', 'closed'];

    test('post_type enum values all have real labels in en and ar', () {
      for (final locale in const [Locale('en', 'US'), Locale('ar', 'SA')]) {
        Get.locale = locale;
        for (final t in postTypes) {
          final label = localizedTag(t);
          expect(label, isNotEmpty);
          expect(
            label,
            isNot(t),
            reason: '$t rendered as the raw token in $locale',
          );
        }
      }
    });

    // volunteer_mission_signups.signup_status — the set the app itself
    // switches on in support_section.dart:150-167 (`_messageForTransition`)
    // and :1126, cross-checked against the `volunteer_mission_<status>`
    // notification family listed above. The assistant's "Your volunteer
    // status" card printed this field with no localization at all, so an
    // Arabic reader was shown `completion_requested` and `no_show`.
    const signupStatuses = [
      'pending',
      'approved',
      'rejected',
      'cancelled',
      'joined',
      'completion_requested',
      'completed',
      'no_show',
    ];

    test('volunteer signup statuses all have real labels in en and ar', () {
      for (final locale in const [Locale('en', 'US'), Locale('ar', 'SA')]) {
        Get.locale = locale;
        for (final s in signupStatuses) {
          final label = localizedTag(s);
          expect(label, isNotEmpty);
          expect(
            label,
            isNot(s),
            reason: '$s rendered as the raw token in $locale',
          );
        }
      }
    });

    test('no volunteer signup status reaches an Arabic screen in Latin', () {
      // Humanising `completion_requested` into "Completion requested" would
      // satisfy the test above while still putting English on an Arabic
      // card. Latin letters are the assertion that matters.
      Get.locale = const Locale('ar', 'SA');
      for (final s in signupStatuses) {
        final label = localizedTag(s);
        expect(
          RegExp(r'[A-Za-z]').hasMatch(label),
          isFalse,
          reason: '$s rendered as "$label" in Arabic',
        );
      }
    });

    test('support ticket statuses render as words, never as tokens', () {
      // technical_support_screen builds `status_<value>`; localizedTag is the
      // fallback when that key is absent. Either way no underscore may show.
      Get.locale = const Locale('ar', 'SA');
      for (final s in supportStatuses) {
        expect(
          'status_$s'.tr,
          isNot('status_$s'),
          reason: 'status_$s has no Arabic entry',
        );
        expect(localizedTag(s), isNot(contains('_')));
      }
    });
  });

  // ─── SHAPE 1 · a backend enum printed with no localization at all (B1) ───
  //
  // notifications_screen.dart built the "filter by type" dropdown from
  // `controller.availableTypes` — the distinct notification_type values on the
  // rows the API returned — and rendered each one as a bare `Text(type)`, one
  // line below a sibling that correctly used `.tr`. So the Arabic UI listed
  // `marketplace_order_approved`, `system_test`, `registration_approved`, …
  //
  // The whole vocabulary is asserted rather than the six values the client
  // happened to have rows for: which types appear depends entirely on that
  // account's history, so testing only the observed ones would leave the rest
  // to be reported again by the next user.
  group('notification type filter', () {
    test('every type has a real English label, not the raw token', () {
      for (final t in notificationTypes) {
        expect(localizedTag(t), isNot(t), reason: '$t rendered as its token');
      }
    });

    test('every type reads in Arabic with no Latin letters left', () {
      // THE test for this row. Humanising `marketplace_order_approved` into
      // "Marketplace order approved" fixes the snake_case but is still English
      // on an Arabic screen, so `isNot(contains('_'))` would pass a UI the
      // client would report again. Latin characters are the real assertion.
      Get.locale = const Locale('ar', 'SA');
      for (final t in notificationTypes) {
        final label = localizedTag(t);
        expect(label, isNotEmpty);
        expect(
          RegExp(r'[A-Za-z]').hasMatch(label),
          isFalse,
          reason: '$t rendered as "$label" in Arabic',
        );
      }
    });

    test('an unknown type still degrades, never to snake_case', () {
      // The dropdown is built from whatever the server sent, so a type added
      // server-side tomorrow reaches it before anyone translates it. That is
      // the case localizedTag exists for.
      for (final locale in const [
        Locale('en', 'US'),
        Locale('ar', 'SA'),
        Locale('ar', 'IQ'), // Sorani
        Locale('ar', 'TR'), // Badini
      ]) {
        Get.locale = locale;
        final label = localizedTag('some_future_backend_type');
        expect(label, isNotEmpty);
        expect(
          label,
          isNot(contains('_')),
          reason: 'raw token leaked in $locale',
        );
      }
    });
  });

  // ─── SHAPE 2 · one value localized on one surface, raw on another ───
  //
  // The list card rendered `notification.categoryLabel.tr` (→ "عاجل") and the
  // detail dialog behind it rendered `_Pill(label: n.categoryLabel)` with no
  // `.tr` at all (→ "Urgent"). Same field, same screen, two answers — so the
  // Arabic entry already existed and a map-coverage test would have passed
  // while the defect was on screen. Only pumping the dialog catches it.
  group('notification detail dialog', () {
    testWidgets('the category badge is Arabic, like the card behind it', (
      tester,
    ) async {
      Get.locale = const Locale('ar', 'SA');
      final n = _urgentNotification();

      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showNotificationDetail(context, n),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The list card's answer, which was already correct.
      final cardLabel = n.categoryLabel.tr;
      expect(cardLabel, 'عاجل');
      // The dialog must agree with it.
      expect(
        find.text(cardLabel),
        findsOneWidget,
        reason: 'the dialog badge disagrees with the list card badge',
      );
      expect(
        find.text('Urgent'),
        findsNothing,
        reason: 'the English category label reached the Arabic dialog',
      );
    });

    test('every category label has an Arabic entry to resolve to', () {
      // categoryLabel returns one of six fixed English words; each needs a
      // translation for the widget test above to have anything to find.
      Get.locale = const Locale('ar', 'SA');
      for (final label in const [
        'Urgent',
        'Payment',
        'Campaign',
        'System',
        'Reminder',
        'Normal',
      ]) {
        expect(
          RegExp(r'[A-Za-z]').hasMatch(label.tr),
          isFalse,
          reason: '$label has no Arabic entry',
        );
      }
    });
  });

  // ─── SHAPE 3 · a literal handed to a widget that translates internally ───
  //
  // AppEmpty, AppScreen, SectionScaffold, SectionTile, AppFigure and InfoChip
  // all apply `.tr` to a String FIELD rather than at the call site, so a call
  // site passing a bare English literal looks correct and compiles. GetX
  // returns the key unchanged on a miss, so the English sentence renders
  // verbatim in Arabic. That is B21's residue: not a missing `.tr`, a missing
  // map entry.
  //
  // These are the exact literals reaching those fields today, found by
  // scanning lib/ for both shapes (`'x'.tr` and `field: 'x'`) and diffing
  // against the `_en` key set.
  group('screen strings that widgets translate internally', () {
    const untranslated = <String>[
      // sponsorship_section.dart — the Kafala section header
      'Eligible support',
      'Kafala Support',
      'Submit help requests and track admin review in one place.',
      'Monitor sponsorship plans, your submitted projects, and stories.',
      // my_donations_page.dart — مساهماتي
      'gifts',
      'contributions',
      'Delivered',
      'Awaiting confirmation',
      'No gifts yet',
      'Every gift you make appears here with its reference code and '
          'delivery status, so you always know where it went.',
      // chat_conversation_screen.dart — an empty conversation
      'Send the first message to start the conversation.',
      // proposal_services_section.dart — the Services list
      'Send a support request and track the reply.',
      // support_section.dart — volunteer mission cards
      'Flexible',
      'My volunteer application',
      'Submit your skills and availability to the institution.',
      "When you're available",
      // technical_support_screen.dart — the in-flight submit button
      'Sending...',
      // dashboard.dart — the campaigns carousel empty state
      'Featured campaigns will appear here once published.',
      // community_services_section.dart — city guide empty states
      'Approved places in the city guide will appear here. You can suggest '
          'one with Add an Activity.',
      'Nothing in the guide matches this sector yet. Clear the filter to see '
          'every place.',
      // messages_screen.dart — the support assistant card
      "Ask me anything — I'll guide you through the app",
      // guest_upgrade.dart — claiming a guest account
      "We'll text you a one-time code to confirm it's yours.",
      // marriage_my_profile_screen.dart / edit_profile.dart — review notices
      'new one for review.',
      'edited here.',
    ];

    test('each has an English entry, so `.tr` is not a no-op', () {
      // Without an `_en` key the string is not merely untranslated — it is
      // invisible to the whole mechanism, including the Kurdish layering that
      // reads `_en` as its base.
      for (final s in untranslated) {
        expect(
          AppTranslations.englishForTest.containsKey(s),
          isTrue,
          reason: 'no _en entry for "$s"',
        );
      }
    });

    test('none of them renders English on an Arabic screen', () {
      Get.locale = const Locale('ar', 'SA');
      for (final s in untranslated) {
        final label = s.tr;
        expect(label, isNot(s), reason: '"$s" rendered verbatim in Arabic');
        expect(
          RegExp(r'[A-Za-z]').hasMatch(label),
          isFalse,
          reason: '"$s" rendered as "$label" in Arabic',
        );
      }
    });
  });

  // Kurdish is deliberately incomplete and must NOT be invented — an English
  // fallback is honest, a machine-translated Kurdish label is not. This pins
  // that the fallback actually works for everything added above, so the
  // outstanding keys can sit in TRANSLATION_REQUEST.md without leaving a
  // Kurdish reader looking at a raw token.
  group('Kurdish falls back to English, never to a token', () {
    test('notification types resolve to something readable in Kurdish', () {
      for (final locale in const [Locale('ar', 'IQ'), Locale('ar', 'TR')]) {
        Get.locale = locale;
        for (final t in notificationTypes) {
          final label = localizedTag(t);
          expect(label, isNotEmpty, reason: '$t vanished in $locale');
          expect(
            label,
            isNot(contains('_')),
            reason: '$t leaked as a token in $locale',
          );
        }
      }
    });
  });
}

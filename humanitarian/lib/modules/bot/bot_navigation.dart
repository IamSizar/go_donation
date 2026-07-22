import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/guest_session.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/modules/auth/screens/edit_profile.dart';
import 'package:flutter_application_1/modules/auth/screens/profile.dart';
import 'package:flutter_application_1/modules/chat/screens/messages_screen.dart';
import 'package:flutter_application_1/modules/community/screens/community_services_section.dart';
import 'package:flutter_application_1/modules/dashboard/screens/guest_sections.dart';
import 'package:flutter_application_1/modules/donations/screens/donations_section.dart';
import 'package:flutter_application_1/modules/donations/screens/my_donations_page.dart';
import 'package:flutter_application_1/modules/marriage/screens/marriage_form_screen.dart';
import 'package:flutter_application_1/modules/notifications/screens/notifications_screen.dart';
import 'package:flutter_application_1/modules/proposal/screens/proposal_services_section.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/beneficiary_campaign_donations_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/beneficiary_pending_projects_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/beneficiary_submit_project_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/sponsorship_section.dart';
import 'package:flutter_application_1/modules/support/screens/support_section.dart';
import 'package:get/get.dart';

/// Central resolver that turns an assistant route key into real navigation.
///
/// Route keys mirror the Go `Route` constants in
/// backend/internal/assistant/knowledge.go. Each key maps to a base dashboard
/// tab and, for "deep" routes, a specific screen that gets pushed on top — so
/// "edit my profile" lands the user ON the Edit Profile form, not just a tab.
class BotNavSpec {
  const BotNavSpec(this.tab, [this.screen]);

  /// The dashboard tab to switch to underneath.
  final int tab;

  /// Optional concrete screen to push after switching tabs. Null = tab only.
  final Widget Function()? screen;
}

abstract final class BotNavigation {
  // Note #41 — the bottom nav is fixed at 4 tabs now:
  //   0 Home · 1 Store · 2 Marriage · 3 City Guide
  // Everything that used to be its own tab (Kafala, Contribute, Alerts,
  // Profile, Volunteer, Services, Messages) is reached by pushing the same
  // screen it always opened, over the Home tab as a base.
  static final Map<String, BotNavSpec> _routes = {
    // Tab-level routes
    'home': const BotNavSpec(0),
    'market': const BotNavSpec(1),
    'city_guide': const BotNavSpec(3),

    // "community" used to be its own tab (the services directory list); that
    // list now lives one tap inside the City Guide tab.
    'community': BotNavSpec(3, () => const CommunityServicesSection()),

    // No longer their own tab — push the same screen over Home.
    'kafala': BotNavSpec(0, () => const SponsorshipSection()),
    'donate': BotNavSpec(0, () => const DonationsSection()),
    'alerts': BotNavSpec(0, () => const NotificationsScreen()),
    'profile': BotNavSpec(
      0,
      () => Scaffold(
        body: isGuestMode() ? GuestAccountSection() : const ProfileSection(),
      ),
    ),
    'volunteer': BotNavSpec(0, () => const SupportSection()),
    'services': BotNavSpec(0, () => const ProposalServicesSection()),
    'messages': BotNavSpec(0, () => const MessagesScreen()),

    // Deep routes → push a specific screen on top of its base tab.
    'my_donations': BotNavSpec(0, () => const MyDonationsPage()),
    'edit_profile': BotNavSpec(0, () => const EditProfilePage()),
    'submit_project': BotNavSpec(0, () => const BeneficiarySubmitProjectScreen()),
    'pending_projects': BotNavSpec(0, () => const BeneficiaryPendingProjectsScreen()),
    'campaign_donations': BotNavSpec(0, () => const BeneficiaryCampaignDonationsScreen()),
    // Marriage now has its own tab; land there, then open the profile form.
    'marriage': BotNavSpec(2, () => const MarriageFormScreen()),
    'support': BotNavSpec(0, () => const SupportTicketFormScreen()),
  };

  /// Localized CTA button labels per route per language (ar / ckb / kmr).
  /// Mirrors the backend `localizedLabels` map so an offline answer's button
  /// reads the same as an online (AI / keyword-engine) answer's button.
  static const Map<String, Map<String, String>> _labels = {
    'donate': {'ar': 'اذهب إلى الحملات', 'ckb': 'بڕۆ بۆ کامپەینەکان', 'kmr': 'هەرە بۆ کامپینان'},
    'my_donations': {'ar': 'عرض تبرعاتي', 'ckb': 'بینینی بەخشینەکانم', 'kmr': 'بەخشینێن من ببینە'},
    'market': {'ar': 'افتح السوق', 'ckb': 'بازاڕ بکەوە', 'kmr': 'بازارێ ڤەکە'},
    'kafala': {'ar': 'افتح الكفالة', 'ckb': 'کەفالە بکەوە', 'kmr': 'کەفالە ڤەکە'},
    'submit_project': {'ar': 'قدّم مشروعاً', 'ckb': 'پڕۆژەیەک تەقدیم بکە', 'kmr': 'پرۆژەیەکێ بنێرە'},
    'pending_projects': {'ar': 'المشاريع المعلقة', 'ckb': 'پڕۆژە هەڵواسراوەکان', 'kmr': 'پرۆژەیێن چاڤەڕوانیێ'},
    'campaign_donations': {'ar': 'تبرعات حملتي', 'ckb': 'بەخشینی کامپەینەکانم', 'kmr': 'بەخشینێن کامپینێن من'},
    'community': {'ar': 'افتح المجتمع', 'ckb': 'کۆمەڵگا بکەوە', 'kmr': 'جڤاکێ ڤەکە'},
    'alerts': {'ar': 'اذهب إلى التنبيهات', 'ckb': 'بڕۆ بۆ ئاگادارکردنەوەکان', 'kmr': 'هەرە بۆ ئاگەهداریان'},
    'profile': {'ar': 'افتح الملف الشخصي', 'ckb': 'پرۆفایل بکەوە', 'kmr': 'پرۆفایلێ ڤەکە'},
    'edit_profile': {'ar': 'تعديل الملف الشخصي', 'ckb': 'دەستکاری پرۆفایل', 'kmr': 'دەستکاریا پرۆفایلێ'},
    'volunteer': {'ar': 'افتح التطوع', 'ckb': 'ڕاهێنان بکەوە', 'kmr': 'خۆبەخشیێ ڤەکە'},
    'services': {'ar': 'افتح الخدمات', 'ckb': 'خزمەتگوزارییەکان بکەوە', 'kmr': 'خزمەتگوزاریان ڤەکە'},
    'marriage': {'ar': 'افتح نموذج الزواج', 'ckb': 'فۆرمی زەواج بکەوە', 'kmr': 'فۆرما هاوسەرگیریێ ڤەکە'},
    'messages': {'ar': 'افتح الرسائل', 'ckb': 'پەیامەکان بکەوە', 'kmr': 'پەیاما ڤەکە'},
    'support': {'ar': 'اتصل بالدعم', 'ckb': 'پەیوەندی بە پشتگیری', 'kmr': 'پەیوەندی ب پشتگیریێ'},
    'home': {'ar': 'اذهب إلى الرئيسية', 'ckb': 'بڕۆ بۆ سەرەتا', 'kmr': 'هەرە بۆ سەرەکی'},
  };

  /// The CTA label for [route] in [lang]. For English (or any gap) returns
  /// [englishFallback] so the exact English wording is preserved. Used by the
  /// offline fallback; the online path already gets a localized label from the
  /// backend.
  static String? localizedLabel(String? route, String lang, String? englishFallback) {
    if (route == null || lang == 'en') return englishFallback;
    final l = _labels[route]?[lang];
    return (l != null && l.isNotEmpty) ? l : englishFallback;
  }

  /// True when the route is known and can be navigated.
  static bool canHandle(String? route) {
    if (route == null) return false;
    if (route.startsWith('tab:')) return true;
    return _routes.containsKey(route);
  }

  /// Performs the navigation for [route]. Supports real route keys and the
  /// synthetic "tab:N" form the offline fallback may emit.
  static void go(String route) {
    BotNavSpec? spec;
    if (route.startsWith('tab:')) {
      final n = int.tryParse(route.substring(4));
      if (n != null) spec = BotNavSpec(n);
    } else {
      spec = _routes[route];
    }
    if (spec == null) return;

    // Switch the base tab, then pop back to the dashboard root (this closes
    // the assistant screen), then push the deep screen if any.
    dashboardTabNotifier.value = spec.tab;
    Get.until((r) => r.isFirst);
    final builder = spec.screen;
    if (builder != null) {
      // Defer one frame so the dashboard has rebuilt at the new tab before we
      // stack the detail screen on top of it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.to(builder);
      });
    }
  }
}

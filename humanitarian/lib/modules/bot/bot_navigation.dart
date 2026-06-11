import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/modules/auth/screens/edit_profile.dart';
import 'package:flutter_application_1/modules/donations/screens/my_donations_page.dart';
import 'package:flutter_application_1/modules/proposal/screens/proposal_services_section.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/beneficiary_campaign_donations_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/beneficiary_pending_projects_screen.dart';
import 'package:flutter_application_1/modules/sponsorship/screens/beneficiary_submit_project_screen.dart';
import 'package:get/get.dart';

/// Central resolver that turns an assistant route key into real navigation.
///
/// Route keys mirror the Go `Route` constants in
/// backend/internal/assistant/knowledge.go. Each key maps to a base dashboard
/// tab and, for "deep" routes, a specific screen that gets pushed on top — so
/// "edit my profile" lands the user ON the Edit Profile form, not just the
/// Profile tab. ("full route")
class BotNavSpec {
  const BotNavSpec(this.tab, [this.screen]);

  /// The dashboard tab to switch to underneath.
  final int tab;

  /// Optional concrete screen to push after switching tabs. Null = tab only.
  final Widget Function()? screen;
}

abstract final class BotNavigation {
  // Dashboard._sections indices:
  //   0 Home · 1 Kafala · 2 Market · 3 Community · 4 Donate · 5 Alerts
  //   6 Profile · 7 Volunteer · 8 Services · 9 Messages
  static final Map<String, BotNavSpec> _routes = {
    // Tab-level routes
    'home': const BotNavSpec(0),
    'kafala': const BotNavSpec(1),
    'market': const BotNavSpec(2),
    'community': const BotNavSpec(3),
    'donate': const BotNavSpec(4),
    'alerts': const BotNavSpec(5),
    'profile': const BotNavSpec(6),
    'volunteer': const BotNavSpec(7),
    'services': const BotNavSpec(8),
    'messages': const BotNavSpec(9),

    // Deep routes → push a specific screen on top of its base tab.
    'my_donations': BotNavSpec(4, () => const MyDonationsPage()),
    'edit_profile': BotNavSpec(6, () => const EditProfilePage()),
    'submit_project': BotNavSpec(1, () => const BeneficiarySubmitProjectScreen()),
    'pending_projects': BotNavSpec(1, () => const BeneficiaryPendingProjectsScreen()),
    'campaign_donations': BotNavSpec(1, () => const BeneficiaryCampaignDonationsScreen()),
    'marriage': BotNavSpec(8, () => const MarriageProfileFormScreen()),
    'support': BotNavSpec(8, () => const SupportTicketFormScreen()),
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

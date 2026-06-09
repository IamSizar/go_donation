import 'package:flutter/material.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:get/get.dart';

/// Campaign row from paginated campaigns API (see PHP `getPaginatedCampaigns`).
/// Maps table-style keys (`project_title`, `amount_needed`, …) and legacy keys (`title`, `goal_amount`, …).
class FeaturedCampaignData {
  FeaturedCampaignData({
    required this.id,
    this.userId = 0,
    required this.titleEn,
    required this.titleAr,
    required this.titleSorani,
    required this.titleBadini,
    required this.categoryEn,
    required this.categoryAr,
    required this.categorySorani,
    required this.categoryBadini,
    required this.summaryEn,
    required this.summaryAr,
    required this.summarySorani,
    required this.summaryBadini,
    required this.descriptionLongEn,
    required this.descriptionLongAr,
    required this.descriptionLongSorani,
    required this.descriptionLongBadini,
    required this.locationEn,
    required this.locationAr,
    required this.locationSorani,
    required this.locationBadini,
    required this.beneficiaryCommunityEn,
    required this.beneficiaryCommunityAr,
    required this.beneficiaryCommunitySorani,
    required this.beneficiaryCommunityBadini,
    required this.amountNeeded,
    required this.raisedAmount,
    required this.currency,
    required this.peopleAffectedTotal,
    this.maleCount = 0,
    this.femaleCount = 0,
    required this.status,
    this.likeCount = 0,
    this.commentCount = 0,
    this.volunteerAgeProfileEn = '',
    this.volunteerAgeProfileAr = '',
    this.volunteerAgeProfileSorani = '',
    this.volunteerAgeProfileBadini = '',
    this.volunteerSkillsEn = '',
    this.volunteerSkillsAr = '',
    this.volunteerSkillsSorani = '',
    this.volunteerSkillsBadini = '',
    this.volunteersExtraEn = '',
    this.volunteersExtraAr = '',
    this.volunteersExtraSorani = '',
    this.volunteersExtraBadini = '',
    this.timelineTargetEn = '',
    this.timelineTargetAr = '',
    this.timelineTargetSorani = '',
    this.timelineTargetBadini = '',
    this.contactPersonEn = '',
    this.contactPersonAr = '',
    this.contactPersonSorani = '',
    this.contactPersonBadini = '',
    this.contactPhone = '',
    this.contactEmail = '',
    this.otherNotesEn = '',
    this.otherNotesAr = '',
    this.otherNotesSorani = '',
    this.otherNotesBadini = '',
  });

  final int id;
  final int userId;
  final String titleEn;
  final String titleAr;
  final String titleSorani;
  final String titleBadini;
  final String categoryEn;
  final String categoryAr;
  final String categorySorani;
  final String categoryBadini;
  final String summaryEn;
  final String summaryAr;
  final String summarySorani;
  final String summaryBadini;
  final String descriptionLongEn;
  final String descriptionLongAr;
  final String descriptionLongSorani;
  final String descriptionLongBadini;
  final String locationEn;
  final String locationAr;
  final String locationSorani;
  final String locationBadini;
  final String beneficiaryCommunityEn;
  final String beneficiaryCommunityAr;
  final String beneficiaryCommunitySorani;
  final String beneficiaryCommunityBadini;
  final double amountNeeded;
  final double raisedAmount;
  final String currency;
  final int peopleAffectedTotal;
  final int maleCount;
  final int femaleCount;
  final String status;
  final int likeCount;
  final int commentCount;
  final String volunteerAgeProfileEn;
  final String volunteerAgeProfileAr;
  final String volunteerAgeProfileSorani;
  final String volunteerAgeProfileBadini;
  final String volunteerSkillsEn;
  final String volunteerSkillsAr;
  final String volunteerSkillsSorani;
  final String volunteerSkillsBadini;
  final String volunteersExtraEn;
  final String volunteersExtraAr;
  final String volunteersExtraSorani;
  final String volunteersExtraBadini;
  final String timelineTargetEn;
  final String timelineTargetAr;
  final String timelineTargetSorani;
  final String timelineTargetBadini;
  final String contactPersonEn;
  final String contactPersonAr;
  final String contactPersonSorani;
  final String contactPersonBadini;
  final String contactPhone;
  final String contactEmail;
  final String otherNotesEn;
  final String otherNotesAr;
  final String otherNotesSorani;
  final String otherNotesBadini;

  String get title => localizedContentFromValues(
    base: titleEn,
    arabic: titleAr,
    sorani: titleSorani,
    badini: titleBadini,
  );

  String get summary {
    final short = localizedContentFromValues(
      base: summaryEn,
      arabic: summaryAr,
      sorani: summarySorani,
      badini: summaryBadini,
    );
    if (short.trim().isNotEmpty) return short;
    final long = descriptionLong;
    if (long.length <= 220) return long;
    return '${long.substring(0, 217)}…';
  }

  /// Localized category label for badges.
  String get category => localizedContentFromValues(
    base: categoryEn,
    arabic: categoryAr,
    sorani: categorySorani,
    badini: categoryBadini,
  ).trim();

  String get location => localizedContentFromValues(
    base: locationEn,
    arabic: locationAr,
    sorani: locationSorani,
    badini: locationBadini,
  ).trim();

  /// Human-readable impact line (people affected, community, or gender counts).
  /// Full long description for detail views (localized).
  String get descriptionLong {
    return localizedContentFromValues(
      base: descriptionLongEn,
      arabic: descriptionLongAr,
      sorani: descriptionLongSorani,
      badini: descriptionLongBadini,
    ).trim();
  }

  /// Beneficiary area / community name (localized).
  String get beneficiaryCommunity {
    return localizedContentFromValues(
      base: beneficiaryCommunityEn,
      arabic: beneficiaryCommunityAr,
      sorani: beneficiaryCommunitySorani,
      badini: beneficiaryCommunityBadini,
    ).trim();
  }

  String get volunteerAgeProfile => localizedContentFromValues(
    base: volunteerAgeProfileEn,
    arabic: volunteerAgeProfileAr,
    sorani: volunteerAgeProfileSorani,
    badini: volunteerAgeProfileBadini,
  ).trim();

  String get volunteerSkillsKnowledge => localizedContentFromValues(
    base: volunteerSkillsEn,
    arabic: volunteerSkillsAr,
    sorani: volunteerSkillsSorani,
    badini: volunteerSkillsBadini,
  ).trim();

  String get volunteersExtraDescription => localizedContentFromValues(
    base: volunteersExtraEn,
    arabic: volunteersExtraAr,
    sorani: volunteersExtraSorani,
    badini: volunteersExtraBadini,
  ).trim();

  String get timelineTarget => localizedContentFromValues(
    base: timelineTargetEn,
    arabic: timelineTargetAr,
    sorani: timelineTargetSorani,
    badini: timelineTargetBadini,
  ).trim();

  String get contactPersonName => localizedContentFromValues(
    base: contactPersonEn,
    arabic: contactPersonAr,
    sorani: contactPersonSorani,
    badini: contactPersonBadini,
  ).trim();

  String get otherNotes => localizedContentFromValues(
    base: otherNotesEn,
    arabic: otherNotesAr,
    sorani: otherNotesSorani,
    badini: otherNotesBadini,
  ).trim();

  String get impact {
    if (peopleAffectedTotal > 0) {
      return '@count people affected'.trParams({
        'count': '$peopleAffectedTotal',
      });
    }
    final community = beneficiaryCommunity;
    if (community.trim().isNotEmpty) return community.trim();
    if (maleCount > 0 || femaleCount > 0) {
      return '@m men · @f women'.trParams({
        'm': '$maleCount',
        'f': '$femaleCount',
      });
    }
    return '';
  }

  double get fundedProgress {
    if (amountNeeded <= 0) return 0;
    return (raisedAmount / amountNeeded).clamp(0, 1);
  }

  String get fundedLabel => '@percent% funded'.trParams({
    'percent': '${(fundedProgress * 100).round()}',
  });

  /// Shown after raised/goal numbers; defaults to IQD, maps legacy USD to IQD.
  String get _fundingCurrencySuffix {
    final raw = currency.trim();
    if (raw.isEmpty) return ' IQD';
    final u = raw.toUpperCase();
    if (u == 'USD' || u == r'US$') return ' IQD';
    return ' $raw';
  }

  /// e.g. `1,200 / 5,000 IQD` when amounts exist.
  String get fundingAmountsLine {
    if (amountNeeded <= 0 && raisedAmount <= 0) return '';
    final suffix = _fundingCurrencySuffix;
    return '@raised / @goal@suffix'.trParams({
      'raised': _formatMoney(raisedAmount),
      'goal': _formatMoney(amountNeeded),
      'suffix': suffix,
    });
  }

  String get displayRaisedAmount => _formatMoney(raisedAmount);

  String get displayAmountNeeded => _formatMoney(amountNeeded);

  static String _formatMoney(double v) {
    if (v == v.roundToDouble()) return _withThousands(v.round());
    final s = v.toStringAsFixed(2);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static String _withThousands(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return n < 0 ? '-$buf' : buf.toString();
  }

  IconData get icon {
    final key = '${categoryEn}_$categoryAr'.toLowerCase();
    if (key.contains('water') || key.contains('ماء')) {
      return Icons.water_drop_rounded;
    }
    if (key.contains('food') ||
        key.contains('غذاء') ||
        key.contains('meal') ||
        key.contains('طعام')) {
      return Icons.restaurant_rounded;
    }
    if (key.contains('health') ||
        key.contains('medical') ||
        key.contains('صح') ||
        key.contains('صحة')) {
      return Icons.local_hospital_rounded;
    }
    if (key.contains('edu') ||
        key.contains('school') ||
        key.contains('تعليم') ||
        key.contains('مدرس')) {
      return Icons.school_rounded;
    }
    if (key.contains('child') ||
        key.contains('family') ||
        key.contains('طفل') ||
        key.contains('أطفال')) {
      return Icons.child_care_rounded;
    }
    if (key.contains('shelter') ||
        key.contains('housing') ||
        key.contains('سكن') ||
        key.contains('إيواء')) {
      return Icons.home_work_rounded;
    }
    const icons = <IconData>[
      Icons.volunteer_activism_rounded,
      Icons.favorite_rounded,
      Icons.handshake_rounded,
      Icons.public_rounded,
    ];
    final idx = id != 0 ? id.abs() : titleEn.hashCode.abs();
    return icons[idx % icons.length];
  }

  Color get color {
    final seed = (categoryEn.isEmpty ? titleEn : categoryEn).hashCode.abs();
    const hues = <double>[175, 265, 32, 200, 330, 145, 25];
    final hue = hues[seed % hues.length];
    return HSVColor.fromAHSV(1, hue, 0.5, 0.88).toColor();
  }

  factory FeaturedCampaignData.fromJson(Map<String, dynamic> json) {
    int? toInt(dynamic v) => int.tryParse(v?.toString() ?? '');

    int readId() {
      for (final k in ['id', 'campaign_id', 'project_id']) {
        final n = toInt(json[k]);
        if (n != null && n > 0) return n;
      }
      return 0;
    }

    String pick(Iterable<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v == null) continue;
        final s = v.toString().trim();
        if (s.isEmpty) continue;
        if (s.toUpperCase() == 'NULL') continue;
        return s;
      }
      return '';
    }

    double readDouble(Iterable<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v == null) continue;
        if (v is num) return v.toDouble();
        final s = v.toString().replaceAll(RegExp(r'[^0-9.]'), '');
        final d = double.tryParse(s);
        if (d != null) return d;
      }
      return 0;
    }

    final titleEn = pick(['project_title', 'title', 'title_en']);
    final titleAr = pick(['project_title_ar', 'title_ar']);
    final titleSorani = pick(['project_title_sorani', 'title_sorani']);
    final titleBadini = pick(['project_title_badini', 'title_badini']);

    final summaryEn = pick(['summary', 'description', 'description_en']);
    final summaryAr = pick(['summary_ar', 'description_ar']);
    final summarySorani = pick(['summary_sorani', 'description_sorani']);
    final summaryBadini = pick(['summary_badini', 'description_badini']);

    final descEn = pick([
      'description_long',
      'description_long_en',
      'long_description',
    ]);
    final descAr = pick(['description_long_ar', 'long_description_ar']);
    final descSorani = pick(['description_long_sorani']);
    final descBadini = pick(['description_long_badini']);

    final goal = readDouble(['amount_needed', 'goal_amount', 'goal']);
    final raised = readDouble(['raised_amount', 'raised']);

    return FeaturedCampaignData(
      id: readId(),
      userId: toInt(json['user_id']) ?? 0,
      titleEn: titleEn,
      titleAr: titleAr,
      titleSorani: titleSorani,
      titleBadini: titleBadini,
      categoryEn: pick(['category', 'category_en']),
      categoryAr: pick(['category_ar']),
      categorySorani: pick(['category_sorani']),
      categoryBadini: pick(['category_badini']),
      summaryEn: summaryEn,
      summaryAr: summaryAr,
      summarySorani: summarySorani,
      summaryBadini: summaryBadini,
      descriptionLongEn: descEn.isNotEmpty ? descEn : summaryEn,
      descriptionLongAr: descAr.isNotEmpty ? descAr : summaryAr,
      descriptionLongSorani: descSorani.isNotEmpty ? descSorani : summarySorani,
      descriptionLongBadini: descBadini.isNotEmpty ? descBadini : summaryBadini,
      locationEn: pick(['location', 'address', 'address_en']),
      locationAr: pick(['location_ar', 'address_ar']),
      locationSorani: pick(['location_sorani', 'address_sorani']),
      locationBadini: pick(['location_badini', 'address_badini']),
      beneficiaryCommunityEn: pick(['beneficiary_community_name']),
      beneficiaryCommunityAr: pick(['beneficiary_community_name_ar']),
      beneficiaryCommunitySorani: pick(['beneficiary_community_name_sorani']),
      beneficiaryCommunityBadini: pick(['beneficiary_community_name_badini']),
      amountNeeded: goal,
      raisedAmount: raised,
      currency: pick(['currency']),
      peopleAffectedTotal: toInt(json['people_affected_total']) ?? 0,
      maleCount: toInt(json['male_count']) ?? 0,
      femaleCount: toInt(json['female_count']) ?? 0,
      status: pick(['status']),
      likeCount: toInt(json['like_count']) ?? 0,
      commentCount: toInt(json['comment_count']) ?? 0,
      volunteerAgeProfileEn: pick(['volunteer_age_profile']),
      volunteerAgeProfileAr: pick(['volunteer_age_profile_ar']),
      volunteerAgeProfileSorani: pick(['volunteer_age_profile_sorani']),
      volunteerAgeProfileBadini: pick(['volunteer_age_profile_badini']),
      volunteerSkillsEn: pick(['volunteer_skills_knowledge']),
      volunteerSkillsAr: pick(['volunteer_skills_knowledge_ar']),
      volunteerSkillsSorani: pick(['volunteer_skills_knowledge_sorani']),
      volunteerSkillsBadini: pick(['volunteer_skills_knowledge_badini']),
      volunteersExtraEn: pick(['people_volunteers_extra_description']),
      volunteersExtraAr: pick(['people_volunteers_extra_description_ar']),
      volunteersExtraSorani: pick([
        'people_volunteers_extra_description_sorani',
      ]),
      volunteersExtraBadini: pick([
        'people_volunteers_extra_description_badini',
      ]),
      timelineTargetEn: pick(['timeline_target']),
      timelineTargetAr: pick(['timeline_target_ar']),
      timelineTargetSorani: pick(['timeline_target_sorani']),
      timelineTargetBadini: pick(['timeline_target_badini']),
      contactPersonEn: pick(['contact_person_name']),
      contactPersonAr: pick(['contact_person_name_ar']),
      contactPersonSorani: pick(['contact_person_name_sorani']),
      contactPersonBadini: pick(['contact_person_name_badini']),
      contactPhone: pick(['contact_phone']),
      contactEmail: pick(['contact_email']),
      otherNotesEn: pick(['other_notes']),
      otherNotesAr: pick(['other_notes_ar']),
      otherNotesSorani: pick(['other_notes_sorani']),
      otherNotesBadini: pick(['other_notes_badini']),
    );
  }
}

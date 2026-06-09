import 'package:flutter/widgets.dart';
import 'package:flutter_application_1/localization/locale_service.dart';
import 'package:get/get.dart';

String currentContentLocaleTag([Locale? locale]) {
  return AppLocaleService.contentLocaleTag(locale ?? Get.locale);
}

String localizedContentFromMap(
  Map<String, dynamic> item,
  String baseKey, {
  String fallback = '',
}) {
  final order = AppLocaleService.localizedKeyOrder(baseKey, Get.locale);
  for (final key in order) {
    final value = (item[key] ?? '').toString().trim();
    if (value.isNotEmpty) {
      return value;
    }
  }
  return fallback;
}

String localizedContentFromValues({
  required String base,
  String arabic = '',
  String sorani = '',
  String badini = '',
  String fallback = '',
}) {
  final locale = Get.locale;
  final order = AppLocaleService.localizedVariantOrder(locale);
  for (final variant in order) {
    final value = switch (variant) {
      'ar' => arabic.trim(),
      'sorani' => sorani.trim(),
      'badini' => badini.trim(),
      _ => base.trim(),
    };
    if (value.isNotEmpty) {
      return value;
    }
  }
  return fallback;
}

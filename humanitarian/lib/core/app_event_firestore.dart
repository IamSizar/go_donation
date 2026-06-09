import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/core/app_state.dart';

class AppEventFirestore {
  AppEventFirestore._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> log({
    required String eventType,
    String? eventLabel,
    String? module,
    String? action,
    String status = 'success',
    int? userId,
    int? roleId,
    String? name,
    String? number,
    int? entityId,
    int? targetId,
    num? amount,
    String? currency,
    String? paymentMethod,
    String? contentLocale,
    String? note,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final resolvedUserId =
          userId ?? int.tryParse(sharedPreferences.getString('id_user') ?? '');
      final resolvedRoleId =
          roleId ?? int.tryParse(sharedPreferences.getString('role_id') ?? '');
      final resolvedName =
          _clean(name) ?? _clean(sharedPreferences.getString('name_user'));
      final resolvedNumber =
          _clean(number) ?? _clean(sharedPreferences.getString('phone_user'));

      await _firestore.collection('events').add({
        'event_type': eventType,
        'event_label': _clean(eventLabel) ?? eventType,
        'module': _clean(module),
        'action': _clean(action),
        'status': status,
        'source': 'app',
        'user_id': resolvedUserId,
        'role_id': resolvedRoleId,
        'name': resolvedName,
        'number': resolvedNumber,
        'number_digits': _digitsOnly(resolvedNumber),
        'entity_id': entityId,
        'target_id': targetId,
        'amount': amount,
        'currency': _clean(currency),
        'payment_method': _clean(paymentMethod),
        'content_locale': _clean(contentLocale),
        'note': _clean(note),
        'metadata': metadata ?? <String, dynamic>{},
        'created_at': FieldValue.serverTimestamp(),
        'created_at_ms': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {
      // Event logging should never break the main user flow.
    }
  }

  static String? _clean(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _digitsOnly(String? value) {
    if (value == null) {
      return '';
    }
    return value.replaceAll(RegExp(r'\D'), '');
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:get/get.dart';

/// The three ways the spec lets a user ask to be put in touch with a profile:
/// an in-person meeting, contact handled by a staff member, or a visit
/// request. Previously there was one generic button, so all three arrived at
/// the Admin Panel looking identical and staff could not tell what was being
/// asked for.
///
/// Returns the chosen type, or null if the user dismissed the sheet.
Future<String?> pickMarriageRequestType(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppThemeConfig.elevatedSurface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              'marriage_request_how'.tr,
              style: TextStyle(
                color: AppThemeConfig.text(context),
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.handshake_rounded),
            title: Text('marriage_request_meeting'.tr),
            subtitle: Text('marriage_request_meeting_sub'.tr),
            onTap: () => Navigator.of(ctx).pop('meeting'),
          ),
          ListTile(
            leading: const Icon(Icons.support_agent_rounded),
            title: Text('marriage_request_intermediary'.tr),
            subtitle: Text('marriage_request_intermediary_sub'.tr),
            onTap: () => Navigator.of(ctx).pop('intermediary'),
          ),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: Text('marriage_request_visit'.tr),
            subtitle: Text('marriage_request_visit_sub'.tr),
            onTap: () => Navigator.of(ctx).pop('visit'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

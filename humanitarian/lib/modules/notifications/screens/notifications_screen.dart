import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/localization/content_localizer.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';

import '../controllers/notifications_controller.dart';
import '../widgets/notification_detail_dialog.dart';
import '../models/app_notification_model.dart';
import '../widgets/notification_summary_card.dart';
import '../widgets/notification_tile.dart';
import 'package:flutter_application_1/core/widgets/app_states.dart';

class NotificationsScreen extends GetView<NotificationsController> {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GradientScreen(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: PageTopBar(title: 'Notifications'),
            ),
            Expanded(
              child: Obx(() {
                final items = controller.filteredNotifications;
                return RefreshIndicator(
                  onRefresh: controller.refreshNotifications,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    children: [
                      // The summary and filters stay OUTSIDE AppAsync: the
                      // empty state is normally "nothing matches the filters
                      // you chose", and hiding them with the results would
                      // leave no way to undo the selection that emptied the
                      // screen.
                      // countsKnown: a failed load leaves the lists empty,
                      // and an empty list renders as "All caught up / 0 / 0 /
                      // 0" — a confident claim that the user has nothing,
                      // sitting directly above a banner admitting we could not
                      // find out. Same rule as the wallet: a wrong number is
                      // worse than a missing one.
                      NotificationSummaryCard(
                        controller: controller,
                        countsKnown:
                            controller.errorMessage.value == null ||
                            controller.notifications.isNotEmpty,
                      ),
                      const SizedBox(height: 16),
                      _FilterSection(controller: controller),
                      const SizedBox(height: 16),
                      AppAsync<List<AppNotificationModel>>(
                        // `loading` is passed straight through: AppAsync only
                        // shows the skeleton when there is no data yet, so a
                        // background poll updates the list in place instead of
                        // swapping it for a spinner every few seconds - the
                        // behaviour the old `isLoading && notifications.isEmpty`
                        // guard was hand-rolling.
                        loading: controller.isLoading.value,
                        error: controller.errorMessage.value,
                        onRetry: controller.refreshNotifications,
                        data: items,
                        isEmpty: (list) => list.isEmpty,
                        // Two different empties. The list opens on Unread, so
                        // the ordinary way to arrive here is having read
                        // everything — "nothing matches your filters" would
                        // read as a fault when it is the good outcome. The
                        // filter wording is kept for the case it describes.
                        empty: AppEmpty(
                          title: 'Notifications'.tr,
                          message: controller.isDefaultFilter
                              ? 'You have read everything. New alerts appear here.'
                                    .tr
                              : 'No notifications match the selected filters.'
                                    .tr,
                        ),
                        // The error used to be a bare centred sentence with no
                        // way to recover - a dead end for anyone who lost
                        // connection.
                        builder: (list) => Column(
                          children: [
                            for (var i = 0; i < list.length; i++) ...[
                              NotificationTile(
                                notification: list[i],
                                // Show the whole record first; the type's
                                // destination (when it has one) is an explicit
                                // action inside the dialog.
                                onTap: () async {
                                  final n = list[i];
                                  await controller.markAsRead(n);
                                  if (!context.mounted) return;
                                  await showNotificationDetail(
                                    context,
                                    n,
                                    onOpen: controller.destinationFor(n),
                                  );
                                },
                                onDismissed: list[i].isRead
                                    ? null
                                    : () => controller.markAsRead(list[i]),
                              ),
                              if (i < list.length - 1)
                                const SizedBox(height: 12),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.controller});

  final NotificationsController controller;

  @override
  Widget build(BuildContext context) {
    final categories = const [
      ('all', 'All categories'),
      ('urgent', 'Urgent'),
      ('payment', 'Payment'),
      ('campaign', 'Campaign'),
      ('system', 'System'),
      ('reminder', 'Reminder'),
      ('normal', 'Normal'),
    ];

    // Compact by design. This block used to be three headed sections — a
    // 3-chip row, a 7-chip grid that wrapped onto two lines, and a full-width
    // dropdown, each under its own bold heading. On a 402pt screen that spent
    // more than half the viewport on filters before a single notification was
    // visible, which is backwards for a list you open to read the list.
    //
    // Now: one line of status chips, then category and type side by side.
    //
    // The headings are gone but nothing lost its name. The status chips show
    // every option at once, so the group explains itself. The two dropdowns
    // carry `labelText`, which floats above the selected value — that keeps
    // the property B20 was about (a closed dropdown must say what it filters,
    // not just show its current value) while costing no extra row, and the
    // label is also the control's accessible name.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppThemeConfig.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeConfig.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in const [
                ('all', 'All'),
                ('unread', 'Unread'),
                ('read', 'Read'),
              ])
                ChoiceChip(
                  label: Text(
                    entry.$2.tr,
                    style: const TextStyle(fontSize: 13),
                  ),
                  selected: controller.selectedReadStatus.value == entry.$1,
                  onSelected: (_) => controller.setReadStatus(entry.$1),
                  visualDensity: VisualDensity.compact,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _CompactDropdown(
                  label: 'Category'.tr,
                  value: controller.selectedCategory.value,
                  items: [
                    for (final entry in categories)
                      DropdownMenuItem<String>(
                        value: entry.$1,
                        child: Text(
                          entry.$2.tr,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => controller.setCategory(value ?? 'all'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CompactDropdown(
                  label: 'Type'.tr,
                  value: controller.selectedType.value,
                  items: [
                    DropdownMenuItem<String>(
                      value: 'all',
                      child: Text(
                        'All types'.tr,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // The options are backend notification_type enums, built
                    // from whatever the API actually returned. They were
                    // rendered raw, one line below a sibling that uses `.tr`,
                    // so the Arabic UI listed `marketplace_order_approved` and
                    // `system_test`.
                    //
                    // localizedTag is the app's single mechanism for a backend
                    // tag: a translated label wins, and anything the server
                    // adds before it is translated degrades to readable words
                    // instead of snake_case. The VALUE stays the raw enum — it
                    // is what the filter sends back to the controller.
                    ...controller.availableTypes.map(
                      (type) => DropdownMenuItem<String>(
                        value: type,
                        child: Text(
                          localizedTag(type),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) => controller.setType(value ?? 'all'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A dropdown sized for a filter row rather than a form.
///
/// Two of these sit side by side on a 402pt screen, so it is dense, its label
/// floats instead of occupying its own line, and its selected value ellipsises
/// rather than overflowing — notification type names are long and arrive from
/// the server, so no fixed width can be assumed safe.
class _CompactDropdown extends StatelessWidget {
  const _CompactDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: AppThemeConfig.border(context)),
    );
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      isDense: true,
      style: TextStyle(fontSize: 13, color: AppThemeConfig.text(context)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontSize: 13,
          color: AppThemeConfig.mutedText(context),
        ),
        floatingLabelStyle: TextStyle(
          fontSize: 12,
          color: AppThemeConfig.mutedText(context),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        filled: true,
        fillColor: AppThemeConfig.softSurface(context),
        border: border,
        enabledBorder: border,
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

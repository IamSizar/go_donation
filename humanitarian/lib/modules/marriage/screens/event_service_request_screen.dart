import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/links.dart';
import 'package:flutter_application_1/api/module_api.dart';
import 'package:flutter_application_1/core/app_state.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:flutter_application_1/localization/failure_message.dart';
import 'package:get/get.dart';

/// Simple request form for the event-services tiles on the Events hub (Hall
/// booking, Photographer, Wedding stage setup, Decorations, Tents &
/// equipment, or a free-text "other" service). Reuses the existing support
/// ticket endpoint — same pattern as Technical Support — so no new backend
/// work was needed; the service name just gets folded into the subject line
/// so staff can triage it like any other request.
class EventServiceRequestScreen extends StatefulWidget {
  const EventServiceRequestScreen({
    super.key,
    required this.serviceLabel,
    this.customService = false,
  });

  /// Fixed service name (e.g. "Hall booking"), or the generic label shown
  /// for the free-text "Add another service" tile.
  final String serviceLabel;

  /// When true, the service name is a free-text field the user fills in
  /// (the "Add another service" tile) instead of a fixed label.
  final bool customService;

  @override
  State<EventServiceRequestScreen> createState() =>
      _EventServiceRequestScreenState();
}

class _EventServiceRequestScreenState extends State<EventServiceRequestScreen> {
  late final TextEditingController _serviceController;
  final _nameController = TextEditingController(
    text: sharedPreferences.getString('name_user') ?? '',
  );
  final _phoneController = TextEditingController(
    text: sharedPreferences.getString('phone_user') ?? '',
  );
  final _detailsController = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _serviceController = TextEditingController(
      text: widget.customService ? '' : widget.serviceLabel,
    );
  }

  @override
  void dispose() {
    _serviceController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final service = _serviceController.text.trim();
    if (service.isEmpty || _nameController.text.trim().isEmpty) {
      Get.snackbar(
        'Missing details'.tr,
        'Please fill in the service and your name.'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await const ModuleApi().postJson(supportTicketsUrl, {
        'user_id': sharedPreferences.getString('id_user') ?? '',
        'subject': 'Event service request: $service',
        'message':
            'Name: ${_nameController.text.trim()}\n'
            'Phone: ${_phoneController.text.trim()}\n\n'
            '${_detailsController.text.trim()}',
      });
      if (!mounted) return;
      Get.back<void>();
      Get.snackbar('Submitted'.tr, 'Your request was sent to our team.'.tr);
    } catch (e) {
      debugPrint('event service request failed: $e');
      if (mounted) {
        Get.snackbar(
          'Error'.tr,
          failureMessage(e, 'error_service_request_failed'),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionScaffold(
      title: widget.customService ? 'Request a service' : widget.serviceLabel,
      subtitle: 'Tell us what you need and our team will get back to you.',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          GlassPanel(
            child: Column(
              children: [
                if (widget.customService) ...[
                  TextField(
                    controller: _serviceController,
                    decoration: InputDecoration(labelText: 'Service'.tr),
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(labelText: 'Full name'.tr),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: 'Phone'.tr),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _detailsController,
                  maxLines: 4,
                  decoration: InputDecoration(labelText: 'Details'.tr),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('Send request'.tr),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

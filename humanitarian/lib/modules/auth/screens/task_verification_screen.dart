import 'package:flutter/material.dart';
import 'package:flutter_application_1/api/task_api.dart';
import 'package:flutter_application_1/core/theme/app_theme_config.dart';
import 'package:flutter_application_1/shared/widgets/glass_ui.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// Client note — "Task Verification": staff assign a task from the admin
/// dashboard; the user sees it here and marks it done themselves (a
/// self-reported completion, not a separate admin re-verification step).
class TaskVerificationScreen extends StatefulWidget {
  const TaskVerificationScreen({super.key});

  @override
  State<TaskVerificationScreen> createState() =>
      _TaskVerificationScreenState();
}

class _TaskVerificationScreenState extends State<TaskVerificationScreen> {
  bool _loading = true;
  List<AppTask> _tasks = const [];
  final _completing = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tasks = await fetchMyTasks();
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _loading = false;
    });
  }

  Future<void> _markDone(AppTask task) async {
    setState(() => _completing.add(task.id));
    final ok = await completeTask(task.id);
    if (!mounted) return;
    setState(() => _completing.remove(task.id));
    if (ok) {
      Get.snackbar('Task Verification'.tr, 'Task marked as done.'.tr);
      await _load();
    } else {
      Get.snackbar('Error'.tr, 'Unable to update the task. Try again.'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _tasks.where((t) => !t.isCompleted).toList();
    final completed = _tasks.where((t) => t.isCompleted).toList();

    return SectionScaffold(
      title: 'Task Verification',
      subtitle: 'Tasks assigned to you — mark them done when finished.',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  if (_tasks.isEmpty)
                    SectionTile(
                      icon: Icons.fact_check_rounded,
                      title: 'Task Verification',
                      subtitle: 'No tasks have been assigned to you yet.'.tr,
                      color: Colors.deepOrange,
                    ),
                  if (pending.isNotEmpty) ...[
                    SectionLabel(title: 'Pending'.tr),
                    const SizedBox(height: 10),
                    for (var i = 0; i < pending.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _TaskCard(
                        task: pending[i],
                        completing: _completing.contains(pending[i].id),
                        onMarkDone: () => _markDone(pending[i]),
                      ),
                    ],
                    const SizedBox(height: 22),
                  ],
                  if (completed.isNotEmpty) ...[
                    SectionLabel(title: 'Completed'.tr),
                    const SizedBox(height: 10),
                    for (var i = 0; i < completed.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _TaskCard(task: completed[i]),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, this.completing = false, this.onMarkDone});

  final AppTask task;
  final bool completing;
  final VoidCallback? onMarkDone;

  @override
  Widget build(BuildContext context) {
    final locale = Get.locale?.toLanguageTag() ?? 'en';
    final date = DateFormat.yMMMd(locale).format(task.createdAt.toLocal());

    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TileIcon(
            icon: task.isCompleted
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: task.isCompleted ? Colors.green : Colors.deepOrange,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppThemeConfig.text(context),
                  ),
                ),
                if (task.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    task.description,
                    style: TextStyle(
                      color: AppThemeConfig.mutedText(context),
                      height: 1.4,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  date,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppThemeConfig.mutedText(context),
                  ),
                ),
                if (!task.isCompleted) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: completing ? null : onMarkDone,
                      icon: completing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded, size: 16),
                      label: Text('Mark as done'.tr),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

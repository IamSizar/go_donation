import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_session.dart';
import 'links.dart';

/// Client note — "Task Verification": staff assign a task to a user, who
/// sees it here and marks it done themselves.
class AppTask {
  const AppTask({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.createdAt,
    this.completedAt,
  });

  final int id;
  final String title;
  final String description;
  final String status; // pending | completed
  final DateTime createdAt;
  final DateTime? completedAt;

  bool get isCompleted => status == 'completed';

  factory AppTask.fromMap(Map<String, dynamic> m) {
    return AppTask(
      id: int.tryParse('${m['id']}') ?? 0,
      title: (m['title'] ?? '').toString(),
      description: (m['description'] ?? '').toString(),
      status: (m['status'] ?? 'pending').toString(),
      createdAt: DateTime.tryParse('${m['created_at']}') ?? DateTime.now(),
      completedAt: m['completed_at'] == null
          ? null
          : DateTime.tryParse('${m['completed_at']}'),
    );
  }
}

/// Fetches the current user's own assigned tasks.
Future<List<AppTask>> fetchMyTasks() async {
  try {
    final resp = await http
        .get(Uri.parse(tasksUrl), headers: withApiAuthHeaders())
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) return [];
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map || decoded['tasks'] is! List) return [];
    return (decoded['tasks'] as List)
        .whereType<Map>()
        .map((m) => AppTask.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  } catch (_) {
    return [];
  }
}

/// Marks one of the current user's own tasks as done.
Future<bool> completeTask(int taskId) async {
  try {
    final resp = await http
        .post(
          Uri.parse('$tasksUrl/$taskId/complete'),
          headers: withApiAuthHeaders(),
        )
        .timeout(const Duration(seconds: 12));
    return resp.statusCode == 200;
  } catch (_) {
    return false;
  }
}

import 'dart:convert';

class TaskEvent {
  const TaskEvent({
    required this.type,
    this.requestId,
    this.taskId,
    this.data = const <String, dynamic>{},
  });

  final String type;
  final String? requestId;
  final String? taskId;
  final Map<String, dynamic> data;

  bool get isTaskEvent => type.startsWith('task_');

  factory TaskEvent.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final eventData = rawData is Map
        ? rawData.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};

    return TaskEvent(
      type: json['type']?.toString() ?? '',
      requestId: _stringOrNull(json['requestId'] ?? json['request_id']),
      taskId: _stringOrNull(json['taskId'] ?? json['task_id']),
      data: eventData,
    );
  }

  static TaskEvent? tryParseMessage(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) {
        return null;
      }

      final payload =
          decoded.map((key, value) => MapEntry(key.toString(), value));
      final event = TaskEvent.fromJson(payload);
      if (!event.isTaskEvent) {
        return null;
      }

      return event;
    } catch (_) {
      return null;
    }
  }

  static String? _stringOrNull(dynamic value) {
    final normalized = value?.toString().trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}

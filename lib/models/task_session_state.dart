import 'task_event.dart';
import 'task_step.dart';

class TaskSessionState {
  const TaskSessionState({
    this.requestId,
    this.taskId,
    this.status,
    this.steps = const <TaskStep>[],
    this.lastData = const <String, dynamic>{},
  });

  final String? requestId;
  final String? taskId;
  final String? status;
  final List<TaskStep> steps;
  final Map<String, dynamic> lastData;

  TaskSessionState copyWith({
    String? requestId,
    String? taskId,
    String? status,
    List<TaskStep>? steps,
    Map<String, dynamic>? lastData,
  }) {
    return TaskSessionState(
      requestId: requestId ?? this.requestId,
      taskId: taskId ?? this.taskId,
      status: status ?? this.status,
      steps: steps ?? this.steps,
      lastData: lastData ?? this.lastData,
    );
  }

  TaskSessionState applyEvent(TaskEvent event) {
    final nextStatus = _parseStatus(event.data) ?? status;
    final nextSteps = _parseSteps(event.data, steps);

    return copyWith(
      requestId: event.requestId ?? requestId,
      taskId: event.taskId ?? taskId,
      status: nextStatus,
      steps: nextSteps,
      lastData: event.data,
    );
  }

  static String? _parseStatus(Map<String, dynamic> data) {
    final value = data['status'];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  static List<TaskStep> _parseSteps(
    Map<String, dynamic> data,
    List<TaskStep> current,
  ) {
    final stepsPayload = data['steps'];
    if (stepsPayload is List) {
      final parsed = <TaskStep>[];
      for (final item in stepsPayload) {
        if (item is! Map) {
          continue;
        }
        parsed.add(
          TaskStep.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        );
      }
      return parsed;
    }

    final singleStep = data['step'];
    if (singleStep is Map) {
      final step = TaskStep.fromJson(
        singleStep.map((key, value) => MapEntry(key.toString(), value)),
      );
      final next = List<TaskStep>.from(current);
      final index = next.indexWhere((item) => item.id == step.id);
      if (index >= 0) {
        next[index] = step;
      } else {
        next.add(step);
      }
      return next;
    }

    return current;
  }
}

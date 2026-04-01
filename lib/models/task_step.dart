class TaskStep {
  const TaskStep({
    required this.id,
    required this.status,
    this.title,
    this.data = const <String, dynamic>{},
  });

  final String id;
  final String status;
  final String? title;
  final Map<String, dynamic> data;

  factory TaskStep.fromJson(Map<String, dynamic> json) {
    final stepId =
        (json['id'] ?? json['stepId'] ?? json['step_id'])?.toString() ?? '';
    final status = (json['status'] ?? '').toString();
    final title = json['title']?.toString();

    return TaskStep(
      id: stepId,
      status: status,
      title: title,
      data: json,
    );
  }

  TaskStep copyWith({
    String? id,
    String? status,
    String? title,
    Map<String, dynamic>? data,
  }) {
    return TaskStep(
      id: id ?? this.id,
      status: status ?? this.status,
      title: title ?? this.title,
      data: data ?? this.data,
    );
  }
}

/// 历史消息模型，仅记录输入文本与时间信息。
class ConversationMessage {
  const ConversationMessage({
    required this.id,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String text;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ConversationMessage.fromJson(Map<String, dynamic> json) {
    final currentText = (json['text'] as String?)?.trim();
    final legacyText = (json['userText'] as String?)?.trim();
    final resolvedText = (currentText?.isNotEmpty ?? false)
        ? currentText!
        : (legacyText?.isNotEmpty ?? false)
            ? legacyText!
            : '';

    return ConversationMessage(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? (json['id'] as String).trim()
          : DateTime.now().microsecondsSinceEpoch.toString(),
      text: resolvedText,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

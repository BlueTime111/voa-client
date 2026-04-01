import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nova_voice_assistant/models/conversation_message.dart';
import 'package:nova_voice_assistant/providers/app_provider.dart';

void main() {
  test('ConversationMessage.fromJson reads legacy userText field', () {
    final message = ConversationMessage.fromJson(<String, dynamic>{
      'id': 'legacy-1',
      'userText': 'open taobao and search 三国',
      'assistantText': 'ignored for history',
      'createdAt': '2026-03-29T10:00:00Z',
    });

    expect(message.text, 'open taobao and search 三国');
  });

  test('ConversationMessage.toJson persists text-only payload', () {
    final message = ConversationMessage(
      id: 'new-1',
      text: 'buy milk',
      createdAt: DateTime.parse('2026-03-29T10:00:00Z'),
    );

    final raw = message.toJson();
    expect(raw['text'], 'buy milk');
    expect(raw.containsKey('userText'), isFalse);
    expect(raw.containsKey('assistantText'), isFalse);
  });

  test('AppProvider stores text history newest first', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final provider = AppProvider();

    await provider.load();
    await provider.addHistoryText('first input');
    await provider.addHistoryText('second input');

    expect(provider.history, hasLength(2));
    expect(provider.history.first.text, 'second input');
    expect(provider.history[1].text, 'first input');
  });
}

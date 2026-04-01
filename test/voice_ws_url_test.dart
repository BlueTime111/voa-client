import 'package:flutter_test/flutter_test.dart';

import 'package:nova_voice_assistant/utils/voice_ws_url.dart';

void main() {
  test('deriveVoiceUrlFromAgentUrl replaces /agent with /voice', () {
    final url = deriveVoiceUrlFromAgentUrl('ws://127.0.0.1:18080/agent');

    expect(url, 'ws://127.0.0.1:18080/voice');
  });

  test('deriveVoiceUrlFromAgentUrl keeps query parameters', () {
    final url =
        deriveVoiceUrlFromAgentUrl('ws://10.0.2.2:18080/agent?token=abc');

    expect(url, 'ws://10.0.2.2:18080/voice?token=abc');
  });

  test('deriveVoiceUrlFromAgentUrl appends /voice when no /agent suffix', () {
    final url = deriveVoiceUrlFromAgentUrl('ws://localhost:8080/ws');

    expect(url, 'ws://localhost:8080/ws/voice');
  });

  test('deriveVoiceUrlFromAgentUrl keeps /voice unchanged', () {
    final url = deriveVoiceUrlFromAgentUrl('ws://127.0.0.1:18080/voice');

    expect(url, 'ws://127.0.0.1:18080/voice');
  });
}

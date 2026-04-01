/// AppConfig 模型序列化测试。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nova_voice_assistant/models/app_config.dart';
import 'package:nova_voice_assistant/utils/constants.dart';

void main() {
  test('AppConfig initial should default to custom websocket', () {
    final config = AppConfig.initial();

    expect(config.communicationMode, CommunicationMode.customWebSocket);
    expect(
      config.activeWebSocketUrl,
      AppConstants.defaultCustomWebSocketUrl,
    );
  });

  test('AppConfig should serialize and deserialize correctly', () {
    const config = AppConfig(
      communicationMode: CommunicationMode.customWebSocket,
      geminiWebSocketUrl: 'wss://gemini.example/ws',
      customWebSocketUrl: 'ws://localhost:8080/ws',
      audioQuality: AudioQuality.high,
      autoSendDelay: Duration(milliseconds: 900),
      themeMode: ThemeMode.dark,
    );

    final json = config.toJson();
    final parsed = AppConfig.fromJson(json);

    expect(parsed.communicationMode, config.communicationMode);
    expect(parsed.geminiWebSocketUrl, config.geminiWebSocketUrl);
    expect(parsed.customWebSocketUrl, config.customWebSocketUrl);
    expect(parsed.activeWebSocketUrl, config.activeWebSocketUrl);
    expect(parsed.audioQuality, config.audioQuality);
    expect(parsed.autoSendDelay, config.autoSendDelay);
    expect(parsed.themeMode, config.themeMode);
  });
}

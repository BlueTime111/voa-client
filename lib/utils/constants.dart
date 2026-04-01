/// 应用常量与主题色定义。
import 'package:flutter/material.dart';

class AppConstants {
  static const String appName = 'Voice On Assistant';

  static const String defaultGeminiWebSocketUrl =
      'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';
  static const String defaultCustomWebSocketUrl =
      'ws://<backend-ip>:18080/agent';

  /// 兼容旧配置与旧代码路径，默认指向自定义 WebSocket。
  static const String defaultWebSocketUrl = defaultCustomWebSocketUrl;

  static const int sampleRate = 16000;
  static const int numChannels = 1;
  static const int bitDepth = 16;
  static const Duration heartbeatInterval = Duration(seconds: 10);
  static const Duration heartbeatTimeout = Duration(seconds: 25);
  static const int voiceIdleDisconnectSeconds = 90;
  static const int maxReconnectAttempts = 3;
  static const int reconnectBaseSeconds = 1;

  static const int defaultChunkDurationMs = 200;
  static const String prefsConfigKey = 'app_config';
  static const String prefsHistoryKey = 'conversation_history';

  static int chunkSizeBytesFrom(Duration duration) {
    final totalMs = duration.inMilliseconds;
    final bytesPerSecond = sampleRate * numChannels * (bitDepth ~/ 8);
    return (bytesPerSecond * totalMs) ~/ 1000;
  }
}

class AppColors {
  static const Color backgroundStart = Color(0xFF0A1929);
  static const Color backgroundEnd = Color(0xFF000000);
  static const Color primaryBlue = Color(0xFF1E88E5);
  static const Color accentBlue = Color(0xFF42A5F5);
  static const Color textSecondary = Color(0xFFBDBDBD);
  static const Color navIcon = Color(0xFF9E9E9E);
}

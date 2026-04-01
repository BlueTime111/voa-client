/// 应用配置模型，保存 WebSocket、音频质量、发送延迟和主题模式。
import 'package:flutter/material.dart';

import '../utils/constants.dart';

enum CommunicationMode {
  geminiWebSocket,
  customWebSocket,
}

extension CommunicationModeX on CommunicationMode {
  String get label {
    switch (this) {
      case CommunicationMode.geminiWebSocket:
        return 'Gemini WebSocket';
      case CommunicationMode.customWebSocket:
        return 'Custom WebSocket';
    }
  }
}

enum AudioQuality {
  low,
  medium,
  high,
}

extension AudioQualityX on AudioQuality {
  String get label {
    switch (this) {
      case AudioQuality.low:
        return 'Low';
      case AudioQuality.medium:
        return 'Medium';
      case AudioQuality.high:
        return 'High';
    }
  }

  Duration get chunkDuration {
    switch (this) {
      case AudioQuality.low:
        return const Duration(milliseconds: 500);
      case AudioQuality.medium:
        return const Duration(
            milliseconds: AppConstants.defaultChunkDurationMs);
      case AudioQuality.high:
        return const Duration(milliseconds: 180);
    }
  }
}

class AppConfig {
  const AppConfig({
    required this.communicationMode,
    required this.geminiWebSocketUrl,
    required this.customWebSocketUrl,
    required this.audioQuality,
    required this.autoSendDelay,
    required this.themeMode,
  });

  final CommunicationMode communicationMode;
  final String geminiWebSocketUrl;
  final String customWebSocketUrl;
  final AudioQuality audioQuality;
  final Duration autoSendDelay;
  final ThemeMode themeMode;

  String get activeWebSocketUrl {
    switch (communicationMode) {
      case CommunicationMode.geminiWebSocket:
        return geminiWebSocketUrl;
      case CommunicationMode.customWebSocket:
        return customWebSocketUrl;
    }
  }

  /// 兼容旧调用方语义：返回当前模式生效 URL。
  String get webSocketUrl => activeWebSocketUrl;

  factory AppConfig.initial() {
    return const AppConfig(
      communicationMode: CommunicationMode.customWebSocket,
      geminiWebSocketUrl: AppConstants.defaultGeminiWebSocketUrl,
      customWebSocketUrl: AppConstants.defaultCustomWebSocketUrl,
      audioQuality: AudioQuality.medium,
      autoSendDelay: Duration(milliseconds: 180),
      themeMode: ThemeMode.dark,
    );
  }

  AppConfig copyWith({
    CommunicationMode? communicationMode,
    String? geminiWebSocketUrl,
    String? customWebSocketUrl,
    String? webSocketUrl,
    AudioQuality? audioQuality,
    Duration? autoSendDelay,
    ThemeMode? themeMode,
  }) {
    final nextMode = communicationMode ?? this.communicationMode;
    var nextGeminiUrl = geminiWebSocketUrl ?? this.geminiWebSocketUrl;
    var nextCustomUrl = customWebSocketUrl ?? this.customWebSocketUrl;

    if (webSocketUrl != null) {
      if (nextMode == CommunicationMode.geminiWebSocket) {
        nextGeminiUrl = webSocketUrl;
      } else {
        nextCustomUrl = webSocketUrl;
      }
    }

    return AppConfig(
      communicationMode: nextMode,
      geminiWebSocketUrl: nextGeminiUrl,
      customWebSocketUrl: nextCustomUrl,
      audioQuality: audioQuality ?? this.audioQuality,
      autoSendDelay: autoSendDelay ?? this.autoSendDelay,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'communicationMode': communicationMode.name,
      'geminiWebSocketUrl': geminiWebSocketUrl,
      'customWebSocketUrl': customWebSocketUrl,
      // 兼容历史版本序列化字段。
      'webSocketUrl': activeWebSocketUrl,
      'audioQuality': audioQuality.name,
      'autoSendDelayMs': autoSendDelay.inMilliseconds,
      'themeMode': themeMode.name,
    };
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final legacyUrl = (json['webSocketUrl'] as String?)?.trim();
    final modeName = json['communicationMode'] as String?;
    final inferredLegacyMode = _isGeminiWebSocketUrl(legacyUrl)
        ? CommunicationMode.geminiWebSocket
        : CommunicationMode.customWebSocket;

    final mode = CommunicationMode.values.firstWhere(
      (value) => value.name == modeName,
      orElse: () => inferredLegacyMode,
    );

    final rawGeminiUrl = (json['geminiWebSocketUrl'] as String?)?.trim();
    final rawCustomUrl = (json['customWebSocketUrl'] as String?)?.trim();

    final geminiUrl = (rawGeminiUrl != null && rawGeminiUrl.isNotEmpty)
        ? rawGeminiUrl
        : (_isGeminiWebSocketUrl(legacyUrl)
            ? legacyUrl!
            : AppConstants.defaultGeminiWebSocketUrl);

    final customUrl = (rawCustomUrl != null && rawCustomUrl.isNotEmpty)
        ? rawCustomUrl
        : (!_isGeminiWebSocketUrl(legacyUrl) &&
                legacyUrl != null &&
                legacyUrl.isNotEmpty
            ? legacyUrl
            : AppConstants.defaultCustomWebSocketUrl);

    final qualityName =
        json['audioQuality'] as String? ?? AudioQuality.medium.name;
    final themeName = json['themeMode'] as String? ?? ThemeMode.dark.name;

    return AppConfig(
      communicationMode: mode,
      geminiWebSocketUrl: geminiUrl,
      customWebSocketUrl: customUrl,
      audioQuality: AudioQuality.values.firstWhere(
        (value) => value.name == qualityName,
        orElse: () => AudioQuality.medium,
      ),
      autoSendDelay: Duration(
        milliseconds: (json['autoSendDelayMs'] as int?) ?? 180,
      ),
      themeMode: ThemeMode.values.firstWhere(
        (value) => value.name == themeName,
        orElse: () => ThemeMode.dark,
      ),
    );
  }

  static bool _isGeminiWebSocketUrl(String? url) {
    if (url == null || url.isEmpty) {
      return false;
    }
    return url.contains(
      'generativelanguage.googleapis.com/ws/google.ai.generativelanguage.',
    );
  }
}

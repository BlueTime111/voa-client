/// 程序主入口：初始化 Provider 并启动应用。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'providers/app_provider.dart';
import 'providers/audio_provider.dart';
import 'providers/voice_websocket_provider.dart';
import 'providers/websocket_provider.dart';
import 'services/audio_service.dart';
import 'services/permission_service.dart';
import 'services/websocket_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppProvider>(
          create: (_) => AppProvider()..load(),
        ),
        ChangeNotifierProvider<AudioProvider>(
          create: (_) => AudioProvider(
            audioService: AudioService(),
            permissionService: PermissionService(),
          ),
        ),
        ChangeNotifierProvider<WebSocketProvider>(
          create: (_) => WebSocketProvider(
            webSocketService: WebSocketService(),
          )..init(),
        ),
        ChangeNotifierProvider<VoiceWebSocketProvider>(
          create: (_) => VoiceWebSocketProvider(
            webSocketService: WebSocketService(),
          )..init(),
        ),
      ],
      child: const NovaVoiceAssistantApp(),
    ),
  );

  unawaited(
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: <SystemUiOverlay>[SystemUiOverlay.bottom],
    ),
  );
}

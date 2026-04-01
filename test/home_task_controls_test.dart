import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nova_voice_assistant/providers/app_provider.dart';
import 'package:nova_voice_assistant/providers/audio_provider.dart';
import 'package:nova_voice_assistant/providers/voice_websocket_provider.dart';
import 'package:nova_voice_assistant/providers/websocket_provider.dart';
import 'package:nova_voice_assistant/screens/home_screen.dart';
import 'package:nova_voice_assistant/services/audio_service.dart';
import 'package:nova_voice_assistant/services/permission_service.dart';
import 'package:nova_voice_assistant/services/websocket_service.dart';
import 'package:nova_voice_assistant/utils/constants.dart';
import 'package:nova_voice_assistant/widgets/voice_button.dart';

void main() {
  testWidgets('running task shows stop icon and sends task_cancel',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final appProvider = AppProvider();
    final fakeAudioService = _FakeAudioService();
    final audioProvider = AudioProvider(
      audioService: fakeAudioService,
      permissionService: _FakePermissionService(),
    );
    final webSocketService = _FakeWebSocketService();
    final wsProvider = WebSocketProvider(webSocketService: webSocketService)
      ..init();
    final voiceWebSocketService = _FakeWebSocketService();
    final voiceWsProvider =
        VoiceWebSocketProvider(webSocketService: voiceWebSocketService)..init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: appProvider),
          ChangeNotifierProvider<AudioProvider>.value(value: audioProvider),
          ChangeNotifierProvider<WebSocketProvider>.value(value: wsProvider),
          ChangeNotifierProvider<VoiceWebSocketProvider>.value(
            value: voiceWsProvider,
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    webSocketService.emitMessage(jsonEncode(<String, dynamic>{
      'type': 'task_created',
      'requestId': 'req-1',
      'taskId': 'task-1',
      'data': <String, dynamic>{},
    }));
    webSocketService.emitMessage(jsonEncode(<String, dynamic>{
      'type': 'task_status',
      'requestId': 'req-1',
      'taskId': 'task-1',
      'data': <String, dynamic>{'status': 'running'},
    }));
    webSocketService.emitStatus(WsConnectionStatus.connected);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    expect(webSocketService.sentMessages, isNotEmpty);
    final payload =
        jsonDecode(webSocketService.sentMessages.last) as Map<String, dynamic>;
    expect(payload['type'], 'task_cancel');
    expect(payload['taskId'], 'task-1');
  });

  testWidgets('mic tap lazily connects voice socket and starts recording',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final appProvider = AppProvider();
    final fakeAudioService = _FakeAudioService();
    final audioProvider = AudioProvider(
      audioService: fakeAudioService,
      permissionService: _FakePermissionService(),
    );
    final taskWebSocketService = _FakeWebSocketService();
    final wsProvider = WebSocketProvider(webSocketService: taskWebSocketService)
      ..init();
    final voiceWebSocketService = _FakeWebSocketService();
    final voiceWsProvider =
        VoiceWebSocketProvider(webSocketService: voiceWebSocketService)..init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: appProvider),
          ChangeNotifierProvider<AudioProvider>.value(value: audioProvider),
          ChangeNotifierProvider<WebSocketProvider>.value(value: wsProvider),
          ChangeNotifierProvider<VoiceWebSocketProvider>.value(
            value: voiceWsProvider,
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(taskWebSocketService.connectCalls, 0);
    expect(voiceWebSocketService.connectCalls, 1);
    expect(voiceWebSocketService.lastConnectedUrl, endsWith('/voice'));
    expect(fakeAudioService.startRecordingCalls, 1);
    expect(voiceWebSocketService.asrStartCalls, 1);
  });

  testWidgets('connect icon toggles websocket connect and disconnect',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final appProvider = AppProvider();
    final audioProvider = AudioProvider(
      audioService: _FakeAudioService(),
      permissionService: _FakePermissionService(),
    );
    final webSocketService = _FakeWebSocketService();
    final wsProvider = WebSocketProvider(webSocketService: webSocketService)
      ..init();
    final voiceWebSocketService = _FakeWebSocketService();
    final voiceWsProvider =
        VoiceWebSocketProvider(webSocketService: voiceWebSocketService)..init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: appProvider),
          ChangeNotifierProvider<AudioProvider>.value(value: audioProvider),
          ChangeNotifierProvider<WebSocketProvider>.value(value: wsProvider),
          ChangeNotifierProvider<VoiceWebSocketProvider>.value(
            value: voiceWsProvider,
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    expect(find.byIcon(Icons.link_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.link_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(webSocketService.connectCalls, 1);

    expect(find.byIcon(Icons.link_off_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.link_off_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(webSocketService.disconnectCalls, 1);
  });

  testWidgets('connected websocket makes orb active even before recording',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final appProvider = AppProvider();
    final audioProvider = AudioProvider(
      audioService: _FakeAudioService(),
      permissionService: _FakePermissionService(),
    );
    final webSocketService = _FakeWebSocketService();
    final wsProvider = WebSocketProvider(webSocketService: webSocketService)
      ..init();
    final voiceWebSocketService = _FakeWebSocketService();
    final voiceWsProvider =
        VoiceWebSocketProvider(webSocketService: voiceWebSocketService)..init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: appProvider),
          ChangeNotifierProvider<AudioProvider>.value(value: audioProvider),
          ChangeNotifierProvider<WebSocketProvider>.value(value: wsProvider),
          ChangeNotifierProvider<VoiceWebSocketProvider>.value(
            value: voiceWsProvider,
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    webSocketService.emitStatus(WsConnectionStatus.connected);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final voiceButton = tester.widget<VoiceButton>(find.byType(VoiceButton));
    expect(voiceButton.isListening, isTrue);
  });

  testWidgets('home copy uses natural Chinese strings', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final appProvider = AppProvider();
    final audioProvider = AudioProvider(
      audioService: _FakeAudioService(),
      permissionService: _FakePermissionService(),
    );
    final webSocketService = _FakeWebSocketService();
    final wsProvider = WebSocketProvider(webSocketService: webSocketService)
      ..init();
    final voiceWebSocketService = _FakeWebSocketService();
    final voiceWsProvider =
        VoiceWebSocketProvider(webSocketService: voiceWebSocketService)..init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: appProvider),
          ChangeNotifierProvider<AudioProvider>.value(value: audioProvider),
          ChangeNotifierProvider<WebSocketProvider>.value(value: wsProvider),
          ChangeNotifierProvider<VoiceWebSocketProvider>.value(
            value: voiceWsProvider,
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('今天想让我帮你做什么？'), findsOneWidget);
    expect(find.text('点击连接以开始，点麦克风可直接说话。'), findsOneWidget);
    expect(find.text('告诉我你想让我做什么'), findsOneWidget);
  });

  testWidgets('voice asr_final fills task input field', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final appProvider = AppProvider();
    final audioProvider = AudioProvider(
      audioService: _FakeAudioService(),
      permissionService: _FakePermissionService(),
    );
    final taskWebSocketService = _FakeWebSocketService();
    final wsProvider = WebSocketProvider(webSocketService: taskWebSocketService)
      ..init();
    final voiceWebSocketService = _FakeWebSocketService();
    final voiceWsProvider =
        VoiceWebSocketProvider(webSocketService: voiceWebSocketService)..init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: appProvider),
          ChangeNotifierProvider<AudioProvider>.value(value: audioProvider),
          ChangeNotifierProvider<WebSocketProvider>.value(value: wsProvider),
          ChangeNotifierProvider<VoiceWebSocketProvider>.value(
            value: voiceWsProvider,
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    voiceWebSocketService.emitMessage(
      jsonEncode(<String, dynamic>{
        'type': 'asr_final',
        'userTranscript': '打开设置页',
      }),
    );
    await tester.pump();

    final textField = tester
        .widget<TextField>(find.byKey(const ValueKey('task-input-field')));
    expect(textField.controller?.text, '打开设置页');
  });

  testWidgets('first mic tap waits loaded config before voice connect',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppConstants.prefsConfigKey: jsonEncode(<String, dynamic>{
        'communicationMode': 'customWebSocket',
        'geminiWebSocketUrl':
            'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent',
        'customWebSocketUrl': 'ws://10.0.2.2:18080/agent',
        'webSocketUrl': 'ws://10.0.2.2:18080/agent',
        'audioQuality': 'medium',
        'autoSendDelayMs': 180,
        'themeMode': 'dark',
      }),
    });

    final appProvider =
        _DelayedLoadAppProvider(const Duration(milliseconds: 220));
    final audioProvider = AudioProvider(
      audioService: _FakeAudioService(),
      permissionService: _FakePermissionService(),
    );
    final taskWebSocketService = _FakeWebSocketService();
    final wsProvider = WebSocketProvider(webSocketService: taskWebSocketService)
      ..init();
    final voiceWebSocketService = _FakeWebSocketService();
    final voiceWsProvider =
        VoiceWebSocketProvider(webSocketService: voiceWebSocketService)..init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: appProvider),
          ChangeNotifierProvider<AudioProvider>.value(value: audioProvider),
          ChangeNotifierProvider<WebSocketProvider>.value(value: wsProvider),
          ChangeNotifierProvider<VoiceWebSocketProvider>.value(
            value: voiceWsProvider,
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(voiceWebSocketService.lastConnectedUrl, 'ws://10.0.2.2:18080/voice');
  });

  testWidgets('keyboard mode limits task input to 2 lines', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final appProvider = AppProvider();
    final audioProvider = AudioProvider(
      audioService: _FakeAudioService(),
      permissionService: _FakePermissionService(),
    );
    final taskWebSocketService = _FakeWebSocketService();
    final wsProvider = WebSocketProvider(webSocketService: taskWebSocketService)
      ..init();
    final voiceWebSocketService = _FakeWebSocketService();
    final voiceWsProvider =
        VoiceWebSocketProvider(webSocketService: voiceWebSocketService)..init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: appProvider),
          ChangeNotifierProvider<AudioProvider>.value(value: audioProvider),
          ChangeNotifierProvider<WebSocketProvider>.value(value: wsProvider),
          ChangeNotifierProvider<VoiceWebSocketProvider>.value(
            value: voiceWsProvider,
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();

    final textField = tester
        .widget<TextField>(find.byKey(const ValueKey('task-input-field')));
    expect(textField.maxLines, 2);
  });
}

class _DelayedLoadAppProvider extends AppProvider {
  _DelayedLoadAppProvider(this.delay);

  final Duration delay;

  @override
  Future<void> load() async {
    await Future<void>.delayed(delay);
    return super.load();
  }
}

class _FakePermissionService extends PermissionService {
  @override
  Future<MicrophonePermissionResult> ensureMicrophonePermission() async {
    return MicrophonePermissionResult.granted;
  }

  @override
  Future<bool> openSystemSettings() async => false;
}

class _FakeAudioService extends AudioService {
  final StreamController<double> _volumeController =
      StreamController<double>.broadcast();
  int startRecordingCalls = 0;
  int stopRecordingCalls = 0;

  @override
  Stream<double> get volumeStream => _volumeController.stream;

  @override
  Future<Stream<Uint8List>> startRecordingStream() async {
    startRecordingCalls++;
    return const Stream<Uint8List>.empty();
  }

  @override
  Future<void> pauseRecording() async {}

  @override
  Future<void> resumeRecording() async {}

  @override
  Future<void> stopRecording() async {
    stopRecordingCalls++;
  }

  @override
  Future<void> dispose() async {
    await _volumeController.close();
  }
}

class _FakeWebSocketService extends WebSocketService {
  final StreamController<String> _messageController =
      StreamController<String>.broadcast();
  final StreamController<WsConnectionStatus> _statusController =
      StreamController<WsConnectionStatus>.broadcast();
  final StreamController<WsLiveState> _liveStateController =
      StreamController<WsLiveState>.broadcast();
  final List<String> sentMessages = <String>[];
  int connectCalls = 0;
  int disconnectCalls = 0;
  int asrStartCalls = 0;
  int disableCustomAsrCaptionCalls = 0;
  int endOfAudioSignalCalls = 0;
  String? lastConnectedUrl;
  WsConnectionStatus _status = WsConnectionStatus.disconnected;

  @override
  WsConnectionStatus get currentStatus => _status;

  @override
  Stream<String> get messageStream => _messageController.stream;

  @override
  Stream<WsConnectionStatus> get statusStream => _statusController.stream;

  @override
  Stream<WsLiveState> get liveStateStream => _liveStateController.stream;

  void emitLiveState(WsLiveState state) {
    _liveStateController.add(state);
  }

  void emitMessage(String message) {
    _messageController.add(message);
  }

  void emitStatus(WsConnectionStatus status) {
    _statusController.add(status);
  }

  @override
  Future<void> connect(
    String url, {
    bool autoReconnect = true,
    Duration? connectTimeout,
  }) async {
    connectCalls++;
    lastConnectedUrl = url;
    _status = WsConnectionStatus.connected;
    _statusController.add(WsConnectionStatus.connected);
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    _status = WsConnectionStatus.disconnected;
    _statusController.add(WsConnectionStatus.disconnected);
  }

  @override
  void sendText(String message) {
    sentMessages.add(message);
  }

  @override
  void sendAudioChunk(Uint8List bytes) {}

  @override
  void sendEndOfAudioSignal() {
    endOfAudioSignalCalls++;
  }

  @override
  void sendAsrStartEvent() {
    asrStartCalls++;
  }

  @override
  void disableCustomAsrCaptionEvents() {
    disableCustomAsrCaptionCalls++;
    _liveStateController.add(
      const WsLiveState(
        userTranscript: '',
        aiTranscript: '',
        playbackVolume: 0,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await _messageController.close();
    await _statusController.close();
    await _liveStateController.close();
  }
}

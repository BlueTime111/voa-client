import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:nova_voice_assistant/providers/voice_websocket_provider.dart';
import 'package:nova_voice_assistant/services/websocket_service.dart';

void main() {
  test('VoiceWebSocketProvider ensureConnected connects voice socket',
      () async {
    final service = _FakeVoiceWebSocketService();
    final provider = VoiceWebSocketProvider(webSocketService: service)..init();

    final ok = await provider.ensureConnected(
      'ws://127.0.0.1:18080/voice',
      connectTimeout: const Duration(milliseconds: 200),
    );

    expect(ok, isTrue);
    expect(provider.isConnected, isTrue);
    expect(service.connectCalls, 1);
    expect(service.lastConnectedUrl, 'ws://127.0.0.1:18080/voice');

    provider.dispose();
  });

  test('VoiceWebSocketProvider idle timer disconnects socket', () async {
    final service = _FakeVoiceWebSocketService();
    final provider = VoiceWebSocketProvider(webSocketService: service)..init();

    await provider.ensureConnected('ws://127.0.0.1:18080/voice');
    provider.scheduleIdleDisconnect(const Duration(milliseconds: 20));

    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(service.disconnectCalls, 1);
    expect(provider.isConnected, isFalse);

    provider.dispose();
  });

  test('VoiceWebSocketProvider exposes final transcript from asr_final event',
      () async {
    final service = _FakeVoiceWebSocketService();
    final provider = VoiceWebSocketProvider(webSocketService: service)..init();

    service.emitMessage(
      '{"type":"asr_final","userTranscript":"你好 世界"}',
    );
    await Future<void>.delayed(Duration.zero);

    expect(provider.lastFinalTranscript, '你好 世界');
    expect(provider.finalTranscriptRevision, 1);

    provider.dispose();
  });

  test('VoiceWebSocketProvider ensureConnected handles delayed status stream',
      () async {
    final service = _SlowStatusVoiceWebSocketService();
    final provider = VoiceWebSocketProvider(webSocketService: service)..init();

    final ok = await provider.ensureConnected(
      'ws://127.0.0.1:18080/voice',
      connectTimeout: const Duration(milliseconds: 300),
    );

    expect(ok, isTrue);
    expect(provider.isConnected, isTrue);

    provider.dispose();
  });
}

class _FakeVoiceWebSocketService extends WebSocketService {
  final StreamController<String> _messageController =
      StreamController<String>.broadcast();
  final StreamController<WsConnectionStatus> _statusController =
      StreamController<WsConnectionStatus>.broadcast();
  final StreamController<WsLiveState> _liveStateController =
      StreamController<WsLiveState>.broadcast();

  int connectCalls = 0;
  int disconnectCalls = 0;
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

  void emitMessage(String message) {
    _messageController.add(message);
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
  Future<void> dispose() async {
    await _messageController.close();
    await _statusController.close();
    await _liveStateController.close();
  }
}

class _SlowStatusVoiceWebSocketService extends _FakeVoiceWebSocketService {
  WsConnectionStatus _status = WsConnectionStatus.disconnected;

  @override
  WsConnectionStatus get currentStatus => _status;

  @override
  Future<void> connect(
    String url, {
    bool autoReconnect = true,
    Duration? connectTimeout,
  }) async {
    connectCalls++;
    lastConnectedUrl = url;
    _status = WsConnectionStatus.connected;
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      _statusController.add(WsConnectionStatus.connected);
    });
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    _status = WsConnectionStatus.disconnected;
    _statusController.add(WsConnectionStatus.disconnected);
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:nova_voice_assistant/providers/websocket_provider.dart';
import 'package:nova_voice_assistant/services/websocket_service.dart';

void main() {
  test('WebSocketProvider exposes task status and recent step summaries',
      () async {
    final service = _FakeWebSocketService();
    final provider = WebSocketProvider(webSocketService: service);
    provider.init();

    service.emitMessage(
      jsonEncode(<String, dynamic>{
        'type': 'task_update',
        'requestId': 'req-9',
        'taskId': 'task-9',
        'data': <String, dynamic>{
          'status': 'running',
          'steps': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'plan',
              'title': 'Plan solution',
              'status': 'done',
            },
            <String, dynamic>{
              'id': 'implement',
              'title': 'Implement changes',
              'status': 'running',
            },
          ],
        },
      }),
    );

    await Future<void>.delayed(Duration.zero);

    expect(provider.taskStatus, 'running');
    expect(
      provider.recentTaskStepSummaries,
      <String>['Implement changes (running)', 'Plan solution (done)'],
    );

    provider.dispose();
  });

  test('WebSocketProvider task status defaults to idle without task events',
      () {
    final service = _FakeWebSocketService();
    final provider = WebSocketProvider(webSocketService: service);

    expect(provider.taskStatus, 'idle');
    expect(provider.recentTaskStepSummaries, isEmpty);

    provider.dispose();
  });

  test('disconnected status clears task state after task event', () async {
    final service = _FakeWebSocketService();
    final provider = WebSocketProvider(webSocketService: service);
    provider.init();

    service.emitMessage(
      jsonEncode(<String, dynamic>{
        'type': 'task_update',
        'requestId': 'req-clear',
        'taskId': 'task-clear',
        'data': <String, dynamic>{
          'status': 'running',
          'step': <String, dynamic>{
            'id': 's-1',
            'title': 'Run',
            'status': 'running',
          },
        },
      }),
    );
    await Future<void>.delayed(Duration.zero);

    expect(provider.taskStatus, 'running');
    expect(provider.recentTaskStepSummaries, isNotEmpty);

    service.emitStatus(WsConnectionStatus.disconnected);
    await Future<void>.delayed(Duration.zero);

    expect(provider.lastTaskEvent, isNull);
    expect(provider.taskStatus, 'idle');
    expect(provider.recentTaskStepSummaries, isEmpty);

    provider.dispose();
  });

  test('recent task step summaries are capped to 5 latest items', () async {
    final service = _FakeWebSocketService();
    final provider = WebSocketProvider(webSocketService: service);
    provider.init();

    final steps = List<Map<String, dynamic>>.generate(
      7,
      (index) => <String, dynamic>{
        'id': 'step-$index',
        'title': 'Step $index',
        'status': 'done',
      },
    );

    service.emitMessage(
      jsonEncode(<String, dynamic>{
        'type': 'task_update',
        'taskId': 'task-many',
        'data': <String, dynamic>{
          'status': 'running',
          'steps': steps,
        },
      }),
    );

    await Future<void>.delayed(Duration.zero);

    expect(provider.recentTaskStepSummaries, hasLength(5));
    expect(provider.recentTaskStepSummaries.first, 'Step 6 (done)');
    expect(provider.recentTaskStepSummaries.last, 'Step 2 (done)');

    provider.dispose();
  });

  test('fallback summary uses id and pending when title/status are empty',
      () async {
    final service = _FakeWebSocketService();
    final provider = WebSocketProvider(webSocketService: service);
    provider.init();

    service.emitMessage(
      jsonEncode(<String, dynamic>{
        'type': 'task_update',
        'taskId': 'task-fallback',
        'data': <String, dynamic>{
          'step': <String, dynamic>{
            'id': 'step-fallback',
            'title': '   ',
            'status': '   ',
          },
        },
      }),
    );

    await Future<void>.delayed(Duration.zero);

    expect(
        provider.recentTaskStepSummaries, <String>['step-fallback (pending)']);

    provider.dispose();
  });
}

class _FakeWebSocketService extends WebSocketService {
  final StreamController<String> _messageController =
      StreamController<String>.broadcast();
  final StreamController<WsConnectionStatus> _statusController =
      StreamController<WsConnectionStatus>.broadcast();
  final StreamController<WsLiveState> _liveStateController =
      StreamController<WsLiveState>.broadcast();

  @override
  Stream<String> get messageStream => _messageController.stream;

  @override
  Stream<WsConnectionStatus> get statusStream => _statusController.stream;

  @override
  Stream<WsLiveState> get liveStateStream => _liveStateController.stream;

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
  }) async {}

  @override
  Future<void> disconnect() async {}

  @override
  void sendText(String message) {}

  @override
  void sendAudioChunk(Uint8List bytes) {}

  @override
  void sendEndOfAudioSignal() {}

  @override
  void sendAsrStartEvent() {}

  @override
  void disableCustomAsrCaptionEvents() {}

  @override
  Future<void> dispose() async {
    await _messageController.close();
    await _statusController.close();
    await _liveStateController.close();
  }
}

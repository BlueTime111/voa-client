import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:nova_voice_assistant/models/task_event.dart';
import 'package:nova_voice_assistant/models/task_session_state.dart';
import 'package:nova_voice_assistant/providers/websocket_provider.dart';
import 'package:nova_voice_assistant/services/websocket_service.dart';
import 'package:nova_voice_assistant/utils/constants.dart';

void main() {
  test('TaskEvent parses required fields from json payload', () {
    final event = TaskEvent.fromJson(<String, dynamic>{
      'type': 'task_update',
      'requestId': 'req-1',
      'taskId': 'task-1',
      'data': <String, dynamic>{'status': 'running'},
    });

    expect(event.type, 'task_update');
    expect(event.requestId, 'req-1');
    expect(event.taskId, 'task-1');
    expect(event.data['status'], 'running');
  });

  test('TaskEvent.tryParseMessage returns null on non-task payload', () {
    final parsed = TaskEvent.tryParseMessage(
      jsonEncode(<String, dynamic>{'type': 'asr_partial', 'text': 'hello'}),
    );

    expect(parsed, isNull);
  });

  test('TaskEvent.fromJson supports snake_case ids and blank ids to null', () {
    final event = TaskEvent.fromJson(<String, dynamic>{
      'type': 'task_started',
      'request_id': '   ',
      'task_id': 'task-snake',
      'data': <String, dynamic>{'status': 'started'},
    });

    expect(event.requestId, isNull);
    expect(event.taskId, 'task-snake');
  });

  test('TaskEvent.tryParseMessage returns null for malformed or non-map json',
      () {
    final malformed = TaskEvent.tryParseMessage('{"type":"task_update"');
    final nonMap = TaskEvent.tryParseMessage('[{"type":"task_update"}]');

    expect(malformed, isNull);
    expect(nonMap, isNull);
  });

  test('WebSocketService task helpers send expected payload', () {
    final service = _FakeWebSocketService();

    service.sendTaskCreate(
      requestId: 'req-1',
      data: <String, dynamic>{'text': 'summarize'},
    );
    service.sendTaskCancel(taskId: 'task-1', requestId: 'req-2');
    service.sendTaskApprove(taskId: 'task-1', requestId: 'req-3');
    service.sendTaskReject(taskId: 'task-1', requestId: 'req-4');

    expect(service.sentMessages, hasLength(4));

    final createPayload =
        jsonDecode(service.sentMessages.first) as Map<String, dynamic>;
    expect(createPayload['type'], 'task_create');
    expect(createPayload['requestId'], 'req-1');
    expect(createPayload['data'], <String, dynamic>{'text': 'summarize'});

    final cancelPayload =
        jsonDecode(service.sentMessages[1]) as Map<String, dynamic>;
    expect(cancelPayload['type'], 'task_cancel');
    expect(cancelPayload['requestId'], 'req-2');
    expect(cancelPayload['taskId'], 'task-1');

    final approvePayload =
        jsonDecode(service.sentMessages[2]) as Map<String, dynamic>;
    expect(approvePayload['type'], 'task_approve');
    expect(approvePayload['requestId'], 'req-3');
    expect(approvePayload['taskId'], 'task-1');

    final rejectPayload =
        jsonDecode(service.sentMessages[3]) as Map<String, dynamic>;
    expect(rejectPayload['type'], 'task_reject');
    expect(rejectPayload['requestId'], 'req-4');
    expect(rejectPayload['taskId'], 'task-1');
  });

  test('WebSocketProvider parses task event into task session state', () async {
    final service = _FakeWebSocketService();
    final provider = WebSocketProvider(webSocketService: service);
    provider.init();

    service.emitMessage(
      jsonEncode(<String, dynamic>{
        'type': 'task_update',
        'requestId': 'req-3',
        'taskId': 'task-3',
        'data': <String, dynamic>{'status': 'running'},
      }),
    );

    await Future<void>.delayed(Duration.zero);

    expect(provider.lastTaskEvent, isNotNull);
    expect(provider.lastTaskEvent?.type, 'task_update');
    expect(provider.taskSessionState.taskId, 'task-3');
    expect(provider.taskSessionState.requestId, 'req-3');
    expect(provider.taskSessionState.status, 'running');

    provider.dispose();
  });

  test('Default custom websocket url points to agent endpoint', () {
    expect(AppConstants.defaultCustomWebSocketUrl, endsWith('/agent'));
  });

  test('Default Gemini websocket url does not include hardcoded key', () {
    expect(AppConstants.defaultGeminiWebSocketUrl, isNot(contains('key=')));
  });

  test('TaskSessionState.applyEvent upserts and replaces step by id', () {
    var state = const TaskSessionState();

    state = state.applyEvent(
      TaskEvent.fromJson(<String, dynamic>{
        'type': 'task_update',
        'data': <String, dynamic>{
          'step': <String, dynamic>{
            'id': 'step-1',
            'status': 'running',
            'title': 'First',
          },
        },
      }),
    );

    state = state.applyEvent(
      TaskEvent.fromJson(<String, dynamic>{
        'type': 'task_update',
        'data': <String, dynamic>{
          'step': <String, dynamic>{
            'id': 'step-1',
            'status': 'done',
            'title': 'First updated',
          },
        },
      }),
    );

    state = state.applyEvent(
      TaskEvent.fromJson(<String, dynamic>{
        'type': 'task_update',
        'data': <String, dynamic>{
          'step': <String, dynamic>{
            'id': 'step-2',
            'status': 'queued',
          },
        },
      }),
    );

    expect(state.steps, hasLength(2));
    expect(state.steps[0].id, 'step-1');
    expect(state.steps[0].status, 'done');
    expect(state.steps[0].title, 'First updated');
    expect(state.steps[1].id, 'step-2');
  });
}

class _FakeWebSocketService extends WebSocketService {
  final StreamController<String> _messageController =
      StreamController<String>.broadcast();
  final StreamController<WsConnectionStatus> _statusController =
      StreamController<WsConnectionStatus>.broadcast();
  final StreamController<WsLiveState> _liveStateController =
      StreamController<WsLiveState>.broadcast();

  final List<String> sentMessages = <String>[];

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
  }) async {}

  @override
  Future<void> disconnect() async {}

  @override
  void sendText(String message) {
    sentMessages.add(message);
  }

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

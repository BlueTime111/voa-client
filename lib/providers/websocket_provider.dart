/// WebSocket 状态管理：提供连接状态、消息流与发送能力。
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/task_event.dart';
import '../models/task_session_state.dart';
import '../models/task_step.dart';
import '../services/websocket_service.dart';
import '../utils/logger.dart';

class WebSocketProvider extends ChangeNotifier {
  WebSocketProvider({required WebSocketService webSocketService})
      : _webSocketService = webSocketService;

  final WebSocketService _webSocketService;

  final StreamController<String> _incomingMessageController =
      StreamController<String>.broadcast();

  StreamSubscription<String>? _messageSubscription;
  StreamSubscription<WsConnectionStatus>? _statusSubscription;
  StreamSubscription<WsLiveState>? _liveStateSubscription;

  final List<String> _recentMessages = <String>[];
  WsConnectionStatus _connectionStatus = WsConnectionStatus.disconnected;
  String? _lastMessage;
  String? _errorText;
  String _userTranscript = '';
  String _aiTranscript = '';
  double _playbackVolume = 0;
  TaskEvent? _lastTaskEvent;
  TaskSessionState _taskSessionState = const TaskSessionState();
  bool _initialized = false;

  WsConnectionStatus get connectionStatus => _connectionStatus;
  String? get lastMessage => _lastMessage;
  String? get errorText => _errorText;
  String get userTranscript => _userTranscript;
  String get aiTranscript => _aiTranscript;
  double get playbackVolume => _playbackVolume;
  TaskEvent? get lastTaskEvent => _lastTaskEvent;
  TaskSessionState get taskSessionState => _taskSessionState;
  String get taskStatus =>
      (_taskSessionState.status?.trim().isNotEmpty ?? false)
          ? _taskSessionState.status!.trim()
          : 'idle';
  List<TaskStep> get taskSteps =>
      List<TaskStep>.unmodifiable(_taskSessionState.steps);
  List<String> get recentTaskStepSummaries {
    if (_taskSessionState.steps.isEmpty) {
      return const <String>[];
    }

    final summaries = <String>[];
    for (final step in _taskSessionState.steps.reversed.take(5)) {
      final title = (step.title?.trim().isNotEmpty ?? false)
          ? step.title!.trim()
          : step.id;
      final status =
          step.status.trim().isEmpty ? 'pending' : step.status.trim();
      summaries.add('$title ($status)');
    }
    return summaries;
  }

  List<String> get recentMessages => List<String>.unmodifiable(_recentMessages);
  Stream<String> get incomingMessageStream => _incomingMessageController.stream;

  bool get isConnected => _connectionStatus == WsConnectionStatus.connected;

  /// 初始化监听器。
  void init() {
    if (_initialized) {
      return;
    }
    _initialized = true;

    _messageSubscription = _webSocketService.messageStream.listen((message) {
      final taskEvent = TaskEvent.tryParseMessage(message);
      if (taskEvent != null) {
        _lastTaskEvent = taskEvent;
        _taskSessionState = _taskSessionState.applyEvent(taskEvent);
      }

      final displayText = _extractDisplayText(message);
      _lastMessage = displayText;
      _recentMessages.insert(0, displayText);
      if (_recentMessages.length > 50) {
        _recentMessages.removeRange(50, _recentMessages.length);
      }
      _incomingMessageController.add(message);
      notifyListeners();
    });

    _statusSubscription = _webSocketService.statusStream.listen((status) {
      _connectionStatus = status;
      if (status == WsConnectionStatus.disconnected ||
          status == WsConnectionStatus.error) {
        _lastTaskEvent = null;
        _taskSessionState = const TaskSessionState();
      }
      notifyListeners();
    });

    _liveStateSubscription = _webSocketService.liveStateStream.listen((state) {
      final nextUser = state.userTranscript;
      var nextAi = state.aiTranscript;
      final nextVolume = state.playbackVolume;

      if (state.interrupted) {
        nextAi = '';
      }

      final changed = nextUser != _userTranscript ||
          nextAi != _aiTranscript ||
          (nextVolume - _playbackVolume).abs() >= 0.01;
      if (!changed) {
        return;
      }

      _userTranscript = nextUser;
      _aiTranscript = nextAi;
      _playbackVolume = nextVolume;

      notifyListeners();
    });
  }

  /// 建立连接。
  Future<void> connect(
    String url, {
    bool autoReconnect = true,
    Duration? connectTimeout,
  }) async {
    if (!_initialized) {
      init();
    }

    _errorText = null;
    _userTranscript = '';
    _aiTranscript = '';
    _playbackVolume = 0;
    _lastTaskEvent = null;
    _taskSessionState = const TaskSessionState();
    notifyListeners();

    try {
      await _webSocketService.connect(
        url,
        autoReconnect: autoReconnect,
        connectTimeout: connectTimeout,
      );
    } catch (error, stackTrace) {
      _errorText = error.toString();
      AppLogger.error('WebSocketProvider connect error.', error, stackTrace);
      notifyListeners();
    }
  }

  /// 断开连接。
  Future<void> disconnect() async {
    try {
      await _webSocketService.disconnect();
      _userTranscript = '';
      _aiTranscript = '';
      _playbackVolume = 0;
      _lastTaskEvent = null;
      _taskSessionState = const TaskSessionState();
      notifyListeners();
    } catch (error, stackTrace) {
      _errorText = error.toString();
      AppLogger.error('WebSocketProvider disconnect error.', error, stackTrace);
      notifyListeners();
    }
  }

  /// 发送文本。
  void sendText(String message) {
    _webSocketService.sendText(message);
  }

  /// 发送二进制音频分块。
  void sendAudioChunk(Uint8List bytes) {
    _webSocketService.sendAudioChunk(bytes);
  }

  /// 发送语音结束信号。
  void sendEndOfAudioSignal() {
    _webSocketService.sendEndOfAudioSignal();
  }

  /// 清空实时字幕与播放音量展示（仅 UI 状态）。
  void clearLiveCaptions() {
    if (_userTranscript.isEmpty &&
        _aiTranscript.isEmpty &&
        _playbackVolume == 0) {
      return;
    }

    _userTranscript = '';
    _aiTranscript = '';
    _playbackVolume = 0;
    notifyListeners();
  }

  /// 停止后冻结 Custom ASR 回包更新，避免 final 回包再次点亮字幕。
  void freezeCustomAsrCaptions() {
    _webSocketService.disableCustomAsrCaptionEvents();
    clearLiveCaptions();
  }

  /// 发送 Custom ASR 开始事件，并清理本轮实时字幕。
  void sendAsrStartEvent() {
    _webSocketService.sendAsrStartEvent();
    if (_userTranscript.isNotEmpty ||
        _aiTranscript.isNotEmpty ||
        _playbackVolume > 0) {
      _userTranscript = '';
      _aiTranscript = '';
      _playbackVolume = 0;
      notifyListeners();
    }
  }

  void sendTaskCreate({String? requestId, Map<String, dynamic>? data}) {
    _webSocketService.sendTaskCreate(requestId: requestId, data: data);
  }

  void sendTaskCancel({
    required String taskId,
    String? requestId,
    Map<String, dynamic>? data,
  }) {
    _webSocketService.sendTaskCancel(
      taskId: taskId,
      requestId: requestId,
      data: data,
    );
  }

  void sendTaskApprove({
    required String taskId,
    String? requestId,
    Map<String, dynamic>? data,
  }) {
    _webSocketService.sendTaskApprove(
      taskId: taskId,
      requestId: requestId,
      data: data,
    );
  }

  void sendTaskReject({
    required String taskId,
    String? requestId,
    Map<String, dynamic>? data,
  }) {
    _webSocketService.sendTaskReject(
      taskId: taskId,
      requestId: requestId,
      data: data,
    );
  }

  String _extractDisplayText(String message) {
    try {
      final decoded = jsonDecode(message);
      if (decoded is Map) {
        final payload =
            decoded.map((key, value) => MapEntry(key.toString(), value));
        const keys = <String>[
          'assistant',
          'text',
          'message',
          'response',
          'answer',
          'content',
        ];
        for (final key in keys) {
          final value = payload[key];
          if (value is String && value.trim().isNotEmpty) {
            return value.trim();
          }
        }
      }
    } catch (_) {
      // 非 JSON 消息走原文。
    }
    return message;
  }

  @override
  void dispose() {
    unawaited(_messageSubscription?.cancel());
    unawaited(_statusSubscription?.cancel());
    unawaited(_liveStateSubscription?.cancel());
    unawaited(_incomingMessageController.close());
    unawaited(_webSocketService.dispose());
    super.dispose();
  }
}

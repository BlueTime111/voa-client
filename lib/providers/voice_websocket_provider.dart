import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../services/websocket_service.dart';
import '../utils/logger.dart';

class VoiceWebSocketProvider extends ChangeNotifier {
  VoiceWebSocketProvider({required WebSocketService webSocketService})
      : _webSocketService = webSocketService;

  final WebSocketService _webSocketService;

  StreamSubscription<WsConnectionStatus>? _statusSubscription;
  StreamSubscription<WsLiveState>? _liveStateSubscription;
  StreamSubscription<String>? _messageSubscription;

  WsConnectionStatus _connectionStatus = WsConnectionStatus.disconnected;
  String? _errorText;
  String _userTranscript = '';
  String _aiTranscript = '';
  double _playbackVolume = 0;
  String _lastFinalTranscript = '';
  int _finalTranscriptRevision = 0;
  Timer? _idleDisconnectTimer;
  bool _initialized = false;

  WsConnectionStatus get connectionStatus => _connectionStatus;
  bool get isConnected => _connectionStatus == WsConnectionStatus.connected;
  String? get errorText => _errorText;
  String get userTranscript => _userTranscript;
  String get aiTranscript => _aiTranscript;
  double get playbackVolume => _playbackVolume;
  String get lastFinalTranscript => _lastFinalTranscript;
  int get finalTranscriptRevision => _finalTranscriptRevision;

  void init() {
    if (_initialized) {
      return;
    }
    _initialized = true;

    _statusSubscription = _webSocketService.statusStream.listen((status) {
      _connectionStatus = status;
      if (status == WsConnectionStatus.disconnected ||
          status == WsConnectionStatus.error) {
        _playbackVolume = 0;
      }
      notifyListeners();
    });

    _liveStateSubscription = _webSocketService.liveStateStream.listen((state) {
      final changed = state.userTranscript != _userTranscript ||
          state.aiTranscript != _aiTranscript ||
          (state.playbackVolume - _playbackVolume).abs() >= 0.01;
      if (!changed) {
        return;
      }

      _userTranscript = state.userTranscript;
      _aiTranscript = state.aiTranscript;
      _playbackVolume = state.playbackVolume;
      notifyListeners();
    });

    _messageSubscription = _webSocketService.messageStream.listen((message) {
      _handleIncomingMessage(message);
    });
  }

  Future<bool> ensureConnected(
    String url, {
    Duration? connectTimeout,
  }) async {
    if (!_initialized) {
      init();
    }
    if (isConnected) {
      _cancelIdleDisconnectTimer();
      return true;
    }

    _cancelIdleDisconnectTimer();
    _errorText = null;
    notifyListeners();

    try {
      await _webSocketService.connect(
        url,
        autoReconnect: false,
        connectTimeout: connectTimeout,
      );

      // connect() 返回时服务侧状态已经确定，优先使用同步状态避免首轮点击竞态。
      final immediateStatus = _webSocketService.currentStatus;
      if (_connectionStatus != immediateStatus) {
        _connectionStatus = immediateStatus;
        notifyListeners();
      }
      if (immediateStatus == WsConnectionStatus.connected) {
        return true;
      }

      final settleTimeout =
          (connectTimeout ?? const Duration(milliseconds: 600)) <
                  const Duration(seconds: 1)
              ? const Duration(seconds: 1)
              : (connectTimeout ?? const Duration(milliseconds: 600));
      return _waitUntilConnected(timeout: settleTimeout);
    } catch (error, stackTrace) {
      _errorText = error.toString();
      AppLogger.error(
          'VoiceWebSocketProvider connect error.', error, stackTrace);
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnect() async {
    _cancelIdleDisconnectTimer();
    try {
      await _webSocketService.disconnect();
      _userTranscript = '';
      _aiTranscript = '';
      _playbackVolume = 0;
      notifyListeners();
    } catch (error, stackTrace) {
      _errorText = error.toString();
      AppLogger.error(
        'VoiceWebSocketProvider disconnect error.',
        error,
        stackTrace,
      );
      notifyListeners();
    }
  }

  void sendAsrStartEvent() {
    _cancelIdleDisconnectTimer();
    _webSocketService.sendAsrStartEvent();
  }

  void sendAudioChunk(Uint8List bytes) {
    _cancelIdleDisconnectTimer();
    _webSocketService.sendAudioChunk(bytes);
  }

  void sendEndOfAudioSignal() {
    _webSocketService.sendEndOfAudioSignal();
  }

  void clearLiveCaptions() {
    _webSocketService.disableCustomAsrCaptionEvents();
  }

  void freezeCustomAsrCaptions() {
    _webSocketService.disableCustomAsrCaptionEvents();
  }

  void scheduleIdleDisconnect(Duration timeout) {
    _cancelIdleDisconnectTimer();
    if (!isConnected) {
      return;
    }
    _idleDisconnectTimer = Timer(timeout, () {
      _idleDisconnectTimer = null;
      unawaited(disconnect());
    });
  }

  void _cancelIdleDisconnectTimer() {
    _idleDisconnectTimer?.cancel();
    _idleDisconnectTimer = null;
  }

  Future<bool> _waitUntilConnected({required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (isConnected ||
          _webSocketService.currentStatus == WsConnectionStatus.connected) {
        if (_connectionStatus != WsConnectionStatus.connected) {
          _connectionStatus = WsConnectionStatus.connected;
          notifyListeners();
        }
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return isConnected;
  }

  void _handleIncomingMessage(String message) {
    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) {
        return;
      }
      payload = decoded.map((key, value) => MapEntry(key.toString(), value));
    } catch (_) {
      return;
    }

    final type = payload['type']?.toString().trim();
    if (type != 'asr_final') {
      return;
    }

    final text = (payload['userTranscript'] ?? payload['text'])
            ?.toString()
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim() ??
        '';
    if (text.isEmpty) {
      return;
    }

    _lastFinalTranscript = text;
    _finalTranscriptRevision += 1;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelIdleDisconnectTimer();
    unawaited(_messageSubscription?.cancel());
    unawaited(_statusSubscription?.cancel());
    unawaited(_liveStateSubscription?.cancel());
    unawaited(_webSocketService.dispose());
    super.dispose();
  }
}

/// WebSocket 服务：负责连接管理、心跳、断线重连与消息分发。
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:logger/logger.dart' show Level;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/constants.dart';
import '../utils/logger.dart';

enum WsConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

enum _WsProtocol {
  custom,
  geminiLive,
}

class WsLiveState {
  const WsLiveState({
    required this.userTranscript,
    required this.aiTranscript,
    required this.playbackVolume,
    this.interrupted = false,
  });

  final String userTranscript;
  final String aiTranscript;
  final double playbackVolume;
  final bool interrupted;
}

class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  final StreamController<String> _messageController =
      StreamController<String>.broadcast();
  final StreamController<WsConnectionStatus> _statusController =
      StreamController<WsConnectionStatus>.broadcast();
  final StreamController<WsLiveState> _liveStateController =
      StreamController<WsLiveState>.broadcast();

  final _GeminiAudioPlayer _geminiAudioPlayer = _GeminiAudioPlayer();

  String _activeUrl = AppConstants.defaultWebSocketUrl;
  int _retryCount = 0;
  bool _manuallyDisconnected = false;
  bool _autoReconnect = true;
  WsConnectionStatus _currentStatus = WsConnectionStatus.disconnected;
  _WsProtocol _protocol = _WsProtocol.custom;
  bool _customAsrCaptionEventsEnabled = true;
  bool _customAsrAwaitingFirstChunk = false;
  bool _didLogAudioDroppedWhileDisconnected = false;
  DateTime? _lastHeartbeatAckAt;

  Completer<void>? _geminiSetupCompleter;
  String _geminiInputTranscript = '';
  String _geminiOutputTranscript = '';
  final StringBuffer _geminiModelTextBuffer = StringBuffer();
  int _geminiOutputSampleRate = 24000;
  String _liveUserTranscript = '';
  String _liveAiTranscript = '';
  double _livePlaybackVolume = 0;
  Timer? _volumeDecayTimer;
  WsLiveState? _lastEmittedLiveState;
  DateTime? _lastLiveStateEmitAt;

  static const String _geminiModel =
      'models/gemini-2.5-flash-native-audio-preview-12-2025';
  static const String _geminiVoiceName = 'Zephyr';
  static const String _geminiSystemInstruction =
      'You are a helpful, futuristic voice assistant named Nova. '
      'Keep responses concise and friendly.';

  Stream<String> get messageStream => _messageController.stream;
  Stream<WsConnectionStatus> get statusStream => _statusController.stream;
  Stream<WsLiveState> get liveStateStream => _liveStateController.stream;
  WsConnectionStatus get currentStatus => _currentStatus;

  /// 建立 WebSocket 连接。
  Future<void> connect(
    String url, {
    bool autoReconnect = true,
    Duration? connectTimeout,
  }) async {
    _activeUrl = url;
    _protocol =
        _isGeminiLiveUrl(url) ? _WsProtocol.geminiLive : _WsProtocol.custom;
    _customAsrCaptionEventsEnabled = true;
    _customAsrAwaitingFirstChunk = false;
    _lastHeartbeatAckAt = null;
    _manuallyDisconnected = false;
    _autoReconnect = autoReconnect;
    _cancelReconnectTimer();
    _resetGeminiTurnState();
    _resetLiveState();
    _geminiAudioPlayer.stopAndClear();

    final nextStatus = _retryCount == 0
        ? WsConnectionStatus.connecting
        : WsConnectionStatus.reconnecting;
    _updateStatus(nextStatus);

    await _closeChannelOnly();

    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;

      _channelSubscription = channel.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: true,
      );

      final readyFuture = channel.ready;
      if (connectTimeout == null) {
        await readyFuture;
      } else {
        await readyFuture.timeout(connectTimeout);
      }

      if (_protocol == _WsProtocol.geminiLive) {
        _geminiSetupCompleter = Completer<void>();
        _sendGeminiSetup();

        final setupFuture = _geminiSetupCompleter!.future;
        final setupTimeout = connectTimeout ?? const Duration(seconds: 8);
        await setupFuture.timeout(setupTimeout);
        await _geminiAudioPlayer.prepare(sampleRate: _geminiOutputSampleRate);

        _retryCount = 0;
        _updateStatus(WsConnectionStatus.connected);
        AppLogger.info('Gemini Live setup completed.');
      } else {
        _retryCount = 0;
        _lastHeartbeatAckAt = DateTime.now();
        _updateStatus(WsConnectionStatus.connected);
        _startHeartbeat();
        AppLogger.info('WebSocket connected: $url');
      }
    } catch (error, stackTrace) {
      AppLogger.error('WebSocket connect failed', error, stackTrace);
      _failGeminiSetup(error);
      await _closeChannelOnly();
      _onError(error);
      rethrow;
    }
  }

  /// 主动断开连接。
  Future<void> disconnect() async {
    _manuallyDisconnected = true;
    _autoReconnect = false;
    _retryCount = 0;
    _cancelReconnectTimer();
    _stopHeartbeat();
    _lastHeartbeatAckAt = null;
    _failGeminiSetup(StateError('Disconnected by user.'));
    _resetGeminiTurnState();
    _resetLiveState();
    _geminiAudioPlayer.stopAndClear();
    await _closeChannelOnly();
    _updateStatus(WsConnectionStatus.disconnected);
    AppLogger.info('WebSocket disconnected by user.');
  }

  /// 发送文本消息。
  void sendText(String message) {
    if (_currentStatus != WsConnectionStatus.connected) {
      AppLogger.warn('sendText ignored: socket not connected.');
      return;
    }
    _sendRawText(message);
  }

  /// 发送 task_create 事件。
  void sendTaskCreate({
    String? requestId,
    Map<String, dynamic>? data,
  }) {
    sendText(
      jsonEncode(<String, dynamic>{
        'type': 'task_create',
        if (requestId != null && requestId.trim().isNotEmpty)
          'requestId': requestId.trim(),
        if (data != null) 'data': data,
      }),
    );
  }

  /// 发送 task_cancel 事件。
  void sendTaskCancel({
    required String taskId,
    String? requestId,
    Map<String, dynamic>? data,
  }) {
    sendText(
      jsonEncode(<String, dynamic>{
        'type': 'task_cancel',
        'taskId': taskId,
        if (requestId != null && requestId.trim().isNotEmpty)
          'requestId': requestId.trim(),
        if (data != null) 'data': data,
      }),
    );
  }

  /// 发送 task_approve 事件。
  void sendTaskApprove({
    required String taskId,
    String? requestId,
    Map<String, dynamic>? data,
  }) {
    sendText(
      jsonEncode(<String, dynamic>{
        'type': 'task_approve',
        'taskId': taskId,
        if (requestId != null && requestId.trim().isNotEmpty)
          'requestId': requestId.trim(),
        if (data != null) 'data': data,
      }),
    );
  }

  /// 发送 task_reject 事件。
  void sendTaskReject({
    required String taskId,
    String? requestId,
    Map<String, dynamic>? data,
  }) {
    sendText(
      jsonEncode(<String, dynamic>{
        'type': 'task_reject',
        'taskId': taskId,
        if (requestId != null && requestId.trim().isNotEmpty)
          'requestId': requestId.trim(),
        if (data != null) 'data': data,
      }),
    );
  }

  /// 发送二进制音频分块。
  void sendAudioChunk(Uint8List bytes) {
    if (_currentStatus != WsConnectionStatus.connected) {
      if (!_didLogAudioDroppedWhileDisconnected) {
        AppLogger.warn('sendAudioChunk ignored: socket not connected.');
        _didLogAudioDroppedWhileDisconnected = true;
      }
      return;
    }

    _didLogAudioDroppedWhileDisconnected = false;

    if (_protocol == _WsProtocol.geminiLive) {
      _sendGeminiRealtimeAudio(bytes);
      return;
    }

    if (_customAsrAwaitingFirstChunk) {
      _customAsrCaptionEventsEnabled = true;
      _customAsrAwaitingFirstChunk = false;
    }

    _channel?.sink.add(bytes);
  }

  /// 发送语音结束信号。
  void sendEndOfAudioSignal() {
    if (_currentStatus != WsConnectionStatus.connected) {
      AppLogger.warn('sendEndOfAudioSignal ignored: socket not connected.');
      return;
    }

    if (_protocol == _WsProtocol.geminiLive) {
      final payload = <String, dynamic>{
        'realtimeInput': <String, dynamic>{'audioStreamEnd': true},
      };
      sendText(jsonEncode(payload));
      return;
    }

    sendText('{"type":"end_of_audio"}');
  }

  /// Custom ASR 开始事件：用于开启新一轮识别并清空旧字幕。
  void sendAsrStartEvent() {
    if (_currentStatus != WsConnectionStatus.connected) {
      AppLogger.warn('sendAsrStartEvent ignored: socket not connected.');
      return;
    }

    if (_protocol == _WsProtocol.geminiLive) {
      return;
    }

    _customAsrCaptionEventsEnabled = true;
    _customAsrAwaitingFirstChunk = true;

    _liveUserTranscript = '';
    _liveAiTranscript = '';
    _livePlaybackVolume = 0;
    _emitLiveState();

    sendText(jsonEncode(<String, dynamic>{
      'type': 'asr_start',
      'sampleRate': AppConstants.sampleRate,
      'channels': AppConstants.numChannels,
      'format': 'pcm16',
    }));
  }

  /// 禁用 Custom ASR 字幕更新，并清空当前字幕。
  void disableCustomAsrCaptionEvents() {
    if (_protocol == _WsProtocol.geminiLive) {
      return;
    }
    _customAsrCaptionEventsEnabled = false;
    _customAsrAwaitingFirstChunk = false;
    _liveUserTranscript = '';
    _liveAiTranscript = '';
    _livePlaybackVolume = 0;
    _emitLiveState();
  }

  void _onData(dynamic data) {
    if (_protocol == _WsProtocol.geminiLive) {
      _handleGeminiData(data);
      return;
    }

    _markHeartbeatAlive();

    if (data is String) {
      if (_handleCustomLiveAsrEvent(data)) {
        return;
      }
      _messageController.add(data);
      return;
    }

    if (data is List<int>) {
      final text = utf8.decode(data, allowMalformed: true);
      if (_handleCustomLiveAsrEvent(text)) {
        return;
      }
      _messageController.add(text);
      return;
    }

    _messageController.add(data.toString());
  }

  bool _handleCustomLiveAsrEvent(String payload) {
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        return false;
      }
      data = decoded.map((key, value) => MapEntry(key.toString(), value));
    } catch (_) {
      return false;
    }

    final type = data['type']?.toString();
    if (type == null) {
      return false;
    }

    if (type == 'ping' || type == 'pong') {
      return true;
    }

    if (type == 'asr_start' || type == 'asr_started') {
      _customAsrCaptionEventsEnabled = false;
      _customAsrAwaitingFirstChunk = true;
      _liveUserTranscript = '';
      _liveAiTranscript = '';
      _livePlaybackVolume = 0;
      _emitLiveState();
      return true;
    }

    if (!_customAsrCaptionEventsEnabled && type == 'asr_partial') {
      return true;
    }

    if (type == 'asr_partial') {
      final text = _normalizeAsrText(data['text']?.toString() ?? '');
      if (text.isEmpty) {
        return true;
      }

      if (_liveUserTranscript == text) {
        return true;
      }

      _liveUserTranscript = text;
      _liveAiTranscript = '';
      _emitLiveState();
      return true;
    }

    if (type == 'asr_final') {
      final text = _normalizeAsrText(
        (data['text'] ?? data['userTranscript'])?.toString() ?? '',
      );

      if (text.isNotEmpty) {
        _messageController.add(
          jsonEncode(<String, dynamic>{
            'type': 'asr_final',
            'userTranscript': text,
          }),
        );

        if (_customAsrCaptionEventsEnabled) {
          _liveUserTranscript = text;
        }
      }

      if (_customAsrCaptionEventsEnabled) {
        _liveAiTranscript = '';
        _livePlaybackVolume = 0;
        _emitLiveState();
      }
      return true;
    }

    if (type == 'asr_reset') {
      _liveUserTranscript = '';
      _liveAiTranscript = '';
      _livePlaybackVolume = 0;
      _emitLiveState();
      return true;
    }

    return false;
  }

  void _onError(Object error) {
    AppLogger.warn('WebSocket error: $error');
    _failGeminiSetup(error);
    _stopHeartbeat();
    _lastHeartbeatAckAt = null;
    _livePlaybackVolume = 0;
    _emitLiveState();
    _updateStatus(WsConnectionStatus.error);
    if (_autoReconnect) {
      _scheduleReconnect();
    }
  }

  void _onDone() {
    AppLogger.warn('WebSocket connection closed.');
    _failGeminiSetup(StateError('WebSocket connection closed before setup.'));
    _stopHeartbeat();
    _lastHeartbeatAckAt = null;
    _livePlaybackVolume = 0;
    _emitLiveState();

    if (_manuallyDisconnected) {
      _updateStatus(WsConnectionStatus.disconnected);
      return;
    }

    if (_autoReconnect) {
      _scheduleReconnect();
    } else {
      _updateStatus(WsConnectionStatus.error);
    }
  }

  void _startHeartbeat() {
    if (_protocol == _WsProtocol.geminiLive) {
      return;
    }

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(AppConstants.heartbeatInterval, (_) {
      if (_isHeartbeatTimedOut()) {
        _handleHeartbeatTimeout();
        return;
      }

      final payload = jsonEncode(
        <String, dynamic>{
          'type': 'ping',
          'ts': DateTime.now().toIso8601String(),
        },
      );
      sendText(payload);
    });
  }

  bool _isHeartbeatTimedOut() {
    final lastAck = _lastHeartbeatAckAt;
    if (lastAck == null) {
      return false;
    }

    final elapsed = DateTime.now().difference(lastAck);
    return elapsed > AppConstants.heartbeatTimeout;
  }

  void _markHeartbeatAlive() {
    _lastHeartbeatAckAt = DateTime.now();
  }

  void _handleHeartbeatTimeout() {
    final timeout = TimeoutException(
      'Heartbeat timeout after ${AppConstants.heartbeatTimeout.inSeconds}s',
    );
    AppLogger.warn('WebSocket heartbeat timeout. Closing stale connection.');
    unawaited(_closeChannelOnly());
    _onError(timeout);
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _scheduleReconnect() {
    if (_manuallyDisconnected) {
      return;
    }

    if (_reconnectTimer != null) {
      return;
    }

    if (_retryCount >= AppConstants.maxReconnectAttempts) {
      AppLogger.error('WebSocket reconnect reached max attempts.');
      _updateStatus(WsConnectionStatus.error);
      return;
    }

    _retryCount += 1;
    final backoffSeconds =
        AppConstants.reconnectBaseSeconds << (_retryCount - 1);
    final delay = Duration(seconds: backoffSeconds);
    _updateStatus(WsConnectionStatus.reconnecting);

    AppLogger.warn('WebSocket reconnect #$_retryCount in ${delay.inSeconds}s');
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_manuallyDisconnected) {
        return;
      }
      unawaited(
        connect(_activeUrl, autoReconnect: _autoReconnect).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          AppLogger.error(
            'WebSocket reconnect attempt failed.',
            error,
            stackTrace,
          );
        }),
      );
    });
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<void> _closeChannelOnly() async {
    _stopHeartbeat();
    _lastHeartbeatAckAt = null;

    await _channelSubscription?.cancel();
    _channelSubscription = null;

    final currentChannel = _channel;
    _channel = null;

    await currentChannel?.sink.close();
  }

  void _updateStatus(WsConnectionStatus status) {
    if (_currentStatus == status) {
      return;
    }
    _currentStatus = status;
    if (status == WsConnectionStatus.connected) {
      _didLogAudioDroppedWhileDisconnected = false;
    }
    _statusController.add(status);
  }

  /// 释放资源。
  Future<void> dispose() async {
    _manuallyDisconnected = true;
    _cancelReconnectTimer();
    _failGeminiSetup(StateError('Service disposed.'));
    _volumeDecayTimer?.cancel();
    _volumeDecayTimer = null;
    await _closeChannelOnly();
    await _geminiAudioPlayer.dispose();
    await _messageController.close();
    await _statusController.close();
    await _liveStateController.close();
  }

  bool _isGeminiLiveUrl(String url) {
    return url.contains(
            'generativelanguage.googleapis.com/ws/google.ai.generativelanguage.') &&
        url.contains('BidiGenerateContent');
  }

  void _sendGeminiSetup() {
    final payload = <String, dynamic>{
      'setup': <String, dynamic>{
        'model': _geminiModel,
        'generationConfig': <String, dynamic>{
          'responseModalities': <String>['AUDIO'],
          'speechConfig': <String, dynamic>{
            'voiceConfig': <String, dynamic>{
              'prebuiltVoiceConfig': <String, dynamic>{
                'voiceName': _geminiVoiceName,
              },
            },
          },
        },
        'systemInstruction': <String, dynamic>{
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{'text': _geminiSystemInstruction},
          ],
        },
        'inputAudioTranscription': <String, dynamic>{},
        'outputAudioTranscription': <String, dynamic>{},
      },
    };

    _sendRawText(jsonEncode(payload));
  }

  void _sendGeminiRealtimeAudio(Uint8List bytes) {
    final payload = <String, dynamic>{
      'realtimeInput': <String, dynamic>{
        'mediaChunks': <Map<String, dynamic>>[
          <String, dynamic>{
            'mimeType': 'audio/pcm;rate=${AppConstants.sampleRate}',
            'data': base64Encode(bytes),
          },
        ],
      },
    };
    _sendRawText(jsonEncode(payload));
  }

  void _sendRawText(String message) {
    final channel = _channel;
    if (channel == null) {
      AppLogger.warn('sendRawText ignored: socket channel is null.');
      return;
    }
    channel.sink.add(message);
  }

  void _handleGeminiData(dynamic data) {
    final String messageText;
    if (data is String) {
      messageText = data;
    } else if (data is List<int>) {
      messageText = utf8.decode(data, allowMalformed: true);
    } else {
      messageText = data.toString();
    }

    Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(messageText);
      if (decoded is! Map) {
        return;
      }
      message = decoded.map((key, value) => MapEntry(key.toString(), value));
    } catch (_) {
      return;
    }

    if (message['setupComplete'] != null) {
      _completeGeminiSetup();
      _retryCount = 0;
      _updateStatus(WsConnectionStatus.connected);
    }

    final serverContent = message['serverContent'];
    if (serverContent is Map) {
      _handleGeminiServerContent(
        serverContent.map((key, value) => MapEntry(key.toString(), value)),
      );
      return;
    }

    final error = message['error'];
    if (error is Map) {
      final errorMessage =
          error['message']?.toString() ?? 'Gemini Live server returned error.';
      AppLogger.warn(errorMessage);
      _messageController.add(errorMessage);
    }
  }

  void _handleGeminiServerContent(Map<String, dynamic> serverContent) {
    if (serverContent['interrupted'] == true) {
      _geminiAudioPlayer.stopAndClear();
      _resetGeminiTurnState();
      _liveAiTranscript = '';
      _livePlaybackVolume = 0;
      _emitLiveState(interrupted: true);
      return;
    }

    final inputTranscription = serverContent['inputTranscription'];
    if (inputTranscription is Map) {
      final inputText = inputTranscription['text'];
      if (inputText is String && inputText.trim().isNotEmpty) {
        final normalized = inputText.trim();
        _liveUserTranscript = _mergeTranscript(_liveUserTranscript, normalized);
        _liveAiTranscript = '';
        _geminiInputTranscript =
            _mergeTranscript(_geminiInputTranscript, normalized);
        _emitLiveState();
      }
    }

    final outputTranscription = serverContent['outputTranscription'];
    if (outputTranscription is Map) {
      final outputText = outputTranscription['text'];
      if (outputText is String && outputText.trim().isNotEmpty) {
        final normalized = outputText.trim();
        _liveAiTranscript = _mergeTranscript(_liveAiTranscript, normalized);
        _liveUserTranscript = '';
        _geminiOutputTranscript =
            _mergeTranscript(_geminiOutputTranscript, normalized);
        _emitLiveState();
      }
    }

    final modelTurn = serverContent['modelTurn'];
    if (modelTurn is Map) {
      final parts = modelTurn['parts'];
      if (parts is List) {
        for (final part in parts) {
          if (part is! Map) {
            continue;
          }

          final text = part['text'];
          if (text is String && text.trim().isNotEmpty) {
            _geminiModelTextBuffer.write(text);
          }

          final inlineData = part['inlineData'];
          if (inlineData is! Map) {
            continue;
          }

          final base64Audio = inlineData['data'];
          final mimeType = inlineData['mimeType'];
          if (base64Audio is String && mimeType is String) {
            _enqueueGeminiAudio(base64Audio, mimeType);
          }
        }
      }
    }

    if (serverContent['turnComplete'] == true) {
      final assistantText = _resolveGeminiAssistantText();
      final userTranscript = _geminiInputTranscript.trim();
      if (assistantText.isNotEmpty || userTranscript.isNotEmpty) {
        _messageController.add(
          jsonEncode(<String, dynamic>{
            'assistant': assistantText,
            'userTranscript': userTranscript,
          }),
        );
      }
      _resetGeminiTurnState();
      _livePlaybackVolume = 0;
      _emitLiveState();
    }
  }

  void _enqueueGeminiAudio(String base64Audio, String mimeType) {
    try {
      final bytes = base64Decode(base64Audio);
      if (bytes.isEmpty) {
        return;
      }

      final lowerMime = mimeType.toLowerCase();
      if (lowerMime.contains('audio/pcm')) {
        final sampleRate =
            _parseSampleRateFromMimeType(mimeType) ?? _geminiOutputSampleRate;
        _geminiOutputSampleRate = sampleRate;
        final rms = _computePcm16Rms(bytes);
        _livePlaybackVolume = (_livePlaybackVolume * 0.8) + (rms * 0.2);
        _emitLiveState();
        _scheduleVolumeDecay();
        _geminiAudioPlayer.feedPcmData(bytes, sampleRate: sampleRate);
        return;
      }

      if (lowerMime.contains('audio/wav') ||
          lowerMime.contains('audio/x-wav')) {
        final wavPcm = _extractPcm16DataFromWav(bytes);
        if (wavPcm != null && wavPcm.isNotEmpty) {
          final rms = _computePcm16Rms(wavPcm);
          _livePlaybackVolume = (_livePlaybackVolume * 0.8) + (rms * 0.2);
          _emitLiveState();
          _scheduleVolumeDecay();
          _geminiAudioPlayer.feedPcmData(
            wavPcm,
            sampleRate: _geminiOutputSampleRate,
          );
        }
      }
    } catch (error) {
      AppLogger.warn('Failed to decode Gemini audio chunk: $error');
    }
  }

  int? _parseSampleRateFromMimeType(String mimeType) {
    final match = RegExp(r'rate=(\d+)').firstMatch(mimeType.toLowerCase());
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1) ?? '');
  }

  Uint8List? _extractPcm16DataFromWav(Uint8List wavBytes) {
    if (wavBytes.lengthInBytes < 44) {
      return null;
    }

    if (wavBytes[0] != 0x52 ||
        wavBytes[1] != 0x49 ||
        wavBytes[2] != 0x46 ||
        wavBytes[3] != 0x46) {
      return null;
    }

    if (wavBytes[8] != 0x57 ||
        wavBytes[9] != 0x41 ||
        wavBytes[10] != 0x56 ||
        wavBytes[11] != 0x45) {
      return null;
    }

    final data = ByteData.sublistView(wavBytes);
    var offset = 12;
    while (offset + 8 <= wavBytes.lengthInBytes) {
      final chunkId = ascii.decode(wavBytes.sublist(offset, offset + 4));
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      final chunkStart = offset + 8;
      final chunkEnd = chunkStart + chunkSize;

      if (chunkEnd > wavBytes.lengthInBytes) {
        return null;
      }

      if (chunkId == 'fmt ') {
        if (chunkSize >= 8) {
          final audioFormat = data.getUint16(chunkStart, Endian.little);
          if (audioFormat != 1) {
            return null;
          }
          final channels = data.getUint16(chunkStart + 2, Endian.little);
          final sampleRate = data.getUint32(chunkStart + 4, Endian.little);
          if (channels != 1) {
            return null;
          }
          _geminiOutputSampleRate = sampleRate;
        }
      }

      if (chunkId == 'data') {
        return Uint8List.fromList(wavBytes.sublist(chunkStart, chunkEnd));
      }

      offset = chunkEnd + (chunkSize.isOdd ? 1 : 0);
    }

    return null;
  }

  String _resolveGeminiAssistantText() {
    final outputTranscript = _geminiOutputTranscript.trim();
    if (outputTranscript.isNotEmpty) {
      return outputTranscript;
    }

    final modelText = _geminiModelTextBuffer.toString().trim();
    if (modelText.isNotEmpty) {
      return modelText;
    }

    return '';
  }

  String _mergeTranscript(String current, String incoming) {
    final next = incoming.trim();
    if (next.isEmpty) {
      return current;
    }
    if (current.isEmpty) {
      return next;
    }
    if (next.startsWith(current)) {
      return next;
    }
    if (current.endsWith(next) || current.contains(next)) {
      return current;
    }

    final currentEndsWithSpace = current.trimRight().length != current.length;
    final nextStartsWithPunctuationOrSpace =
        RegExp(r'^[\s,.;!?]').hasMatch(next);
    final needSpace =
        !currentEndsWithSpace && !nextStartsWithPunctuationOrSpace;
    return needSpace ? '$current $next' : '$current$next';
  }

  double _computePcm16Rms(Uint8List pcmBytes) {
    if (pcmBytes.lengthInBytes < 2) {
      return 0;
    }

    final view = ByteData.sublistView(pcmBytes);
    final sampleCount = pcmBytes.lengthInBytes ~/ 2;
    var sumSquares = 0.0;

    for (var i = 0; i < sampleCount; i++) {
      final sample = view.getInt16(i * 2, Endian.little) / 32768.0;
      sumSquares += sample * sample;
    }

    final rms = math.sqrt(sumSquares / sampleCount);
    return rms.clamp(0.0, 1.0);
  }

  void _scheduleVolumeDecay() {
    _volumeDecayTimer?.cancel();
    _volumeDecayTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (_livePlaybackVolume <= 0.01) {
        _livePlaybackVolume = 0;
        _emitLiveState();
        _volumeDecayTimer?.cancel();
        _volumeDecayTimer = null;
        return;
      }

      _livePlaybackVolume *= 0.72;
      _emitLiveState();
    });
  }

  void _emitLiveState({bool interrupted = false}) {
    _emitLiveStateInternal(interrupted: interrupted);
  }

  void _emitLiveStateInternal({bool interrupted = false, bool force = false}) {
    if (_liveStateController.isClosed) {
      return;
    }

    final next = WsLiveState(
      userTranscript: _liveUserTranscript,
      aiTranscript: _liveAiTranscript,
      playbackVolume: _livePlaybackVolume,
      interrupted: interrupted,
    );

    if (!force) {
      final previous = _lastEmittedLiveState;
      final now = DateTime.now();
      final elapsedMs = _lastLiveStateEmitAt == null
          ? 9999
          : now.difference(_lastLiveStateEmitAt!).inMilliseconds;

      if (previous != null) {
        final transcriptChanged =
            previous.userTranscript != next.userTranscript ||
                previous.aiTranscript != next.aiTranscript ||
                previous.interrupted != next.interrupted;
        final volumeDiff =
            (previous.playbackVolume - next.playbackVolume).abs();
        final volumeReachedZero =
            previous.playbackVolume > 0 && next.playbackVolume <= 0;
        final volumeSignificantAndDue = volumeDiff >= 0.025 && elapsedMs >= 80;

        if (!interrupted &&
            !transcriptChanged &&
            !volumeReachedZero &&
            !volumeSignificantAndDue) {
          return;
        }
      }

      _lastLiveStateEmitAt = now;
    } else {
      _lastLiveStateEmitAt = DateTime.now();
    }

    _lastEmittedLiveState = next;
    _liveStateController.add(next);
  }

  void _resetLiveState() {
    _volumeDecayTimer?.cancel();
    _volumeDecayTimer = null;
    _liveUserTranscript = '';
    _liveAiTranscript = '';
    _livePlaybackVolume = 0;
    _lastEmittedLiveState = null;
    _lastLiveStateEmitAt = null;
    _emitLiveStateInternal(force: true);
  }

  String _normalizeAsrText(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  void _resetGeminiTurnState() {
    _geminiInputTranscript = '';
    _geminiOutputTranscript = '';
    _geminiModelTextBuffer.clear();
    _geminiOutputSampleRate = 24000;
  }

  void _completeGeminiSetup() {
    final completer = _geminiSetupCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    completer.complete();
  }

  void _failGeminiSetup(Object error) {
    final completer = _geminiSetupCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    completer.completeError(error);
  }
}

class _GeminiAudioPlayer {
  static const int _streamBufferSize = 4096;
  static const int _maxPendingFeedTasks = 24;

  final FlutterSoundPlayer _player = FlutterSoundPlayer(logLevel: Level.error);

  Future<void> _feedChain = Future<void>.value();
  bool _isOpen = false;
  bool _isStreaming = false;
  int _currentSampleRate = 24000;
  int _pendingFeedTasks = 0;
  bool _backpressureWarningShown = false;

  Future<void> prepare({required int sampleRate}) async {
    await _ensureReady(sampleRate);
  }

  void feedPcmData(Uint8List pcmBytes, {required int sampleRate}) {
    if (pcmBytes.isEmpty) {
      return;
    }

    if (_pendingFeedTasks >= _maxPendingFeedTasks) {
      if (!_backpressureWarningShown) {
        _backpressureWarningShown = true;
        AppLogger.warn('Gemini audio backlog high. Dropping stale chunks.');
      }
      return;
    }

    _pendingFeedTasks += 1;

    _feedChain = _feedChain.then((_) async {
      await _ensureReady(sampleRate);
      await _player.feedUint8FromStream(pcmBytes);
    }).catchError((Object error, StackTrace stackTrace) {
      AppLogger.warn('Gemini stream feed failed: $error');
    }).whenComplete(() {
      _pendingFeedTasks = math.max(0, _pendingFeedTasks - 1);
      if (_pendingFeedTasks < 8) {
        _backpressureWarningShown = false;
      }
    });
  }

  Future<void> _ensureReady(int sampleRate) async {
    if (!_isOpen) {
      await _player.openPlayer();
      _isOpen = true;
    }

    if (_isStreaming && _currentSampleRate == sampleRate) {
      return;
    }

    if (_isStreaming) {
      await _player.stopPlayer();
      _isStreaming = false;
    }

    await _player.startPlayerFromStream(
      codec: Codec.pcm16,
      interleaved: true,
      numChannels: AppConstants.numChannels,
      sampleRate: sampleRate,
      bufferSize: _streamBufferSize,
      onBufferUnderflow: () {},
    );
    _currentSampleRate = sampleRate;
    _isStreaming = true;
  }

  void stopAndClear() {
    _feedChain = _feedChain.then((_) async {
      if (_isStreaming) {
        await _player.stopPlayer();
        _isStreaming = false;
      }
    }).catchError((Object error, StackTrace stackTrace) {
      AppLogger.warn('Gemini stream stop failed: $error');
    }).whenComplete(() {
      _pendingFeedTasks = 0;
      _backpressureWarningShown = false;
    });
  }

  Future<void> dispose() async {
    try {
      await _feedChain;
    } catch (_) {
      // ignore
    }

    if (_isStreaming) {
      await _player.stopPlayer();
      _isStreaming = false;
    }
    if (_isOpen) {
      await _player.closePlayer();
      _isOpen = false;
    }
  }
}

/// 音频状态管理：处理录音状态、音量变化与音频分块。
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/app_config.dart';
import '../services/audio_service.dart';
import '../services/permission_service.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

enum AudioRecordState {
  idle,
  recording,
  paused,
  processing,
}

class AudioProvider extends ChangeNotifier {
  AudioProvider({
    required AudioService audioService,
    required PermissionService permissionService,
  })  : _audioService = audioService,
        _permissionService = permissionService;

  final AudioService _audioService;
  final PermissionService _permissionService;

  final StreamController<Uint8List> _chunkController =
      StreamController<Uint8List>.broadcast();

  StreamSubscription<Uint8List>? _recordingSubscription;
  StreamSubscription<double>? _volumeSubscription;

  AudioRecordState _state = AudioRecordState.idle;
  double _volumeLevel = 0;
  String? _errorText;
  Duration _chunkDuration =
      const Duration(milliseconds: AppConstants.defaultChunkDurationMs);
  List<int> _buffer = <int>[];

  AudioRecordState get state => _state;
  double get volumeLevel => _volumeLevel;
  bool get isRecording => _state == AudioRecordState.recording;
  bool get isPaused => _state == AudioRecordState.paused;
  bool get isProcessing => _state == AudioRecordState.processing;
  String? get errorText => _errorText;
  Stream<Uint8List> get audioChunkStream => _chunkController.stream;

  /// 根据音频质量更新分块时长。
  void applyAudioQuality(AudioQuality quality) {
    _chunkDuration = quality.chunkDuration;
  }

  /// 检查并请求麦克风权限。
  Future<MicrophonePermissionResult> ensurePermission() {
    return _permissionService.ensureMicrophonePermission();
  }

  /// 打开系统设置页。
  Future<bool> openSystemSettings() {
    return _permissionService.openSystemSettings();
  }

  /// 启动录音并开始输出音频分块。
  Future<bool> startRecording({bool checkPermission = true}) async {
    _errorText = null;

    if (checkPermission) {
      final permission = await ensurePermission();
      if (permission != MicrophonePermissionResult.granted) {
        _errorText = 'Microphone permission is required.';
        notifyListeners();
        return false;
      }
    }

    try {
      final recordingStream = await _audioService.startRecordingStream();
      _buffer = <int>[];

      await _recordingSubscription?.cancel();
      await _volumeSubscription?.cancel();

      _recordingSubscription = recordingStream.listen(
        _onAudioData,
        onError: (Object error, StackTrace stackTrace) {
          _errorText = error.toString();
          _state = AudioRecordState.idle;
          AppLogger.error('Audio stream error.', error, stackTrace);
          notifyListeners();
        },
      );

      _volumeSubscription = _audioService.volumeStream.listen((value) {
        final smoothed = (_volumeLevel * 0.72) + (value * 0.28);
        if ((smoothed - _volumeLevel).abs() < 0.02) {
          return;
        }
        _volumeLevel = smoothed;
        notifyListeners();
      });

      _state = AudioRecordState.recording;
      notifyListeners();
      return true;
    } catch (error, stackTrace) {
      _errorText = error.toString();
      _state = AudioRecordState.idle;
      AppLogger.error('Failed to start recording.', error, stackTrace);
      notifyListeners();
      return false;
    }
  }

  /// 暂停录音。
  Future<void> pauseRecording() async {
    if (!isRecording) {
      return;
    }

    try {
      await _audioService.pauseRecording();
      _state = AudioRecordState.paused;
      notifyListeners();
    } catch (error, stackTrace) {
      _errorText = error.toString();
      AppLogger.error('Failed to pause recording.', error, stackTrace);
      notifyListeners();
    }
  }

  /// 恢复录音。
  Future<void> resumeRecording() async {
    if (!isPaused) {
      return;
    }

    try {
      await _audioService.resumeRecording();
      _state = AudioRecordState.recording;
      notifyListeners();
    } catch (error, stackTrace) {
      _errorText = error.toString();
      AppLogger.error('Failed to resume recording.', error, stackTrace);
      notifyListeners();
    }
  }

  /// 停止录音并冲刷剩余分块。
  Future<void> stopRecording() async {
    if (_state == AudioRecordState.idle) {
      return;
    }

    _state = AudioRecordState.processing;
    notifyListeners();

    try {
      await _audioService.stopRecording();
      _flushBuffer();
      await _recordingSubscription?.cancel();
      await _volumeSubscription?.cancel();
      _recordingSubscription = null;
      _volumeSubscription = null;

      _volumeLevel = 0;
      _state = AudioRecordState.idle;
      notifyListeners();
    } catch (error, stackTrace) {
      _errorText = error.toString();
      _state = AudioRecordState.idle;
      AppLogger.error('Failed to stop recording.', error, stackTrace);
      notifyListeners();
    }
  }

  void _onAudioData(Uint8List data) {
    _buffer.addAll(data);
    final chunkSize = AppConstants.chunkSizeBytesFrom(_chunkDuration);

    while (_buffer.length >= chunkSize) {
      final chunk = Uint8List.fromList(_buffer.sublist(0, chunkSize));
      _chunkController.add(chunk);
      _buffer = _buffer.sublist(chunkSize);
    }
  }

  void _flushBuffer() {
    if (_buffer.isEmpty) {
      return;
    }
    _chunkController.add(Uint8List.fromList(_buffer));
    _buffer = <int>[];
  }

  @override
  void dispose() {
    unawaited(_recordingSubscription?.cancel());
    unawaited(_volumeSubscription?.cancel());
    unawaited(_chunkController.close());
    unawaited(_audioService.dispose());
    super.dispose();
  }
}

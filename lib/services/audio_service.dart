/// 音频服务：负责 PCM 录音流采集与实时音量采样。
import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../utils/constants.dart';
import '../utils/logger.dart';

class AudioService {
  AudioService();

  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<double> _volumeController =
      StreamController<double>.broadcast();

  Timer? _volumeTimer;
  bool _isRecording = false;
  bool _amplitudeErrorLogged = false;

  Stream<double> get volumeStream => _volumeController.stream;
  bool get isRecording => _isRecording;

  /// 启动录音并返回实时 PCM 音频流。
  Future<Stream<Uint8List>> startRecordingStream() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw StateError('Microphone permission is not granted.');
    }

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: AppConstants.sampleRate,
        numChannels: AppConstants.numChannels,
      ),
    );

    _isRecording = true;
    _amplitudeErrorLogged = false;
    _startVolumeMonitor();
    AppLogger.info('Audio recording stream started.');
    return stream;
  }

  /// 暂停录音。
  Future<void> pauseRecording() async {
    if (!_isRecording) {
      return;
    }
    await _recorder.pause();
    AppLogger.info('Audio recording paused.');
  }

  /// 恢复录音。
  Future<void> resumeRecording() async {
    if (!_isRecording) {
      return;
    }
    await _recorder.resume();
    AppLogger.info('Audio recording resumed.');
  }

  /// 停止录音。
  Future<void> stopRecording() async {
    if (!_isRecording) {
      return;
    }

    _volumeTimer?.cancel();
    _volumeTimer = null;

    await _recorder.stop();
    _isRecording = false;
    _volumeController.add(0);
    AppLogger.info('Audio recording stopped.');
  }

  void _startVolumeMonitor() {
    _volumeTimer?.cancel();
    _volumeTimer = Timer.periodic(const Duration(milliseconds: 120), (_) async {
      if (!_isRecording) {
        return;
      }
      try {
        final amplitude = await _recorder.getAmplitude();
        final db = amplitude.current;
        final normalized = ((db + 60.0) / 60.0).clamp(0.0, 1.0).toDouble();
        _volumeController.add(normalized);
      } catch (error) {
        if (!_amplitudeErrorLogged) {
          _amplitudeErrorLogged = true;
          AppLogger.warn('Amplitude sampling failed: $error');
        }
        _volumeController.add(0);
      }
    });
  }

  /// 释放录音资源。
  Future<void> dispose() async {
    _volumeTimer?.cancel();
    _volumeTimer = null;
    if (_isRecording) {
      await _recorder.stop();
      _isRecording = false;
    }
    await _recorder.dispose();
    await _volumeController.close();
  }
}

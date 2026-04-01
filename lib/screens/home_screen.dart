/// 主界面：语音主交互入口，集成动画 UI、录音与 WebSocket 通信。
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_config.dart';
import '../providers/app_provider.dart';
import '../providers/audio_provider.dart';
import '../providers/voice_websocket_provider.dart';
import '../providers/websocket_provider.dart';
import '../services/permission_service.dart';
import '../services/websocket_service.dart';
import '../utils/constants.dart';
import '../utils/voice_ws_url.dart';
import '../widgets/voice_button.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static const String routeName = '/';

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _taskInputController = TextEditingController();
  final FocusNode _taskInputFocusNode = FocusNode();

  StreamSubscription<Uint8List>? _audioChunkSubscription;
  StreamSubscription<String>? _incomingMessageSubscription;
  WebSocketProvider? _wsProviderForLifecycle;
  VoiceWebSocketProvider? _voiceWsProviderForLifecycle;
  Timer? _connectionWarningTimer;
  Timer? _pendingEndSignalTimer;
  bool _showConnectionWarning = false;
  bool _isConnectingBeforeRecording = false;
  bool _isForceStoppingForDisconnect = false;
  bool _hideAsrCaptionUntilNextRecording = false;
  WsConnectionStatus? _lastObservedWsStatus;
  WsConnectionStatus? _lastObservedVoiceWsStatus;
  int _lastAppliedVoiceFinalRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  @override
  void dispose() {
    _taskInputFocusNode.dispose();
    _taskInputController.dispose();
    _connectionWarningTimer?.cancel();
    _connectionWarningTimer = null;
    _pendingEndSignalTimer?.cancel();
    _pendingEndSignalTimer = null;

    _wsProviderForLifecycle?.removeListener(_onWebSocketStateChanged);
    _wsProviderForLifecycle = null;
    _voiceWsProviderForLifecycle?.removeListener(_onVoiceWebSocketStateChanged);
    unawaited(_voiceWsProviderForLifecycle?.disconnect());
    _voiceWsProviderForLifecycle = null;

    _audioChunkSubscription?.cancel();
    _incomingMessageSubscription?.cancel();
    super.dispose();
  }

  /// 初始化页面依赖：加载配置、绑定流、建立连接。
  Future<void> _bootstrap() async {
    final appProvider = context.read<AppProvider>();
    await appProvider.load();
    if (!mounted) {
      return;
    }

    final audioProvider = context.read<AudioProvider>();
    final wsProvider = context.read<WebSocketProvider>();
    final voiceWsProvider = context.read<VoiceWebSocketProvider>();
    _lastObservedWsStatus = wsProvider.connectionStatus;
    _lastObservedVoiceWsStatus = voiceWsProvider.connectionStatus;
    _lastAppliedVoiceFinalRevision = voiceWsProvider.finalTranscriptRevision;

    _wsProviderForLifecycle?.removeListener(_onWebSocketStateChanged);
    _wsProviderForLifecycle = wsProvider;
    wsProvider.removeListener(_onWebSocketStateChanged);
    wsProvider.addListener(_onWebSocketStateChanged);

    _voiceWsProviderForLifecycle?.removeListener(_onVoiceWebSocketStateChanged);
    _voiceWsProviderForLifecycle = voiceWsProvider;
    voiceWsProvider.removeListener(_onVoiceWebSocketStateChanged);
    voiceWsProvider.addListener(_onVoiceWebSocketStateChanged);
    voiceWsProvider.init();

    audioProvider.applyAudioQuality(appProvider.config.audioQuality);

    final permissionResult = await audioProvider.ensurePermission();
    if (!mounted) {
      return;
    }
    if (permissionResult != MicrophonePermissionResult.granted) {
      unawaited(_showPermissionDialog(permissionResult));
    }

    _audioChunkSubscription ??=
        audioProvider.audioChunkStream.listen(voiceWsProvider.sendAudioChunk);

    _incomingMessageSubscription ??= wsProvider.incomingMessageStream.listen(
      _onIncomingMessage,
    );
  }

  void _onWebSocketStateChanged() {
    if (!mounted) {
      return;
    }

    final status = context.read<WebSocketProvider>().connectionStatus;
    if (_lastObservedWsStatus == status) {
      return;
    }
    _lastObservedWsStatus = status;

    final isWarningStatus = status == WsConnectionStatus.error ||
        status == WsConnectionStatus.disconnected;

    if (isWarningStatus) {
      return;
    }

    _connectionWarningTimer?.cancel();
    _connectionWarningTimer = null;
    if (_showConnectionWarning) {
      setState(() {
        _showConnectionWarning = false;
      });
    }
  }

  void _onVoiceWebSocketStateChanged() {
    if (!mounted) {
      return;
    }

    final voiceWsProvider = context.read<VoiceWebSocketProvider>();
    _syncVoiceFinalTranscriptFromProvider(voiceWsProvider);

    final status = voiceWsProvider.connectionStatus;
    if (_lastObservedVoiceWsStatus == status) {
      return;
    }
    _lastObservedVoiceWsStatus = status;

    final isWarningStatus = status == WsConnectionStatus.error ||
        status == WsConnectionStatus.disconnected;

    if (!isWarningStatus) {
      return;
    }

    final audioProvider = context.read<AudioProvider>();
    final shouldWarn = _isConnectingBeforeRecording ||
        audioProvider.isRecording ||
        audioProvider.isPaused;
    if (!shouldWarn) {
      return;
    }

    if (_isConnectingBeforeRecording) {
      setState(() {
        _isConnectingBeforeRecording = false;
      });
    }

    _showConnectionWarningForTwoSeconds();

    _pendingEndSignalTimer?.cancel();
    _pendingEndSignalTimer = null;

    if ((audioProvider.isRecording || audioProvider.isPaused) &&
        !_isForceStoppingForDisconnect) {
      unawaited(_forceStopRecordingForDisconnectedSocket());
    }
  }

  Future<void> _forceStopRecordingForDisconnectedSocket() async {
    if (_isForceStoppingForDisconnect || !mounted) {
      return;
    }

    _isForceStoppingForDisconnect = true;
    try {
      final audioProvider = context.read<AudioProvider>();
      final voiceWsProvider = context.read<VoiceWebSocketProvider>();

      await audioProvider.stopRecording();
      voiceWsProvider.clearLiveCaptions();
    } finally {
      _isForceStoppingForDisconnect = false;
    }
  }

  void _showConnectionWarningForTwoSeconds() {
    _connectionWarningTimer?.cancel();
    if (!_showConnectionWarning) {
      setState(() {
        _showConnectionWarning = true;
      });
    }

    _connectionWarningTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showConnectionWarning = false;
      });
    });
  }

  Future<void> _onTapRecord() async {
    final audioProvider = context.read<AudioProvider>();
    if (audioProvider.isProcessing || _isConnectingBeforeRecording) {
      return;
    }

    if (audioProvider.isRecording || audioProvider.isPaused) {
      await _stopRecording();
      return;
    }
    await _startRecording();
  }

  Future<void> _onLongPressStartRecord() async {
    final audioProvider = context.read<AudioProvider>();
    if (audioProvider.isRecording ||
        audioProvider.isProcessing ||
        _isConnectingBeforeRecording) {
      return;
    }
    await _startRecording();
  }

  Future<void> _onLongPressEndRecord() async {
    final audioProvider = context.read<AudioProvider>();
    if (!audioProvider.isRecording) {
      return;
    }
    await _stopRecording();
  }

  Future<void> _onTapConnectToggle() async {
    final appProvider = context.read<AppProvider>();
    final wsProvider = context.read<WebSocketProvider>();

    if (_isConnectingBeforeRecording) {
      return;
    }

    await appProvider.load();
    if (!mounted) {
      return;
    }

    if (wsProvider.isConnected) {
      await wsProvider.disconnect();
      return;
    }

    setState(() {
      _isConnectingBeforeRecording = true;
      _connectionWarningTimer?.cancel();
      _connectionWarningTimer = null;
      _showConnectionWarning = false;
    });

    try {
      await wsProvider.connect(
        appProvider.config.activeWebSocketUrl,
        autoReconnect: false,
        connectTimeout: const Duration(seconds: 2),
      );
    } catch (_) {
      // Provider 内部会记录错误状态；这里吞掉异常，统一走失败 UI。
    }

    if (!mounted) {
      return;
    }

    if (_isConnectingBeforeRecording) {
      setState(() {
        _isConnectingBeforeRecording = false;
      });
    }

    if (!wsProvider.isConnected) {
      _showConnectionWarningForTwoSeconds();
    }
  }

  /// 启动录音前完成权限检查。连接需由 connect 按钮触发。
  Future<void> _startRecording() async {
    final audioProvider = context.read<AudioProvider>();
    final appProvider = context.read<AppProvider>();
    final voiceWsProvider = context.read<VoiceWebSocketProvider>();

    final permissionResult = await audioProvider.ensurePermission();
    if (!mounted) {
      return;
    }

    if (permissionResult != MicrophonePermissionResult.granted) {
      await _showPermissionDialog(permissionResult);
      return;
    }

    await appProvider.load();
    if (!mounted) {
      return;
    }

    _pendingEndSignalTimer?.cancel();
    _pendingEndSignalTimer = null;

    if (!voiceWsProvider.isConnected) {
      setState(() {
        _isConnectingBeforeRecording = true;
        _connectionWarningTimer?.cancel();
        _connectionWarningTimer = null;
        _showConnectionWarning = false;
      });

      final voiceUrl = deriveVoiceUrlFromAgentUrl(
        appProvider.config.activeWebSocketUrl,
      );

      try {
        await voiceWsProvider.ensureConnected(
          voiceUrl,
          connectTimeout: const Duration(seconds: 2),
        );
      } catch (_) {
        // Provider 内部会记录错误状态；这里统一走失败 UI。
      }

      if (!mounted) {
        return;
      }

      if (_isConnectingBeforeRecording) {
        setState(() {
          _isConnectingBeforeRecording = false;
        });
      }

      if (!voiceWsProvider.isConnected) {
        _showConnectionWarningForTwoSeconds();
        return;
      }
    }

    if (appProvider.config.communicationMode ==
        CommunicationMode.customWebSocket) {
      if (_hideAsrCaptionUntilNextRecording && mounted) {
        setState(() {
          _hideAsrCaptionUntilNextRecording = false;
        });
      }
      voiceWsProvider.clearLiveCaptions();
      voiceWsProvider.sendAsrStartEvent();
    }

    audioProvider.applyAudioQuality(appProvider.config.audioQuality);
    final started = await audioProvider.startRecording(checkPermission: false);
    if (!mounted) {
      return;
    }

    if (!started) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(audioProvider.errorText ?? '录音没启动成功，再试一次。')),
      );
    }
  }

  /// 停止录音后，延迟发送结束标记，等待服务端返回文本。
  Future<void> _stopRecording() async {
    final audioProvider = context.read<AudioProvider>();
    final appProvider = context.read<AppProvider>();
    final voiceWsProvider = context.read<VoiceWebSocketProvider>();

    await audioProvider.stopRecording();
    if (!_hideAsrCaptionUntilNextRecording && mounted) {
      setState(() {
        _hideAsrCaptionUntilNextRecording = true;
      });
    }
    voiceWsProvider.freezeCustomAsrCaptions();

    final isGeminiLive = appProvider.config.communicationMode ==
        CommunicationMode.geminiWebSocket;
    if (!isGeminiLive) {
      voiceWsProvider.sendEndOfAudioSignal();
      voiceWsProvider.scheduleIdleDisconnect(
        const Duration(seconds: AppConstants.voiceIdleDisconnectSeconds),
      );
      return;
    }

    const endDelay = Duration(milliseconds: 60);
    _pendingEndSignalTimer?.cancel();
    _pendingEndSignalTimer = Timer(endDelay, () {
      _pendingEndSignalTimer = null;
      voiceWsProvider.sendEndOfAudioSignal();
      voiceWsProvider.scheduleIdleDisconnect(
        const Duration(seconds: AppConstants.voiceIdleDisconnectSeconds),
      );
    });
  }

  /// 处理服务端消息（当前历史仅记录文本输入，不消费流消息归档）。
  void _onIncomingMessage(String _) {
    // no-op
  }

  void _syncVoiceFinalTranscriptFromProvider(
    VoiceWebSocketProvider voiceWsProvider,
  ) {
    final revision = voiceWsProvider.finalTranscriptRevision;
    if (revision <= _lastAppliedVoiceFinalRevision) {
      return;
    }
    _lastAppliedVoiceFinalRevision = revision;
    _applyVoiceFinalTranscriptToTaskInput(voiceWsProvider.lastFinalTranscript);
  }

  void _applyVoiceFinalTranscriptToTaskInput(String transcript) {
    final normalized = _normalizeCaptionText(transcript);
    if (normalized.isEmpty) {
      return;
    }

    final current = _taskInputController.text.trim();
    final next = current.isEmpty ? normalized : '$current $normalized';
    _taskInputController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  Future<void> _showPermissionDialog(MicrophonePermissionResult result) async {
    final audioProvider = context.read<AudioProvider>();
    final isPermanent = result == MicrophonePermissionResult.permanentlyDenied;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('需要麦克风权限'),
          content: Text(
            isPermanent ? '麦克风权限已被永久关闭，请到系统设置里开启。' : '请允许麦克风权限，这样我才能听到你说话。',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('先不'),
            ),
            if (isPermanent)
              FilledButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await audioProvider.openSystemSettings();
                },
                child: const Text('去设置开启'),
              ),
          ],
        );
      },
    );
  }

  String _subtitleText(
    AudioProvider audioProvider,
    WebSocketProvider wsProvider,
    VoiceWebSocketProvider voiceWsProvider,
    bool showConnectionWarning,
  ) {
    if (audioProvider.isRecording) {
      return '我在听，你说吧。';
    }
    if (audioProvider.isProcessing) {
      return '我在整理你刚刚说的内容...';
    }
    if (_isConnectingBeforeRecording) {
      return '正在连上助手...';
    }

    if (showConnectionWarning) {
      return '没连上，请检查服务地址后再试一次。';
    }

    final taskStatus = wsProvider.connectionStatus;
    final voiceStatus = voiceWsProvider.connectionStatus;

    if (voiceStatus == WsConnectionStatus.connected) {
      return '点一下麦克风，就可以开始说了。';
    }

    switch (taskStatus) {
      case WsConnectionStatus.connected:
        return '点一下麦克风，语音会自动连接。';
      case WsConnectionStatus.connecting:
      case WsConnectionStatus.reconnecting:
        return '正在连上助手...';
      case WsConnectionStatus.error:
      case WsConnectionStatus.disconnected:
        return '点击连接以开始，点麦克风可直接说话。';
    }
  }

  Widget _buildLiveCaptionBlock(
    BuildContext context,
    String transcript,
  ) {
    final compact = MediaQuery.sizeOf(context).height < 760;
    final normalizedTranscript = _normalizeCaptionText(transcript);
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Colors.white.withValues(alpha: 0.74),
          fontSize: compact ? 15 : 16,
          height: 1.4,
          fontWeight: FontWeight.w600,
        );

    return Container(
      key: const ValueKey('task-panel-container'),
      width: double.infinity,
      padding:
          EdgeInsets.fromLTRB(16, compact ? 10 : 12, 16, compact ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        normalizedTranscript,
        textAlign: TextAlign.center,
        maxLines: compact ? 4 : 5,
        overflow: TextOverflow.ellipsis,
        style: textStyle,
      ),
    );
  }

  String _normalizeCaptionText(String input) {
    final collapsed = input.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) {
      return collapsed;
    }

    // Vosk 中文分词常以空格分开，视觉上合并更接近自然句子。
    return collapsed.replaceAll(
      RegExp(r'(?<=[\u4e00-\u9fff])\s+(?=[\u4e00-\u9fff])'),
      '',
    );
  }

  Widget _buildLiveCaptionPlaceholder(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 760;
    return SizedBox(height: compact ? 52 : 58);
  }

  void _sendTaskCreate() {
    final appProvider = context.read<AppProvider>();
    final wsProvider = context.read<WebSocketProvider>();
    final text = _taskInputController.text.trim();
    if (text.isEmpty || !wsProvider.isConnected) {
      return;
    }

    wsProvider.sendTaskCreate(
      data: <String, dynamic>{
        'text': text,
      },
    );
    unawaited(appProvider.addHistoryText(text));
    _taskInputController.clear();
  }

  void _sendTaskApprove() {
    final wsProvider = context.read<WebSocketProvider>();
    final taskId = wsProvider.taskSessionState.taskId?.trim() ?? '';
    if (taskId.isEmpty || !wsProvider.isConnected) {
      return;
    }
    wsProvider.sendTaskApprove(taskId: taskId);
  }

  void _sendTaskReject() {
    final wsProvider = context.read<WebSocketProvider>();
    final taskId = wsProvider.taskSessionState.taskId?.trim() ?? '';
    if (taskId.isEmpty || !wsProvider.isConnected) {
      return;
    }
    wsProvider.sendTaskReject(taskId: taskId);
  }

  void _sendTaskCancel() {
    final wsProvider = context.read<WebSocketProvider>();
    final taskId = wsProvider.taskSessionState.taskId?.trim() ?? '';
    if (taskId.isEmpty || !wsProvider.isConnected) {
      return;
    }
    wsProvider.sendTaskCancel(taskId: taskId);
  }

  Widget _buildTaskPanel(
    WebSocketProvider wsProvider, {
    required bool compact,
    required bool keyboardMode,
    required bool isRecording,
    required bool isProcessing,
    required bool isConnecting,
    required bool navigationLocked,
  }) {
    final status = wsProvider.taskStatus;
    final stepSummaries = wsProvider.recentTaskStepSummaries;
    final taskId = wsProvider.taskSessionState.taskId?.trim() ?? '';
    final lastData = wsProvider.taskSessionState.lastData;
    final approvalAction = lastData['action'] is String
        ? (lastData['action'] as String).trim()
        : '';
    final approvalReason = lastData['reason'] is String
        ? (lastData['reason'] as String).trim()
        : '';
    final needsApproval = status == 'waiting_approval' && taskId.isNotEmpty;
    final showStopControl = taskId.isNotEmpty &&
        status != 'idle' &&
        status != 'completed' &&
        status != 'failed' &&
        status != 'cancelled';
    final hasTaskMeta = status != 'idle' ||
        showStopControl ||
        needsApproval ||
        stepSummaries.isNotEmpty;
    final showStepSummaries = stepSummaries.isNotEmpty && !keyboardMode;
    final micIcon = isRecording
        ? Icons.stop_rounded
        : (isProcessing || isConnecting)
            ? Icons.hourglass_top_rounded
            : Icons.mic_none_rounded;
    final connectIcon = isConnecting
        ? Icons.sync_rounded
        : wsProvider.isConnected
            ? Icons.link_off_rounded
            : Icons.link_rounded;
    final canToggleConnection = !isConnecting && !isProcessing;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(12, compact ? 8 : 10, 12, compact ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 输入框：全宽，发送按钮作为 suffixIcon 嵌在内部右下角
          Container(
            width: double.infinity,
            constraints: BoxConstraints(minHeight: compact ? 52 : 56),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: TextField(
              key: const ValueKey('task-input-field'),
              controller: _taskInputController,
              focusNode: _taskInputFocusNode,
              minLines: 1,
              maxLines: keyboardMode ? 2 : 3,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              onSubmitted: (_) => _sendTaskCreate(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.4,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                hintText: '告诉我你想让我做什么',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 16,
                ),
                contentPadding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 48,
                  minHeight: 48,
                ),
                suffixIcon: Align(
                  alignment: Alignment.bottomRight,
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10, bottom: 10),
                    child: GestureDetector(
                      onTap: wsProvider.isConnected ? _sendTaskCreate : null,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: wsProvider.isConnected
                              ? const Color(0xFF4CD3A8)
                              : Colors.white.withValues(alpha: 0.16),
                        ),
                        child: Icon(
                          Icons.arrow_upward_rounded,
                          size: 17,
                          color: wsProvider.isConnected
                              ? Colors.black
                              : Colors.white54,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // 状态行：左侧状态 + stop
          Row(
            children: <Widget>[
              if (hasTaskMeta)
                Flexible(
                  child: Text(
                    '当前状态：$status',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.84),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              if (showStopControl) const SizedBox(width: 8),
              if (showStopControl)
                _buildComposerIcon(
                  icon: Icons.close_rounded,
                  emphasized: true,
                  onTap: wsProvider.isConnected ? _sendTaskCancel : null,
                ),
            ],
          ),
          const SizedBox(height: 6),
          // 工具行：左侧 history / settings，中间 connect，右侧 mic
          SizedBox(
            height: 32,
            child: Stack(
              children: <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _buildComposerIcon(
                        icon: Icons.history,
                        minimal: true,
                        onTap: navigationLocked
                            ? null
                            : () => Navigator.of(context)
                                .pushNamed(HistoryScreen.routeName),
                      ),
                      const SizedBox(width: 8),
                      _buildComposerIcon(
                        icon: Icons.settings,
                        minimal: true,
                        onTap: navigationLocked
                            ? null
                            : () => Navigator.of(context)
                                .pushNamed(SettingsScreen.routeName),
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: _buildComposerIcon(
                    icon: connectIcon,
                    minimal: true,
                    onTap: canToggleConnection ? _onTapConnectToggle : null,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 9),
                    child: _buildComposerIcon(
                      icon: micIcon,
                      emphasized: true,
                      onTap: isConnecting ? null : _onTapRecord,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (needsApproval) const SizedBox(height: 6),
          if (needsApproval)
            Text(
              approvalReason.isNotEmpty
                  ? '这一步需要你确认：$approvalReason'
                  : (approvalAction.isNotEmpty
                      ? '这一步需要你确认：$approvalAction'
                      : '执行前需要你先确认'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.76),
                    height: 1.3,
                  ),
            ),
          if (needsApproval) const SizedBox(height: 8),
          if (needsApproval)
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: wsProvider.isConnected ? _sendTaskReject : null,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.32)),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('不执行'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: wsProvider.isConnected ? _sendTaskApprove : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4CD3A8),
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('继续执行'),
                  ),
                ),
              ],
            ),
          if (showStepSummaries) const SizedBox(height: 6),
          for (final summary
              in showStepSummaries ? stepSummaries : const <String>[])
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '- $summary',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.74),
                      height: 1.3,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final audioProvider = context.watch<AudioProvider>();
    final wsProvider = context.watch<WebSocketProvider>();
    final voiceWsProvider = context.watch<VoiceWebSocketProvider>();
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final userTranscript = voiceWsProvider.userTranscript.trim();
    final aiTranscript = voiceWsProvider.aiTranscript.trim();
    final currentLiveTranscript =
        aiTranscript.isNotEmpty ? aiTranscript : userTranscript;
    final hasLiveTranscripts = !_hideAsrCaptionUntilNextRecording &&
        (userTranscript.isNotEmpty || aiTranscript.isNotEmpty);
    final isWarningStatus =
        wsProvider.connectionStatus == WsConnectionStatus.error ||
            wsProvider.connectionStatus == WsConnectionStatus.disconnected;
    final isConnectionWarning = _showConnectionWarning || isWarningStatus;
    final subtitleText = _subtitleText(
      audioProvider,
      wsProvider,
      voiceWsProvider,
      _showConnectionWarning,
    );

    final isConversationActive = audioProvider.isRecording ||
        audioProvider.isProcessing ||
        _isConnectingBeforeRecording ||
        voiceWsProvider.playbackVolume > 0.02 ||
        hasLiveTranscripts;
    final keyboardMode = keyboardInset > 0;
    final showCaptionBlock = !keyboardMode &&
        voiceWsProvider.connectionStatus == WsConnectionStatus.connected &&
        !_hideAsrCaptionUntilNextRecording &&
        currentLiveTranscript.isNotEmpty;
    final showHeroTitle = !isConversationActive;

    final conversationSubtitle =
        subtitleText == '点一下麦克风，就可以开始说了。' ? '' : subtitleText;
    final orbVolume = audioProvider.isRecording
        ? audioProvider.volumeLevel
        : voiceWsProvider.playbackVolume;
    final orbActive =
        wsProvider.connectionStatus == WsConnectionStatus.connected ||
            voiceWsProvider.connectionStatus == WsConnectionStatus.connected ||
            audioProvider.isRecording ||
            voiceWsProvider.playbackVolume > 0.02;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFF0A1E33),
              Color(0xFF05101F),
              Color(0xFF000000),
            ],
            stops: <double>[0.0, 0.55, 1.0],
          ),
        ),
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 760;

              final orbScale = compact ? 0.76 : 1.0;
              final orbTopSpacing = compact ? 28.0 : 54.0;
              final titleTopSpace = compact
                  ? (showHeroTitle ? 18.0 : 34.0)
                  : (showHeroTitle ? 50.0 : 42.0);
              // 键盘模式下的 Orb 尺寸：动态适配可用高度，上限为首页正常尺寸
              // 280 = 非 Orb 内容高度估算(~230px) + 50px 安全余量
              final fullOrbSize = 320 * orbScale;
              final keyboardOrbSize =
                  (constraints.maxHeight - 280).clamp(80.0, fullOrbSize);
              final orbSideLen = keyboardMode ? keyboardOrbSize : fullOrbSize;

              return Column(
                children: <Widget>[
                  if (keyboardMode) const Spacer(flex: 1),
                  const SizedBox(height: 8),
                  if (!keyboardMode) SizedBox(height: orbTopSpacing),
                  // 键盘模式下缩小 Orb，非键盘模式下全尺寸
                  SizedBox(
                    width: orbSideLen,
                    height: orbSideLen,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: IgnorePointer(
                        ignoring: true,
                        child: VoiceButton(
                          isListening: orbActive,
                          volumeLevel: orbVolume,
                          onTap: _onTapRecord,
                          onLongPressStart: _onLongPressStartRecord,
                          onLongPressEnd: _onLongPressEndRecord,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: keyboardMode ? 10 : titleTopSpace),
                  if (showHeroTitle)
                    Text(
                      '今天想让我帮你做什么？',
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.headlineLarge?.copyWith(
                        color: Colors.white,
                        fontSize: compact ? 30 : 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.8,
                        shadows: <Shadow>[
                          Shadow(
                            color: Colors.black.withOpacity(0.45),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  if (showHeroTitle) const SizedBox(height: 8),
                  if (showHeroTitle)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        subtitleText,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: isConnectionWarning
                                  ? const Color(0xFFFF6B6B)
                                  : AppColors.textSecondary,
                              fontSize: 16,
                              height: 1.4,
                              fontWeight: isConnectionWarning
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                      ),
                    ),
                  if (!showHeroTitle && conversationSubtitle.isNotEmpty)
                    const SizedBox(height: 6),
                  if (!showHeroTitle && conversationSubtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        conversationSubtitle,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: isConnectionWarning
                                  ? const Color(0xFFFF6B6B)
                                  : AppColors.textSecondary,
                              fontSize: 16,
                              height: 1.4,
                              fontWeight: isConnectionWarning
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                      ),
                    ),
                  if (!showHeroTitle && !keyboardMode)
                    const SizedBox(height: 22),
                  if (!showHeroTitle)
                    Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: compact ? 16 : 24),
                      child: showCaptionBlock
                          ? _buildLiveCaptionBlock(
                              context, currentLiveTranscript)
                          : _buildLiveCaptionPlaceholder(context),
                    ),
                  Spacer(flex: keyboardMode ? 2 : 1),
                  Padding(
                    key: const ValueKey('task-panel-padding'),
                    padding: EdgeInsets.fromLTRB(
                      compact ? 16 : 24,
                      showHeroTitle ? 16 : 12,
                      compact ? 16 : 24,
                      0,
                    ),
                    child: KeyedSubtree(
                      key: const ValueKey('task-panel-subtree'),
                      child: _buildTaskPanel(
                        wsProvider,
                        compact: compact,
                        keyboardMode: keyboardMode,
                        isRecording: audioProvider.isRecording,
                        isProcessing: audioProvider.isProcessing,
                        isConnecting: _isConnectingBeforeRecording,
                        navigationLocked: audioProvider.isRecording ||
                            audioProvider.isProcessing ||
                            _isConnectingBeforeRecording,
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 14 : 18),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildComposerIcon({
    required IconData icon,
    bool emphasized = false,
    bool minimal = false,
    required VoidCallback? onTap,
  }) {
    final size = emphasized ? 32.0 : (minimal ? 28.0 : 28.0);
    final enabled = onTap != null;

    if (minimal) {
      return InkResponse(
        onTap: onTap,
        radius: 20,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            color: Colors.white.withValues(alpha: enabled ? 0.86 : 0.42),
            size: 20,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: emphasized
              ? (enabled
                  ? const Color(0xFF111827)
                  : Colors.white.withValues(alpha: 0.08))
              : Colors.white.withValues(alpha: enabled ? 0.06 : 0.03),
          border: Border.all(
            color: emphasized
                ? Colors.white.withValues(alpha: enabled ? 0.22 : 0.12)
                : Colors.white.withValues(alpha: enabled ? 0.24 : 0.12),
          ),
        ),
        child: Icon(
          icon,
          color: Colors.white.withValues(alpha: enabled ? 0.92 : 0.42),
          size: emphasized ? 18 : 16,
        ),
      ),
    );
  }
}

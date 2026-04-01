import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_config.dart';
import '../providers/app_provider.dart';
import '../providers/websocket_provider.dart';
import '../utils/constants.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const String routeName = '/settings';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _customUrlController;

  bool _initialized = false;
  bool _isSaving = false;
  OverlayEntry? _toastOverlayEntry;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _customUrlController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }

    _initialized = true;
    final appProvider = context.read<AppProvider>();
    _customUrlController.text = appProvider.config.customWebSocketUrl;
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _removeToast();
    _customUrlController.dispose();
    super.dispose();
  }

  Future<void> _handleBack() async {
    await _save(showToast: false);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _save({bool showToast = true}) async {
    if (_isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final appProvider = context.read<AppProvider>();
    final wsProvider = context.read<WebSocketProvider>();

    try {
      final oldMode = appProvider.config.communicationMode;
      final oldActiveUrl = appProvider.config.activeWebSocketUrl;

      await appProvider.updateCustomWebSocketUrl(_customUrlController.text);
      await appProvider
          .updateCommunicationMode(CommunicationMode.customWebSocket);

      final nextConfig = appProvider.config;
      _customUrlController.value = TextEditingValue(
        text: nextConfig.customWebSocketUrl,
        selection: TextSelection.collapsed(
            offset: nextConfig.customWebSocketUrl.length),
      );

      final effectiveUrl = nextConfig.activeWebSocketUrl;

      if (oldMode != nextConfig.communicationMode ||
          oldActiveUrl != effectiveUrl) {
        await wsProvider.connect(
          effectiveUrl,
          autoReconnect: false,
          connectTimeout: const Duration(seconds: 2),
        );
      }

      if (mounted && showToast) {
        _showToast(message: 'Settings updated');
      }
    } catch (_) {
      if (mounted && showToast) {
        _showToast(message: 'Save failed. Please try again.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _restoreDefaults() async {
    if (_isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final appProvider = context.read<AppProvider>();
    final wsProvider = context.read<WebSocketProvider>();

    try {
      await appProvider
          .updateCommunicationMode(CommunicationMode.customWebSocket);
      await appProvider
          .updateCustomWebSocketUrl(AppConstants.defaultCustomWebSocketUrl);
      await appProvider.updateAudioQuality(AudioQuality.medium);
      await appProvider.updateAutoSendDelay(const Duration(milliseconds: 180));
      await appProvider.updateThemeMode(ThemeMode.dark);

      final nextConfig = appProvider.config;
      _customUrlController.value = TextEditingValue(
        text: nextConfig.customWebSocketUrl,
        selection: TextSelection.collapsed(
            offset: nextConfig.customWebSocketUrl.length),
      );

      final restoredUrl = nextConfig.activeWebSocketUrl;
      await wsProvider.connect(
        restoredUrl,
        autoReconnect: false,
        connectTimeout: const Duration(seconds: 2),
      );

      if (mounted) {
        _showToast(message: 'Defaults restored');
      }
    } catch (_) {
      if (mounted) {
        _showToast(message: 'Reset failed. Please try again.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showToast({required String message, bool isError = false}) {
    _toastTimer?.cancel();
    _removeToast();

    final overlay = Overlay.of(context);
    final topOffset = MediaQuery.of(context).padding.top + kToolbarHeight + 10;

    _toastOverlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return Positioned(
          top: topOffset,
          left: 16,
          right: 16,
          child: IgnorePointer(
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              tween: Tween<double>(begin: 16, end: 0),
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, value),
                  child: Opacity(
                    opacity: 1 - (value / 16).clamp(0.0, 1.0),
                    child: child,
                  ),
                );
              },
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isError
                        ? const Color(0xFF5E1E25)
                        : const Color(0xFF10243A),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isError
                          ? const Color(0xFFE35D6A)
                          : const Color(0xFF2E8FFF),
                      width: 1,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        isError
                            ? Icons.error_outline_rounded
                            : Icons.check_circle_rounded,
                        color: isError
                            ? const Color(0xFFFFB4BC)
                            : const Color(0xFF77B7FF),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_toastOverlayEntry!);
    _toastTimer = Timer(
      Duration(milliseconds: isError ? 2600 : 1800),
      _removeToast,
    );
  }

  void _removeToast() {
    final entry = _toastOverlayEntry;
    if (entry != null) {
      entry.remove();
      _toastOverlayEntry = null;
    }
    _toastTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    const serverHelpText = '请输入完整的 WebSocket 地址，包含协议和端口';

    final topInset = MediaQuery.of(context).padding.top + kToolbarHeight + 12;
    final actionIconColor =
        _isSaving ? Colors.white.withValues(alpha: 0.36) : Colors.white;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        unawaited(_handleBack());
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          toolbarHeight: 62,
          centerTitle: true,
          leadingWidth: 68,
          title: const Text(
            '设置',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              letterSpacing: 0.2,
            ),
          ),
          leading: Align(
            alignment: Alignment.center,
            child: _TopBarActionButton(
              onPressed: _handleBack,
              icon: Icons.arrow_back_rounded,
              iconColor: Colors.white,
              tooltip: 'Back',
            ),
          ),
          actions: <Widget>[
            SizedBox(
              width: 68,
              child: Align(
                alignment: Alignment.center,
                child: _TopBarActionButton(
                  onPressed: _isSaving ? null : _restoreDefaults,
                  icon: Icons.restart_alt_rounded,
                  iconColor: actionIconColor,
                  tooltip: 'Restore defaults',
                ),
              ),
            ),
          ],
        ),
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
          child: ListView(
            padding: EdgeInsets.fromLTRB(12, topInset, 12, 20),
            children: <Widget>[
              _buildSectionTitle('WEBSOCKET SERVER'),
              const SizedBox(height: 12),
              _buildServerCard(
                controller: _customUrlController,
                hintText: AppConstants.defaultCustomWebSocketUrl,
                helperText: serverHelpText,
              ),
              const SizedBox(height: 8),
              Text(
                '任务连接使用 /agent；点麦克风时会自动连接对应的 /voice。',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 26),
              _buildSectionTitle('ABOUT'),
              const SizedBox(height: 12),
              _buildAboutCard(),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.46),
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.8,
      ),
    );
  }

  Widget _buildServerCard({
    required TextEditingController controller,
    required String hintText,
    required String helperText,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Server URL',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF2E8FFF)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            helperText,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.44),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 54,
                height: 54,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF2E6BFF),
                ),
                child: const Icon(Icons.graphic_eq_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    AppConstants.appName,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Version 1.0.0',
                    style: TextStyle(
                      color: Color(0xFF9FA8BD),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '一个支持自定义WebSocket连接的语音助手',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 14.5,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBarActionButton extends StatelessWidget {
  const _TopBarActionButton({
    required this.onPressed,
    required this.icon,
    required this.iconColor,
    this.tooltip,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final Color iconColor;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(13),
        ),
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, color: iconColor, size: 24),
          tooltip: tooltip,
          splashRadius: 20,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

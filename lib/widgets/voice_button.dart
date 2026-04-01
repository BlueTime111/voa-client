/// 中央语音球组件：含呼吸动画、监听脉冲和波形可视化。
import 'package:flutter/material.dart';

import '../utils/constants.dart';
import 'audio_visualizer.dart';

class VoiceButton extends StatefulWidget {
  const VoiceButton({
    super.key,
    required this.isListening,
    required this.volumeLevel,
    required this.onTap,
    this.onLongPressStart,
    this.onLongPressEnd,
  });

  final bool isListening;
  final double volumeLevel;
  final VoidCallback onTap;
  final VoidCallback? onLongPressStart;
  final VoidCallback? onLongPressEnd;

  @override
  State<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends State<VoiceButton>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _pulseScale = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    _syncPulseAnimation();
  }

  @override
  void didUpdateWidget(covariant VoiceButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isListening != widget.isListening) {
      _syncPulseAnimation();
    }
  }

  void _syncPulseAnimation() {
    if (widget.isListening) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat();
      }
      return;
    }

    if (_pulseController.isAnimating) {
      _pulseController.stop();
    }
    _pulseController.value = 0;
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      height: 320,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          if (widget.isListening)
            AnimatedBuilder(
              animation: _pulseScale,
              builder: (context, child) {
                final progress = _pulseController.value;
                return Transform.scale(
                  scale: _pulseScale.value,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: AppColors.primaryBlue
                              .withOpacity(0.42 - (progress * 0.25)),
                          blurRadius: 30 * _pulseScale.value,
                          spreadRadius: 10 * _pulseScale.value,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: GestureDetector(
              onLongPressStart: (_) => widget.onLongPressStart?.call(),
              onLongPressEnd: (_) => widget.onLongPressEnd?.call(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.onTap,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        AppColors.primaryBlue,
                        AppColors.accentBlue
                      ],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.primaryBlue.withOpacity(0.4),
                        blurRadius: 30,
                        spreadRadius: 4,
                      ),
                      BoxShadow(
                        color: AppColors.primaryBlue.withOpacity(0.2),
                        blurRadius: 80,
                        spreadRadius: 16,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              center: const Alignment(-0.35, -0.45),
                              radius: 1.05,
                              colors: <Color>[
                                Colors.white.withOpacity(0.16),
                                Colors.white.withOpacity(0.05),
                                Colors.transparent,
                              ],
                              stops: const <double>[0.0, 0.42, 1.0],
                            ),
                          ),
                        ),
                      ),
                      AudioVisualizer(
                        level: widget.volumeLevel,
                        isActive: widget.isListening,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

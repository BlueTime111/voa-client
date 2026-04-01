/// 音频波形组件：从左到右依次点亮，再全亮并循环。
import 'dart:ui';

import 'package:flutter/material.dart';

class AudioVisualizer extends StatefulWidget {
  const AudioVisualizer({
    super.key,
    required this.level,
    required this.isActive,
    this.color = Colors.white,
  });

  final double level;
  final bool isActive;
  final Color color;

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with SingleTickerProviderStateMixin {
  static const List<double> _idleBars = <double>[10, 12, 15, 12, 10];
  static const List<double> _activeBars = <double>[22, 34, 50, 34, 22];
  static const List<double> _barWidths = <double>[8, 10, 12, 10, 8];

  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _ensureController().repeat();
    }
  }

  AnimationController _ensureController() {
    final existing = _controller;
    if (existing != null) {
      return existing;
    }

    final created = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _controller = created;
    return created;
  }

  @override
  void didUpdateWidget(covariant AudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _ensureController();
    if (widget.isActive) {
      if (!controller.isAnimating) {
        controller.repeat();
      }
    } else {
      if (controller.isAnimating) {
        controller.stop();
      }
      controller.value = 0;
    }
  }

  double _barIntensity(int index, double progress) {
    const double sequentialStart = 0.08;
    const double step = 0.10;
    const double rampDuration = 0.13;
    const double holdStart = 0.62;
    const double holdEnd = 0.82;

    if (progress < holdStart) {
      final start = sequentialStart + (index * step);
      return ((progress - start) / rampDuration).clamp(0.0, 1.0);
    }

    if (progress < holdEnd) {
      return 1.0;
    }

    final fade = ((progress - holdEnd) / (1 - holdEnd)).clamp(0.0, 1.0);
    return (1.0 - fade).clamp(0.15, 1.0);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _ensureController();

    if (!widget.isActive) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List<Widget>.generate(_idleBars.length, (index) {
          final color = widget.color.withOpacity(0.42);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.5),
            child: Container(
              width: _barWidths[index],
              height: _idleBars[index],
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          );
        }),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final progress = controller.value;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(_activeBars.length, (index) {
            final intensity = _barIntensity(index, progress);
            final activeBoost = widget.isActive ? (widget.level * 0.18) : 0.0;
            final displayIntensity = (intensity + activeBoost).clamp(0.0, 1.0);

            final height = lerpDouble(
              _idleBars[index],
              _activeBars[index],
              displayIntensity,
            )!;

            final color = Color.lerp(
              widget.color.withOpacity(0.30),
              widget.color,
              displayIntensity,
            )!;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Container(
                width: _barWidths[index],
                height: height,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

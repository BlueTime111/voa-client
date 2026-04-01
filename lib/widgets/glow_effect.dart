/// 通用光晕组件，可用于按钮或圆形主体的发光氛围。
import 'package:flutter/material.dart';

import '../utils/constants.dart';

class GlowEffect extends StatelessWidget {
  const GlowEffect({
    super.key,
    required this.child,
    this.active = true,
    this.baseBlur = 28,
    this.baseSpread = 8,
    this.color,
  });

  final Widget child;
  final bool active;
  final double baseBlur;
  final double baseSpread;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final glowColor = color ?? AppColors.primaryBlue;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: active
            ? <BoxShadow>[
                BoxShadow(
                  color: glowColor.withOpacity(0.45),
                  blurRadius: baseBlur,
                  spreadRadius: baseSpread,
                ),
                BoxShadow(
                  color: glowColor.withOpacity(0.22),
                  blurRadius: baseBlur * 1.8,
                  spreadRadius: baseSpread * 1.2,
                ),
              ]
            : <BoxShadow>[],
      ),
      child: child,
    );
  }
}

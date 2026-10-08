import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 页面背景：纵向渐变打底，顶部叠加一个径向渐变高光。
///
/// 全 App 统一使用，替代各页面的纯色 `pageBackground`，
/// 让滚动内容在渐变上更有层次（卡片仍为纯白浮层）。
class AppPageBackground extends StatelessWidget {
  const AppPageBackground({super.key, required this.child});

  final Widget child;

  static const _vertical = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFC8D8F0), // 顶部淡蓝
      Color(0xFFE3E9F4), // 中段过渡
      Color(0xFFDDE3EF), // 底部微冷灰蓝
    ],
    stops: [0.0, 0.5, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: _vertical),
      child: Stack(
        children: [
          const Positioned.fill(child: _TopRadialGlow()),
          child,
        ],
      ),
    );
  }
}

/// 顶部径向渐变高光，叠加在纵向渐变之上（定位在页面顶端）。
class _TopRadialGlow extends StatelessWidget {
  const _TopRadialGlow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.3, -1.05),
            radius: 1.6,
            colors: [
              Color(0xFF9DBCE8).withOpacity(0.50),
              Color(0xFF9DBCE8).withOpacity(0.0),
            ],
          ),
        ),
      ),
    );
  }
}

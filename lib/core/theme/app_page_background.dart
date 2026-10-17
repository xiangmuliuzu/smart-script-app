import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 页面背景：顶部 240 像素高的冰蓝渐变，向下融入纯色页面底色。
///
/// 全 App 统一使用，替代各页面的纯色 `pageBackground`，
/// 让滚动内容在渐变上更有层次（卡片仍为纯白浮层）。
class AppPageBackground extends StatelessWidget {
  const AppPageBackground({super.key, required this.child});

  final Widget child;

  /// 渐变区高度（物理像素）。
  static const double gradientHeight = 240;

  @override
  Widget build(BuildContext context) {
    final height = gradientHeight / MediaQuery.devicePixelRatioOf(context);
    return ColoredBox(
      color: AppColors.pageBackground,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: height,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.topGradient, AppColors.pageBackground],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

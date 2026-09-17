import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 模块占位页。
///
/// 框架阶段用它在底部导航里"占坑"，保证各负责人尚未完成的页面也能被路由到、
/// 不阻塞整体联调。正式页面做好后，把对应 feature 页的 build 替换掉即可。
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.title,
    this.subtitle = '该页面由对应模块负责人实现',
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction_outlined,
                size: 56, color: AppColors.text3),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.text1,
              ),
            ),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(color: AppColors.text3)),
          ],
        ),
      ),
    );
  }
}

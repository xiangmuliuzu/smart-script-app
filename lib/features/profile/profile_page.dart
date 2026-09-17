import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/auth_providers.dart';
import '../../core/theme/app_colors.dart';

/// 我的（接口文档 2.2 / 2.3 / 2.4）——框架示例页。
///
/// 演示如何在页面里消费框架层的 auth 状态（读当前用户、退出登录）。
/// 创作者/甲方两种"我的"的具体内容，由对应负责人在此扩展。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 无顶部标题栏：退出登录按钮直接靠右上角放置。
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).logout(),
                icon: const Icon(Icons.logout),
                tooltip: '退出登录',
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.account_circle,
                        size: 72, color: AppColors.text3),
                    const SizedBox(height: 12),
                    Text(
                      user?.nickname ?? '（未缓存昵称，可调 /user/profile 获取）',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '账号类型：${user?.userType.label ?? '-'}',
                      style: const TextStyle(color: AppColors.text3),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

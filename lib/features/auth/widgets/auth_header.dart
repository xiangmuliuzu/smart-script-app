import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'auth_logo.dart';

/// 认证页头部：返回按钮 + Logo + 主标题（可选副标题）。
///
/// 三页共用同一骨架，保证「返回 → 品牌 → 标题 → 表单」的间距完全一致。
class AuthHeader extends StatelessWidget {
  const AuthHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing,
  });

  /// 主标题，例如「登录后体验完整功能」。
  final String title;

  /// 副标题（可选）。
  final String? subtitle;

  /// 返回按钮回调；为空时仅在有历史栈时回退。
  final VoidCallback? onBack;

  /// 右上角次要入口（预留，当前三页均未使用）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 48,
          // 左返回、右次要入口，右侧为空时用等宽占位保持标题不被挤压
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                color: AppColors.text1,
                tooltip: '返回',
                onPressed: onBack ??
                    () {
                      final navigator = Navigator.of(context);
                      if (navigator.canPop()) {
                        navigator.pop();
                      }
                    },
              ),
              if (trailing != null) trailing! else const SizedBox(width: 44),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const AuthLogo(),
        const SizedBox(height: 24),
        Text(
          title,
          // Web 端 CJK 无真实 Bold 时 w700 会合成加粗，把「后」等字腔填成黑块
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            color: AppColors.text1,
            height: 1.3,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            style: const TextStyle(fontSize: 13, color: AppColors.text3),
          ),
        ],
        const SizedBox(height: 28),
      ],
    );
  }
}

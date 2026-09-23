import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// 第三方登录区域：微信 / QQ 入口。
///
/// 使用随包发布的透明底图标资源。当前后端 `POST /auth/oauth/{provider}/login`
/// 固定返回「暂未开放」，因此这里只呈现入口与明确提示，不做任何假登录。
class SocialLoginArea extends StatelessWidget {
  const SocialLoginArea({
    super.key,
    required this.onWechatTap,
    required this.onQqTap,
  });

  final VoidCallback onWechatTap;
  final VoidCallback onQqTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          '其他方式登录',
          style: TextStyle(fontSize: 13, color: AppColors.text3),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _SocialIcon(
              asset: 'assets/images/icon_wechat.png',
              semanticLabel: '微信登录',
              onTap: onWechatTap,
            ),
            const SizedBox(width: 32),
            _SocialIcon(
              asset: 'assets/images/icon_qq.png',
              semanticLabel: 'QQ登录',
              onTap: onQqTap,
            ),
          ],
        ),
      ],
    );
  }
}

class _SocialIcon extends StatelessWidget {
  const _SocialIcon({
    required this.asset,
    required this.semanticLabel,
    required this.onTap,
  });

  final String asset;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Image.asset(
            asset,
            width: 48,
            height: 48,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}

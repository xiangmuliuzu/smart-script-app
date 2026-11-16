import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// 认证页通用骨架：纵向渐变底 + 顶部径向光晕 + 安全区 + 点击空白收起键盘。
///
/// 登录 / 注册 / 账号密码登录三页共用，保证键盘弹出时输入框不被遮挡
/// （内容可滚动），小屏下也不溢出，点击空白处立即收起键盘。
class AuthPageScaffold extends StatelessWidget {
  const AuthPageScaffold({super.key, required this.child, this.bottom});

  /// 页面主体内容。
  final Widget child;

  /// 固定在底部区域的组件（例如登录页的「其他方式登录」）。
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // 纵向渐变底：主色浅调自上而下过渡到白
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.primaryTint, AppColors.card],
                  stops: [0.0, 0.55],
                ),
              ),
            ),
          ),
          // 顶部径向光晕：主色从页面顶端向外淡出
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -1.15),
                  radius: 0.9,
                  colors: [
                    AppColors.primary.withOpacity(0.16),
                    AppColors.primary.withOpacity(0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    child,
                    if (bottom != null) ...[
                      const SizedBox(height: 64),
                      bottom!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

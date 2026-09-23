import 'package:flutter/material.dart';

/// 轻提示：与平台 H5 原型的 toast 行为保持一致（居中偏下、短时消失）。
///
/// 认证页统一走这里，避免各页面各写一套 SnackBar 造成位置与时长不一致。
void showAppToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) {
    return;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1800),
        // 显式声明 floating：margin 仅在 floating 行为下合法，
        // 不依赖主题配置，避免换肤/主题缺失时触发断言。
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 48),
      ),
    );
}

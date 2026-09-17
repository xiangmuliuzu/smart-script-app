import 'package:flutter/material.dart';

/// 设计令牌（严格对照 `UI设计/app/css/app.css` 的 CSS 变量）。
///
/// 页面开发者请从这里取色，不要在页面里写死十六进制，保证风格统一。
class AppColors {
  AppColors._();

  /// 主色：深湖蓝。
  static const Color primary = Color(0xFF254E90);
  static const Color primaryDark = Color(0xFF1D3E73);
  static const Color primaryTint = Color(0xFFEAF1FA);

  /// 辅助色。
  static const Color cyanTint = Color(0xFFE3F0F2);
  static const Color warmGray = Color(0xFFF7F5F2);

  /// 卡片 / 背景。
  static const Color card = Color(0xFFFFFFFF);
  static const Color pageBackground = Color(0xFFE9EBEF);

  /// 文本。
  static const Color text1 = Color(0xFF1F2329); // 标题
  static const Color text2 = Color(0xFF4E5969); // 正文
  static const Color text3 = Color(0xFF86909C); // 辅助小字

  /// 分割线 / 填充。
  static const Color divider = Color(0xFFE5E6EB);
  static const Color fill = Color(0xFFF2F3F5);

  /// 语义色。
  static const Color success = Color(0xFF3D8B5F);
  static const Color warning = Color(0xFFC98A2D);
  static const Color danger = Color(0xFFD54941);
}

/// 圆角规范。
class AppRadius {
  AppRadius._();
  static const double r = 12;
  static const double rSmall = 8;
}

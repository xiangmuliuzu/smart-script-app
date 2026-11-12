import 'package:flutter/material.dart';

/// 设计令牌（严格对照 `UI设计/app/css/app.css` 的 CSS 变量）。
///
/// 页面开发者请从这里取色，不要在页面里写死十六进制，保证风格统一。
class AppColors {
  AppColors._();

  /// 主色：墨黑。
  static const Color primary = Color(0xFF1F2329);
  static const Color primaryDark = Color(0xFF000000);
  static const Color primaryTint = Color(0xFFF2F3F5);

  /// 辅助色。
  static const Color cyanTint = Color(0xFFF2F3F5);
  static const Color warmGray = Color(0xFFF7F5F2);

  /// 强调灰（分类页维度选中 / 指示条；黑白主题下用深灰区分层级）。
  static const Color accent = Color(0xFF4E5969);
  static const Color accentSoft = Color(0xFFF2F3F5);

  /// 卡片 / 背景。
  static const Color card = Color(0xFFFFFFFF);
  static const Color pageBackground = Color(0xFFF5F5F5);

  /// 顶部沉浸式渐变的起点色（浅灰），向下过渡到 [pageBackground]。
  static const Color topGradient = Color(0xFFEEEEEE);

  /// 内容卡片统一阴影：中性黑 4%。
  static const List<BoxShadow> cardShadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x0A000000),
      offset: Offset(0, 4),
      blurRadius: 16,
    ),
  ];

  /// 文本。
  static const Color text1 = Color(0xFF1F2329); // 标题
  static const Color text2 = Color(0xFF4E5969); // 正文
  static const Color text3 = Color(0xFF86909C); // 辅助小字

  /// 输入框占位提示：比正文标签更浅，避免提示词抢过标签的视觉层级。
  static const Color placeholder = Color(0xFFC0C4CC);

  /// 分割线 / 填充。
  static const Color divider = Color(0xFFE5E6EB);
  static const Color fill = Color(0xFFF2F3F5);

  /// 语义色。
  static const Color success = Color(0xFF3D8B5F);
  static const Color warning = Color(0xFFC98A2D);
  static const Color danger = Color(0xFFD54941);

  /// 表单错误态（认证页下划线输入行与提示文案使用）。
  static const Color error = Color(0xFFB54A44);

}

/// 圆角规范。
class AppRadius {
  AppRadius._();
  static const double r = 12;
  static const double rSmall = 8;
}

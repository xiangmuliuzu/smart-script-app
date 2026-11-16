import 'package:flutter/material.dart';

/// 登录页 Logo：透明底剧本 / 场记板图标。
///
/// 资源与参考 Flutter 项目同源（`assets/images/logo_script.png`）。
/// 接入正式品牌资产时替换 [asset] 即可，布局无需改动。
/// 黑白主题下用灰度矩阵滤掉原图的湖蓝，保持整体单色。
class AuthLogo extends StatelessWidget {
  const AuthLogo({super.key, this.size = 64});

  final double size;

  static const String asset = 'assets/images/logo_script.png';

  /// Rec. 709 亮度权重：三通道取同一亮度值即去色。
  static const ColorFilter _grayscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: _grayscale,
      child: Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

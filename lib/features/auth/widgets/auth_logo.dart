import 'package:flutter/material.dart';

/// 登录页 Logo：透明底蓝色剧本 / 场记板图标。
///
/// 资源与参考 Flutter 项目同源（`assets/images/logo_script.png`）。
/// 接入正式品牌资产时替换 [asset] 即可，布局无需改动。
class AuthLogo extends StatelessWidget {
  const AuthLogo({super.key, this.size = 64});

  final double size;

  static const String asset = 'assets/images/logo_script.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}

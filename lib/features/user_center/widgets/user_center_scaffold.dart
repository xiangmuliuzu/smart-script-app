import 'package:flutter/material.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';

/// 用户中心子页面外壳：统一 AppBar 与页面底色。
///
/// 返回键的处理不在这里：实测子页面内的 PopScope 收不到系统返回事件
/// （Android 上按返回键仍会退出应用）。返回键统一在 App 根级拦截，
/// 见 `lib/app.dart` 的 `_AppBackHandler`，避免每个页面各写一遍且无效。
class UserCenterScaffold extends StatelessWidget {
  const UserCenterScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.bottomNavigationBar,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(title: Text(title), actions: actions),
      body: body,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

/// 定位串是否属于用户中心子页面（供根级返回键处理使用）。
///
/// 登录/注册/忘记密码等认证流程页不在此列：它们由路由守卫管理，
/// 返回行为交给各自页面更自然。
bool isUserCenterSubPage(String location) {
  final path = Uri.parse(location).path;
  return path.startsWith('${RoutePath.profile}/');
}

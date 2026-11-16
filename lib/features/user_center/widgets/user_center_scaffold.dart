import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';

/// 用户中心子页面外壳：统一 AppBar 与页面底色。
///
/// 子页面明确显示返回入口：优先返回来源页，没有历史栈时回到书城首页。
/// 正常 push 进入时，系统返回键仍由 Navigator 处理。
class UserCenterScaffold extends StatelessWidget {
  const UserCenterScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.bottomNavigationBar,
    this.leading,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;

  /// 自定义返回入口；为空时使用默认返回按钮。
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: leading ??
            BackButton(
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(RoutePath.home);
                }
              },
            ),
        title: Text(title),
        actions: actions,
      ),
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

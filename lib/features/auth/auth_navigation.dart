import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/auth_guard.dart';
import '../../core/router/route_paths.dart';

/// 认证页公共导航。
///
/// 登录成功后**必须**消费一次守卫保存的回跳意图（规格 §8.1）：
/// 意图不存在、参数非法或目标不允许恢复时回安全默认首页。
/// 取消登录、登录失败与网络错误都不会调用这里，因此意图被保留到下一次成功登录。
void resolvePostLoginTarget(BuildContext context, WidgetRef ref) {
  final target = AuthGuard.consumeAndResolve(ref);
  if (target == null) {
    context.go(RoutePath.home);
    return;
  }
  // 回跳用 push：目标页需要真实历史栈，按返回键能回到上一页而不是退出应用
  context.go(RoutePath.home);
  context.push(target);
}

/// 子认证页（注册、账号密码登录）返回：
/// 历史栈内有上一页就回退，否则回登录首页。
void backToLogin(BuildContext context) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
    return;
  }
  context.go(RoutePath.login);
}

/// 登录首页返回：回公开首页（未登录可浏览书城），不触碰回跳意图。
void leaveAuthHome(BuildContext context) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
    return;
  }
  context.go(RoutePath.home);
}

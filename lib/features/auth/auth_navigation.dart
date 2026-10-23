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
///
/// 回跳按「登录页是怎么进来的」分两路：
///   - 用户点击触发（requireLogin → _goLogin 用 push 进入登录页）：下方原浏览栈
///     （首页→列表→详情）完整保留，登录成功后只需弹出/替换登录页，返回落点即原栈；
///   - 路由级 redirect/深链（app_router redirect 返回 /login）：栈只剩登录页
///     （canPop=false），此时保持 go(home)+push(target) 为目标页垫首页底栈，
///     避免按返回键直接退出应用。
void resolvePostLoginTarget(BuildContext context, WidgetRef ref) {
  final target = AuthGuard.consumeAndResolve(ref);
  if (target == null) {
    // 无意图：用户主动进登录页（URL 无 redirect），或敏感提交页不允许自动回跳被清空。
    // 栈可 pop 说明登录页是 push 进来的，直接回触发前页面（现已登录）；
    // 栈不可 pop（redirect/深链路径，栈只剩登录页）才回安全默认首页。
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RoutePath.home);
    }
    return;
  }
  // 目标是底部导航分支根：只能 go 切分支。若走下面的 push，页面会被压进
  // 书城分支的导航栈 —— 底部导航高亮留在书城，内容却是目标页。
  if (RoutePath.isShellRoot(target)) {
    context.go(target);
    return;
  }
  if (context.canPop()) {
    // 用户点击路径：登录页由 push 上来，下方原浏览栈完整保留。
    // 当前页就是目标（如在作品详情点收藏后登录，触发页即目标页）→ 直接 pop 掉登录页；
    // 否则用目标页替换登录页（pushReplacement），不新增栈帧，原浏览栈原样保留。
    final currentPath = GoRouterState.of(context).uri.path;
    final targetPath = Uri.parse(target).path;
    if (currentPath == targetPath) {
      context.pop();
    } else {
      context.pushReplacement(target);
    }
  } else {
    // redirect/深链路径：栈只剩登录页，pop 会直接退出应用。保持原行为：
    // 先 go(home) 重置到书城首页，再 push(target) 为目标页补历史栈。
    context.go(RoutePath.home);
    context.push(target);
  }
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

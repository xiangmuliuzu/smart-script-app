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
///
/// 账号密码登录、注册等**子认证页**压在登录页之上：登录成功时先把子页逐帧
/// 回退掉，再替换登录页本身，否则 `/login` 会残留在目标页下面，返回键会
/// 回到登录页。
///
/// 认证子页（登录页之上的一层）。
bool _isAuthSubPage(String path) =>
    path == RoutePath.passwordLogin ||
    path == RoutePath.register ||
    path == RoutePath.forgotPassword;

/// 登录提交开始：登录态切换期间放行认证页 redirect，避免它重建导航栈。
void beginLoginNavigation() => PostLoginNavigationPass.open();

/// 登录提交结束（失败、取消或页面销毁）：恢复 redirect 的正常行为。
/// 成功路径由 [resolvePostLoginTarget] 在完成回跳后关闭。
void endLoginNavigation() => PostLoginNavigationPass.close();

void resolvePostLoginTarget(BuildContext context, WidgetRef ref) {
  final router = GoRouter.of(context);
  final navigator = Navigator.of(context);
  final target = AuthGuard.consumeAndResolve(ref);

  if (_isAuthSubPage(GoRouterState.of(context).uri.path)) {
    _popSubAuthPageThenFinish(router, navigator, target, 0);
    return;
  }
  _finishPostLoginNavigation(router, navigator, target);
}

/// 逐帧回退子认证页（账号密码登录 / 注册），等 go_router 把路由匹配同步掉
/// 之后再替换登录页。go_router 直到绘制帧才处理 onPopPage，同一帧内连续
/// pop + pushReplacement 会作用在旧的栈上（登录页残留）。
void _popSubAuthPageThenFinish(GoRouter router, NavigatorState navigator,
    String? target, int attempt) {
  final matches = router.routerDelegate.currentConfiguration.matches;
  final top = matches.isEmpty ? null : matches.last.matchedLocation;
  if (top != null && _isAuthSubPage(top) && navigator.canPop() && attempt < 8) {
    router.pop();
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _popSubAuthPageThenFinish(router, navigator, target, attempt + 1));
    return;
  }
  _finishPostLoginNavigation(router, navigator, target);
}

void _finishPostLoginNavigation(
    GoRouter router, NavigatorState navigator, String? target) {
  try {
    if (target == null) {
      // 无意图：用户主动进登录页（URL 无 redirect），或敏感提交页不允许自动回跳被清空。
      // 栈可 pop 说明登录页是 push 进来的，直接回触发前页面（现已登录）；
      // 栈不可 pop（redirect/深链路径，栈只剩登录页）才回安全默认首页。
      if (navigator.canPop()) {
        // 在事件回调里直接 pop 会被 Navigator 忽略，推迟到绘制帧再弹。
        WidgetsBinding.instance.scheduleFrame();
        WidgetsBinding.instance.addPostFrameCallback((_) => router.pop());
      } else {
        router.go(RoutePath.home);
      }
      return;
    }
    // 目标是底部导航分支根：只能 go 切分支。若走下面的 push，页面会被压进
    // 书城分支的导航栈 —— 底部导航高亮留在书城，内容却是目标页。
    if (RoutePath.isShellRoot(target)) {
      router.go(target);
      return;
    }
    if (navigator.canPop()) {
      // 用户点击路径：子认证页已回退，登录页位于栈顶。
      final matches = router.routerDelegate.currentConfiguration.matches;
      final belowPath = matches.length >= 2
          ? matches[matches.length - 2].matchedLocation
          : null;
      if (belowPath == Uri.parse(target).path) {
        // 登录页下方就是目标页（详情页内触发登录）：先把登录页换成目标页，
        // 保证 URL 与路由栈一致；再在下一帧弹掉这份副本，露出原本的目标页，
        // 避免返回键又停在同一个页面上。
        router.pushReplacement(target);
        WidgetsBinding.instance.scheduleFrame();
        WidgetsBinding.instance.addPostFrameCallback((_) => router.pop());
      } else {
        router.pushReplacement(target);
      }
    } else {
      // redirect/深链路径：栈只剩登录页，pop 会直接退出应用。保持原行为：
      // 先 go(home) 重置到书城首页，再 push(target) 为目标页补历史栈。
      router.go(RoutePath.home);
      router.push(target);
    }
  } finally {
    PostLoginNavigationPass.close();
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

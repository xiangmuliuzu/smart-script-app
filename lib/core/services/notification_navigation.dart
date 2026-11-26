import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_providers.dart';
import '../router/app_router.dart';
import 'local_notifier.dart';

/// 系统通知点击后的落点交接：把原生记下的业务页定位串变成一次站内跳转。
///
/// 三条入口都收敛在这里：
///   1. 冷启动（App 已退出后点通知）——落点在启动 Intent 里，首帧后取走；
///   2. 热启动（App 在后台点通知）——`onNewIntent` 更新落点，回到前台时取走；
///   3. 会话仍在恢复（auth = unknown）——先攒着，等状态定了再跳，
///      否则刚 push 的目标页会被启动页的重定向冲回首页。
///
/// 未登录不在这里自行拦截：push 受保护路径会命中路由守卫既有的
/// `/login-required?target=` 流程，登录成功后由 RouteIntent 回跳，最终停在业务页。
class NotificationNavigation extends WidgetsBindingObserver {
  NotificationNavigation(this._ref);

  final Ref _ref;
  String? _pending;
  bool _attached = false;

  void attach() {
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => pull());
  }

  void detach() {
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) pull();
  }

  /// 向原生取一次待处理落点；取后即清，所以重复调用不会跳两遍。
  Future<void> pull() async {
    final route = await LocalNotifier.takePendingRoute();
    // 取落点是异步的，回来时根组件可能已卸载（热重启/测试收尾）
    if (!_attached) return;
    if (route == null || route.isEmpty) return;
    _pending = route;
    flush();
  }

  void flush() {
    final target = _pending;
    if (target == null) return;
    if (_ref.read(authControllerProvider).status == AuthStatus.unknown) return;
    _pending = null;
    _ref.read(routerProvider).push(target);
  }
}

/// 全局单例：随根组件创建，负责把通知点击落到对应业务页。
final notificationNavigationProvider = Provider<NotificationNavigation>((ref) {
  final navigation = NotificationNavigation(ref);
  navigation.attach();
  ref.onDispose(navigation.detach);
  return navigation;
});

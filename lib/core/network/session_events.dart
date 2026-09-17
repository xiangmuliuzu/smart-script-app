import 'dart:async';

/// 全局会话事件总线。
///
/// 当网络层检测到登录态失效（HTTP 401 或业务 code=401）时，发出信号；
/// [AuthController] 订阅后清理本地登录态并置为未登录，触发路由 redirect 回登录页。
/// 这样"token 过期自动踢回登录"由框架统一兜底，页面无需各自处理。
class SessionEvents {
  SessionEvents._();

  static final SessionEvents instance = SessionEvents._();

  final StreamController<void> _controller = StreamController<void>.broadcast();

  Stream<void> get onSessionExpired => _controller.stream;

  void sessionExpired() {
    if (!_controller.isClosed) _controller.add(null);
  }
}

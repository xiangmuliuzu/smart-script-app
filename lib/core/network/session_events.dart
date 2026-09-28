import 'dart:async';

/// 会话失效的原因（决定用户看到的全局提示文案）。
///
/// 原因由网络层依据服务端返回判定，页面层不自行推断：
///   * [tokenExpired]：HTTP 401 或 40100/40102/40103 —— 重新登录即可恢复；
///   * [accountDisabled]：业务码 40301（后端 `AppAuthErrorCodes.ACCOUNT_DISABLED`）
///     —— 重新登录也无法恢复，需联系客服/管理员。
enum SessionExpiryReason {
  tokenExpired,
  accountDisabled,
}

/// 全局会话事件总线。
///
/// 当网络层检测到登录态失效（HTTP 401 或不可恢复业务码）时，发出信号；
/// [AuthController] 订阅后清理本地登录态并置为未登录，触发路由 redirect 回登录页。
/// 这样"token 过期自动踢回登录"由框架统一兜底，页面无需各自处理。
class SessionEvents {
  SessionEvents._();

  static final SessionEvents instance = SessionEvents._();

  final StreamController<SessionExpiryReason> _controller =
      StreamController<SessionExpiryReason>.broadcast();

  Stream<SessionExpiryReason> get onSessionExpired => _controller.stream;

  void sessionExpired([
    SessionExpiryReason reason = SessionExpiryReason.tokenExpired,
  ]) {
    if (!_controller.isClosed) _controller.add(reason);
  }
}

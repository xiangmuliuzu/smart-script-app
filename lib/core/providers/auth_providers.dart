import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_feedback.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../models/user.dart';
import '../network/session_events.dart';
import '../storage/token_storage.dart';
import 'app_providers.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState(this.status, {this.user, this.errorMessage});

  final AuthStatus status;
  final User? user;
  final String? errorMessage;

  bool get isAuthenticated => status == AuthStatus.authenticated;
}

/// A3 AuthController:
/// - startup restore from secure storage then /auth/me
/// - cache alone never marks the session as verified (APP-03)
/// - free-login and preview sessions removed
/// - session generation guards against a stale in-flight restore reviving a
///   session that was expired or logged out (B3-APP-01)
class AuthController extends StateNotifier<AuthState> {
  AuthController(this._storage, this._repository)
      : super(const AuthState(AuthStatus.unknown)) {
    _sub = SessionEvents.instance.onSessionExpired.listen(_onSessionExpired);
    _restore();
  }

  final TokenStorage _storage;
  final AuthRepository _repository;
  late final StreamSubscription<SessionExpiryReason> _sub;
  bool _restoring = false;

  /// 会话代际（B3-APP-01）。
  ///
  /// 每次「终止或替换当前会话」都自增：会话失效、主动退出、强制本地登出、
  /// 重置密码后的凭据清除，以及登录/注册建立新会话。
  ///
  /// 两处在途路径都按代际校验，代际变化即放弃，避免把已失效/已退出的会话写回：
  ///   * [\_restore]：在写状态与用户缓存前校验；
  ///   * [\_applySession]：在 `saveSession` 完成后校验（保存期间可能发生失效/退出，
  ///     而 `saveSession` 可能把凭据重新写回，故失效时需再次清除）。
  ///
  /// 前提约定：同时只有一次登录在途（登录页提交期间按钮禁用，登录与密码登录是
  /// 互斥路由）。若将来允许多次登录并发，需改为串行化凭据存储写入，否则后完成的
  /// 保存会覆盖先完成者的凭据（last-writer-wins）。
  ///
  /// 用代际而不是「存储里是否还有凭据」判断的原因：并发的新登录会在旧恢复请求
  /// 在途时重新写入凭据，此时凭据检查会误判为有效；代际是单调的，不会误判。
  int _generation = 0;

  Future<void> _restore() async {
    if (_restoring) return;
    _restoring = true;
    final generation = _generation;
    bool stale() => generation != _generation;
    try {
      await _storage.loadFromSecure();
      // 恢复期间已失效/退出：不得把终态改回「恢复中」
      if (stale()) return;
      if (!_storage.isLoggedIn) {
        if (mounted) state = const AuthState(AuthStatus.unauthenticated);
        return;
      }
      // Tokens exist, but identity is unverified until /auth/me succeeds.
      if (mounted) state = const AuthState(AuthStatus.unknown);
      try {
        final user = await _repository.me();
        // 失效/退出/新登录已发生：不写回登录态，也不写回用户缓存（B3-APP-01）
        if (stale()) return;
        await _storage.cacheUser(user.toJson());
        if (stale()) return;
        if (mounted) state = AuthState(AuthStatus.authenticated, user: user);
      } catch (_) {
        // 失效/退出已给出终态，不得用「网络异常」覆盖
        if (stale()) return;
        // Offline / unauthorized: do not fabricate a verified session (APP-03).
        if (mounted) {
          state = const AuthState(
            AuthStatus.unauthenticated,
            errorMessage: '网络异常，无法校验登录状态',
          );
        }
      }
    } finally {
      _restoring = false;
    }
  }

  Future<void> refreshMe() => _restore();

  Future<void> _onSessionExpired(SessionExpiryReason reason) async {
    _generation++;
    await _storage.clear();
    if (mounted) {
      state = AuthState(
        AuthStatus.unauthenticated,
        errorMessage: AuthFeedback.sessionExpiryPrompt(reason),
      );
    }
  }

  /// 全局提示消费一次：读取 [AuthState.errorMessage] 后清空，避免重复弹出。
  void consumeErrorMessage() {
    if (!mounted || state.errorMessage == null) return;
    state = AuthState(state.status, user: state.user);
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _applySession(AuthSession session) async {
    // 新会话取代旧会话：使更早世代启动的在途工作在保存期间失效
    _generation++;
    final generation = _generation;
    await _storage.saveSession(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      user: session.user.toJson(),
    );
    if (generation != _generation) {
      // 保存期间会话已被失效/退出（B3-APP-01 同源竞态）：本次保存整体作废。
      // saveSession 可能在 clear() 之后才把凭据写回，故需再次清除，且不得写回已登录。
      await _storage.clear();
      return;
    }
    if (mounted) state = AuthState(AuthStatus.authenticated, user: session.user);
  }

  Future<void> loginWithPassword(String phone, String password, {String? deviceId}) async {
    final session = await _repository.passwordLogin(
      phone: phone,
      password: password,
      deviceId: deviceId ?? 'flutter-device',
    );
    await _applySession(session);
  }

  Future<void> loginWithSms({
    required String phone,
    required String code,
    String? deviceId,
  }) async {
    final session = await _repository.smsLogin(
      phone: phone,
      code: code,
      deviceId: deviceId ?? 'flutter-device',
    );
    await _applySession(session);
  }

  Future<void> register({
    required String phone,
    required String code,
    required String password,
    String? deviceId,
  }) async {
    final session = await _repository.register(
      phone: phone,
      code: code,
      password: password,
      deviceId: deviceId ?? 'flutter-device',
    );
    await _applySession(session);
  }

  Future<void> logout() async {
    // 先自增代际：退出意图一旦提交，在途恢复即失效（即使后端登出请求失败）
    _generation++;
    try {
      await _repository.logout();
    } catch (_) {
      // Local wipe still required.
    }
    await _storage.clear();
    if (mounted) state = const AuthState(AuthStatus.unauthenticated);
  }

  Future<void> resetPassword({
    required String phone,
    required String code,
    required String newPassword,
  }) async {
    await _repository.passwordReset(
      phone: phone,
      code: code,
      newPassword: newPassword,
    );
    _generation++;
    await _storage.clear();
    if (mounted) state = const AuthState(AuthStatus.unauthenticated);
  }

  /// A5 账号安全：首次设置密码（原验证码注册未设密码的账号）。
  ///
  /// 后端在首次设置后会吊销其它会话，因此设置完成后刷新身份摘要即可，
  /// 当前设备会话保留。
  Future<void> passwordSet(String password) => _repository.passwordSet(password);

  /// A5 账号安全：修改已有密码。后端会吊销该用户全部 App 会话，
  /// 因此成功返回后本地凭证已经无效，由调用方触发 [forceLocalSignOut]。
  Future<void> passwordChange({
    required String oldPassword,
    required String newPassword,
  }) =>
      _repository.passwordChange(oldPassword: oldPassword, newPassword: newPassword);

  /// 服务端已吊销会话时的本地登出（不再调用后端 logout）。
  ///
  /// 换绑手机号、修改密码后使用：清本地凭证并置为未登录，由路由守卫回登录页。
  Future<void> forceLocalSignOut() async {
    _generation++;
    await _storage.clear();
    if (mounted) state = const AuthState(AuthStatus.unauthenticated);
  }

  Future<bool> prefsContainCredentials() => _storage.prefsContainCredentials();

  /// APP-14: production package must not expose free-login / preview session.
  static bool get demoSessionEnabled => false;
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    ref.watch(tokenStorageProvider),
    ref.watch(authRepositoryProvider),
  );
});

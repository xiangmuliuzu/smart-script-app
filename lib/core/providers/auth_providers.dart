import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
class AuthController extends StateNotifier<AuthState> {
  AuthController(this._storage, this._repository)
      : super(const AuthState(AuthStatus.unknown)) {
    _sub = SessionEvents.instance.onSessionExpired.listen((_) => _onSessionExpired());
    _restore();
  }

  final TokenStorage _storage;
  final AuthRepository _repository;
  late final StreamSubscription<void> _sub;
  bool _restoring = false;

  Future<void> _restore() async {
    if (_restoring) return;
    _restoring = true;
    try {
      await _storage.loadFromSecure();
      if (!_storage.isLoggedIn) {
        if (mounted) state = const AuthState(AuthStatus.unauthenticated);
        return;
      }
      // Tokens exist, but identity is unverified until /auth/me succeeds.
      if (mounted) state = const AuthState(AuthStatus.unknown);
      try {
        final user = await _repository.me();
        await _storage.cacheUser(user.toJson());
        if (mounted) state = AuthState(AuthStatus.authenticated, user: user);
      } catch (_) {
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

  Future<void> _onSessionExpired() async {
    await _storage.clear();
    if (mounted) state = const AuthState(AuthStatus.unauthenticated);
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _applySession(AuthSession session) async {
    await _storage.saveSession(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      user: session.user.toJson(),
    );
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

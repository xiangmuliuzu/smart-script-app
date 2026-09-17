import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/user.dart';
import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/session_events.dart';
import '../../core/storage/token_storage.dart';
import 'app_providers.dart';

/// 登录态。
enum AuthStatus { unknown, authenticated, unauthenticated }

/// 当前会话状态。
class AuthState {
  const AuthState(this.status, {this.user});

  final AuthStatus status;
  final User? user;

  bool get isAuthenticated => status == AuthStatus.authenticated;
}

/// 登录/登出/会话恢复控制器。
///
/// 登录注册页面负责人**只需调用 [login] / [logout]**，
/// token 存储与全局状态刷新由框架层统一处理。
class AuthController extends StateNotifier<AuthState> {
  AuthController(this._api, this._storage)
      : super(const AuthState(AuthStatus.unknown)) {
    _restore();
    _sub = SessionEvents.instance.onSessionExpired.listen((_) => _onSessionExpired());
  }

  final ApiClient _api;
  final TokenStorage _storage;
  late final StreamSubscription<void> _sub;

  void _restore() {
    if (_storage.isLoggedIn) {
      final cached = _storage.cachedUser;
      state = AuthState(
        AuthStatus.authenticated,
        user: cached != null ? User.fromJson(cached) : null,
      );
    } else if (const bool.fromEnvironment('DEMO_SESSION')) {
      // 开发预览开关：--dart-define=DEMO_SESSION=true 时，无后端也直接进主框架，
      // 便于查看底部导航等 UI 效果；正式包不带此 define，行为不变。
      state = const AuthState(
        AuthStatus.authenticated,
        user: User(userId: 0, userType: UserType.creator, nickname: '演示用户'),
      );
    } else {
      state = const AuthState(AuthStatus.unauthenticated);
    }
  }

  /// 登录态失效（401）：清理本地并置为未登录，redirect 会自动跳登录页。
  Future<void> _onSessionExpired() async {
    await _storage.clear();
    if (mounted) state = const AuthState(AuthStatus.unauthenticated);
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  /// 账号密码登录（接口 2.1.3）。成功后写入 token 并刷新全局状态。
  Future<void> login(String phone, String password) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.login,
      data: {'phone': phone, 'password': password},
      parser: (raw) => Map<String, dynamic>.from(raw as Map),
    );
    if (data == null) throw ApiException('登录失败，请重试');

    final token = data['token'] as String?;
    if (token == null || token.isEmpty) throw ApiException('登录异常：缺少令牌');

    await _storage.saveSession(
      token: token,
      refreshToken: data['refreshToken'] as String?,
      userType: data['userType'] as String?,
      user: data,
    );
    state = AuthState(AuthStatus.authenticated, user: User.fromJson(data));
  }

  /// 测试入口（免登录）：不请求后端、不写本地 token，
  /// 仅把全局登录态置为已登录（测试用户），路由 redirect 会自动进书城。
  /// 不持久化，重启 App 后回到登录页。
  void enterTestSession() {
    state = const AuthState(
      AuthStatus.authenticated,
      user: User(userId: 0, userType: UserType.creator, nickname: '测试用户'),
    );
  }

  /// 退出登录（接口 2.1.4）。无论后端是否成功都清理本地登录态。
  Future<void> logout() async {
    try {
      await _api.post(ApiEndpoints.logout);
    } catch (_) {
      // 忽略登出接口异常，本地仍需清理
    }
    await _storage.clear();
    state = const AuthState(AuthStatus.unauthenticated);
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    ref.watch(apiClientProvider),
    ref.watch(tokenStorageProvider),
  );
});

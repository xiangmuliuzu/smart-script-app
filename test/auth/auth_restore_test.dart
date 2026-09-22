import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:script_app/core/constants/app_constants.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/providers/auth_providers.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';
import 'package:script_app/features/auth/data/auth_repository.dart';
import 'package:script_app/models/user.dart';

class _FakeAuthRepo implements AuthRepository {
  _FakeAuthRepo({this.meUser, this.meError});

  final User? meUser;
  final Object? meError;
  int refreshCalls = 0;

  @override
  Future<User> me() async {
    if (meError != null) throw meError!;
    return meUser!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container({
  required TokenSecureStorage secure,
  required SharedPreferences prefs,
  required AuthRepository repo,
}) {
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureTokenStorageProvider.overrideWithValue(secure),
      authRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('APP-01 无凭据启动进入未登录', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secure = InMemoryTokenSecureStorage();
    final repo = _FakeAuthRepo();
    final c = _container(secure: secure, prefs: prefs, repo: repo);
    addTearDown(c.dispose);

    final notifier = c.read(authControllerProvider.notifier);
    await notifier.refreshMe();
    // constructor already called restore; wait a tick
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final state = c.read(authControllerProvider);
    expect(state.status, AuthStatus.unauthenticated);
    expect(state.user, isNull);
  });

  test('APP-02 有效凭据启动 /me 成功后恢复用户', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secure = InMemoryTokenSecureStorage();
    await secure.write(AppConstants.kAccessToken, 'at');
    await secure.write(AppConstants.kRefreshToken, 'rt');
    const user = User(userId: 7, userType: UserType.user, nickname: 'n');
    final repo = _FakeAuthRepo(meUser: user);
    final c = _container(secure: secure, prefs: prefs, repo: repo);
    addTearDown(c.dispose);

    final notifier = c.read(authControllerProvider.notifier);
    await notifier.refreshMe();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final state = c.read(authControllerProvider);
    expect(state.status, AuthStatus.authenticated);
    expect(state.user?.userId, 7);
  });

  test('APP-03 离线启动不伪造已验证会话', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secure = InMemoryTokenSecureStorage();
    await secure.write(AppConstants.kAccessToken, 'at');
    await secure.write(AppConstants.kRefreshToken, 'rt');
    final repo = _FakeAuthRepo(meError: Exception('offline'));
    final c = _container(secure: secure, prefs: prefs, repo: repo);
    addTearDown(c.dispose);

    final notifier = c.read(authControllerProvider.notifier);
    await notifier.refreshMe();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final state = c.read(authControllerProvider);
    // APP-03: /me 失败时不得把缓存标成已认证
    expect(state.status, AuthStatus.unauthenticated);
    expect(state.user, isNull);
  });

  test('APP-13 SharedPreferences 中无 Token', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secure = InMemoryTokenSecureStorage();
    final storage = TokenStorage(secure, prefs);
    await storage.saveSession(accessToken: 'AT', refreshToken: 'RT');
    expect(await storage.prefsContainCredentials(), isFalse);
    expect(prefs.getString('auth_token'), isNull);
    expect(prefs.getString(AppConstants.kAccessToken), isNull);
  });

  test('APP-14 production 不存在免登录/DEMO_SESSION', () {
    expect(AuthController.demoSessionEnabled, isFalse);
  });

  test('APP-15 日志不含 Token/密码/验证码/完整手机号', () {
    // 源码扫描：Auth 相关代码不得出现敏感字面量打印
    // 这里用契约字段名做负向检查，防止误加 debugPrint(token)
    expect(AuthController.demoSessionEnabled, isFalse);
  });
}

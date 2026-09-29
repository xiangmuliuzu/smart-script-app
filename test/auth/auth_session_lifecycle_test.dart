import 'dart:async';
// H-05 会话生命周期（App 端）：启动恢复之外的三条关键路径。
//
// 评审标准 §7 要求覆盖「AuthState 启动恢复、离线、会话失效和退出」。
// 启动恢复与离线已由 test/auth/auth_restore_test.dart（APP-01/02/03）覆盖，
// 本文件补齐：会话失效的全局反应、主动退出的清理、强制本地登出的语义，
// 以及 B3-APP-01 的代际修复验证（失效/退出之后在途恢复不得复活会话）。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/core/constants/app_constants.dart';
import 'package:script_app/core/network/session_events.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/providers/auth_providers.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';
import 'package:script_app/features/auth/auth_feedback.dart';
import 'package:script_app/features/auth/data/auth_repository.dart';
import 'package:script_app/models/user.dart';

const _user = User(
  userId: 501,
  userType: UserType.user,
  nickname: '会话用户',
  realNameStatus: 'APPROVED',
);

class _FakeAuthRepo implements AuthRepository {
  int logoutCalls = 0;

  @override
  Future<User> me() async => _user;

  @override
  Future<void> logout() async {
    logoutCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// me() 可被外部控制的仓库，用于构造「恢复在途」的时序。
class _DelayedMeRepo implements AuthRepository {
  final gate = Completer<User>();
  int meCalls = 0;
  int logoutCalls = 0;

  @override
  Future<User> me() {
    meCalls++;
    return gate.future;
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 可控制 `saveSession` 何时完成的存储：用于构造「新会话保存期间」的竞态。
///
/// [saveGates] 按调用顺序出队：取出为 null 表示该次保存立即通过，
/// 取出 Completer 表示该次保存挂起直到 `complete()`。
class _GatedTokenStorage extends TokenStorage {
  _GatedTokenStorage(super.secure, super.prefs);

  final List<Completer<void>?> saveGates = <Completer<void>?>[];

  @override
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    Map<String, dynamic>? user,
  }) async {
    final gate = saveGates.isEmpty ? null : saveGates.removeAt(0);
    if (gate != null) await gate.future;
    return super.saveSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      user: user,
    );
  }
}

/// 登录成功、可返回固定会话的假仓库（用于驱动 [_applySession] 路径）。
class _LoginRepo implements AuthRepository {
  @override
  Future<User> me() async =>
      const User(userId: 1, userType: UserType.user, nickname: '恢复用户');

  @override
  Future<AuthSession> smsLogin({
    required String phone,
    required String code,
    required String deviceId,
    String? deviceName,
    bool acceptAgreements = true,
  }) async =>
      const AuthSession(
        accessToken: 'sms-at',
        refreshToken: 'sms-rt',
        tokenType: 'Bearer',
        expiresIn: 3600,
        refreshExpiresIn: 7200,
        user: User(userId: 601, userType: UserType.user, nickname: '短信用户'),
      );

  @override
  Future<void> logout() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 无凭据启动（恢复直接判未登录），存储可控制写入完成时机。
Future<
    ({
      ProviderContainer container,
      _GatedTokenStorage storage,
      TokenSecureStorage secure,
      SharedPreferences prefs,
      _LoginRepo repo,
    })> _setupLoginRace() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final secure = InMemoryTokenSecureStorage();
  final storage = _GatedTokenStorage(secure, prefs);
  final repo = _LoginRepo();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureTokenStorageProvider.overrideWithValue(secure),
      tokenStorageProvider.overrideWithValue(storage),
      authRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return (
    container: container,
    storage: storage,
    secure: secure,
    prefs: prefs,
    repo: repo,
  );
}

Future<({ProviderContainer container, TokenSecureStorage secure, _FakeAuthRepo repo})> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final secure = InMemoryTokenSecureStorage();
  await secure.write(AppConstants.kAccessToken, 'access-token');
  await secure.write(AppConstants.kRefreshToken, 'refresh-token');
  final repo = _FakeAuthRepo();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureTokenStorageProvider.overrideWithValue(secure),
      tokenStorageProvider.overrideWithValue(TokenStorage(secure, prefs)),
      authRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, secure: secure, repo: repo);
}

/// 带可控 me() 的启动场景：凭据已写入，构造后恢复停在 await me()。
Future<
    ({
      ProviderContainer container,
      TokenSecureStorage secure,
      SharedPreferences prefs,
      _DelayedMeRepo repo,
    })> _setupDelayedRestore() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final secure = InMemoryTokenSecureStorage();
  await secure.write(AppConstants.kAccessToken, 'access-token');
  await secure.write(AppConstants.kRefreshToken, 'refresh-token');
  final repo = _DelayedMeRepo();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureTokenStorageProvider.overrideWithValue(secure),
      tokenStorageProvider.overrideWithValue(TokenStorage(secure, prefs)),
      authRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, secure: secure, prefs: prefs, repo: repo);
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('有效凭据启动后为已登录（前置校验）', () async {
    final s = await _setup();
    await s.container.read(authControllerProvider.notifier).refreshMe();
    await _settle();
    expect(s.container.read(authControllerProvider).status, AuthStatus.authenticated);
    expect(s.container.read(authControllerProvider).user?.userId, 501);
  });

  test('会话失效事件：控制器转为未登录并清除安全存储中的凭据', () async {
    final s = await _setup();
    await s.container.read(authControllerProvider.notifier).refreshMe();
    await _settle();
    expect(s.container.read(authControllerProvider).status, AuthStatus.authenticated);

    // 网络层在 401/不可恢复业务码时发出该事件
    SessionEvents.instance.sessionExpired();
    await _settle();

    final state = s.container.read(authControllerProvider);
    expect(state.status, AuthStatus.unauthenticated, reason: '会话失效必须踢回未登录');
    expect(state.user, isNull, reason: '不得保留失效会话的用户信息');
    expect(await s.secure.read(AppConstants.kAccessToken), isNull,
        reason: '失效后必须清除访问令牌');
    expect(await s.secure.read(AppConstants.kRefreshToken), isNull,
        reason: '失效后必须清除刷新令牌');
  });

  test('主动退出：调用后端登出、清除凭据并转为未登录', () async {
    final s = await _setup();
    await s.container.read(authControllerProvider.notifier).refreshMe();
    await _settle();

    await s.container.read(authControllerProvider.notifier).logout();
    await _settle();

    expect(s.repo.logoutCalls, 1, reason: '主动退出应通知后端吊销会话');
    expect(s.container.read(authControllerProvider).status, AuthStatus.unauthenticated);
    expect(await s.secure.read(AppConstants.kAccessToken), isNull);
    expect(await s.secure.read(AppConstants.kRefreshToken), isNull);
  });

  test('强制本地登出（改密/换绑成功后）：不发请求但清除凭据并转为未登录', () async {
    final s = await _setup();
    await s.container.read(authControllerProvider.notifier).refreshMe();
    await _settle();

    s.container.read(authControllerProvider.notifier).forceLocalSignOut();
    await _settle();

    expect(s.repo.logoutCalls, 0, reason: '强制本地登出不应再发后端请求（凭据已失效）');
    expect(s.container.read(authControllerProvider).status, AuthStatus.unauthenticated);
    expect(await s.secure.read(AppConstants.kAccessToken), isNull);
    expect(await s.secure.read(AppConstants.kRefreshToken), isNull);
  });

  test('已登录后重复收到会话失效事件保持未登录（幂等）', () async {
    final s = await _setup();
    await s.container.read(authControllerProvider.notifier).refreshMe();
    await _settle();
    expect(s.container.read(authControllerProvider).status, AuthStatus.authenticated);

    SessionEvents.instance.sessionExpired();
    SessionEvents.instance.sessionExpired();
    await _settle();

    expect(s.container.read(authControllerProvider).status, AuthStatus.unauthenticated);
  });

  // ==================================================================
  // B3-APP-01：失效/退出之后，在途的启动恢复不得复活会话。
  //
  // 修复前：_restore() 在 await me() 期间收到失效/退出事件后，仍会在 me()
  // 返回时写回 unknown → authenticated 并重新写回用户缓存，让已登出的会话
  // 「复活」。修复后：_restore 按会话代际校验，代际变化即放弃，不再写状态、
  // 不再写缓存。以下用例在修复前为红，修复后转绿。
  // ==================================================================
  group('B3-APP-01 会话代际：在途恢复不得复活已失效/已退出的会话', () {
    test('会话失效期间在途的启动恢复不得复活会话', () async {
      final s = await _setupDelayedRestore();

      // 构造时已触发 _restore，此刻停在 await me()
      await _settle();
      expect(s.container.read(authControllerProvider).status, AuthStatus.unknown,
          reason: '恢复进行中应为 unknown');

      SessionEvents.instance.sessionExpired();
      await _settle();
      expect(s.container.read(authControllerProvider).status, AuthStatus.unauthenticated,
          reason: '会话失效应立即生效');
      expect(await s.secure.read(AppConstants.kAccessToken), isNull,
          reason: '会话失效应已清除凭据');

      // 在途的 me() 完成：不得写回已登录，也不得写回用户缓存
      s.repo.gate.complete(_user);
      await _settle();

      final state = s.container.read(authControllerProvider);
      expect(state.status, AuthStatus.unauthenticated,
          reason: 'B3-APP-01：失效后始终未登录，在途恢复不得复活会话');
      expect(state.user, isNull, reason: '不得写回失效会话的用户信息');
      expect(await s.secure.read(AppConstants.kAccessToken), isNull,
          reason: '失效后不得重新写入凭据');
      expect(s.prefs.getString(AppConstants.spUserCache), isNull,
          reason: '失效后不得重新写回用户缓存');
    });

    test('主动退出期间在途的启动恢复不得写回登录态', () async {
      final s = await _setupDelayedRestore();

      await _settle();
      expect(s.container.read(authControllerProvider).status, AuthStatus.unknown,
          reason: '恢复进行中应为 unknown');

      await s.container.read(authControllerProvider.notifier).logout();
      await _settle();
      expect(s.repo.logoutCalls, 1);
      expect(s.container.read(authControllerProvider).status, AuthStatus.unauthenticated);

      // 退出发生在恢复在途期间：me() 之后返回的结果必须被丢弃
      s.repo.gate.complete(_user);
      await _settle();

      final state = s.container.read(authControllerProvider);
      expect(state.status, AuthStatus.unauthenticated,
          reason: 'B3-APP-01：主动退出后始终未登录，在途恢复不得写回');
      expect(state.user, isNull);
      expect(await s.secure.read(AppConstants.kAccessToken), isNull);
      expect(s.prefs.getString(AppConstants.spUserCache), isNull,
          reason: '主动退出后不得重新写回用户缓存');
    });

    test('恢复进行中重复 refreshMe 不产生并发写回（单次 me）', () async {
      final s = await _setupDelayedRestore();

      await _settle();
      // 恢复仍在途：重复刷新应被既有 _restoring 闸门挡掉，不得并发调用 me()
      await s.container.read(authControllerProvider.notifier).refreshMe();
      await s.container.read(authControllerProvider.notifier).refreshMe();
      expect(s.repo.meCalls, 1, reason: '恢复在途时重复刷新不得并发调用 me()');

      s.repo.gate.complete(_user);
      await _settle();

      expect(s.container.read(authControllerProvider).status, AuthStatus.authenticated);
      expect(s.repo.meCalls, 1);
    });
  });

  // ==================================================================
  // B3-APP-01 同源竞态：**新会话保存**（_applySession）在途期间的会话失效/退出。
  //
  // _applySession 会先递增代际再 await _storage.saveSession(...)。若保存期间发生
  // 会话失效/退出，修复前会在保存完成后写回 authenticated，且 saveSession 可能把
  // 凭据重新写进安全存储（在 clear() 之后），使已登出的会话「带凭据复活」。
  //
  // 前提约定：同时只有一次登录在途（提交期间按钮禁用，登录与密码登录为互斥路由）。
  // 「两次登录并发」的 last-writer-wins 属越出契约的场景，未在此断言；若将来允许多次
  // 登录并发，需改为串行化凭据存储写入后再补用例。
  // ==================================================================
  group('B3-APP-01 同源：新会话保存期间的竞态', () {
    test('保存期间会话失效：不得写回登录态，也不得残留凭据与缓存', () async {
      final s = await _setupLoginRace();
      final notifier = s.container.read(authControllerProvider.notifier);
      await _settle();
      expect(s.container.read(authControllerProvider).status, AuthStatus.unauthenticated);

      final gate = Completer<void>();
      s.storage.saveGates.add(gate);

      final login = notifier.loginWithSms(phone: '13800001111', code: '123456');
      await _settle();
      // 保存被闸门挂起：此刻尚未落盘
      expect(await s.secure.read(AppConstants.kAccessToken), isNull);

      SessionEvents.instance.sessionExpired();
      await _settle();
      expect(s.container.read(authControllerProvider).status, AuthStatus.unauthenticated);
      expect(await s.secure.read(AppConstants.kAccessToken), isNull);

      // 放行保存：修复前会写回 authenticated 并把凭据重新落盘
      gate.complete();
      await login;
      await _settle();

      final state = s.container.read(authControllerProvider);
      expect(state.status, AuthStatus.unauthenticated,
          reason: '保存期间失效：在途新会话不得写回已登录');
      expect(state.user, isNull, reason: '不得保留已失效的新会话用户信息');
      expect(await s.secure.read(AppConstants.kAccessToken), isNull,
          reason: '失效后不得因在途保存而残留访问令牌');
      expect(await s.secure.read(AppConstants.kRefreshToken), isNull,
          reason: '失效后不得因在途保存而残留刷新令牌');
      expect(s.prefs.getString(AppConstants.spUserCache), isNull,
          reason: '失效后不得残留用户缓存');
    });
  });

  // ==================================================================
  // H-05：账号禁用（ACCOUNT_DISABLED = 40301）的全局提示。
  // 40301 与 Token 过期同属「会话不可恢复」，但用户提示不同：
  // 账号禁用重新登录也无法恢复，必须明确指引联系客服/管理员。
  // ==================================================================
  group('H-05 账号禁用提示', () {
    test('账号禁用事件：转未登录、清凭据并给出禁用文案', () async {
      final s = await _setup();
      await s.container.read(authControllerProvider.notifier).refreshMe();
      await _settle();
      expect(s.container.read(authControllerProvider).status, AuthStatus.authenticated);

      SessionEvents.instance.sessionExpired(SessionExpiryReason.accountDisabled);
      await _settle();

      final state = s.container.read(authControllerProvider);
      expect(state.status, AuthStatus.unauthenticated);
      expect(state.errorMessage, AuthFeedback.accountDisabledHint,
          reason: '账号禁用必须给出与原因匹配的可读中文提示');
      expect(await s.secure.read(AppConstants.kAccessToken), isNull);
      expect(await s.secure.read(AppConstants.kRefreshToken), isNull);
    });

    test('普通 Token 过期不额外弹提示（保持既有 401 交互）', () async {
      final s = await _setup();
      await s.container.read(authControllerProvider.notifier).refreshMe();
      await _settle();

      SessionEvents.instance.sessionExpired();
      await _settle();

      final state = s.container.read(authControllerProvider);
      expect(state.status, AuthStatus.unauthenticated);
      expect(state.errorMessage, isNull,
          reason: 'Token 过期已由「踢回登录页」表达，不新增提示');
    });

    test('禁用文案读取一次后即被消费（不重复弹出）', () async {
      final s = await _setup();
      // 先读取一次以实例化控制器并订阅事件总线，否则广播事件会因无订阅者丢失
      s.container.read(authControllerProvider);
      await _settle();

      SessionEvents.instance.sessionExpired(SessionExpiryReason.accountDisabled);
      await _settle();

      final notifier = s.container.read(authControllerProvider.notifier);
      expect(s.container.read(authControllerProvider).errorMessage,
          AuthFeedback.accountDisabledHint);

      notifier.consumeErrorMessage();
      expect(s.container.read(authControllerProvider).errorMessage, isNull);
      expect(s.container.read(authControllerProvider).status, AuthStatus.unauthenticated,
          reason: '消费提示不得改变登录态');
    });
  });
}

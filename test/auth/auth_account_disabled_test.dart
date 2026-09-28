// H-05 账号禁用（ACCOUNT_DISABLED = 40301）的全局提示。
//
// 40301 与 Token 过期同属「会话不可恢复」，但用户提示必须不同：
//   * Token 过期 -> 踢回登录页，用户重新登录即可；
//   * 账号禁用   -> 重新登录也无法恢复，必须明确提示联系客服/管理员。
// 另：后端对 A3 码沿用英文文案（`account disabled`），页面不得直接展示英文。
//
// 本文件覆盖两段：
//   1. 网络层 -> 事件总线的原因映射（40301/40100/HTTP 401/普通业务码）；
//   2. 根组件 ScriptApp 的全局提示（不依赖用户当时停在哪个页面）。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/app.dart';
import 'package:script_app/core/constants/app_constants.dart';
import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/core/network/session_events.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/providers/auth_providers.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';
import 'package:script_app/features/auth/auth_feedback.dart';
import 'package:script_app/features/auth/data/auth_repository.dart';
import 'package:script_app/models/user.dart';

import '../support/scripted_api.dart';

class _FakeAuthRepo implements AuthRepository {
  @override
  Future<User> me() async =>
      const User(userId: 701, userType: UserType.user, nickname: '被禁用用户');

  @override
  Future<void> logout() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 通过真实 ApiClient + 脚本化传输层发起请求，返回抛出的异常与收到的失效原因。
Future<({Object? error, List<SessionExpiryReason> reasons})> _call(
  Envelope env,
) async {
  final api = ScriptedApi();
  api.reply('/messages', env);
  final reasons = <SessionExpiryReason>[];
  final sub = SessionEvents.instance.onSessionExpired.listen(reasons.add);
  Object? error;
  try {
    await ApiClient(api.buildDio()).get<Map<String, dynamic>>('/messages');
  } catch (e) {
    error = e;
  }
  await Future<void>.delayed(Duration.zero);
  await sub.cancel();
  return (error: error, reasons: reasons);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('H-05-I 会话失效原因映射（ApiClient 层）', () {
    test('业务码 40301 映射为「账号禁用」并抛出同码异常', () async {
      final r = await _call(Envelope.fail(40301, 'account disabled'));
      expect(r.reasons, [SessionExpiryReason.accountDisabled],
          reason: '40301 必须携带账号禁用原因');
      expect((r.error! as ApiException).code, 40301,
          reason: '页面据此把英文码文案收敛为中文');
    });

    test('业务码 40100 映射为「Token 过期」', () async {
      final r = await _call(Envelope.fail(40100, 'unauthorized'));
      expect(r.reasons, [SessionExpiryReason.tokenExpired]);
    });

    test('HTTP 401 映射为「Token 过期」', () async {
      final r = await _call(Envelope.http(401, '登录状态已过期'));
      expect(r.reasons, [SessionExpiryReason.tokenExpired]);
    });

    test('普通业务码不产生会话失效信号', () async {
      final r = await _call(Envelope.fail(40400, '资源不存在'));
      expect(r.reasons, isEmpty, reason: '40400 属普通业务错误，不得触发失效');
    });
  });

  group('H-05-J 账号禁用的全局提示（ScriptApp）', () {
    testWidgets('停在任意页面都会弹出禁用提示，且只消费一次', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secure = InMemoryTokenSecureStorage();
      await secure.write(AppConstants.kAccessToken, 'at');
      await secure.write(AppConstants.kRefreshToken, 'rt');

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          secureTokenStorageProvider.overrideWithValue(secure),
          tokenStorageProvider.overrideWithValue(TokenStorage(secure, prefs)),
          authRepositoryProvider.overrideWithValue(_FakeAuthRepo()),
        ],
      );
      addTearDown(container.dispose);
      // 先实例化控制器，确保订阅了事件总线
      container.read(authControllerProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ScriptApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // 有效凭据 -> 已登录 -> 停在公开首页（游客态页面也必须有全局提示）
      expect(container.read(authControllerProvider).status, AuthStatus.authenticated);

      SessionEvents.instance.sessionExpired(SessionExpiryReason.accountDisabled);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 同一 Messenger 可能在保活的 Scaffold 中渲染多份，故不断言唯一
      expect(find.text(AuthFeedback.accountDisabledHint), findsWidgets,
          reason: '账号禁用必须在当前页面弹出全局提示');
      expect(container.read(authControllerProvider).status, AuthStatus.unauthenticated);
      expect(container.read(authControllerProvider).errorMessage, isNull,
          reason: '提示必须被消费，避免 rebuild 时重复弹出');
    });
  });
}

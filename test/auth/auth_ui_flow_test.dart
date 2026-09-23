import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/app.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/providers/auth_providers.dart';
import 'package:script_app/core/router/app_router.dart';
import 'package:script_app/core/router/route_intent.dart';
import 'package:script_app/core/router/route_paths.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';
import 'package:script_app/core/theme/app_colors.dart';
import 'package:script_app/features/auth/pages/login_page.dart';
import 'package:script_app/features/auth/pages/password_login_page.dart';
import 'package:script_app/features/auth/widgets/agreement_checkbox.dart';

/// A3 认证页 UI 契约：协议门禁、请求时机与登录回跳。
///
/// 断言重点（对应验收要求）：
///   1. 未勾选协议 -> 不提交任何登录请求，只提示；
///   2. 手机号非法 -> 不发请求，就地展示错误态；
///   3. 登录成功 -> 消费一次守卫保存的回跳意图（回跳行为不回归）。

/// 不触网、不写安全存储的假实现。
class _FakeSecureStorage implements TokenSecureStorage {
  final Map<String, String> _map = {};

  @override
  Future<void> write(String key, String value) async => _map[key] = value;

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> delete(String key) async => _map.remove(key);

  @override
  Future<void> deleteAll() async => _map.clear();
}

/// 记录调用次数的 AuthController：登录直接置为已认证，不发网络请求。
class _RecordingAuthController extends AuthController {
  _RecordingAuthController(super.storage, super.repository);

  int smsLoginCalls = 0;
  int passwordLoginCalls = 0;

  @override
  Future<void> loginWithSms({
    required String phone,
    required String code,
    String? deviceId,
  }) async {
    smsLoginCalls += 1;
    state = const AuthState(AuthStatus.authenticated);
  }

  @override
  Future<void> loginWithPassword(String phone, String password, {String? deviceId}) async {
    passwordLoginCalls += 1;
    state = const AuthState(AuthStatus.authenticated);
  }
}

class _Harness {
  _Harness(this.container, this.auth);

  final ProviderContainer container;
  final _RecordingAuthController auth;
}

Future<_Harness> _pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final storage = TokenStorage(_FakeSecureStorage(), prefs);

  late _RecordingAuthController auth;
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureTokenStorageProvider.overrideWithValue(_FakeSecureStorage()),
      tokenStorageProvider.overrideWithValue(storage),
      authControllerProvider.overrideWith((ref) {
        auth = _RecordingAuthController(
          ref.watch(tokenStorageProvider),
          ref.watch(authRepositoryProvider),
        );
        return auth;
      }),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const ScriptApp(),
    ),
  );
  // 会话恢复（无凭据 -> 未登录）完成后，再开始交互
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return _Harness(container, auth);
}

/// 用受保护入口触发守卫，使登录页拿到一个待消费的回跳意图。
void _seedIntentViaGuard(_Harness harness) {
  harness.container.read(routerProvider).go('${RoutePath.feedbackDetail}?id=42');
}

/// 点击协议圆圈：不落在《用户协议》《隐私政策》文字上，避免误触发跳转。
Future<void> _tapAgreement(WidgetTester tester) async {
  final topLeft = tester.getTopLeft(find.byType(AgreementCheckbox));
  await tester.tapAt(topLeft + const Offset(8, 10));
  await tester.pump();
}

/// 匹配「以错误态样式渲染的文案」，与同名的 placeholder 区分开。
Finder _errorText(String text) => find.byWidgetPredicate(
      (widget) => widget is Text && widget.data == text && widget.style?.color == AppColors.error,
    );

void main() {
  testWidgets('登录首页为「手机号 + 验证码」主流程，未勾选协议不提交请求', (tester) async {
    final harness = await _pumpApp(tester);
    harness.container.read(routerProvider).go(RoutePath.login);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('登录后体验完整功能'), findsOneWidget);
    expect(find.text('未拥有账号？'), findsOneWidget);
    expect(find.text('点击注册'), findsOneWidget);
    expect(find.text('账号密码登录'), findsOneWidget);
    expect(find.text('其他方式登录'), findsOneWidget);

    // 填好手机号与验证码但**不勾选协议**
    await tester.enterText(find.byType(TextField).at(0), '13800001111');
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.tap(find.descendant(of: find.byType(LoginPage), matching: find.text('登录')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(harness.auth.smsLoginCalls, 0, reason: '未勾选协议不得提交登录请求');
    // 同一 ScaffoldMessenger 会在保活的各 Scaffold 中各渲染一份 toast，故不断言唯一
    expect(find.text('请先阅读并同意用户协议和隐私政策'), findsWidgets);
  });

  testWidgets('手机号非法时不发请求，就地展示错误态', (tester) async {
    final harness = await _pumpApp(tester);
    harness.container.read(routerProvider).go(RoutePath.login);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(TextField).at(0), '2380000');
    await _tapAgreement(tester);
    await tester.tap(find.descendant(of: find.byType(LoginPage), matching: find.text('登录')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(harness.auth.smsLoginCalls, 0);
    expect(_errorText('请输入正确的 11 位手机号'), findsOneWidget);
    expect(_errorText('请输入验证码'), findsOneWidget);
  });

  testWidgets('登录成功后消费一次回跳意图（守卫保存的目标被清空）', (tester) async {
    final harness = await _pumpApp(tester);
    _seedIntentViaGuard(harness);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 守卫把未登录用户拦到登录页，并保存了结构化意图
    expect(find.byType(LoginPage), findsOneWidget);
    expect(
      harness.container.read(routeIntentStoreProvider).pending?.target,
      '${RoutePath.feedbackDetail}?id=42',
    );

    await tester.enterText(find.byType(TextField).at(0), '13800001111');
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await _tapAgreement(tester);
    await tester.tap(find.descendant(of: find.byType(LoginPage), matching: find.text('登录')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(harness.auth.smsLoginCalls, 1);
    expect(
      harness.container.read(routeIntentStoreProvider).pending,
      isNull,
      reason: '登录成功必须消费回跳意图，避免下次登录重复回跳',
    );
    expect(harness.container.read(routeIntentStoreProvider).consume(), isNull);
  });

  testWidgets('账号密码登录页复用同一套组件，成功登录同样消费回跳意图', (tester) async {
    final harness = await _pumpApp(tester);
    _seedIntentViaGuard(harness);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    harness.container.read(routerProvider).go(RoutePath.passwordLogin);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PasswordLoginPage), findsOneWidget);
    expect(find.text('使用手机号与登录密码进入平台'), findsOneWidget);
    expect(find.text('忘记密码？'), findsOneWidget);
    expect(find.text('验证码登录'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '13800001111');
    await tester.enterText(find.byType(TextField).at(1), 'Passw0rd1');
    await tester.tap(
      find.descendant(of: find.byType(PasswordLoginPage), matching: find.text('登录')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(harness.auth.passwordLoginCalls, 1);
    expect(harness.container.read(routeIntentStoreProvider).pending, isNull);
  });
}

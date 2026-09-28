// H-05 注册页 / 账号密码登录页的完整表单矩阵（App 端）。
//
// 评审标准 §7「每个登录/注册表单的校验、Loading、防重复提交、服务端错误」：
//   * 本地校验失败 -> 就地展示错误，且**不得**发起请求；
//   * 合法提交 -> 调用对应的控制器方法；
//   * 提交期间 -> 主按钮进入 Loading 且禁用，重复点击不重复提交；
//   * 服务端错误 -> 展示可读文案（含账号禁用的中文收敛）。
//
// 走真实页面代码路径，仅替换认证控制器（不触网）与认证仓库（验证码发送）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/providers/auth_providers.dart';
import 'package:script_app/core/router/route_paths.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';
import 'package:script_app/core/theme/app_colors.dart';
import 'package:script_app/features/auth/auth_feedback.dart';
import 'package:script_app/features/auth/data/auth_repository.dart';
import 'package:script_app/features/auth/pages/password_login_page.dart';
import 'package:script_app/features/auth/pages/register_page.dart';
import 'package:script_app/features/auth/widgets/agreement_checkbox.dart';
import 'package:script_app/models/user.dart';

class _FakeSecure implements TokenSecureStorage {
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

/// 只用于验证码发送的假仓库（注册/登录走被覆写的控制器）。
class _FakeAuthRepo implements AuthRepository {
  int smsSendCalls = 0;
  Object? smsSendError;

  @override
  Future<void> sendSms({
    required String phone,
    required String scene,
    String? deviceId,
  }) async {
    smsSendCalls++;
    final error = smsSendError;
    if (error != null) throw error;
  }

  @override
  Future<User> me() async =>
      const User(userId: 1, userType: UserType.user);

  @override
  Future<void> logout() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 不触网的认证控制器：记录调用、可挂起（验证 Loading/防重复）、可注入错误。
class _ScriptedAuthController extends AuthController {
  _ScriptedAuthController(super.storage, super.repository);

  int registerCalls = 0;
  int passwordLoginCalls = 0;
  Completer<void>? gate;
  Object? registerError;
  Object? passwordLoginError;

  Future<void> _maybeFinish() async {
    final g = gate;
    if (g != null) await g.future;
    state = const AuthState(AuthStatus.authenticated);
  }

  @override
  Future<void> register({
    required String phone,
    required String code,
    required String password,
    String? deviceId,
  }) async {
    registerCalls++;
    final error = registerError;
    if (error != null) throw error;
    await _maybeFinish();
  }

  @override
  Future<void> loginWithPassword(String phone, String password, {String? deviceId}) async {
    passwordLoginCalls++;
    final error = passwordLoginError;
    if (error != null) throw error;
    await _maybeFinish();
  }

  @override
  Future<void> loginWithSms({
    required String phone,
    required String code,
    String? deviceId,
  }) async {
    await _maybeFinish();
  }
}

class _Harness {
  _Harness(this.controller, this.repo);

  final _ScriptedAuthController controller;
  final _FakeAuthRepo repo;
}

Future<_Harness> _pump(WidgetTester tester, Widget Function() page) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final secure = _FakeSecure();
  final storage = TokenStorage(secure, prefs);
  final repo = _FakeAuthRepo();
  late _ScriptedAuthController controller;

  final router = GoRouter(
    initialLocation: '/auth',
    routes: [
      GoRoute(path: '/auth', builder: (_, __) => page()),
      // resolvePostLoginTarget 登录成功后回安全默认首页，必须可导航
      GoRoute(
        path: RoutePath.home,
        builder: (_, __) => const Scaffold(body: Text('首页')),
      ),
    ],
  );

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureTokenStorageProvider.overrideWithValue(secure),
      tokenStorageProvider.overrideWithValue(storage),
      authRepositoryProvider.overrideWithValue(repo),
      authControllerProvider.overrideWith((ref) {
        controller = _ScriptedAuthController(
          ref.watch(tokenStorageProvider),
          ref.watch(authRepositoryProvider),
        );
        return controller;
      }),
    ],
  );
  addTearDown(container.dispose);
  // 覆写是惰性的：先读取一次以实例化控制器，避免 late 变量未初始化
  container.read(authControllerProvider);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  // 会话恢复（无凭据 -> 未登录）完成后开始交互
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return _Harness(controller, repo);
}

/// 点击协议圆圈：避开《用户协议》《隐私政策》文字，防止误触发跳转。
Future<void> _tapAgreement(WidgetTester tester) async {
  final topLeft = tester.getTopLeft(find.byType(AgreementCheckbox));
  await tester.tapAt(topLeft + const Offset(8, 10));
  await tester.pump();
}

Finder _primaryButtonOf(Type page) => find.descendant(
      of: find.byType(page),
      matching: find.byType(ElevatedButton),
    );

bool _primaryDisabled(WidgetTester tester, Type page) =>
    tester.widget<ElevatedButton>(_primaryButtonOf(page)).onPressed == null;

Finder _loadingSpinner(Type page) => find.descendant(
      of: find.byType(page),
      matching: find.byType(CircularProgressIndicator),
    );

/// 匹配「以错误态样式渲染的文案」，与同名的输入占位符区分开
/// （如密码框占位符与错误文案都叫「请输入密码」）。
Finder _errorText(String text) => find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          widget.data == text &&
          widget.style?.color == AppColors.error,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ==================================================================
  group('H-05-F 注册页表单矩阵', () {
    Future<_Harness> pumpRegister(WidgetTester tester) =>
        _pump(tester, () => const RegisterPage());

    Future<void> fillValid(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField).at(0), '13800001111');
      await tester.enterText(find.byType(TextField).at(1), '123456');
      await tester.enterText(find.byType(TextField).at(2), 'Passw0rd1');
      await tester.enterText(find.byType(TextField).at(3), 'Passw0rd1');
    }

    testWidgets('未勾选协议：不提交注册请求，只提示并抖动', (tester) async {
      final h = await pumpRegister(tester);
      await fillValid(tester);

      await tester.tap(find.text('注册并登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(h.controller.registerCalls, 0, reason: '未勾选协议不得提交注册请求');
      expect(find.text('请先阅读并同意用户协议和隐私政策'), findsWidgets);
    });

    testWidgets('逐项本地校验失败：不发请求，且四类错误各就各位', (tester) async {
      final h = await pumpRegister(tester);
      await tester.enterText(find.byType(TextField).at(0), '2380000'); // 手机号非法
      await tester.enterText(find.byType(TextField).at(1), '12'); // 验证码过短
      await tester.enterText(find.byType(TextField).at(2), 'short'); // 密码过弱
      await tester.enterText(find.byType(TextField).at(3), 'other'); // 两次不一致
      await _tapAgreement(tester);

      await tester.tap(find.text('注册并登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(h.controller.registerCalls, 0, reason: '本地校验失败不得发起注册请求');
      expect(find.text('请输入正确的 11 位手机号'), findsOneWidget);
      expect(find.text('请输入 4-8 位数字验证码'), findsOneWidget);
      expect(find.text('密码长度需为 8-64 位'), findsOneWidget);
      expect(find.text('两次输入的密码不一致'), findsOneWidget);
    });

    testWidgets('合法提交：进入 Loading 且按钮禁用，完成后离开', (tester) async {
      final h = await pumpRegister(tester);
      final gate = Completer<void>();
      h.controller.gate = gate;
      await fillValid(tester);
      await _tapAgreement(tester);

      await tester.tap(find.text('注册并登录'));
      await tester.pump();

      expect(h.controller.registerCalls, 1);
      expect(_loadingSpinner(RegisterPage), findsOneWidget, reason: '提交中按钮应展示 Loading');
      expect(_primaryDisabled(tester, RegisterPage), isTrue, reason: '提交中主按钮必须禁用');

      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_loadingSpinner(RegisterPage), findsNothing);
    });

    testWidgets('提交中重复点击不重复提交', (tester) async {
      final h = await pumpRegister(tester);
      h.controller.gate = Completer<void>();
      await fillValid(tester);
      await _tapAgreement(tester);

      await tester.tap(find.text('注册并登录'));
      await tester.pump();
      // 第二次点击：按钮已禁用（文案已被 Loading 替换），按控件定位，不应再触发提交
      await tester.tap(_primaryButtonOf(RegisterPage), warnIfMissed: false);
      await tester.pump();

      expect(h.controller.registerCalls, 1, reason: '提交中重复点击不得重复提交');
    });

    testWidgets('服务端错误：展示服务端可读文案', (tester) async {
      final h = await pumpRegister(tester);
      h.controller.registerError = ApiException('该手机号已注册', code: 40902);
      await fillValid(tester);
      await _tapAgreement(tester);

      await tester.tap(find.text('注册并登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('该手机号已注册'), findsOneWidget);
      expect(_primaryDisabled(tester, RegisterPage), isFalse, reason: '失败后按钮应恢复可点');
    });

    testWidgets('获取验证码：手机号非法不发请求，合法则调用发送接口', (tester) async {
      final h = await pumpRegister(tester);

      // 手机号非法：先本地拦截
      await tester.enterText(find.byType(TextField).at(0), '238');
      await tester.tap(find.text('获取验证码'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(h.repo.smsSendCalls, 0, reason: '手机号非法不得请求验证码');
      expect(find.text('请输入正确的 11 位手机号'), findsOneWidget);

      // 手机号合法：调用发送接口并进入倒计时
      await tester.enterText(find.byType(TextField).at(0), '13800001111');
      await tester.tap(find.text('获取验证码'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(h.repo.smsSendCalls, 1);
      expect(find.text('60s'), findsOneWidget, reason: '发送成功后进入倒计时');

      // 结束前释放倒计时，避免遗留定时器
      await tester.pumpWidget(const SizedBox());
    });
  });

  // ==================================================================
  group('H-05-G 账号密码登录页表单矩阵', () {
    Future<_Harness> pumpPasswordLogin(WidgetTester tester) =>
        _pump(tester, () => const PasswordLoginPage());

    testWidgets('手机号非法 / 密码为空：不发请求并就地报错', (tester) async {
      final h = await pumpPasswordLogin(tester);
      await tester.enterText(find.byType(TextField).at(0), '2380000');

      await tester.tap(find.text('登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(h.controller.passwordLoginCalls, 0, reason: '本地校验失败不得发起登录请求');
      expect(_errorText('请输入正确的 11 位手机号'), findsOneWidget);
      expect(_errorText('请输入密码'), findsOneWidget);
    });

    testWidgets('合法提交：调用密码登录并消费回跳（无意图时回安全首页）', (tester) async {
      final h = await pumpPasswordLogin(tester);
      await tester.enterText(find.byType(TextField).at(0), '13800001111');
      await tester.enterText(find.byType(TextField).at(1), 'Passw0rd1');

      await tester.tap(find.text('登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(h.controller.passwordLoginCalls, 1);
      expect(find.text('首页'), findsOneWidget, reason: '无回跳意图时应回安全默认首页');
    });

    testWidgets('提交中进入 Loading 且重复点击不重复提交', (tester) async {
      final h = await pumpPasswordLogin(tester);
      h.controller.gate = Completer<void>();
      await tester.enterText(find.byType(TextField).at(0), '13800001111');
      await tester.enterText(find.byType(TextField).at(1), 'Passw0rd1');

      await tester.tap(find.text('登录'));
      await tester.pump();

      expect(h.controller.passwordLoginCalls, 1);
      expect(_loadingSpinner(PasswordLoginPage), findsOneWidget);
      expect(_primaryDisabled(tester, PasswordLoginPage), isTrue);

      // 提交中按钮文案已替换为 Loading，按控件定位后重复点击
      await tester.tap(_primaryButtonOf(PasswordLoginPage), warnIfMissed: false);
      await tester.pump();
      expect(h.controller.passwordLoginCalls, 1, reason: '提交中重复点击不得重复提交');
    });

    testWidgets('服务端错误：展示服务端可读文案', (tester) async {
      final h = await pumpPasswordLogin(tester);
      h.controller.passwordLoginError = ApiException('手机号或密码错误', code: 40000);
      await tester.enterText(find.byType(TextField).at(0), '13800001111');
      await tester.enterText(find.byType(TextField).at(1), 'Passw0rd1');

      await tester.tap(find.text('登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('手机号或密码错误'), findsOneWidget);
    });

    testWidgets('账号禁用（40301）：展示中文禁用提示，不出现英文 account disabled', (tester) async {
      final h = await pumpPasswordLogin(tester);
      h.controller.passwordLoginError = ApiException('account disabled', code: 40301);
      await tester.enterText(find.byType(TextField).at(0), '13800001111');
      await tester.enterText(find.byType(TextField).at(1), 'Passw0rd1');

      await tester.tap(find.text('登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(AuthFeedback.accountDisabledHint), findsOneWidget,
          reason: '40301 必须收敛为中文禁用提示');
      expect(find.text('account disabled'), findsNothing,
          reason: '不得把服务端英文码文案直接展示给用户');
    });
  });
}

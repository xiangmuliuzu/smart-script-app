// G6-D 回归：登录成功后按返回键必须回到触发登录前的页面，不能回到登录页，
// 也不能把登录页下方的原浏览栈重建掉。
//
// 复现路径（用户反馈）：游客在任务详情页点「接单」→ 确认登录 → 登录成功回到
// 详情页 → 按系统返回键却回到登录页（账号密码登录子页会把 /login 留在栈里）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/app.dart';
import 'package:script_app/core/constants/demand_task_type.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/router/app_router.dart';
import 'package:script_app/core/router/route_paths.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';
import 'package:script_app/features/auth/data/auth_repository.dart';
import 'package:script_app/features/auth/pages/login_page.dart';
import 'package:script_app/features/auth/widgets/agreement_checkbox.dart';
import 'package:script_app/features/auth/widgets/auth_buttons.dart';
import 'package:script_app/features/trade/data/demand_providers.dart';
import 'package:script_app/features/trade/data/trade_models.dart';
import 'package:script_app/models/user.dart';

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

const _user = User(userId: 1, userType: UserType.user);

class _FakeAuthRepo implements AuthRepository {
  @override
  Future<Map<String, dynamic>> captcha() async => {'captchaEnabled': false};

  @override
  Future<AuthSession> passwordLogin({
    required String phone,
    required String password,
    required String deviceId,
    String? deviceName,
    String? code,
    String? uuid,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return AuthSession(token: 'test-token', user: _user);
  }

  @override
  Future<AuthSession> smsLogin({
    required String phone,
    required String code,
    required String deviceId,
    String? deviceName,
    bool acceptAgreements = true,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return AuthSession(token: 'test-token', user: _user);
  }

  @override
  Future<User> me() async => _user;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

const _task = DemandTask(
  demandId: 60,
  title: '游客可见任务',
  taskType: DemandTaskType.script,
  budget: 20000,
  status: 'open',
);

Future<void> _pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final storage = TokenStorage(_FakeSecureStorage(), prefs);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        secureTokenStorageProvider.overrideWithValue(_FakeSecureStorage()),
        tokenStorageProvider.overrideWithValue(storage),
        authRepositoryProvider.overrideWithValue(_FakeAuthRepo()),
        demandDetailProvider.overrideWith((ref, id) => Future.value(_task)),
      ],
      child: const ScriptApp(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// 登录回跳会逐帧回退子认证页再替换登录页，需要多推几帧让转场结束。
Future<void> _settleAfterLogin(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await _settle(tester);
  }
}

/// 游客从任务广场进入任务详情（详情页压在任务广场之上），点「接单」触发登录。
Future<void> _enterLoginFromDemandDetail(WidgetTester tester) async {
  final router = _containerOf(tester).read(routerProvider);
  router.go(RoutePath.demandTab);
  await _settle(tester);
  router.push(RoutePath.demandDetailUrl(60));
  await _settle(tester);
  expect(find.text('任务详情'), findsOneWidget);

  // 押金/托管随资金托管下线后，游客在详情页触发登录的入口是「接单」
  await tester.tap(find.textContaining('我要接单').first);
  await _settle(tester);
  expect(find.text('需要登录'), findsOneWidget);
  await tester.tap(find.descendant(
      of: find.byType(AlertDialog), matching: find.text('去登录')));
  await _settle(tester);
  expect(find.byType(LoginPage), findsOneWidget);
}

Future<void> _pressSystemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _settle(tester);
}

/// 登录回跳后：详情页在栈顶；返回键回到任务广场，而不是登录页。
Future<void> _expectBackLandsOnTaskSquare(WidgetTester tester) async {
  expect(find.byType(LoginPage), findsNothing);
  expect(find.text('任务详情'), findsOneWidget);

  await _pressSystemBack(tester);
  expect(find.byType(LoginPage), findsNothing,
      reason: '返回键不得回到登录页（G6-D 回归）');
  // 任务广场的分段头部（书城首页只有一个「任务广场」入口卡片，没有这两个分段）。
  expect(find.text('我的任务'), findsOneWidget,
      reason: '返回键应回到触发登录前的任务广场，导航栈不能被重建');
  expect(find.text('广场'), findsOneWidget);
}

void main() {
  testWidgets('账号密码登录后返回键回到任务广场', (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await _pumpApp(tester);
    await _enterLoginFromDemandDetail(tester);

    await tester.tap(find.text('账号密码登录'));
    await _settle(tester);
    final fields = find.byType(TextField).hitTestable();
    await tester.enterText(fields.at(0), '13800138000');
    await tester.enterText(fields.at(1), 'secret123');
    await tester.tap(find.widgetWithText(PrimaryButton, '登录').hitTestable());
    await _settleAfterLogin(tester);

    await _expectBackLandsOnTaskSquare(tester);
  });

  testWidgets('验证码登录后返回键回到任务广场', (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await _pumpApp(tester);
    await _enterLoginFromDemandDetail(tester);

    final fields = find.byType(TextField).hitTestable();
    await tester.enterText(fields.at(0), '13800138000');
    await tester.enterText(fields.at(1), '123456');
    // 点左侧圆形勾选框（行中间的文字带协议链接，会打开协议页）。
    await tester.tapAt(
        tester.getTopLeft(find.byType(AgreementCheckbox)) + const Offset(10, 10));
    await tester.pump();
    await tester.tap(find.widgetWithText(PrimaryButton, '登录').hitTestable());
    await _settleAfterLogin(tester);

    await _expectBackLandsOnTaskSquare(tester);
  });
}

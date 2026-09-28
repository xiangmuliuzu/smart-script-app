// H-05 设备级集成测试（App 端）：真实界面 + 真实后端 + 真实安全存储。
//
// 与 test/live/ 的区别：本文件在**真机/模拟器**上运行完整 Flutter 应用，
// 走真实渲染、真实路由、真实平台安全存储与真实后端（Android 模拟器经 10.0.2.2 访问宿主机）。
//
// 运行（需先启动后端与 Android 模拟器）：
//   flutter test integration_test -d emulator-5554 --dart-define=APP_SMS_MOCK_CODE=<mock>
//
// 说明：
//   * multidex 由 android/gradle.properties 的 `multidex-enabled=true` 启用（minSdk 19 不变）；
//   * 凭据只经 --dart-define 注入，缺失即失败（不静默跳过）；
//   * 设备上存在真实异步 IO（安全存储、网络），因此一律使用 [waitFor] 轮询等待，
//     不用固定毫秒数断言，也不用 pumpAndSettle（页面存在持续动画，可能永不 settle）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/app.dart';
import 'package:script_app/core/constants/app_constants.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/features/auth/pages/login_page.dart';
import 'package:script_app/features/auth/widgets/agreement_checkbox.dart';

/// 测试环境 Mock 短信验证码（后端 APP_SMS_MOCK_CODE），只从 --dart-define 注入。
const String kMockCode = String.fromEnvironment('APP_SMS_MOCK_CODE');

/// 轮询等待某个 finder 出现（真实设备上异步 IO 耗时不确定）。
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 25),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('等待超时（${timeout.inSeconds}s）：${reason ?? finder.describeMatch(Plurality.many)}');
}

Future<void> _pumpApp(WidgetTester tester) async {
  // 集成测试使用真实插件。必须先清空**偏好设置**与**平台安全存储**：
  // 上一次运行（登录用例）会把 Token/Refresh Token 写进设备安全存储，
  // 若不清空，下一次运行的「游客冷启动」用例会以已登录态开始而失效。
  // 清理放在每个用例开头，保证连续多次运行结果一致（可重复）。
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  await FlutterSecureTokenStorage().deleteAll();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        secureTokenStorageProvider.overrideWithValue(FlutterSecureTokenStorage()),
      ],
      child: const ScriptApp(),
    ),
  );
  await tester.pump();
}

String _freshPhone() {
  final n = DateTime.now().microsecondsSinceEpoch % 100000000;
  return '139${n.toString().padLeft(8, '0')}';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    if (kMockCode.isEmpty) {
      fail('缺少 --dart-define=APP_SMS_MOCK_CODE：设备级联调不接受内置凭据，也不允许跳过。');
    }
  });

  testWidgets('游客可浏览书城；受保护入口被守卫拦截到登录页', (tester) async {
    await _pumpApp(tester);

    // 前置自检：确实以游客态开始（设备上无上次运行残留的凭据）。
    // 这条断言让「连续运行两次仍通过」成为可验证的事实，而不是隐含假设。
    expect(await FlutterSecureTokenStorage().read(AppConstants.kAccessToken), isNull,
        reason: '用例前置：设备安全存储不应残留 Token（否则游客冷启动用例无效）');

    // 冷启动：启动页 -> 会话恢复完成 -> 公开首页（书城）
    await waitFor(tester, find.text('书城'), reason: '游客冷启动应落到公开首页「书城」');
    expect(find.byType(LoginPage), findsNothing, reason: '游客不应被强制登录');

    // 进入受保护入口（我的）应被守卫拦截到登录页
    await tester.tap(find.text('我的').first);
    await waitFor(tester, find.byType(LoginPage), reason: '游客进入「我的」必须被守卫拦截到登录页');
  });

  testWidgets('验证码登录主流程：真实后端建号并进入用户中心', (tester) async {
    await _pumpApp(tester);
    await waitFor(tester, find.text('书城'), reason: '冷启动落到书城');

    await tester.tap(find.text('我的').first);
    await waitFor(tester, find.byType(LoginPage), reason: '进入登录页');

    // 1) 手机号：登录页只有「手机号 + 验证码」两个输入框
    final fields = find.byType(TextField);
    expect(fields.evaluate().length, greaterThanOrEqualTo(2),
        reason: '登录页应有手机号与验证码输入框；实际可见文本：${_visibleTexts(tester)}');
    await tester.enterText(fields.at(0), _freshPhone());
    await tester.pump(const Duration(milliseconds: 300));

    // 2) 获取验证码（真实调用后端 /auth/sms/send，scene=LOGIN）
    await tester.tap(find.text('获取验证码'));
    await tester.pump(const Duration(seconds: 3));

    // 3) 验证码
    await tester.enterText(fields.at(1), kMockCode);
    await tester.pump(const Duration(milliseconds: 300));

    // 4) 勾选协议：用坐标点击左侧方块，避免命中协议文本链接
    final agreementFinder = find.byType(AgreementCheckbox);
    if (agreementFinder.evaluate().isNotEmpty) {
      final topLeft = tester.getTopLeft(agreementFinder);
      await tester.tapAt(topLeft + const Offset(8, 10));
      await tester.pump(const Duration(milliseconds: 300));
    }

    // 5) 提交：限定在登录页内，避免匹配到页面外的「登录」文本
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 300));
    final submit = find.descendant(of: find.byType(LoginPage), matching: find.text('登录'));
    expect(submit.evaluate(), isNotEmpty,
        reason: '登录页内应有「登录」主按钮；实际可见文本：${_visibleTexts(tester)}');
    await tester.tap(submit.first, warnIfMissed: false);

    // 登录成功后登录页应消失（真实后端下发会话 + 守卫消费回跳意图）
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    var leftLogin = false;
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(LoginPage).evaluate().isEmpty) {
        leftLogin = true;
        break;
      }
    }
    expect(leftLogin, isTrue,
        reason: '登录成功后必须离开登录页（真实后端应已下发会话）；'
            '当前可见文本：${_visibleTexts(tester)}');

    // 进一步确认「已登录」而非仅离开登录页：应落到用户中心并展示其入口
    await waitFor(tester, find.text('个人资料'),
        reason: '登录后应回到用户中心并展示入口；当前可见文本：${_visibleTexts(tester)}');
  });
}

/// 失败诊断：列出当前可见文本，避免在设备上反复试错。
String _visibleTexts(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .where((s) => s.isNotEmpty)
      .take(25)
      .join(' | ');
  return texts.isEmpty ? '(无可见文本)' : texts;
}

// H-05 / A5-07 Android 系统返回真机验证（App 端，第 21 批）。
//
// 验证两条真实系统返回路径在 App 层的同一契约（子页弹出、上一页恢复）：
//   腿 A：BACK 键——宿主机在标记 READY-FOR-BACK-KEY 后发送 `input keyevent 4`；
//   腿 B：返回手势——宿主机切手势导航后在 READY-FOR-BACK-GESTURE 标记后
//         发送 `input swipe 4 <y> 400 <y>`（左缘横滑，Android 系统判定为 BACK）。
// 两条腿最终都以 Android framework 的 BACK 事件进入 Flutter（popRoute 回调），
// 因此本用例断言的就是真机系统返回的 App 层行为（不是测试绑定层模拟）。
//
// 运行：flutter test integration_test/h21_back_nav_test.dart -d emulator-5554
//       --dart-define=APP_SMS_MOCK_CODE=<mock>
// （不需要后端：游客 → 守卫拦截 → 登录页 → 密码登录子页，均为本地导航）
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/app.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/features/auth/pages/login_page.dart';
import 'package:script_app/features/auth/pages/password_login_page.dart';

Future<void> _pumpApp(WidgetTester tester) async {
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

/// 等待 [finder] 消失（宿主机在 READY 标记后发送系统返回事件）。
Future<void> waitForGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 40),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isEmpty) return;
  }
  fail('等待消失超时（${timeout.inSeconds}s）：${reason ?? finder.describeMatch(Plurality.many)}');
}

Future<void> _enterPasswordSubPage(WidgetTester tester) async {
  await _pumpApp(tester);
  await waitFor(tester, find.text('书城'), reason: '游客冷启动落到书城');
  await tester.tap(find.text('我的').first);
  await waitFor(tester, find.byType(LoginPage), reason: '守卫拦截到登录页');
  await tester.tap(find.text('账号密码登录'));
  await waitFor(tester, find.byType(PasswordLoginPage), reason: '应进入密码登录子页');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('腿 A：BACK 键从密码登录子页返回登录页', (tester) async {
    await _enterPasswordSubPage(tester);
    // 标记经 logcat 输出，宿主机看到后发送真实 BACK 键
    debugPrint('H21-BACKNAV: READY-FOR-BACK-KEY', wrapWidth: 200);
    await waitForGone(tester, find.byType(PasswordLoginPage),
        reason: '宿主机已发送 BACK 键（keyevent 4），子页应被弹出');
    await tester.pump(const Duration(milliseconds: 400));
    await waitFor(tester, find.byType(LoginPage), reason: '返回后应回到登录页');
    debugPrint('H21-BACKNAV: LEG-A-OK', wrapWidth: 200);
  });

  testWidgets('腿 B：左缘滑动手势（系统 BACK）从密码登录子页返回登录页', (tester) async {
    await _enterPasswordSubPage(tester);
    debugPrint('H21-BACKNAV: READY-FOR-BACK-GESTURE', wrapWidth: 200);
    await waitForGone(tester, find.byType(PasswordLoginPage),
        reason: '宿主机已执行左缘滑动手势（系统判定 BACK），子页应被弹出');
    await tester.pump(const Duration(milliseconds: 400));
    await waitFor(tester, find.byType(LoginPage), reason: '手势返回后应回到登录页');
    debugPrint('H21-BACKNAV: LEG-B-OK', wrapWidth: 200);
  });
}

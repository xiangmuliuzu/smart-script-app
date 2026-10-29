import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/router/route_paths.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/theme/app_theme.dart';
import 'package:script_app/features/profile/pages/phone_change_page.dart';
import 'package:script_app/features/user_center/widgets/user_center_widgets.dart';

import '../support/scripted_api.dart';

void main() {
  testWidgets('换手机号只显示当前步骤，失败保留页面，成功后逐步替换并退出登录', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = ScriptedApi();
    const oldVerify = '/users/me/phone/change/old/verify';
    const newSend = '/users/me/phone/change/new/send';
    const confirm = '/users/me/phone/change/confirm';
    api.reply(oldVerify, Envelope.fail(40901, '验证码错误'));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(initialLocation: '/change-phone', routes: [
      GoRoute(
          path: '/change-phone', builder: (_, __) => const PhoneChangePage()),
      GoRoute(
        path: RoutePath.login,
        builder: (_, __) => const Scaffold(body: Text('重新登录')),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        api.override,
        sharedPreferencesProvider.overrideWithValue(prefs),
        secureTokenStorageProvider
            .overrideWithValue(InMemoryTokenSecureStorage()),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ));
    await tester.pumpAndSettle();

    Future<void> submit() async {
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .clearSnackBars();
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
    }

    void expectStep(int step, String title) {
      expect(find.byType(UserStepCard), findsOneWidget);
      expect(
          tester.widget<UserStepCard>(find.byType(UserStepCard)).index, step);
      expect(find.text(title), step == 3 ? findsNWidgets(2) : findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      final content = find.ancestor(
          of: find.byType(ElevatedButton), matching: find.byType(Column));
      expect(tester.getSize(find.byType(ElevatedButton)).width,
          tester.getSize(content.first).width,
          reason: '主按钮铺满步骤卡内容宽度');
      expect(tester.takeException(), isNull);
    }

    expectStep(1, '验证当前账号');
    expect(find.text('填写新手机号'), findsNothing);
    expect(find.text('确认换绑'), findsNothing);
    await submit();
    expect(api.countOf(oldVerify), 0);
    expectStep(1, '验证当前账号');

    await tester.enterText(find.byType(TextField), '123456');
    await submit();
    expectStep(1, '验证当前账号');
    expect(find.text('验证码错误'), findsOneWidget);
    api.reply(oldVerify,
        Envelope.ok({'stepUpToken': 'verified-old-phone', 'expiresIn': 600}));
    await submit();
    expectStep(2, '填写新手机号');
    expect(find.text('验证当前账号'), findsNothing);
    expect(find.text('确认换绑'), findsNothing);

    await tester.enterText(find.byType(TextField), '123');
    await submit();
    expect(api.countOf(newSend), 0);
    expectStep(2, '填写新手机号');
    api.reply(newSend, Envelope.fail(40900, '该手机号已被注册'));
    await tester.enterText(find.byType(TextField), '13900000000');
    await submit();
    expectStep(2, '填写新手机号');
    expect(find.text('该手机号已被注册'), findsOneWidget);

    api.reply(newSend, Envelope.ok(null));
    await submit();
    expectStep(3, '确认换绑');
    expect(find.text('填写新手机号'), findsNothing);
    expect(find.text('验证当前账号'), findsNothing);
    final resend = find.widgetWithText(TextButton, '60s');
    expect(tester.widget<TextButton>(resend).onPressed, isNull);
    api.reply(confirm, Envelope.fail(40901, '验证码已失效'));
    await tester.enterText(find.byType(TextField), '654321');
    await submit();
    expectStep(3, '确认换绑');
    expect(find.text('验证码已失效'), findsOneWidget);

    api.reply(confirm, Envelope.ok({'phoneMasked': '139****0000'}));
    await submit();
    expect(find.text('重新登录'), findsOneWidget);
    expect(find.byType(PhoneChangePage), findsNothing);
    final request = api.requests.lastWhere((r) => r.path.contains(confirm));
    expect(request.data, containsPair('newPhone', '13900000000'));
    expect(request.data, containsPair('code', '654321'));
    expect(request.data, containsPair('stepUpToken', 'verified-old-phone'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

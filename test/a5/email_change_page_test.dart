import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/router/route_paths.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/features/profile/pages/email_change_page.dart';
import '../support/scripted_api.dart';

void main() {
  testWidgets('验证旧账号和新邮箱后绑定并退出登录', (tester) async {
    final api = ScriptedApi();
    const verify = '/users/me/phone/change/old/verify';
    const send = '/users/me/email/change/new/send';
    const confirm = '/users/me/email/change/confirm';
    api.reply(verify, Envelope.ok({'stepUpToken': 'verified-account', 'expiresIn': 600}));
    api.reply(send, Envelope.ok(null));
    api.reply(confirm, Envelope.ok({'changed': true}));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(initialLocation: '/email', routes: [
      GoRoute(path: '/email', builder: (_, __) => const EmailChangePage()),
      GoRoute(path: RoutePath.login, builder: (_, __) => const Scaffold(body: Text('重新登录'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      api.override, sharedPreferencesProvider.overrideWithValue(prefs),
      secureTokenStorageProvider.overrideWithValue(InMemoryTokenSecureStorage()),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(find.text('验证当前账号'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('填写新邮箱'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'invalid');
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(api.countOf(send), 0);
    await tester.enterText(find.byType(TextField), 'Writer@Example.com');
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(api.countOf(send), 1);
    await tester.enterText(find.byType(TextField), '654321');
    await tester.tap(find.text('确认绑定').last);
    await tester.pumpAndSettle();
    expect(find.text('重新登录'), findsOneWidget);
    final request = api.requests.lastWhere((r) => r.path.contains(confirm));
    expect(request.data, containsPair('newEmail', 'writer@example.com'));
    expect(request.data, containsPair('stepUpToken', 'verified-account'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

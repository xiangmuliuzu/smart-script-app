import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:script_app/core/router/route_paths.dart';
import 'package:script_app/features/message/pages/message_list_page.dart';

import 'support/scripted_api.dart';

Future<GoRouter> pumpMessages(WidgetTester tester, String initial) async {
  final api = ScriptedApi();
  api.reply('/messages/unread-count', Envelope.ok({'total': 0}));
  api.reply('/messages', Envelope.ok({'total': 0, 'list': []}));
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(
      path: RoutePath.home,
      builder: (_, __) => const Scaffold(body: Text('书城首页')),
    ),
    GoRoute(
      path: RoutePath.profile,
      builder: (_, __) => const Scaffold(body: Text('我的页面')),
    ),
    GoRoute(
      path: RoutePath.messages,
      builder: (_, __) => const MessageListPage(),
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [api.override],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('消息页没有历史栈也显示返回键，并回到书城', (tester) async {
    await pumpMessages(tester, RoutePath.messages);
    expect(find.text('消息中心'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('书城首页'), findsOneWidget);
  });

  testWidgets('从书城或我的进入消息后，返回各自的来源页', (tester) async {
    final router = await pumpMessages(tester, RoutePath.home);
    for (final entry in {
      RoutePath.home: '书城首页',
      RoutePath.profile: '我的页面',
    }.entries) {
      router.go(entry.key);
      await tester.pumpAndSettle();
      router.push(RoutePath.messages);
      await tester.pumpAndSettle();
      expect(find.text('消息中心'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
    }
  });
}

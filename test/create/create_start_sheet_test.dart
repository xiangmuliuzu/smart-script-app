// 创作入口「创作分镜」：底部导航与「我的作品」共用同一套「选作品 → 分镜页」流程。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:script_app/core/router/route_paths.dart';
import 'package:script_app/features/create/data/author_work_models.dart';
import 'package:script_app/features/create/data/author_work_providers.dart';
import 'package:script_app/features/create/widgets/create_start_sheet.dart';

const _works = <AuthorWorkItem>[
  AuthorWorkItem(workId: 7, title: '深夜频率', status: 'draft', wordCount: 1800),
  AuthorWorkItem(workId: 8, title: '雨夜列车', status: 'published', wordCount: 900),
];

Future<GoRouter> _pumpHost(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, _) => Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => pickWorkForStoryboard(context, ref),
                  child: const Text('创作分镜'),
                ),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: RoutePath.aiStoryboard,
        builder: (_, state) => Scaffold(
          body: Text('分镜页 ${state.uri.queryParameters['workId']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      myWorksProvider('all').overrideWith((ref) async => _works),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('选作品弹层列出本人作品，选中后进入该作品的分镜页', (tester) async {
    await _pumpHost(tester);
    await tester.tap(find.text('创作分镜'));
    await tester.pumpAndSettle();

    // 先弹「选择作品」，而不是直接进入分镜页。
    expect(find.text('选择作品'), findsOneWidget);
    expect(find.text('深夜频率'), findsOneWidget);
    expect(find.text('雨夜列车'), findsOneWidget);
    expect(find.textContaining('分镜页'), findsNothing);

    await tester.tap(find.text('雨夜列车'));
    await tester.pumpAndSettle();
    expect(find.text('分镜页 8'), findsOneWidget);
  });

  testWidgets('没有作品时提示先创建作品，不进入分镜页', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        myWorksProvider('all').overrideWith((ref) async => const <AuthorWorkItem>[]),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => pickWorkForStoryboard(context, ref),
                  child: const Text('创作分镜'),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('创作分镜'));
    await tester.pumpAndSettle();

    expect(find.text('选择作品'), findsNothing);
    expect(find.textContaining('还没有作品'), findsOneWidget);
  });
}

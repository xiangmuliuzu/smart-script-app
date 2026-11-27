// 作品工作台（v3）：作品资料入口 + 章节进度状态。
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/core/router/route_paths.dart';
import 'package:script_app/features/create/data/author_work_models.dart';
import 'package:script_app/features/create/data/author_work_repository.dart';
import 'package:script_app/features/create/data/author_work_providers.dart';
import 'package:script_app/features/create/data/blueprint_repository.dart';
import 'package:script_app/features/create/data/chapter_meta_models.dart' show ChapterDraftResult;
import 'package:script_app/features/create/data/create_repository.dart';
import 'package:script_app/features/create/data/blueprint_providers.dart';
import 'package:script_app/features/create/data/chapter_meta_models.dart' hide ChapterDraftResult;
import 'package:script_app/features/create/pages/work_workspace_page.dart';
import 'package:script_app/features/welfare/data/welfare_models.dart';
import 'package:script_app/features/welfare/data/welfare_providers.dart';

const _detail = AuthorWorkDetail(
  work: AuthorWorkItem(
    workId: 7,
    title: '深夜频率',
    status: 'draft',
    wordCount: 1800,
  ),
  shelfStatus: 'off_shelf',
  chapters: [
    AuthorChapterItem(
      chapterId: 55,
      chapterNo: 1,
      chapterTitle: '无人接听',
      content: '',
      summary: '凌晨三点，沈默照常开播。',
    ),
    AuthorChapterItem(
      chapterId: 56,
      chapterNo: 2,
      chapterTitle: '母带',
      content: '',
      summary: '',
    ),
    AuthorChapterItem(
      chapterId: 57,
      chapterNo: 3,
      chapterTitle: '三点零七分',
      content: '正文内容正文内容',
      summary: '',
      wordCount: 8,
    ),
  ],
);

const _metas = ChapterMetaTable({
  2: ChapterMeta(source: 'ai', aiSummary: 'AI 起草的本章概要'),
});

/// 起草接口固定失败：验证积分不足 / AI 不可用时仍能新建空白章。
class _FailingBlueprintRepository extends BlueprintRepository {
  _FailingBlueprintRepository()
      : super(
          ApiClient(Dio()),
          AuthorWorkRepository(ApiClient(Dio())),
          CreateRepository(ApiClient(Dio())),
        );

  @override
  Future<ChapterDraftResult> draftChapter({
    required int workId,
    required int chapterNo,
    String? instruction,
    String? model,
    int? skillId,
    void Function(String delta)? onDelta,
  }) async =>
      throw ApiException('AI 服务暂不可用');
}

/// 只拦截「新增章节」的作品仓库：返回固定 chapterId，并记录调用。
class _StubWorkRepository extends AuthorWorkRepository {
  _StubWorkRepository({required this.onAdd}) : super(ApiClient(Dio()));

  final VoidCallback onAdd;

  @override
  Future<int> addChapter(
    int workId, {
    required int chapterNo,
    required String chapterTitle,
    String? content,
    String? summary,
    bool isFree = false,
  }) async {
    onAdd();
    return 60;
  }
}

Future<void> _pump(WidgetTester tester, {GoRouter? router}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final child = router == null
      ? const MaterialApp(home: WorkWorkspacePage(workId: 7))
      : MaterialApp.router(routerConfig: router);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authorWorkDetailProvider(7).overrideWith((ref) async => _detail),
      workChapterMetaProvider(7).overrideWith((ref) async => _metas),
    ],
    child: child,
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('顶部作品卡提供「作品资料」「设置」入口', (tester) async {
    await _pump(tester);
    expect(find.text('作品资料'), findsOneWidget);
    expect(find.text('设置'), findsWidgets);
    expect(find.text('深夜频率'), findsWidgets);
    expect(find.textContaining('1800 字'), findsOneWidget);
  });

  testWidgets('章节列表按进度展示状态', (tester) async {
    await _pump(tester);
    expect(find.text('第 1 章 · 无人接听'), findsOneWidget);
    expect(find.text('概要已定 · 待写正文'), findsOneWidget);
    // 第 2 章只有 AI 起草的本章资料。
    expect(find.text('AI 已起草概要 · 待写正文'), findsOneWidget);
    // 第 3 章有正文。
    expect(find.textContaining('已写 8 字'), findsOneWidget);
  });

  testWidgets('作品资料入口打开作品资料页', (tester) async {
    final router = GoRouter(
      initialLocation: '/ws',
      routes: [
        GoRoute(
          path: '/ws',
          builder: (_, __) => const WorkWorkspacePage(workId: 7),
        ),
        GoRoute(
          path: RoutePath.aiBlueprint,
          builder: (_, state) => Scaffold(
            body: Text('资料页 ${state.uri.queryParameters['workId']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await _pump(tester, router: router);
    await tester.tap(find.text('作品资料'));
    await tester.pumpAndSettle();
    expect(find.text('资料页 7'), findsOneWidget);
  });

  testWidgets('新建章节入口唯一：不出现右下角 FAB，只有底部整宽按钮', (tester) async {
    await _pump(tester);
    // 章节列表与底部「新建章节」按钮同时存在时，不应再有 FAB 文案「写新章节」。
    expect(find.text('写新章节'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('新建章节'), findsOneWidget);
  });

  testWidgets('积分为 0 时仍可降级新建空白章节', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var addCalls = 0;
    final repository = _StubWorkRepository(onAdd: () => addCalls++);
    final router = GoRouter(
      initialLocation: '/ws',
      routes: [
        GoRoute(
          path: '/ws',
          builder: (_, __) => const WorkWorkspacePage(workId: 7),
        ),
        GoRoute(
          path: RoutePath.chapterWrite,
          builder: (_, state) => Scaffold(
            body: Text('写章 ${state.uri.queryParameters['chapterId']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authorWorkDetailProvider(7).overrideWith((ref) async => _detail),
        workChapterMetaProvider(7)
            .overrideWith((ref) async => ChapterMetaTable.empty),
        authorWorkRepositoryProvider.overrideWithValue(repository),
        // 本用例只验证「降级建空白章」，AI 起草固定失败（避免真实 HTTP 往返）。
        blueprintRepositoryProvider.overrideWithValue(_FailingBlueprintRepository()),
        welfareAssetProvider.overrideWith(
            (ref) async => (points: const PointsBalance(balance: 0), aiAvailable: 0)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建章节'));
    await tester.pump();
    // 建章是真实的 HTTP 往返（Dio + 可编排适配器），需要让真实异步跑完。
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pumpAndSettle();

    // 不弹「积分不足」拦路弹窗，直接降级建空白章并进入章节页。
    expect(find.text('去福利中心获取积分'), findsNothing);
    expect(addCalls, 1);
    expect(find.text('写章 60'), findsOneWidget);
  });
}

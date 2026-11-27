import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/router/route_paths.dart';
import 'package:script_app/features/ai/ai_storyboard_page.dart';
import 'package:script_app/features/ai/data/ai_models.dart';
import 'package:script_app/features/ai/data/ai_providers.dart';
import 'package:script_app/features/ai/data/ai_repository.dart';
import 'package:script_app/features/bookstore/data/content_providers.dart';
import 'package:script_app/features/bookstore/pages/work_storyboard_page.dart';
import 'package:script_app/features/create/data/author_work_models.dart';
import 'package:script_app/features/create/data/author_work_providers.dart';
import 'package:script_app/features/create/pages/chapter_write_page.dart';
import 'package:script_app/features/create/pages/work_workspace_page.dart';

class _StoryboardRepository extends AiRepository {
  _StoryboardRepository() : super(ApiClient(Dio()));

  String? sentScript;
  String? sentTitle;
  String? savedTitle;
  int? savedWork;

  @override
  Future<AiWriteResult> storyboardStream({
    required String script,
    String? style,
    int? skillId,
    String? model,
    int? workId,
    String? chapterTitle,
    required void Function(String delta) onDelta,
  }) async {
    sentScript = script;
    sentTitle = chapterTitle;
    return AiWriteResult.fromJson({'content': '镜头一：列车进站'});
  }

  @override
  Future<void> saveStoryboard({
    required int workId,
    required String title,
    required String content,
    String source = 'ai',
    int? chapterId,
    int? chapterNo,
  }) async {
    savedTitle = title;
    savedWork = workId;
  }

  @override
  Future<List<AiSkill>> listSkills() async => [];

  @override
  Future<List<AiChannel>> listModels() async => [];
}

void main() {
  testWidgets('作者查看分镜，从章节编辑进入 AI 分镜并刷新目录', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _StoryboardRepository();
    final router = GoRouter(
      initialLocation: '/work',
      routes: [
        GoRoute(
          path: '/work',
          builder: (_, __) => const WorkWorkspacePage(workId: 4),
        ),
        GoRoute(
          path: RoutePath.chapterWrite,
          builder: (_, __) => const ChapterWritePage(workId: 4, chapterId: 7),
        ),
        GoRoute(
          path: RoutePath.aiStoryboard,
          builder: (_, state) {
            final params = state.uri.queryParameters;
            return AiStoryboardPage(
              workId: int.tryParse(params['workId'] ?? ''),
              chapterId: int.tryParse(params['chapterId'] ?? ''),
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        aiRepositoryProvider.overrideWithValue(repository),
        authorWorkDetailProvider(4)
            .overrideWith((ref) async => const AuthorWorkDetail(
                  work: AuthorWorkItem(workId: 4, title: '雨夜列车'),
                  chapters: [
                    AuthorChapterItem(
                      chapterId: 7,
                      chapterTitle: '第一章 雨夜',
                      chapterNo: 1,
                      content: '<p>窗外下着雨。</p>',
                    ),
                  ],
                )),
        workStoryboardsProvider(4).overrideWith((ref) async => [
              {
                'storyboardId': 9,
                'chapterId': 7,
                'chapterTitle': '第一章 雨夜',
                'status':
                    repository.savedTitle == null ? 'rejected' : 'ai_reviewing',
                'content': '镜头一：列车进站',
                'readable': true,
              }
            ]),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分镜'));
    await tester.pumpAndSettle();
    expect(find.text('未通过审核'), findsOneWidget);
    expect(find.text('创作分镜'), findsOneWidget);
    await tester.tap(find.text('第一章 雨夜'));
    await tester.pumpAndSettle();
    expect(find.byType(StoryboardReadPage), findsOneWidget);
    expect(find.text('镜头一：列车进站'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('章节'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第 1 章 · 第一章 雨夜'));
    await tester.pumpAndSettle();
    // v3 章节页把分镜收进「分镜」Tab：状态与正文在 Tab 内展示。
    await tester.tap(find.text('分镜'));
    await tester.pumpAndSettle();
    expect(find.text('镜头一：列车进站'), findsOneWidget);
    expect(find.textContaining('未通过审核'), findsWidgets);
    await tester.tap(find.text('独立分镜页'));
    await tester.pumpAndSettle();
    expect(find.byType(AiStoryboardPage), findsOneWidget);
    final script = tester.widget<TextField>(find.byType(TextField).first);
    expect(script.controller?.text, '窗外下着雨。');
    final generate = find.widgetWithText(ElevatedButton, '生成分镜');
    await tester.ensureVisible(generate);
    await tester.tap(generate);
    await tester.pumpAndSettle();
    expect(repository.sentScript, '窗外下着雨。');
    expect(repository.sentTitle, '第一章 雨夜');
    expect(repository.savedWork, 4);
    expect(repository.savedTitle, '第一章 雨夜');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('分镜'));
    await tester.pumpAndSettle();
    expect(find.textContaining('AI 审核中'), findsWidgets);
  });
}

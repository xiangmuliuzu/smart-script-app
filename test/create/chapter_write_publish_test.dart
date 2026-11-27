// 章节创作页（v3）：概要 / 正文 / 分镜 / 本章资料 四段 + 自动保存 + AI 先预览后写入。
//
// 走真实 AuthorWorkRepository / ApiClient 代码路径，只替换 HTTP 传输层（ScriptedApi）。
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:script_app/features/ai/data/ai_models.dart';
import 'package:script_app/features/ai/data/ai_providers.dart';
import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/features/create/data/author_work_repository.dart';
import 'package:script_app/features/create/data/author_work_providers.dart';
import 'package:script_app/core/network/api_exception.dart';
import 'dart:async';

import 'package:script_app/features/ai/data/ai_repository.dart';
import 'package:script_app/features/create/pages/chapter_write_page.dart';

import '../support/scripted_api.dart';

/// 作品详情（draft 作品可编辑）。
Envelope _detailEmptyCatalog() => Envelope.ok({
      'work': {'workId': 7, 'title': '联调作品', 'status': 'draft', 'wordCount': 0},
      'tags': <Object>[],
      'chapters': <Object>[],
      'latestReview': null,
      'shelfStatus': 'on_shelf',
    });

/// 作品详情：单章草稿（status="1"），带 AI 起草的概要。
Envelope _detailDraftChapter({String summary = ''}) => Envelope.ok({
      'work': {'workId': 7, 'title': '联调作品', 'status': 'draft'},
      'chapters': [
        {
          'chapterId': 55,
          'chapterNo': 1,
          'chapterTitle': '第一章',
          'content': '正文',
          'summary': summary,
          'isFree': '0',
          'status': '1',
        },
      ],
    });

Envelope _detailReviewing() => Envelope.ok({
      'work': {'workId': 7, 'title': '联调作品', 'status': 'reviewing'},
      'chapters': [
        {
          'chapterId': 55,
          'chapterNo': 1,
          'chapterTitle': '第一章',
          'content': '正文',
          'summary': '概要',
          'isFree': '0',
          'status': '1',
        },
      ],
    });

/// 章节 AI 草稿仓库：只替换流式写作，其余走父类（不会真正发请求）。
class _DraftRepository extends AiRepository {
  _DraftRepository([ApiClient? client]) : super(client ?? ApiClient(Dio()));

  final List<String> prompts = [];

  /// 模拟流到第一段后中断（用于验证已收到文本被保留）。
  bool interruptText = false;

  @override
  Future<AiWriteResult> writeStream({
    required String prompt,
    String? type,
    int? skillId,
    String? model,
    int? workId,
    required void Function(String delta) onDelta,
  }) async {
    prompts.add(prompt);
    onDelta('凌晨三点，');
    if (interruptText) throw ApiException('网络中断');
    onDelta('沈默照常开播。');
    return const AiWriteResult(content: '凌晨三点，沈默照常开播。', recordId: 9);
  }

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
    prompts.add(script);
    onDelta('01 特写｜红灯亮起');
    return const AiWriteResult(content: '01 特写｜红灯亮起', recordId: 10);
  }
}

/// 可控「请求飞行」的作品仓库：把 updateChapter 挂起，用于验证保存期间继续编辑的丢失问题。
class _HoldableWorkRepository extends AuthorWorkRepository {
  _HoldableWorkRepository(super.api);

  Completer<void>? hold;

  @override
  Future<void> updateChapter(
    int chapterId, {
    int? workId,
    String? chapterTitle,
    String? content,
    String? summary,
    bool? isFree,
    String? status,
  }) async {
    final gate = hold;
    if (gate != null) await gate.future;
    return super.updateChapter(
      chapterId,
      workId: workId,
      chapterTitle: chapterTitle,
      content: content,
      summary: summary,
      isFree: isFree,
      status: status,
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  ScriptedApi api, {
  int chapterId = 0,
  AiRepository? aiRepository,
  AuthorWorkRepository? workRepository,
  Map<String, Object> chapterMeta = const <String, Object>{},
  Envelope? blueprint,
}) async {
  api.reply('/content/works/7/chapter-meta', Envelope.ok(chapterMeta));
  api.reply('/content/works/7/ledger', Envelope.ok(<String, Object>{}));
  api.reply('/content/works/7/blueprint', blueprint ?? Envelope.ok(null));
  api.reply('/content/works/7/storyboards', Envelope.ok(<Object>[]));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        api.override,
        if (aiRepository != null)
          aiRepositoryProvider.overrideWithValue(aiRepository),
        if (workRepository != null)
          authorWorkRepositoryProvider.overrideWithValue(workRepository),
      ],
      child: MaterialApp(
        home: ChapterWritePage(workId: 7, chapterId: chapterId),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pump(const Duration(milliseconds: 20));
}

/// 推进自动保存防抖（3 秒）并等网络往返完成。
Future<void> _flushAutoSave(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('新建章节自动保存：显式 chapterNo，标题默认「第 N 章」', (tester) async {
    final api = ScriptedApi();
    api.reply('/users/me/works/7', _detailEmptyCatalog());
    api.reply('/content/works/7/chapters', Envelope.ok({'chapterId': 55}));
    api.reply('/content/chapters/55', Envelope.ok(null));
    await _pump(tester, api);

    expect(find.text('新建章节'), findsOneWidget);
    expect(find.text('第 1 章'), findsWidgets);
    // 切到正文并输入内容，触发自动保存。
    await tester.tap(find.text('正文'));
    await tester.pump();
    await tester.tap(find.text('自己写'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '正文内容');
    await _flushAutoSave(tester);

    final post = api.requests.singleWhere((r) => r.method == 'POST');
    expect(post.path, contains('/content/works/7/chapters'));
    expect((post.data as Map)['chapterNo'], 1);
  });

  testWidgets('编辑正文：PUT 不带 summary（null=不改）', (tester) async {
    final api = ScriptedApi();
    api.reply('/users/me/works/7', _detailDraftChapter(summary: '旧概要'));
    api.reply('/content/chapters/55', Envelope.ok(null));
    await _pump(tester, api, chapterId: 55);

    await tester.tap(find.text('正文'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '新的正文');
    await _flushAutoSave(tester);

    final put = api.requests.singleWhere((r) => r.method == 'PUT');
    expect(put.path, contains('/users/me/works/7/chapters/55'));
    expect((put.data as Map)['content'], '新的正文');
    expect((put.data as Map).containsKey('summary'), isFalse);
  });

  testWidgets('编辑概要：PUT 带 summary，可清空', (tester) async {
    final api = ScriptedApi();
    api.reply('/users/me/works/7', _detailDraftChapter(summary: '旧概要'));
    api.reply('/content/chapters/55', Envelope.ok(null));
    await _pump(tester, api, chapterId: 55);

    await tester.enterText(find.byType(TextField).last, '');
    await _flushAutoSave(tester);

    final put = api.requests.singleWhere((r) => r.method == 'PUT');
    expect(put.path, contains('/users/me/works/7/chapters/55'));
    expect((put.data as Map)['summary'], '');
  });

  testWidgets('审核中的作品为只读，不发起保存', (tester) async {
    final api = ScriptedApi();
    api.reply('/users/me/works/7', _detailReviewing());
    await _pump(tester, api, chapterId: 55);

    expect(find.text('只读'), findsOneWidget);
    expect(find.text('按这版概要写正文 →'), findsOneWidget);
    expect(find.textContaining('作品审核中'), findsOneWidget);
    await tester.tap(find.text('正文'));
    await tester.pump();
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields.every((field) => field.enabled != true), isTrue);
    expect(api.requests.where((r) => r.method == 'PUT'), isEmpty);
  });

  testWidgets('四段切换：概要 / 正文空态 / 分镜空态 / 本章资料', (tester) async {
    final api = ScriptedApi();
    api.reply('/users/me/works/7', _detailDraftChapter(summary: '本章概要'));
    await _pump(tester, api, chapterId: 55);

    // 概要 Tab：有概要与 AI 提示位置。
    expect(find.textContaining('/ 500 字'), findsOneWidget);

    await tester.tap(find.text('正文'));
    await tester.pump();
    // 已有正文直接进入编辑态。
    expect(find.byType(TextField).last, findsOneWidget);

    await tester.tap(find.text('分镜'));
    await tester.pump();
    expect(find.text('还没有分镜'), findsOneWidget);
    expect(find.text('✦ AI 按正文拆镜'), findsOneWidget);
    expect(find.text('自己写'), findsOneWidget);

    await tester.tap(find.text('本章资料'));
    await tester.pumpAndSettle();
    expect(find.text('出场人物'), findsOneWidget);
    expect(find.text('本章物品'), findsOneWidget);
    expect(find.text('本章关系'), findsOneWidget);
    // 本章资料 Tab 不显示悬浮 AI 胶囊。
    expect(find.widgetWithText(GestureDetector, 'AI 创作'), findsNothing);
  });

  testWidgets('正文空态：AI 弹层生成后先预览，确认才写入', (tester) async {
    final api = ScriptedApi();
    api.reply('/users/me/works/7', _detailDraftChapter());
    api.reply('/content/chapters/55', Envelope.ok(null));
    final repo = _DraftRepository();
    await _pump(tester, api, chapterId: 55, aiRepository: repo);

    await tester.tap(find.text('正文'));
    await tester.pump();
    // 本章有正文时不再展示空态卡，直接用悬浮胶囊打开 AI 弹层。
    await tester.tap(find.text('AI 创作'));
    await tester.pumpAndSettle();

    expect(find.text('AI 创作 · 章节正文'), findsOneWidget);
    expect(find.text('参考范围'), findsOneWidget);
    expect(find.text('作品资料'), findsOneWidget);
    expect(find.text('内容概要'), findsOneWidget);
    expect(find.text('上一章'), findsOneWidget);

    await tester.tap(find.text('✦ 生成正文草稿'));
    await tester.pumpAndSettle();
    expect(find.text('AI 草稿 · 第 1 章'), findsOneWidget);
    expect(find.text('凌晨三点，沈默照常开播。'), findsOneWidget);
    // 预览阶段还没有写入正文（正文控件未变化、也没有保存）。
    expect(repo.prompts.single, contains('请写《联调作品》第 1 章'));
    expect(api.requests.where((r) => r.method == 'PUT'), isEmpty);

    await tester.tap(find.text('插入到正文'));
    await tester.pumpAndSettle();
    expect(find.textContaining('凌晨三点，沈默照常开播。'), findsWidgets);
  });

  testWidgets('分镜 Tab：AI 拆镜先预览，确认后保存到作品分镜目录', (tester) async {
    final api = ScriptedApi();
    api.reply('/users/me/works/7', _detailDraftChapter());
    api.handle('/content/works/7/storyboards',
        (options) => options.method == 'POST'
            ? Envelope.ok({'storyboardId': 9})
            : Envelope.ok(<Object>[]));
    api.reply('/content/chapters/55', Envelope.ok(null));
    final repo = _DraftRepository(ApiClient(api.buildDio()));
    await _pump(tester, api, chapterId: 55, aiRepository: repo);

    await tester.tap(find.text('分镜'));
    await tester.pump();
    expect(find.text('还没有分镜'), findsOneWidget);
    await tester.tap(find.text('✦ AI 按正文拆镜'));
    await tester.pumpAndSettle();
    expect(find.text('AI 创作 · 章节分镜'), findsOneWidget);
    await tester.tap(find.text('✦ 生成章节分镜'));
    await tester.pumpAndSettle();
    expect(find.text('01 特写｜红灯亮起'), findsOneWidget);
    await tester.tap(find.text('应用到分镜页'));
    await tester.pumpAndSettle();
    expect(repo.prompts.last, contains('请拆成分镜'));

    // 写入分镜后触发自动保存：POST 到分镜目录并带本章章节 ID。
    await _flushAutoSave(tester);
    final post = api.requests.singleWhere(
        (r) => r.method == 'POST' && r.path.contains('/storyboards'));
    expect((post.data as Map)['chapterId'], 55);
    expect((post.data as Map)['content'], contains('01 特写｜红灯亮起'));
  });

  testWidgets('AI 弹层流式预览：生成中实时显示已收到文本', (tester) async {
    final api = ScriptedApi();
    api.reply('/users/me/works/7', _detailDraftChapter());
    api.reply('/content/chapters/55', Envelope.ok(null));
    final repo = _DraftRepository(ApiClient(api.buildDio()));
    await _pump(tester, api, chapterId: 55, aiRepository: repo);

    await tester.tap(find.text('AI 创作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('✦ 生成正文草稿'));
    // 同帧内先渲染一次：流式增量此时已回调（假仓库同步 onDelta）。
    await tester.pump();

    expect(find.textContaining('凌晨三点'), findsWidgets);
    await tester.pumpAndSettle();
    expect(find.text('凌晨三点，沈默照常开播。'), findsOneWidget);
  });

  testWidgets('AI 弹层流中断时保留已收到文本，可继续插入', (tester) async {
    final api = ScriptedApi();
    api.reply('/users/me/works/7', _detailDraftChapter());
    api.reply('/content/chapters/55', Envelope.ok(null));
    final repo = _DraftRepository(ApiClient(api.buildDio()))..interruptText = true;
    await _pump(tester, api, chapterId: 55, aiRepository: repo);

    await tester.tap(find.text('AI 创作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('✦ 生成正文草稿'));
    await tester.pumpAndSettle();

    // 中断后保留半截文本，并提示已保留。
    expect(find.text('凌晨三点，'), findsOneWidget);
    expect(find.textContaining('已保留收到的内容'), findsOneWidget);
    // 仍可把已收到的文本插入正文。
    await tester.tap(find.text('插入到正文'));
    await tester.pumpAndSettle();
    final editor = tester.widget<TextField>(find.byType(TextField).last);
    expect(editor.controller!.text, contains('凌晨三点，'));
  });

  testWidgets('「目录」按钮与返回一致：有未保存修改先保存再离开', (tester) async {
    final api = ScriptedApi();
    api.reply('/users/me/works/7', _detailDraftChapter(summary: '旧概要'));
    api.reply('/content/chapters/55', Envelope.ok(null));
    final router = GoRouter(
      initialLocation: '/list',
      routes: [
        GoRoute(
          path: '/list',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/chapter'),
              child: const Text('打开章节'),
            ),
          ),
        ),
        GoRoute(
          path: '/chapter',
          builder: (_, __) => const ChapterWritePage(workId: 7, chapterId: 55),
        ),
      ],
    );
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [api.override],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开章节'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '改过的概要');
    await tester.pump();
    // 未等自动保存（3 秒）就点「目录」。
    await tester.tap(find.text('目录'));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final put = api.requests.where((r) => r.method == 'PUT').toList();
    expect(put, isNotEmpty, reason: '离开前必须先保存未提交的概要');
    expect((put.last.data as Map)['summary'], '改过的概要');
    // 已离开章节页回到列表。
    expect(find.text('打开章节'), findsOneWidget);
    expect(find.text('目录'), findsNothing);
  });

  testWidgets('保存飞行中继续改概要：下一轮仍带 summary 且会自动保存', (tester) async {
    final api = ScriptedApi();
    api.reply('/users/me/works/7', _detailDraftChapter(summary: '旧概要'));
    api.reply('/content/chapters/55', Envelope.ok(null));
    final works = _HoldableWorkRepository(ApiClient(api.buildDio()));
    await _pump(tester, api, chapterId: 55, workRepository: works);

    await tester.enterText(find.byType(TextField).last, '第一版概要');
    // 让第一轮自动保存进入「请求飞行」。
    works.hold = Completer<void>();
    await tester.pump(const Duration(seconds: 4));
    // 飞行中继续改概要：此时 _onChanged 被保存闸门拦住。
    await tester.enterText(find.byType(TextField).last, '第二版概要');
    await tester.pump(const Duration(milliseconds: 10));
    works.hold!.complete();
    works.hold = null;
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // 第一轮保存结束应重新调度自动保存：等 3 秒防抖再跑一次。
    await tester.pump(const Duration(seconds: 4));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final puts = api.requests.where((r) => r.method == 'PUT').toList();
    expect(puts.length, greaterThanOrEqualTo(2),
        reason: '飞行期间的修改必须触发下一轮自动保存');
    expect((puts.last.data as Map)['summary'], '第二版概要');
  });

  testWidgets('本章物品可点开物品详情（图形 / 持有人 / 出现轨迹）', (tester) async {
    final api = ScriptedApi();
    api.reply('/users/me/works/7', _detailDraftChapter());
    api.reply('/content/chapters/55', Envelope.ok(null));
    await _pump(
      tester,
      api,
      chapterId: 55,
      chapterMeta: {
        '1': {
          'cast': <Object>[],
          'items': [
            {
              'key': 'i-1',
              'name': '开盘母带',
              'role': '本章上场',
              'change': '被沈默带走',
            },
          ],
          'edges': <Object>[],
          'source': 'manual',
        },
      },
      blueprint: Envelope.ok({
      'sessionId': 88,
      'status': 'confirmed',
      'blueprint': {
        'status': 'confirmed',
        'items': [
          {
            'key': 'i-1',
            'name': '开盘母带',
            'icon': 'tape',
            'desc': '十年前的节目母带。',
            'owner': '沈默',
            'count': '1',
            'state': '被带走',
          }
        ],
      },
      }),
    );

    await tester.tap(find.text('本章资料'));
    await tester.pumpAndSettle();
    expect(find.text('开盘母带'), findsOneWidget);
    // 物品行带右箭头（可点提示）。
    expect(find.byIcon(Icons.chevron_right), findsWidgets);

    await tester.tap(find.text('开盘母带'));
    await tester.pumpAndSettle();
    expect(find.text('关键物品 · 沈默持有 · 共 1 件'), findsOneWidget);
    expect(find.text('出现轨迹'), findsOneWidget);
    expect(find.textContaining('被沈默带走'), findsWidgets);
    // 章节页里物品详情只读：没有「编辑物品」入口。
    expect(find.text('编辑物品'), findsNothing);
  });
}

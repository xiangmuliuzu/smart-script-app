// 章节「发布状态」（章节两态）写作页测试。
//
// 对应本次重构：sys_work_chapter.status "0"=已发布（读者可见）/ "1"=草稿（仅作者可见）；
// 新建章节后端默认落草稿，作者选择发布时须在 addChapter 后补一次 updateChapter。
//
// 走真实 AuthorWorkRepository / ApiClient 代码路径，只替换 HTTP 传输层（ScriptedApi）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:script_app/features/create/pages/chapter_write_page.dart';

import '../support/scripted_api.dart';

/// 作品详情（draft 作品可编辑，空目录）。
Envelope _detailEmptyCatalog() => Envelope.ok({
      'work': {'workId': 7, 'title': '联调作品', 'status': 'draft', 'wordCount': 0},
      'tags': <Object>[],
      'chapters': <Object>[],
      'latestReview': null,
      'shelfStatus': 'on_shelf',
    });

/// 作品详情：单章草稿（status="1"）。
Envelope _detailDraftChapter() => Envelope.ok({
      'work': {'workId': 7, 'title': '联调作品', 'status': 'draft'},
      'chapters': [
        {
          'chapterId': 55,
          'chapterNo': 1,
          'chapterTitle': '第一章',
          'content': '正文',
          'isFree': '0',
          'status': '1',
        },
      ],
    });

Future<void> _pump(WidgetTester tester, ScriptedApi api, {int chapterId = 0}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [api.override],
      child: MaterialApp(
        home: ChapterWritePage(workId: 7, chapterId: chapterId),
      ),
    ),
  );
  // 首帧渲染加载占位；随后推进若干帧等详情回包渲染编辑区。
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

  testWidgets('新建章节勾选「发布章节」→ addChapter 后补 updateChapter(status="0")',
      (tester) async {
    final api = ScriptedApi();
    api.reply('/users/me/works/7', _detailEmptyCatalog());
    api.reply('/content/works/7/chapters', Envelope.ok({'chapterId': 55}));
    api.reply('/content/chapters/55', Envelope.ok(null));
    await _pump(tester, api);

    // 标题（首个 TextField）+ 打开第二个开关（发布章节）。
    await tester.enterText(find.byType(TextField).first, '第一章');
    await tester.tap(find.byType(Switch).at(1));
    await tester.pump();
    await _flushAutoSave(tester);

    final post = api.requests.singleWhere((r) => r.method == 'POST');
    expect(post.path, contains('/content/works/7/chapters'));
    final puts = api.requests.where((r) => r.method == 'PUT').toList();
    expect(puts.length, 1, reason: '新建后须补一次状态更新才能落库为已发布');
    expect(puts.single.path, contains('/content/chapters/55'));
    expect((puts.single.data as Map)['status'], '0');
  });

  testWidgets('新建章节不勾选发布 → 仅 addChapter，保持后端默认草稿', (tester) async {
    final api = ScriptedApi();
    api.reply('/users/me/works/7', _detailEmptyCatalog());
    api.reply('/content/works/7/chapters', Envelope.ok({'chapterId': 56}));
    await _pump(tester, api);

    await tester.enterText(find.byType(TextField).first, '第二章');
    await tester.pump();
    await _flushAutoSave(tester);

    expect(api.requests.where((r) => r.method == 'POST').length, 1);
    expect(api.requests.where((r) => r.method == 'PUT'), isEmpty,
        reason: '未选择发布时不得下发 status="0"');
  });

  testWidgets('编辑已有草稿章节并发布 → updateChapter 显式带 status="0"', (tester) async {
    final api = ScriptedApi();
    api.reply('/users/me/works/7', _detailDraftChapter());
    api.reply('/content/chapters/55', Envelope.ok(null));
    await _pump(tester, api, chapterId: 55);

    // 草稿回填：发布开关初始应为关。
    expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isFalse);

    await tester.tap(find.byType(Switch).at(1));
    await tester.pump();
    await _flushAutoSave(tester);

    expect(api.requests.where((r) => r.method == 'POST'), isEmpty);
    final puts = api.requests.where((r) => r.method == 'PUT').toList();
    expect(puts.length, 1);
    expect((puts.single.data as Map)['status'], '0');
  });

  testWidgets('编辑已有已发布章节并下架为草稿 → updateChapter 带 status="1"', (tester) async {
    final api = ScriptedApi();
    api.reply(
      '/users/me/works/7',
      Envelope.ok({
        'work': {'workId': 7, 'title': '联调作品', 'status': 'draft'},
        'chapters': [
          {
            'chapterId': 55,
            'chapterNo': 1,
            'chapterTitle': '第一章',
            'content': '正文',
            'status': '0',
          },
        ],
      }),
    );
    api.reply('/content/chapters/55', Envelope.ok(null));
    await _pump(tester, api, chapterId: 55);

    expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isTrue);

    await tester.tap(find.byType(Switch).at(1));
    await tester.pump();
    await _flushAutoSave(tester);

    final puts = api.requests.where((r) => r.method == 'PUT').toList();
    expect(puts.length, 1);
    expect((puts.single.data as Map)['status'], '1');
  });
}

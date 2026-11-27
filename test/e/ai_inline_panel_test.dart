// 写稿页内嵌 AI 创作面板（E 模块阶段3）。
//
// 覆盖：
//   - AiInlinePanel 三个功能 tab 的输入校验与生成调用（大纲/写作/润色）；
//   - 「插入正文」回调把生成文本交给写稿页；
//   - ChapterWritePage 集成：正文区上方出现「AI 创作」入口，展开后生成并插入正文末尾；
//   - 悬浮窗删除后：写稿页不再挂载 AiQuickPanel（无悬浮球）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/features/ai/data/ai_models.dart';
import 'package:script_app/features/ai/data/ai_providers.dart';
import 'package:script_app/features/ai/data/ai_repository.dart';
import 'package:script_app/features/ai/widgets/ai_inline_panel.dart';
import 'package:script_app/features/create/pages/chapter_write_page.dart';

import '../support/scripted_api.dart';

/// 可控假仓库：大纲/写作/润色返回预设文本并记录调用。
class _FakeAiRepository implements AiRepository {
  _FakeAiRepository({
    this.outlineText = '第一幕：跌落谷底\n第二幕：逆袭崛起',
    this.writeContent = '夜色里，他站在落地窗前，沉默良久。',
    this.polishContent = '【润色】夜色如墨，他立于窗前，久久无言。',
    this.shouldFail = false,
    this.ledger = const {},
    this.writeTruncated = false,
  });

  final String outlineText;
  final String writeContent;
  final String polishContent;
  final bool shouldFail;

  /// 模拟后端下发 truncated=true（上游 finish_reason=length）。
  final bool writeTruncated;

  /// 假台账：面板挂载时读取，续写提示词应带上其中非空字段。
  final Map<String, String> ledger;

  final List<String> calls = [];

  /// 方案 2：插入正文后触发的「摘要 + 台账」回写调用。
  final List<String> summaryCalls = [];

  @override
  Future<Map<String, dynamic>> summarizeChapter({
    required int workId,
    required int chapterId,
    required String content,
    String? model,
  }) async {
    summaryCalls.add('summarizeChapter:$workId|$chapterId|${content.length}');
    calls.add('summarizeChapter:$workId|$chapterId');
    return <String, dynamic>{'summary': '本集摘要', 'ledgerUpdated': true};
  }

  @override
  Future<Map<String, String>> workLedger(int workId) async {
    calls.add('workLedger:$workId');
    return ledger;
  }

  @override
  Future<void> saveWorkLedger(int workId, Map<String, String> ledger) async {
    calls.add('saveWorkLedger:$workId');
    this.ledger
      ..clear()
      ..addAll(ledger);
  }

  @override
  Future<Map<String, dynamic>> reviewChapter({
    required int workId,
    required int chapterId,
    required String content,
    String? model,
  }) async =>
      <String, dynamic>{'passed': true};

  @override
  Future<Map<String, dynamic>> buildVolumeSnapshot({
    required int workId,
    required int volumeNo,
    String? model,
  }) async =>
      <String, dynamic>{};

  @override
  Future<Map<int, String>> workVolumes(int workId) async => const {};

  @override
  Future<AiOutlineResult> outline({
    String? inspiration,
    String? genre,
    String? style,
    int? skillId,
    String? model,
    int? workId,
  }) async {
    calls.add('outline:$inspiration|$genre|$style');
    if (shouldFail) throw ApiException('AI 服务不可用');
    return AiOutlineResult(
      outline: outlineText,
      requestNo: 'AIR01',
      quotaUsed: 1,
    );
  }

  @override
  Future<AiOutlineResult> outlineStream({
    String? inspiration,
    String? genre,
    String? style,
    int? skillId,
    String? model,
    int? workId,
    required void Function(String delta) onDelta,
  }) async {
    calls.add('outlineStream:$inspiration|$genre|$style');
    if (shouldFail) throw ApiException('AI 服务不可用');
    onDelta('第一幕：跌落谷底\n');
    onDelta('第二幕：逆袭崛起');
    return AiOutlineResult(
      outline: outlineText,
      requestNo: 'AIR01',
      quotaUsed: 1,
    );
  }

  @override
  Future<AiWriteResult> write({
    required String prompt,
    String? type,
    int? skillId,
    String? model,
    int? workId,
  }) async {
    calls.add('write:$prompt|$type');
    if (shouldFail) throw ApiException('AI 服务不可用');
    return AiWriteResult(content: writeContent, recordId: 1);
  }

  @override
  Future<AiWriteResult> writeStream({
    required String prompt,
    String? type,
    int? skillId,
    String? model,
    int? workId,
    required void Function(String delta) onDelta,
  }) async {
    calls.add('writeStream:$prompt|$type');
    if (shouldFail) throw ApiException('AI 服务不可用');
    onDelta('夜色里，他站在');
    onDelta('落地窗前，沉默良久。');
    return AiWriteResult(
      content: writeContent,
      recordId: 1,
      truncated: writeTruncated,
    );
  }

  @override
  Future<AiWriteResult> polish({
    required String content,
    String? style,
    int? skillId,
    String? model,
  }) async {
    calls.add('polish:$content|$style');
    if (shouldFail) throw ApiException('AI 服务不可用');
    return AiWriteResult(content: polishContent, recordId: 2);
  }

  @override
  Future<AiWriteResult> polishStream({
    required String content,
    String? style,
    int? skillId,
    String? model,
    required void Function(String delta) onDelta,
  }) async {
    calls.add('polishStream:$content|$style');
    if (shouldFail) throw ApiException('AI 服务不可用');
    onDelta('【润色】夜色如墨，他立于');
    onDelta('窗前，久久无言。');
    return AiWriteResult(content: polishContent, recordId: 2);
  }

  @override
  Future<List<AiChannel>> listModels() async => const [];

  @override
  Future<List<AiSkill>> listSkills() async => const [
        AiSkill(id: 1, skillName: '悬疑烧脑导演'),
        AiSkill(id: 2, skillName: '甜宠爆款导演'),
      ];

  @override
  Future<AiWriteResult> storyboard({
    required String script,
    String? style,
    int? skillId,
    String? model,
  }) async {
    calls.add('storyboard:$script|$style|skill=$skillId');
    return AiWriteResult(content: '【镜1】全景…', recordId: 3);
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
    calls.add('storyboardStream:$script|$style|skill=$skillId');
    onDelta('【镜1】全景…');
    return AiWriteResult(content: '【镜1】全景…', recordId: 3);
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
    calls.add('saveStoryboard:$workId|$title');
  }

  @override
  Future<List<Map<String, dynamic>>> workTimeline(int workId) async => const [];

  @override
  Future<AiPageResult<AiWriteRecord>> writeRecords({
    int page = 1,
    int pageSize = 20,
  }) async =>
      const AiPageResult<AiWriteRecord>();

  @override
  Future<AiQuotaBalance> balance(int userId) async =>
      throw UnimplementedError();
  @override
  Future<int> consume({
    required int userId,
    required String capability,
    int quotaCost = 1,
    int? workId,
    required String idempotencyKey,
  }) async =>
      0;
  @override
  Future<int> refund({
    required int userId,
    int amount = 1,
    int? workId,
    required String idempotencyKey,
  }) async =>
      0;
  @override
  Future<int> exchange({
    required int userId,
    required int points,
    required String idempotencyKey,
  }) async =>
      0;

  @override
  Future<int> deleteWriteRecords(List<int> recordIds) async => recordIds.length;

}

Widget _wrapPanel(
  _FakeAiRepository fake, {
  required ValueChanged<String> onInsert,
  int workId = 0,
  int? chapterId,
  String Function()? chapterTitle,
  String Function()? currentContent,
  String Function()? previousChapter,
}) {
  return ProviderScope(
    overrides: [aiRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AiInlinePanel(
            onInsert: onInsert,
            workId: workId,
            chapterId: chapterId,
            chapterTitle: chapterTitle,
            currentContent: currentContent,
            previousChapter: previousChapter,
          ),
        ),
      ),
    ),
  );
}

/// 作品详情（draft 可编辑，空目录）。
Envelope _detail() => Envelope.ok({
      'work': {'workId': 7, 'title': '联调作品', 'status': 'draft', 'wordCount': 0},
      'tags': <Object>[],
      'chapters': <Object>[],
      'latestReview': null,
      'shelfStatus': 'on_shelf',
    });

Future<void> _pumpPage(WidgetTester tester, ScriptedApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [api.override],
      child: MaterialApp(
        home: ChapterWritePage(workId: 7, chapterId: 0),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('内嵌面板 AiInlinePanel', () {
    testWidgets('剧本续写 tab：无输入即续写，提示词带续写约束', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeAiRepository();
      final inserted = <String>[];
      await tester.pumpWidget(
          _wrapPanel(fake, onInsert: inserted.add));
      await tester.pumpAndSettle();

      // 续写不强制填写「你的要求」，可直接续写后续分集。
      await tester.tap(find.text('生成'));
      await tester.pumpAndSettle();

      expect(fake.calls.first, contains('outlineStream:'));
      expect(fake.calls.first, contains('这是一次「续写」'));
      expect(fake.calls.first, contains('请只输出第1集起、连续 3 集的分集事件卡'));
      expect(fake.calls.first, contains('人物增补'));
      expect(find.textContaining('第一幕：跌落谷底'), findsOneWidget);
      expect(find.text('消耗 1 token'), findsOneWidget);

      // 大纲 tab 的正文写回入口是「按大纲生成各章」，插入按钮只出现在润色/分镜 tab。
      expect(find.text('插入正文'), findsNothing);
      expect(find.text('按大纲生成各章'), findsOneWidget);
    });

    testWidgets('剧本续写注入创作台账，从已有最大集号往后接着写', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeAiRepository(ledger: const {
        'characters': '顾守山 45 岁',
        'relations': '顾守山—顾星宇：父子',
        'foreshadow': '第3集铜铃——第9集已回收',
        'threads': '铜铃为何夜里响｜顾守山｜第2集｜未结\n三年之约｜顾星宇｜第40集｜未结',
      });
      await tester.pumpWidget(_wrapPanel(
        fake,
        onInsert: (_) {},
        workId: 96,
        chapterTitle: () => '第2集：旧照片',
        currentContent: () => '他推开门。',
        previousChapter: () => '上一集结尾，铜铃响了。',
      ));
      await tester.pumpAndSettle();
      expect(fake.calls, contains('workLedger:96'));

      // 「你的要求」是续写表单的第一个输入框。
      await tester.enterText(find.byType(TextField).first, '写重逢');
      await tester.tap(find.text('生成'));
      await tester.pumpAndSettle();
      final prompt =
          fake.calls.firstWhere((call) => call.startsWith('outlineStream:'));
      expect(prompt, contains('【创作台账（已定事实，不得冲突）】'));
      expect(prompt, contains('本集出场人物：\n顾守山 45 岁'));
      expect(prompt, contains('伏笔（埋在哪集/是否回收）：\n第3集铜铃——第9集已回收'));
      expect(prompt, contains('你的要求：\n写重逢'));
      // 本机无大纲、详情无章节时从第 1 集起写，本次新增 3 集。
      expect(prompt, contains('请只输出第1集起、连续 3 集的分集事件卡'));
    });

    testWidgets('润色 tab：选风格后生成并插入', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeAiRepository();
      final inserted = <String>[];
      await tester.pumpWidget(
          _wrapPanel(fake, onInsert: inserted.add));
      await tester.pumpAndSettle();

      await tester.tap(find.text('润色'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('文学优美'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '他很生气地走了。');
      await tester.tap(find.text('生成'));
      await tester.pumpAndSettle();

      expect(fake.calls.first, 'polishStream:他很生气地走了。|文学优美');
      expect(find.textContaining('【润色】'), findsOneWidget);
      await tester.tap(find.text('插入正文'));
      await tester.pump();
      expect(inserted.single, contains('【润色】'));
    });

    testWidgets('插入正文后按章节生成摘要与台账（方案 2）', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeAiRepository();
      final inserted = <String>[];
      await tester.pumpWidget(_wrapPanel(
        fake,
        onInsert: inserted.add,
        workId: 96,
        chapterId: 285,
        currentContent: () =>
            '前文正文，他抬头看了看天。夜色压下来，街上没有人。'
            '他握紧手里的钥匙，一步一步走上楼，楼道里只有自己的脚步声。',
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('润色'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '他很生气地走了。');
      await tester.tap(find.text('生成'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('插入正文'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(inserted.single, contains('【润色】'));
      expect(fake.summaryCalls.single, startsWith('summarizeChapter:96|285|'));
    });

    testWidgets('章节尚未保存（无 chapterId）时插入正文不触发摘要', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeAiRepository();
      final inserted = <String>[];
      await tester.pumpWidget(_wrapPanel(
        fake,
        onInsert: inserted.add,
        workId: 96,
        currentContent: () => '还没有保存的新章节正文，足够长到不会被后端拒绝，只是没有章节 id。',
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('润色'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '他很生气地走了。');
      await tester.tap(find.text('生成'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('插入正文'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(inserted.single, contains('【润色】'));
      expect(fake.summaryCalls, isEmpty);
    });

    testWidgets('分镜 tab：输入剧本后生成分镜并插入', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeAiRepository();
      final inserted = <String>[];
      await tester.pumpWidget(
          _wrapPanel(fake, onInsert: inserted.add));
      await tester.pumpAndSettle();

      await tester.tap(find.text('分镜'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('生成'));
      await tester.pump();
      expect(find.text('请先填写或粘贴剧本文本'), findsOneWidget);

      await tester.enterText(
          find.byType(TextField).first, '第一幕：落魄青年意外获得穿越能力');
      await tester.tap(find.text('短剧竖屏'));
      await tester.pump();
      await tester.tap(find.text('生成'));
      await tester.pumpAndSettle();

      expect(fake.calls.first,
          startsWith('storyboardStream:第一幕：落魄青年意外获得穿越能力'));
      expect(fake.calls.first, contains('短剧竖屏'));
      expect(find.textContaining('【镜1】'), findsOneWidget);
      await tester.tap(find.text('插入正文'));
      await tester.pump();
      expect(inserted.single, contains('【镜1】'));
    });

    testWidgets('生成失败提示且不崩溃', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeAiRepository(shouldFail: true);
      await tester.pumpWidget(
          _wrapPanel(fake, onInsert: (_) {}));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '主题');
      await tester.tap(find.text('生成'));
      await tester.pumpAndSettle();
      expect(find.text('AI 服务不可用'), findsOneWidget);
    });
  });

  group('写稿页集成', () {
    testWidgets('悬浮「AI 创作」胶囊：生成结果先预览，确认后才写入正文', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // 用 ScriptedApi 提供作品详情；AI 仓库用假实现替换。
      final api = ScriptedApi();
      api.reply('/users/me/works/7', _detail());
      final fake = _FakeAiRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            api.override,
            aiRepositoryProvider.overrideWithValue(fake),
          ],
          child: const MaterialApp(
            home: ChapterWritePage(workId: 7, chapterId: 0),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));

      // 正文先写入一段标题与正文（切到正文 Tab 并选择「自己写」）。
      final titleField = find.byType(TextField).first;
      await tester.enterText(titleField, '第一章');
      await tester.tap(find.text('正文'));
      await tester.pump();
      await tester.tap(find.text('自己写'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, '初始正文。');
      await tester.pump();

      // 悬浮胶囊打开 AI 创作弹层。
      await tester.tap(find.text('AI 创作'));
      await tester.pumpAndSettle();
      expect(find.text('AI 创作 · 章节正文'), findsOneWidget);
      await tester.tap(find.text('✦ 生成正文草稿'));
      await tester.pumpAndSettle();
      expect(fake.calls.any((c) => c.startsWith('writeStream:')), isTrue);
      expect(find.textContaining('夜色里，他站在'), findsWidgets);

      // 预览阶段正文仍未写入。
      expect(find.textContaining('初始正文。'), findsWidgets);
      await tester.tap(find.text('插入到正文'));
      await tester.pumpAndSettle();
      // 确认后追加到正文末尾（不覆盖已有内容）。
      final editor = tester.widget<TextField>(find.byType(TextField).last);
      expect(editor.controller!.text, contains('初始正文。'));
      expect(editor.controller!.text, contains('夜色里，他站在落地窗前，沉默良久。'));
    });

    testWidgets('悬浮窗已删除：写稿页无 floatingActionButton 悬浮球', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final api = ScriptedApi();
      api.reply('/users/me/works/7', _detail());
      await _pumpPage(tester, api);

      final scaffold = tester.widget<Scaffold>(
          find.descendant(
              of: find.byType(ChapterWritePage),
              matching: find.byType(Scaffold)));
      expect(scaffold.floatingActionButton, isNull,
          reason: '写稿页不应再挂载 AI 悬浮球');
    });
  });
}

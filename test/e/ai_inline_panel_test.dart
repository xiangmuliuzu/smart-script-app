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
  });

  final String outlineText;
  final String writeContent;
  final String polishContent;
  final bool shouldFail;

  final List<String> calls = [];

  @override
  Future<AiOutlineResult> outline({
    String? inspiration,
    String? genre,
    String? style,
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
  }) async {
    calls.add('write:$prompt|$type');
    if (shouldFail) throw ApiException('AI 服务不可用');
    return AiWriteResult(content: writeContent, recordId: 1);
  }

  @override
  Future<AiWriteResult> writeStream({
    required String prompt,
    String? type,
    required void Function(String delta) onDelta,
  }) async {
    calls.add('writeStream:$prompt|$type');
    if (shouldFail) throw ApiException('AI 服务不可用');
    onDelta('夜色里，他站在');
    onDelta('落地窗前，沉默良久。');
    return AiWriteResult(content: writeContent, recordId: 1);
  }

  @override
  Future<AiWriteResult> polish({
    required String content,
    String? style,
  }) async {
    calls.add('polish:$content|$style');
    if (shouldFail) throw ApiException('AI 服务不可用');
    return AiWriteResult(content: polishContent, recordId: 2);
  }

  @override
  Future<AiWriteResult> polishStream({
    required String content,
    String? style,
    required void Function(String delta) onDelta,
  }) async {
    calls.add('polishStream:$content|$style');
    if (shouldFail) throw ApiException('AI 服务不可用');
    onDelta('【润色】夜色如墨，他立于');
    onDelta('窗前，久久无言。');
    return AiWriteResult(content: polishContent, recordId: 2);
  }

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
}

Widget _wrapPanel(_FakeAiRepository fake, {required ValueChanged<String> onInsert}) {
  return ProviderScope(
    overrides: [aiRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AiInlinePanel(onInsert: onInsert),
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
    testWidgets('大纲 tab：空输入提示；输入后生成并显示结果与消耗', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeAiRepository();
      final inserted = <String>[];
      await tester.pumpWidget(
          _wrapPanel(fake, onInsert: inserted.add));
      await tester.pumpAndSettle();

      // 空输入
      await tester.tap(find.text('生成'));
      await tester.pump();
      expect(find.text('请先输入作品主题或灵感'), findsOneWidget);

      // 输入主题并生成
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '都市青年逆袭');
      await tester.tap(find.text('生成'));
      await tester.pumpAndSettle();

      expect(fake.calls.first, contains('outlineStream:都市青年逆袭'));
      expect(find.textContaining('第一幕：跌落谷底'), findsOneWidget);
      expect(find.text('消耗 1 次'), findsOneWidget);

      // 插入正文回调
      await tester.tap(find.text('插入正文'));
      await tester.pump();
      expect(inserted.single, contains('第一幕：跌落谷底'));
    });

    testWidgets('写作 tab：切换到写作后校验与生成', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeAiRepository();
      await tester.pumpWidget(
          _wrapPanel(fake, onInsert: (_) {}));
      await tester.pumpAndSettle();

      await tester.tap(find.text('写作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('生成'));
      await tester.pump();
      expect(find.text('请先输入写作提示词'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '写一段重逢对手戏');
      await tester.tap(find.text('生成'));
      await tester.pumpAndSettle();
      expect(fake.calls.first, startsWith('writeStream:写一段重逢对手戏'));
      expect(find.text('夜色里，他站在落地窗前，沉默良久。'), findsOneWidget);
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
    testWidgets('正文上方出现「AI 创作」入口，展开可生成并插入正文末尾', (tester) async {
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

      // 入口栏存在
      expect(find.text('AI 创作'), findsOneWidget);
      expect(find.text('展开'), findsOneWidget);

      // 正文先写入一段
      final bodyFields = find.byType(TextField);
      // 标题字段（首个）+ 正文字段
      await tester.enterText(bodyFields.first, '第一章');
      await tester.enterText(bodyFields.at(1), '初始正文。');

      // 展开面板
      await tester.tap(find.text('展开'));
      await tester.pumpAndSettle();
      expect(find.byType(AiInlinePanel), findsOneWidget);

      // 大纲 tab 生成（默认），插入正文
      // 面板内第一个输入框为主题框（面板展开后位于标题框之后）。
      final panelThemeField = find.descendant(
          of: find.byType(AiInlinePanel),
          matching: find.byType(TextField));
      await tester.enterText(panelThemeField.first, '都市青年逆袭');
      await tester.pump();
      final themeField = tester.widget<TextField>(panelThemeField.first);
      expect(themeField.controller!.text, '都市青年逆袭',
          reason: '主题输入应写入面板内主题框');
      await tester.tap(find.text('生成'));
      await tester.pumpAndSettle();
      expect(fake.calls, isNotEmpty, reason: '应已调用 outline 接口');
      expect(find.textContaining('第一幕'), findsOneWidget,
          reason: '生成结果应显示在面板中');
      await tester.tap(find.text('插入正文'));
      await tester.pumpAndSettle();

      // 正文控制器应追加了生成文本（正文框是页面最后一个 TextField）
      final contentField = find.byType(TextField).last;
      final editor = tester.widget<TextField>(contentField);
      final content = editor.controller!.text;
      expect(content, contains('初始正文。'));
      expect(content, contains('第一幕：跌落谷底'));
      expect(content.indexOf('初始正文。'), lessThan(content.indexOf('第一幕：跌落谷底')),
          reason: '生成内容应追加到原正文末尾');
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

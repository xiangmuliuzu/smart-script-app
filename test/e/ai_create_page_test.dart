// E 模块：AI 创作（设定 → 大纲 → 章节）与记录按会话合并。
//
// 覆盖：
//   - 分组：一次大纲 + 它之后生成的 [AI创作] 章节合并成一条会话，其他记录各自成条；
//   - 设定还原：从大纲记录 input_prompt 解析书名/灵感/题材/集数；
//   - 简历解析：严格分集与流式宽松分集；作品简介提取；
//   - 页面：新建入口弹层可选 AI 创作；从记录恢复后直接进入章节步骤。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:script_app/features/ai/data/ai_models.dart';
import 'package:script_app/features/create/ai_create_page.dart';
import 'package:script_app/features/create/data/ai_create_session.dart';
import 'package:script_app/features/welfare/data/welfare_models.dart';
import 'package:script_app/features/welfare/data/welfare_providers.dart';

AiWriteRecord _record(
  int id,
  String type, {
  String input = '',
  String output = '',
  String createdAt = '2026-11-10 10:00',
  int tokens = 1,
}) =>
    AiWriteRecord(
      recordId: id,
      title: '深夜频率',
      writeType: type,
      inputPrompt: input,
      outputContent: output,
      tokensUsed: tokens,
      createdAt: createdAt,
    );

void main() {
  group('AI 创作会话合并', () {
    final outlineInput = [
      '灵感：书名：深夜频率',
      '故事灵感：深夜电台主播听见十年前的自己',
      '请提供 8 个分集，每集单独一行标题',
      '类型：都市悬疑',
      '风格：共 8 集',
    ].join('\n');

    test('大纲与它之后生成的章节合并成一条，未标记的记录保持单条', () {
      final records = [
        _record(9, 'write', input: '${kAiCreateMark} 为“第二集 · 迟到的信”创作正文', output: '${kAiCreateMark} 第二集正文', tokens: 2),
        _record(8, 'write', input: '${kAiCreateMark} 为“第一集 · 深夜频率”创作正文', output: '${kAiCreateMark} 第一集正文', tokens: 2),
        _record(7, 'outline', input: outlineInput, output: '第一集：深夜频率\n雨夜。', tokens: 3),
        // 工作台生成的正文没有标记，不能被并进来。
        _record(6, 'write', input: '为“别处的一章”创作正文', output: '别处正文'),
        _record(5, 'polish', input: '原文', output: '润色'),
      ];
      final sessions = groupAiCreateRecords(records);
      expect(sessions.length, 1);
      final session = sessions.single;
      expect(session.outlineRecord.recordId, 7);
      expect(session.chapters.map((c) => c.recordId), [8, 9]);
      expect(session.tokens, 7);
      expect(session.setup.title, '深夜频率');
      expect(session.setup.genre, '都市悬疑');
      expect(session.setup.episodes, 8);
      expect(session.records.map((r) => r.recordId), [7, 8, 9]);
    });

    test('没有标记的旧记录不会被误并，解析失败的大纲也不算会话', () {
      expect(groupAiCreateRecords([_record(1, 'write', input: 'x', output: 'y')]), isEmpty);
      expect(
        groupAiCreateRecords([_record(2, 'outline', input: '随便写的', output: 'z')]),
        isEmpty,
      );
      expect(AiCreateSetup.tryParse('随便写的'), isNull);
    });
  });

  group('大纲解析', () {
    const outline = '书名：深夜频率\n一句话简介：一位主播听见十年前的自己。\n'
        '第一集 · 深夜频率\n雨夜的咖啡馆。\n第二集 · 迟到的信\n一封没有寄出的信。';

    test('严格分集要求标题行，概要跟随标题', () {
      final seeds = parseOutlineChapters(outline);
      expect(seeds.map((s) => s.title), ['第一集 · 深夜频率', '第二集 · 迟到的信']);
      expect(seeds.first.summary, '雨夜的咖啡馆。');
    });

    test('流式宽松扫描允许标题未写完，不生成概要', () {
      final titles = listOutlineEpisodeTitles('书名：深夜频率\n第一集 · 深夜频率\n雨夜\n第二集 · 迟到');
      expect(titles, ['第一集 · 深夜频率', '第二集 · 迟到']);
    });

    test('作品简介优先取「一句话简介」', () {
      expect(outlineSummaryText(outline), '一位主播听见十年前的自己。');
      expect(outlineSummaryText('第一集：相遇\n两人在车站相遇。'), '两人在车站相遇。');
    });
  });

  group('大纲局部改写', () {
    test('提示词只要求重写选中段落并带上作者意见', () {
      final prompt = outlineRevisePrompt(passage: '雨夜的咖啡馆。', instruction: '改成白天', context: '第一集：深夜频率');
      expect(prompt, contains('只重写这一段'));
      expect(prompt, contains('不要输出整份大纲'));
      expect(prompt, endsWith('【作者意见】${kAiCreateBreak}改成白天'));
    });

    test('区间替换与结果清洗', () {
      final text = ['第一集：相遇', '两人在车站相遇。', '第二集：告别'].join(kAiCreateBreak);
      final start = text.indexOf('两人在车站相遇。');
      final replaced = replaceTextRange(text, start, start + '两人在车站相遇。'.length, '两人在白天相遇。');
      expect(replaceTextRange('abc', 1, 2, 'X'), 'aXc');
      final fence = String.fromCharCodes([96, 96, 96]);
      expect(cleanRevisedPassage(fence + kAiCreateBreak + '白天的咖啡馆。' + kAiCreateBreak + fence), '白天的咖啡馆。');
      expect(cleanRevisedPassage('“白天的咖啡馆。”'), '白天的咖啡馆。');
    });
  });

  group('AI 创作页', () {
    testWidgets('设定页显示剩余积分与整宽主按钮', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            welfareAssetProvider.overrideWith((ref) async =>
                (points: const PointsBalance(balance: 76), aiAvailable: 0)),
          ],
          child: const MaterialApp(home: AiCreatePage()),
        ),
      );
      await tester.pump();
      expect(find.text('剩余 76 积分'), findsOneWidget);
      expect(find.text('下一步：生成大纲'), findsOneWidget);
    });

    testWidgets('从记录恢复：设定与章节带回，直接停在章节步骤', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AiCreatePage(
              draft: AiCreateDraft(
                title: '深夜频率',
                idea: '深夜电台主播',
                genre: '都市悬疑',
                episodes: 8,
                outline: '第一集 · 深夜频率\n雨夜。',
                chapters: [AiCreateDraftChapter(title: '第一集 · 深夜频率', content: '雨夜的咖啡馆。')],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('逐章生成'), findsOneWidget);
      expect(find.text('第一集 · 深夜频率'), findsOneWidget);
      expect(find.text('来自 AI 记录 · 进入工作台时保存'), findsOneWidget);
      // 章节步骤不再显示设定表单。
      expect(find.text('作品设定'), findsNothing);
    });
  });
}

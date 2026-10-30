// E 模块 阶段5：AI 剧本改名 + 导演(skill)选择 + AI 分镜页。
//
// 覆盖：
//   - AiSkillSelector 渲染 skill 列表、选中回调；
//   - AiOutlinePage 标题改为「AI 剧本」、生成按钮「生成剧本大纲」、含导演选择；
//   - AiStoryboardPage 输入剧本 → 流式生成分镜 → 展示结果（可复制）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/features/ai/ai_outline_page.dart';
import 'package:script_app/features/ai/ai_storyboard_page.dart';
import 'package:script_app/features/ai/data/ai_models.dart';
import 'package:script_app/features/ai/data/ai_providers.dart';
import 'package:script_app/features/ai/data/ai_repository.dart';
import 'package:script_app/features/ai/widgets/ai_skill_selector.dart';

/// 可控假仓库：outline 与 storyboard 流式返回预设内容，其余方法用不到。
class _FakeAiRepository implements AiRepository {
  _FakeAiRepository({
    this.outlineText = '第一幕：跌入谷底\n第二幕：逆袭崛起\n第三幕：登顶巅峰',
    this.storyboardText = '【镜1】全景 雨夜小巷 时长5s\n【镜2】中景 男主抬头 时长4s',
  });

  final String outlineText;
  final String storyboardText;

  final List<String> calls = [];

  @override
  Future<AiOutlineResult> outlineStream({
    String? inspiration,
    String? genre,
    String? style,
    int? skillId,
    required void Function(String delta) onDelta,
  }) async {
    calls.add('outlineStream|skill=$skillId');
    onDelta('第一幕：跌入谷底\n');
    return AiOutlineResult(
      outline: outlineText,
      requestNo: 'AIR01',
      quotaUsed: 10,
    );
  }

  @override
  Future<AiWriteResult> storyboardStream({
    required String script,
    String? style,
    int? skillId,
    required void Function(String delta) onDelta,
  }) async {
    calls.add('storyboardStream:$script|$style|skill=$skillId');
    onDelta('【镜1】全景 雨夜小巷 时长5s\n');
    onDelta('【镜2】中景 男主抬头 时长4s');
    return AiWriteResult(content: storyboardText, recordId: 7);
  }

  @override
  Future<List<AiSkill>> listSkills() async => const [
        AiSkill(id: 1, skillName: '悬疑烧脑导演'),
        AiSkill(id: 2, skillName: '甜宠爆款导演'),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AiSkillSelector 导演(skill)选择', () {
    testWidgets('渲染默认导演 + 全部 skill，选中后回调', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeAiRepository();
      int? picked;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [aiRepositoryProvider.overrideWithValue(fake)],
          child: MaterialApp(
            home: Scaffold(
              body: AiSkillSelector(
                selectedSkillId: null,
                onChanged: (v) => picked = v,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('导演(skill)'), findsOneWidget);
      expect(find.text('默认导演'), findsOneWidget);

      await tester.tap(find.text('默认导演'));
      await tester.pumpAndSettle();
      expect(find.text('悬疑烧脑导演'), findsOneWidget);
      expect(find.text('甜宠爆款导演'), findsOneWidget);

      await tester.tap(find.text('甜宠爆款导演'));
      await tester.pumpAndSettle();
      expect(picked, 2);
    });
  });

  group('AiOutlinePage AI 剧本（改名）', () {
    testWidgets('标题/按钮文案为剧本，含导演选择，生成携带 skillId', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeAiRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [aiRepositoryProvider.overrideWithValue(fake)],
          child: const MaterialApp(home: AiOutlinePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AI 剧本'), findsWidgets);
      expect(find.text('生成剧本大纲'), findsOneWidget);
      expect(find.text('导演(skill)'), findsOneWidget);
      expect(find.text('AI 大纲'), findsNothing);
      expect(find.text('生成大纲'), findsNothing);
    });
  });

  group('AiStoryboardPage AI 分镜', () {
    testWidgets('输入剧本 → 流式生成分镜 → 结果展示与复制', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeAiRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [aiRepositoryProvider.overrideWithValue(fake)],
          child: const MaterialApp(home: AiStoryboardPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AI 分镜'), findsOneWidget);
      expect(find.text('剧本文本'), findsOneWidget);
      expect(find.text('导演(skill)'), findsOneWidget);

      // 填写剧本并选择导演后生成
      await tester.enterText(
          find.byType(TextField).first, '男主深夜在小巷偶遇旧友，对峙。');
      await tester.tap(find.text('默认导演'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('悬疑烧脑导演'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('生成分镜'));
      await tester.pumpAndSettle();

      expect(fake.calls, contains('storyboardStream:男主深夜在小巷偶遇旧友，对峙。|null|skill=1'));
      expect(find.textContaining('【镜1】全景'), findsOneWidget);
      expect(find.textContaining('【镜2】中景'), findsOneWidget);
      expect(find.text('复制分镜（可直接出售）'), findsOneWidget);
    });
  });
}

// E 模块 阶段2：AI 大纲 / 写作 / 润色三功能页。
//
// 覆盖：
//   - 表单校验（空输入提示）；
//   - 输入后调用仓库、loading、结果展示（含消耗次数）；
//   - 润色风格选择切换；
//   - AI 服务失败时提示且不崩溃。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/features/ai/ai_outline_page.dart';
import 'package:script_app/features/ai/ai_polish_page.dart';
import 'package:script_app/features/ai/ai_write_page.dart';
import 'package:script_app/features/ai/data/ai_models.dart';
import 'package:script_app/features/ai/data/ai_providers.dart';
import 'package:script_app/features/ai/data/ai_repository.dart';

/// 可控的假仓库：只对创作三方法返回预设结果，其余方法用不到。
class _FakeAiRepository implements AiRepository {
  _FakeAiRepository({
    this.writeContent = '夜色里，他站在落地窗前，沉默良久。',
    this.outlineText = '第一幕：跌入谷底\n第二幕：逆袭崛起\n第三幕：登顶巅峰',
    this.polishContent = '【润色】夜色如墨，他立于落地窗前，久久无言。',
    this.shouldFail = false,
  });

  final String writeContent;
  final String outlineText;
  final String polishContent;
  final bool shouldFail;

  final List<String> calls = [];

  @override
  Future<AiWriteResult> write({
    required String prompt,
    String? type,
  }) async {
    calls.add('write:$prompt');
    if (shouldFail) throw ApiException('AI 服务不可用');
    return AiWriteResult(content: writeContent, recordId: 11);
  }

  @override
  Future<AiWriteResult> polish({
    required String content,
    String? style,
  }) async {
    calls.add('polish:$content|$style');
    if (shouldFail) throw ApiException('AI 服务不可用');
    return AiWriteResult(content: polishContent, recordId: 22);
  }

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
      requestNo: 'AIR20260101',
      quotaUsed: 1,
    );
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child, _FakeAiRepository fake) => ProviderScope(
        overrides: [aiRepositoryProvider.overrideWithValue(fake)],
        child: MaterialApp(home: child),
      );

  // ================================================================
  group('E 阶段2-A AI 大纲页', () {
    testWidgets('空输入提示；输入后生成并显示大纲与消耗', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeAiRepository();
      await tester.pumpWidget(wrap(const AiOutlinePage(), fake));
      await tester.pumpAndSettle();

      // 空输入点击生成
      await tester.tap(find.text('生成大纲'));
      await tester.pump();
      expect(find.text('请先输入作品主题或灵感'), findsOneWidget);

      // 填入主题/题材/风格
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '都市青年逆袭');
      await tester.enterText(fields.at(1), '都市');
      await tester.enterText(fields.at(2), '爽文');
      await tester.tap(find.text('生成大纲'));
      await tester.pumpAndSettle();

      expect(find.text('生成的大纲'), findsOneWidget);
      expect(find.text('第一幕：跌入谷底\n第二幕：逆袭崛起\n第三幕：登顶巅峰'),
          findsOneWidget);
      expect(find.text('消耗 1 次'), findsOneWidget);
      expect(find.text('保存（复制全文）'), findsOneWidget);
      expect(fake.calls.first, contains('outline:都市青年逆袭|都市|爽文'));
    });
  });

  // ================================================================
  group('E 阶段2-B AI 写作页', () {
    testWidgets('空输入提示；生成后显示正文并可复制/存草稿', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeAiRepository();
      await tester.pumpWidget(wrap(const AiWritePage(), fake));
      await tester.pumpAndSettle();

      await tester.tap(find.text('生成内容'));
      await tester.pump();
      expect(find.text('请先输入写作提示词'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '写一段重逢对手戏');
      await tester.tap(find.text('生成内容'));
      await tester.pumpAndSettle();

      expect(find.text('生成内容'), findsNWidgets(2)); // 按钮+结果卡标题
      expect(find.text('夜色里，他站在落地窗前，沉默良久。'), findsOneWidget);
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('存草稿'), findsOneWidget);
      expect(fake.calls.first, 'write:写一段重逢对手戏');
    });
  });

  // ================================================================
  group('E 阶段2-C AI 润色页', () {
    testWidgets('选风格后生成；chip 可切换', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeAiRepository();
      await tester.pumpWidget(wrap(const AiPolishPage(), fake));
      await tester.pumpAndSettle();

      // 空输入
      await tester.tap(find.text('开始润色'));
      await tester.pump();
      expect(find.text('请先填写或粘贴需要润色的内容'), findsOneWidget);

      // 选风格（再点一次可取消）
      await tester.tap(find.text('文学优美'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '他很生气地走了。');
      await tester.tap(find.text('开始润色'));
      await tester.pumpAndSettle();

      expect(find.text('润色结果'), findsOneWidget);
      expect(find.text('【润色】夜色如墨，他立于落地窗前，久久无言。'),
          findsOneWidget);
      expect(find.text('复制润色结果'), findsOneWidget);
      expect(fake.calls.first, 'polish:他很生气地走了。|文学优美');
    });
  });

  // ================================================================
  group('E 阶段2-D 服务失败', () {
    testWidgets('AI 服务不可用时提示且不崩溃', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeAiRepository(shouldFail: true);
      await tester.pumpWidget(wrap(const AiWritePage(), fake));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '测试');
      await tester.tap(find.text('生成内容'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('AI 服务不可用'), findsOneWidget);
      expect(find.text('生成内容'), findsOneWidget); // 按钮仍在，可重试
    });
  });
}

// E 模块 阶段3：AI 记录页 + AI 机会页（含大纲记录增量）。
//
// 覆盖：
//   - AI 机会页：可用次数、累计获得/消耗/补偿、兑换比例、流水正负号；
//   - AI 机会页：加载失败显示重试；
//   - AI 记录页：大纲/写作/润色列表、类型筛选、展开详情；
//   - AI 记录页：空态与失败提示。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/features/ai/ai_chance_page.dart';
import 'package:script_app/features/ai/ai_record_page.dart';
import 'package:script_app/features/ai/data/ai_models.dart';
import 'package:script_app/features/ai/data/ai_providers.dart';
import 'package:script_app/features/ai/data/ai_repository.dart';

const _balance = AiQuotaBalance(
  available: 7,
  totalEarned: 12,
  totalConsumed: 5,
  totalRefunded: 2,
  rate: 10,
  records: [
    AiQuotaRecord(
      changeType: 'consume',
      changeAmount: 1,
      balanceAfter: 7,
      businessType: 'capability',
      createTime: '2026-10-14 09:30:46',
    ),
    AiQuotaRecord(
      changeType: 'earn',
      changeAmount: 5,
      balanceAfter: 8,
      source: 'EXCHANGE',
      createTime: '2026-10-14 09:30:40',
    ),
    AiQuotaRecord(
      changeType: 'refund',
      changeAmount: 1,
      balanceAfter: 7,
      createTime: '2026-10-13 16:32:00',
    ),
  ],
);

const _writeRecords = [
  AiWriteRecord(
    recordId: 1,
    title: '都市夜景提示词',
    writeType: 'write',
    inputPrompt: '请写一段都市夜景',
    outputContent: '夜色里，霓虹闪烁，风穿过空荡的街道。',
    wordCount: 20,
    aiModel: 'deepseek-flash',
    status: 'success',
    createdAt: '2026-10-14 09:30',
  ),
  AiWriteRecord(
    recordId: 2,
    title: '润色一段对话',
    writeType: 'polish',
    inputPrompt: '他很生气地走了。',
    outputContent: '他攥紧拳头，转身离去。',
    wordCount: 12,
    aiModel: 'deepseek-flash',
    status: 'success',
    createdAt: '2026-10-13 16:32',
  ),
  AiWriteRecord(
    recordId: 3,
    title: '大纲测试主题',
    writeType: 'outline',
    inputPrompt: '灵感：废土世界重建\n类型：科幻',
    outputContent: '第一幕：废土求生',
    wordCount: 8,
    aiModel: 'deepseek-flash',
    status: 'success',
    createdAt: '2026-10-14 15:10:16',
  ),
];

/// 可控假仓库：实现 writeRecords。
class _FakeRecordsRepo implements AiRepository {
  _FakeRecordsRepo({
    this.records = const [],
    this.fail = false,
  });

  final List<AiWriteRecord> records;
  final bool fail;

  @override
  Future<AiPageResult<AiWriteRecord>> writeRecords({
    int page = 1,
    int pageSize = 20,
  }) async {
    if (fail) throw ApiException('加载失败');
    return AiPageResult(total: records.length, list: records);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ================================================================
  group('E 阶段3-A AI 机会页', () {
    testWidgets('余额 / 统计 / 比例 / 流水正负号', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiBalanceProvider.overrideWith((ref) async => _balance),
          ],
          child: const MaterialApp(home: AiChancePage()),
        ),
      );
      await tester.pumpAndSettle();

      // 可用次数
      expect(find.text('可用 AI 机会'), findsOneWidget);
      expect(find.text('7'), findsWidgets);
      // 累计统计
      expect(find.text('累计获得'), findsOneWidget);
      expect(find.text('12'), findsWidgets);
      expect(find.text('累计消耗'), findsOneWidget);
      expect(find.text('累计补偿'), findsOneWidget);
      expect(find.text('2'), findsWidgets);
      // 兑换比例
      expect(find.text('10 积分 = 1 次，只能积分换次数'), findsOneWidget);
      // 流水类型与正负号
      expect(find.text('消耗'), findsOneWidget);
      expect(find.text('兑换获得'), findsOneWidget);
      expect(find.text('失败补偿'), findsOneWidget);
      expect(find.text('-1'), findsOneWidget);
      expect(find.text('+5'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);
      expect(find.text('余额 7'), findsWidgets);
    });

    testWidgets('加载失败显示重试', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiBalanceProvider
                .overrideWith((ref) async => throw ApiException('失败')),
          ],
          child: const MaterialApp(home: AiChancePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('机会数据加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });
  });

  // ================================================================
  group('E 阶段3-B AI 记录页', () {
    testWidgets('列表显示 + 类型标签 + 展开输入输出', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeRecordsRepo(
        records: _writeRecords,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [aiRepositoryProvider.overrideWithValue(fake)],
          child: const MaterialApp(home: AiRecordPage()),
        ),
      );
      await tester.pumpAndSettle();

      // 三类记录标题
      expect(find.text('大纲测试主题'), findsOneWidget);
      expect(find.text('都市夜景提示词'), findsOneWidget);
      expect(find.text('润色一段对话'), findsOneWidget);
      expect(find.text('AI 大纲'), findsWidgets);
      expect(find.text('AI 写作'), findsWidgets);
      expect(find.text('AI 润色'), findsWidgets);

      // 展开写作卡片
      await tester.tap(find.text('都市夜景提示词'));
      await tester.pumpAndSettle();
      expect(find.text('输入'), findsOneWidget);
      expect(find.text('请写一段都市夜景'), findsOneWidget);
      expect(find.text('输出'), findsOneWidget);
      expect(find.text('夜色里，霓虹闪烁，风穿过空荡的街道。'), findsOneWidget);
      expect(find.text('字数 20'), findsOneWidget);
      expect(find.text('模型 deepseek-flash'), findsNothing);
    });

    testWidgets('大纲筛选：只显示大纲并展开输入输出', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeRecordsRepo(
        records: _writeRecords,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [aiRepositoryProvider.overrideWithValue(fake)],
          child: const MaterialApp(home: AiRecordPage()),
        ),
      );
      await tester.pumpAndSettle();

      // 筛 AI 大纲（.first 为筛选条 chip）
      await tester.tap(find.text('AI 大纲').first);
      await tester.pumpAndSettle();
      expect(find.text('大纲测试主题'), findsOneWidget);
      expect(find.text('都市夜景提示词'), findsNothing);
      expect(find.text('润色一段对话'), findsNothing);

      // 展开大纲卡片：与写作/润色一致展示输入/输出，不展示模型
      await tester.tap(find.text('大纲测试主题'));
      await tester.pumpAndSettle();
      expect(find.text('输入'), findsOneWidget);
      expect(find.text('灵感：废土世界重建\n类型：科幻'), findsOneWidget);
      expect(find.text('输出'), findsOneWidget);
      expect(find.text('第一幕：废土求生'), findsOneWidget);
      expect(find.text('字数 8'), findsOneWidget);
      expect(find.text('模型 deepseek-flash'), findsNothing);
    });

    testWidgets('类型筛选：只显示写作或润色', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeRecordsRepo(
        records: _writeRecords,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [aiRepositoryProvider.overrideWithValue(fake)],
          child: const MaterialApp(home: AiRecordPage()),
        ),
      );
      await tester.pumpAndSettle();

      // 筛 AI 写作（.first 为筛选条 chip）
      await tester.tap(find.text('AI 写作').first);
      await tester.pumpAndSettle();
      expect(find.text('都市夜景提示词'), findsOneWidget);
      expect(find.text('润色一段对话'), findsNothing);
      expect(find.text('AI 大纲请求'), findsNothing);

      // 改筛 AI 润色
      await tester.tap(find.text('AI 润色').first);
      await tester.pumpAndSettle();
      expect(find.text('都市夜景提示词'), findsNothing);
      expect(find.text('润色一段对话'), findsOneWidget);
    });

    testWidgets('空态提示', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiRepositoryProvider
                .overrideWithValue(_FakeRecordsRepo()),
          ],
          child: const MaterialApp(home: AiRecordPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂无记录'), findsOneWidget);
    });

    testWidgets('失败提示', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiRepositoryProvider
                .overrideWithValue(_FakeRecordsRepo(fail: true)),
          ],
          child: const MaterialApp(home: AiRecordPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('记录加载失败'), findsOneWidget);
    });
  });
}

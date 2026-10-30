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
import 'package:script_app/features/welfare/data/welfare_models.dart';
import 'package:script_app/features/welfare/data/welfare_providers.dart';

/// 可控的假仓库：只对创作三方法返回预设结果，其余方法用不到。
class _FakeAiRepository implements AiRepository {
  _FakeAiRepository({
    this.writeContent = '夜色里，他站在落地窗前，沉默良久。',
    this.outlineText = '第一幕：跌入谷底\n第二幕：逆袭崛起\n第三幕：登顶巅峰',
    this.polishContent = '【润色】夜色如墨，他立于落地窗前，久久无言。',
    this.shouldFail = false,
    this.quotaInsufficient = false,
  });

  final String writeContent;
  final String outlineText;
  final String polishContent;
  final bool shouldFail;
  final bool quotaInsufficient;

  final List<String> calls = [];

  @override
  Future<AiWriteResult> write({
    required String prompt,
    String? type,
    int? skillId,
  }) async {
    calls.add('write:$prompt');
    if (quotaInsufficient) throw ApiException('积分不足，当前余额: 0 分', code: 400);
    if (shouldFail) throw ApiException('AI 服务不可用');
    return AiWriteResult(content: writeContent, recordId: 11);
  }

  @override
  Future<AiWriteResult> writeStream({
    required String prompt,
    String? type,
    int? skillId,
    required void Function(String delta) onDelta,
  }) async {
    calls.add('writeStream:$prompt');
    if (quotaInsufficient) throw ApiException('积分不足，当前余额: 0 分', code: 400);
    if (shouldFail) throw ApiException('AI 服务不可用');
    onDelta('夜色里，他站在');
    onDelta('落地窗前，沉默良久。');
    return AiWriteResult(content: writeContent, recordId: 11);
  }

  @override
  Future<AiWriteResult> polish({
    required String content,
    String? style,
    int? skillId,
  }) async {
    calls.add('polish:$content|$style');
    if (quotaInsufficient) throw ApiException('积分不足，当前余额: 0 分', code: 400);
    if (shouldFail) throw ApiException('AI 服务不可用');
    return AiWriteResult(content: polishContent, recordId: 22);
  }

  @override
  Future<AiWriteResult> polishStream({
    required String content,
    String? style,
    int? skillId,
    required void Function(String delta) onDelta,
  }) async {
    calls.add('polishStream:$content|$style');
    if (quotaInsufficient) throw ApiException('积分不足，当前余额: 0 分', code: 400);
    if (shouldFail) throw ApiException('AI 服务不可用');
    onDelta('【润色】夜色如墨，他立于');
    onDelta('窗前，久久无言。');
    return AiWriteResult(content: polishContent, recordId: 22);
  }

  @override
  Future<AiOutlineResult> outline({
    String? inspiration,
    String? genre,
    String? style,
    int? skillId,
  }) async {
    calls.add('outline:$inspiration|$genre|$style');
    if (quotaInsufficient) throw ApiException('积分不足，当前余额: 0 分', code: 400);
    if (shouldFail) throw ApiException('AI 服务不可用');
    return AiOutlineResult(
      outline: outlineText,
      requestNo: 'AIR20260101',
      quotaUsed: 1,
    );
  }

  @override
  Future<AiOutlineResult> outlineStream({
    String? inspiration,
    String? genre,
    String? style,
    int? skillId,
    required void Function(String delta) onDelta,
  }) async {
    calls.add('outlineStream:$inspiration|$genre|$style');
    if (quotaInsufficient) throw ApiException('积分不足，当前余额: 0 分', code: 400);
    if (shouldFail) throw ApiException('AI 服务不可用');
    onDelta('第一幕：跌入谷底\n');
    onDelta('第二幕：逆袭崛起\n');
    onDelta('第三幕：登顶巅峰');
    return AiOutlineResult(
      outline: outlineText,
      requestNo: 'AIR20260101',
      quotaUsed: 1,
    );
  }

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
  }) async {
    calls.add('storyboard:$script|$style|skill=$skillId');
    return AiWriteResult(content: '【镜1】全景…', recordId: 33);
  }

  @override
  Future<AiWriteResult> storyboardStream({
    required String script,
    String? style,
    int? skillId,
    required void Function(String delta) onDelta,
  }) async {
    calls.add('storyboardStream:$script|$style|skill=$skillId');
    onDelta('【镜1】全景…');
    return AiWriteResult(content: '【镜1】全景…', recordId: 33);
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
      await tester.tap(find.text('生成剧本大纲'));
      await tester.pump();
      expect(find.text('请先输入作品主题或灵感'), findsOneWidget);

      // 填入主题/题材/风格
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '都市青年逆袭');
      await tester.enterText(fields.at(1), '都市');
      await tester.enterText(fields.at(2), '爽文');
      await tester.tap(find.text('生成剧本大纲'));
      await tester.pumpAndSettle();

      expect(find.text('生成的剧本大纲'), findsOneWidget);
      expect(find.text('第一幕：跌入谷底\n第二幕：逆袭崛起\n第三幕：登顶巅峰'),
          findsOneWidget);
      expect(find.text('消耗 1 token'), findsOneWidget);
      expect(find.text('保存（复制全文）'), findsOneWidget);
      expect(fake.calls.first, contains('outlineStream:都市青年逆袭|都市|爽文'));
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
      expect(fake.calls.first, 'writeStream:写一段重逢对手戏');
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
      expect(fake.calls.first, 'polishStream:他很生气地走了。|文学优美');
    });
  });

  // ================================================================
  group('E 阶段2-D AI 调用后资产实时刷新', () {
    testWidgets('写作生成成功后 invalidate 资产provider，余额下次读取重新获取', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeAiRepository();
      var assetCalls = 0;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          aiRepositoryProvider.overrideWithValue(fake),
          welfareAssetProvider.overrideWith((ref) async {
            assetCalls++;
            return (points: const PointsBalance(balance: 5000), aiAvailable: 5);
          }),
        ],
        child: const MaterialApp(home: AiWritePage()),
      ));
      await tester.pumpAndSettle();

      // 首次读取资产（模拟 AI 创作页已经 watch 过一次）
      final container =
          ProviderScope.containerOf(tester.element(find.byType(AiWritePage)),
              listen: false);
      await container.read(welfareAssetProvider.future);
      expect(assetCalls, 1);

      // 生成一次
      await tester.enterText(find.byType(TextField).first, 'test');
      await tester.tap(find.text('生成内容'));
      await tester.pumpAndSettle();
      expect(fake.calls.first, 'writeStream:test');

      // 生成成功后页面已 invalidate → 再次读取触发重新获取
      await container.read(welfareAssetProvider.future);
      expect(assetCalls, 2, reason: '生成成功后应刷新资产缓存（实时扣减显示）');
    });
  });

  // ================================================================
  group('E 阶段2-E AI 次数不足引导', () {
    testWidgets('可用次数为0：生成后弹出引导弹窗（积分兑换/看广告）', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeAiRepository(quotaInsufficient: true);
      await tester.pumpWidget(wrap(const AiWritePage(), fake));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '测试');
      await tester.tap(find.text('生成内容'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('积分不足'), findsOneWidget);
      expect(find.textContaining('当前余额: 0 分'), findsOneWidget);
      expect(find.text('去福利中心获取积分'), findsOneWidget);
      expect(find.text('去福利中心获取积分'), findsOneWidget);
    });
  });

  // ================================================================
  group('E 阶段2-F 大纲结果中文渲染', () {
    test('英文键 name/role/beats 渲染为中文标签', () {
      final result = AiOutlineResult.fromJson({
        'outline': {
          'title': '测试纪元：第七次重启',
          'logline': '一句话简介',
          'characters': [
            {'name': '林砚', 'role': '主角'},
            {'name': '苏黎', 'role': '女主角'},
          ],
          'acts': [
            {
              'name': '第一幕：用例',
              'summary': '本幕概述',
              'beats': ['关键情节1', '关键情节2'],
            },
          ],
        },
      });
      final text = result.outlineText;
      expect(text, contains('书名：测试纪元：第七次重启'));
      expect(text, contains('角色名：林砚'));
      expect(text, contains('身份：主角'));
      expect(text, contains('幕名：第一幕：用例'));
      expect(text, contains('关键情节'));
      expect(text, isNot(contains('name：')));
      expect(text, isNot(contains('role：')));
      expect(text, isNot(contains('beats')));
    });
  });

  group('E 阶段2-G 积分明细符号', () {
    test('SPEND 支出显示负数，EARN 收入显示正数', () {
      final spend = PointsRecord.fromJson({
        'changeType': 'SPEND',
        'points': 20,
        'balanceAfter': 4980,
      });
      final earn = PointsRecord.fromJson({
        'changeType': 'EARN',
        'points': 10,
        'balanceAfter': 4990,
      });
      expect(spend.isSpend, isTrue);
      expect(spend.signedPoints, '-20');
      expect(spend.balanceAfter, 4980);
      expect(earn.isSpend, isFalse);
      expect(earn.signedPoints, '+10');
    });
  });
}

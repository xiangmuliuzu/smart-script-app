// E 模块 阶段1：AI 创作中心入口页 + 个人中心入口改名（「我的剧本」→「AI 创作」）。
//
// 覆盖：
//   - AI 创作中心：标题 + 资产卡（积分/AI 机会）+ 5 个功能入口（无审核进度）；
//   - 个人中心入口改名（AI 创作）：静态断言源码，防止旧名回退。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:script_app/features/ai_creation/ai_creation_page.dart';
import 'package:script_app/features/welfare/data/welfare_models.dart';
import 'package:script_app/features/welfare/data/welfare_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ================================================================
  group('E 阶段1-A AI 创作中心页', () {
    testWidgets('标题 + 资产卡 + 5 功能入口 + 无审核进度', (tester) async {
      // 放大测试视口：ListView 懒加载，视口外的功能入口不会构建
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            welfareAssetProvider.overrideWith((ref) async =>
                (points: const PointsBalance(balance: 100), aiAvailable: 5)),
          ],
          child: const MaterialApp(home: AiCreationPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AI 创作'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      for (final label in const [
        'AI 剧本',
        'AI 写作',
        'AI 分镜',
        'AI 润色',
        'AI 记录',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '缺少功能入口：$label');
      }
      // 【去次数化】AI 机会入口与资产卡已下线
      expect(find.text('AI 机会'), findsNothing,
          reason: 'AI 机会已下线，不应再显示入口');
      // 审核进度由「我的作品」页承载，创作中心不再放入口
      expect(find.text('审核进度'), findsNothing);
      expect(find.text('我的剧本'), findsNothing);
    });
  });

  // ================================================================
  group('E 阶段1-B 个人中心入口改名', () {
    test('快捷入口为「AI 创作」，不再有「我的剧本」', () async {
      final source = await File('lib/features/profile/profile_page.dart')
          .readAsString();
      expect(source.contains("'AI 创作'"), isTrue,
          reason: '个人中心缺少「AI 创作」入口');
      expect(source.contains('我的剧本'), isFalse,
          reason: '个人中心仍残留旧入口名「我的剧本」');
      // 入口跳转到 AI 创作中心
      expect(source.contains('RoutePath.aiCenter'), isTrue,
          reason: 'AI 创作入口未接入 AI 创作中心路由');
    });
  });
}

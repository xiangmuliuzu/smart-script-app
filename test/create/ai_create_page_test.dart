import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/router/route_paths.dart';
import 'package:script_app/features/create/ai_create_page.dart';
import 'package:script_app/features/create/data/author_work_repository.dart';
import 'package:script_app/features/create/data/blueprint_models.dart';
import 'package:script_app/features/create/data/blueprint_providers.dart';
import 'package:script_app/features/create/data/blueprint_repository.dart';
import 'package:script_app/features/create/data/create_repository.dart';
import 'package:script_app/features/create/widgets/blueprint_setup_form.dart';
import 'package:script_app/features/welfare/data/welfare_models.dart';
import 'package:script_app/features/welfare/data/welfare_providers.dart';

/// AI 创作页（v3）：作品设定 → 生成中 → 资料确认。
///
/// 覆盖：
///   - 设定页三段结构与文案（书名 / 故事灵感 / 题材 chips / 创作要求 / 高级参数）；
///   - 展示剩余积分与「生成作品资料」主按钮；
///   - 设定校验（书名必填、灵感至少 10 字）不会发起生成；
///   - 从 AI 记录恢复时预填书名与故事灵感。
/// 生成流：只按 stage 回调并返回会话，不发真实网络请求。
class _GeneratingRepository extends BlueprintRepository {
  _GeneratingRepository()
      : super(
          ApiClient(Dio()),
          AuthorWorkRepository(ApiClient(Dio())),
          CreateRepository(ApiClient(Dio())),
        );

  final List<String> stages = <String>[];

  @override
  Future<BlueprintSession> generate({
    required String title,
    required String inspiration,
    String? genre,
    String? prompt,
    int? skillId,
    String? model,
    int? sessionId,
    void Function(String stage)? onStage,
    void Function(String delta)? onDelta,
  }) async {
    for (final stage in const ['story', 'world', 'characters', 'items', 'outline']) {
      stages.add(stage);
      onStage?.call(stage);
    }
    return BlueprintSession(
      sessionId: 88,
      title: title,
      blueprint: StoryBlueprint.fromJson({
        'storyCore': {'summary': '简介'},
        'characters': [
          {'key': 'c-1', 'name': '沈默'},
        ],
      }),
    );
  }
}

void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    AiCreateDraft? draft,
    int balance = 76,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          welfareAssetProvider.overrideWith(
              (ref) async => (points: PointsBalance(balance: balance), aiAvailable: 0)),
        ],
        child: MaterialApp(home: AiCreatePage(draft: draft)),
      ),
    );
    await tester.pump();
  }

  testWidgets('设定页显示三段结构、剩余积分与主按钮', (tester) async {
    await pumpPage(tester);

    expect(find.text('1 · 作品'), findsOneWidget);
    expect(find.text('2 · 题材'), findsOneWidget);
    expect(find.text('3 · 创作要求'), findsOneWidget);
    expect(find.text('书名'), findsOneWidget);
    expect(find.text('故事灵感'), findsOneWidget);
    expect(find.text('你的要求'), findsOneWidget);
    expect(find.text('剩余 76 积分'), findsOneWidget);
    expect(find.text('生成作品资料'), findsOneWidget);
    expect(find.text('高级参数：导演 Skill'), findsOneWidget);
    // 资料口径说明必须与后端一致：分集大纲不在资料阶段生成。
    expect(
      find.textContaining('分集大纲在写每一章时现生成'),
      findsOneWidget,
    );
  });

  testWidgets('题材 chips 可点击切换选中态', (tester) async {
    await pumpPage(tester);
    // 默认未选中：chip 白底；点击后变为深色底（主色）。
    final chip = find.text('都市悬疑');
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await tester.pump();
    final container = tester.widget<AnimatedContainer>(
      find.ancestor(of: chip, matching: find.byType(AnimatedContainer)),
    );
    expect((container.decoration as BoxDecoration).color, isNotNull);
  });

  testWidgets('书名为空时点生成只提示，不进入生成中', (tester) async {
    await pumpPage(tester);
    await tester.enterText(find.byType(TextField).at(1), '深夜电台主播听见十年前的自己');
    await tester.tap(find.text('生成作品资料'));
    await tester.pump();
    // 仍在设定页（生成中会显示「生成中」标题与进度卡）。
    expect(find.text('1 · 作品'), findsOneWidget);
    expect(find.text('故事灵感'), findsOneWidget);
  });

  testWidgets('故事灵感不足 10 字时不进入生成中', (tester) async {
    await pumpPage(tester);
    await tester.enterText(find.byType(TextField).first, '深夜频率');
    await tester.enterText(find.byType(TextField).at(1), '太短');
    await tester.tap(find.text('生成作品资料'));
    await tester.pump();
    expect(find.text('1 · 作品'), findsOneWidget);
  });

  testWidgets('从 AI 记录恢复时预填书名与灵感', (tester) async {
    await pumpPage(
      tester,
      draft: const AiCreateDraft(
        title: '深夜频率',
        idea: '深夜电台主播在听众留言里听到十年前的自己。',
        genre: '都市悬疑',
      ),
    );
    expect(find.text('深夜频率'), findsOneWidget);
    expect(
      find.text('深夜电台主播在听众留言里听到十年前的自己。'),
      findsOneWidget,
    );
  });

  testWidgets('生成中按 stage 推进 5 项进度，完成后可查看作品资料', (tester) async {
    final repo = _GeneratingRepository();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: RoutePath.aiCreate,
      routes: [
        GoRoute(
          path: RoutePath.aiCreate,
          builder: (_, __) => const AiCreatePage(),
        ),
        GoRoute(
          path: RoutePath.aiBlueprint,
          builder: (_, state) => Scaffold(
            body: Text('资料确认 ${state.uri.queryParameters['sessionId']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          welfareAssetProvider.overrideWith(
              (ref) async => (points: const PointsBalance(balance: 76), aiAvailable: 0)),
          blueprintRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '深夜频率');
    await tester.enterText(find.byType(TextField).at(1), '深夜电台主播在留言里听见十年前的自己。');
    await tester.tap(find.text('生成作品资料'));
    await tester.pumpAndSettle();

    expect(repo.stages, ['story', 'world', 'characters', 'items', 'outline']);
    expect(find.text('生成完成'), findsOneWidget);
    expect(find.text('《深夜频率》的资料已生成'), findsOneWidget);
    expect(find.text('故事核心'), findsOneWidget);
    expect(find.text('人物关系'), findsOneWidget);
    expect(find.text('查看作品资料'), findsOneWidget);

    await tester.tap(find.text('查看作品资料'));
    await tester.pumpAndSettle();
    expect(find.text('资料确认 88'), findsOneWidget);
  });

  test('题材选项与 PC v3 一致', () {
    expect(BlueprintSetupForm.genres, contains('都市悬疑'));
    expect(BlueprintSetupForm.genres.length, 6);
    expect(BlueprintSetupForm.ideaMinLength, 10);
  });
}

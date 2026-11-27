// 作品资料页（资料确认 + 作品资料）：区块渲染、编辑落台账、确认建作品。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:script_app/core/router/route_paths.dart';
import 'package:script_app/features/create/pages/blueprint_page.dart';
import 'package:script_app/features/create/pages/character_profile_page.dart';

import '../support/scripted_api.dart';

const _blueprint = {
  'status': 'draft',
  'storyCore': {
    'logline': '深夜主播听见十年前的自己。',
    'summary': '凌晨三点，城市电台只剩主播沈默一个人。',
    'coreConflict': '他在场。',
    'narrativeStyle': '冷峻',
    'contentBoundary': '不出现血腥',
    'endingTone': '释然',
  },
  'world': {
    'setting': '同一座城市、同一个频率。',
    'rules': [
      {'name': '直播规则', 'detail': '只有直播中的声音能被听见。'}
    ],
    'constraints': ['每条留言只出现一次'],
  },
  'outline': {
    'mainline': '追查留言来源',
    'acts': <Object>[],
    'endingHanger': '母带背面的字',
  },
  'characters': [
    {'key': 'c-1', 'name': '沈默', 'role': '主播', 'age': '34', 'gender': '男'},
    {'key': 'c-2', 'name': '林知夏', 'role': '录音师'},
  ],
  'items': [
    {
      'key': 'i-1',
      'name': '开盘母带',
      'icon': 'tape',
      'desc': '十年前的节目母带。',
      'owner': '沈默',
      'count': '1',
      'state': '被带走',
    }
  ],
  'relations': [
    {'a': 'c-1', 'b': 'c-2', 'label': '旧同事', 'dash': false},
  ],
  'planEpisodes': 12,
  'minutesPerEpisode': 2,
};

Envelope _session({bool confirmed = false, int workId = 0}) => Envelope.ok({
      'sessionId': 88,
      'status': confirmed ? 'confirmed' : 'draft',
      'title': '深夜频率',
      if (workId > 0) 'workId': workId,
      'updatedAt': '2026-11-27 10:00:00',
      'blueprint': {..._blueprint, 'status': confirmed ? 'confirmed' : 'draft'},
    });

Envelope _workDetail() => Envelope.ok({
      'work': {
        'workId': 7,
        'title': '深夜频率',
        'summary': '凌晨三点，城市电台只剩主播沈默一个人。',
        'status': 'draft',
      },
      'tags': <Object>[],
      'chapters': [
        {
          'chapterId': 55,
          'chapterNo': 1,
          'chapterTitle': '无人接听',
          'content': '',
          'summary': '凌晨三点，沈默照常开播。',
          'status': '1',
          'isFree': '0',
        }
      ],
      'latestReview': null,
      'shelfStatus': 'off_shelf',
    });

Future<void> _pump(
  WidgetTester tester,
  ScriptedApi api,
  Widget page, {
  double height = 844,
}) async {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [api.override],
      child: MaterialApp(home: page),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets('资料确认页按原型顺序展示六个区块', (tester) async {
    final api = ScriptedApi();
    api.reply('/content/ai/blueprint/88', _session());
    await _pump(tester, api,
        const BlueprintPage(sessionId: 88, isConfirmation: true),
        height: 2200);
    await tester.pumpAndSettle();

    expect(find.text('资料确认'), findsOneWidget);
    expect(find.text('深夜频率'), findsWidgets);
    expect(find.text('故事核心'), findsOneWidget);
    expect(find.text('世界与规则'), findsOneWidget);
    expect(find.text('主要人物 · 2 位'), findsOneWidget);
    expect(find.text('人物关系'), findsOneWidget);
    expect(find.text('关键物品 · 1 件'), findsOneWidget);
    // 关键物品行与人物卡来自真实资料。
    expect(find.text('开盘母带'), findsOneWidget);
    expect(find.text('沈默'), findsWidgets);
    expect(find.text('林知夏'), findsWidgets);
    expect(find.text('确认，开始创作'), findsOneWidget);
  });

  testWidgets('人物卡可跳人物档案页', (tester) async {
    final api = ScriptedApi();
    api.reply('/content/ai/blueprint/88', _session(confirmed: true, workId: 7));
    api.reply('/users/me/works/7', _workDetail());
    api.reply('/content/works/7/ledger', Envelope.ok(<String, Object>{}));
    api.reply('/content/works/7/chapter-meta', Envelope.ok(<String, Object>{}));
    api.reply('/content/works/7/blueprint', _session(confirmed: true, workId: 7));
    final router = GoRouter(
      initialLocation: '/bp',
      routes: [
        GoRoute(
          path: '/bp',
          builder: (_, __) => const BlueprintPage(workId: 7),
        ),
        GoRoute(
          path: RoutePath.blueprintCharacter,
          builder: (_, state) => CharacterProfilePage(
            workId: int.tryParse(state.uri.queryParameters['workId'] ?? '') ?? 0,
            characterKey: state.uri.queryParameters['key'] ?? '',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(390, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [api.override],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('沈默').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('沈默').first);
    await tester.pumpAndSettle();
    expect(find.byType(CharacterProfilePage), findsOneWidget);
    expect(find.text('人物档案'), findsOneWidget);
    expect(find.text('三视图'), findsOneWidget);
    expect(find.text('人物信息'), findsOneWidget);
  });


  testWidgets('资料确认阶段（workId=0）人物卡可打开只读人物档案', (tester) async {
    final api = ScriptedApi();
    api.reply('/content/ai/blueprint/88', _session());
    final router = GoRouter(
      initialLocation: '/bp',
      routes: [
        GoRoute(
          path: '/bp',
          builder: (_, __) =>
              const BlueprintPage(sessionId: 88, isConfirmation: true),
        ),
        GoRoute(
          path: RoutePath.blueprintCharacter,
          builder: (_, state) => CharacterProfilePage(
            workId:
                int.tryParse(state.uri.queryParameters['workId'] ?? '') ?? 0,
            sessionId:
                int.tryParse(state.uri.queryParameters['sessionId'] ?? '') ?? 0,
            characterKey: state.uri.queryParameters['key'] ?? '',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(390, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [api.override],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('沈默').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('沈默').first);
    await tester.pumpAndSettle();

    expect(find.byType(CharacterProfilePage), findsOneWidget);
    expect(find.text('人物档案'), findsOneWidget);
    expect(find.text('三视图'), findsOneWidget);
    expect(find.text('人物信息'), findsOneWidget);
    // 确认前只读：不出现「编辑」按钮，并给出说明。
    expect(find.text('编辑'), findsNothing);
    expect(find.textContaining('资料确认前只读'), findsOneWidget);
  });

  testWidgets('资料确认阶段「全部」人物列表也能打开档案', (tester) async {
    final api = ScriptedApi();
    api.reply('/content/ai/blueprint/88', _session());
    final router = GoRouter(
      initialLocation: '/bp',
      routes: [
        GoRoute(
          path: '/bp',
          builder: (_, __) =>
              const BlueprintPage(sessionId: 88, isConfirmation: true),
        ),
        GoRoute(
          path: RoutePath.blueprintCharacter,
          builder: (_, state) => CharacterProfilePage(
            workId:
                int.tryParse(state.uri.queryParameters['workId'] ?? '') ?? 0,
            sessionId:
                int.tryParse(state.uri.queryParameters['sessionId'] ?? '') ?? 0,
            characterKey: state.uri.queryParameters['key'] ?? '',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(390, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [api.override],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    // 底部人物列表出现后选第二位。
    await tester.tap(find.text('林知夏').last);
    await tester.pumpAndSettle();

    expect(find.byType(CharacterProfilePage), findsOneWidget);
    expect(find.text('录音师'), findsWidgets);
    expect(find.text('编辑'), findsNothing);
  });

  testWidgets('关系图节点在确认阶段也可点开人物档案', (tester) async {
    final api = ScriptedApi();
    api.reply('/content/ai/blueprint/88', _session());
    final router = GoRouter(
      initialLocation: '/bp',
      routes: [
        GoRoute(
          path: '/bp',
          builder: (_, __) =>
              const BlueprintPage(sessionId: 88, isConfirmation: true),
        ),
        GoRoute(
          path: RoutePath.blueprintCharacter,
          builder: (_, state) => CharacterProfilePage(
            sessionId:
                int.tryParse(state.uri.queryParameters['sessionId'] ?? '') ?? 0,
            characterKey: state.uri.queryParameters['key'] ?? '',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [api.override],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    // 关系图里的节点名带有白底标签，取最后一个「沈默」节点点击。
    final nodes = find.text('沈默');
    await tester.ensureVisible(nodes.last);
    await tester.pumpAndSettle();
    await tester.tap(nodes.last);
    await tester.pumpAndSettle();
    expect(find.byType(CharacterProfilePage), findsOneWidget);
  });

  testWidgets('编辑故事核心：保存后写台账（与 PC 共用一份）', (tester) async {
    final api = ScriptedApi();
    api.reply('/users/me/works/7', _workDetail());
    api.reply('/content/works/7/chapter-meta', Envelope.ok(<String, Object>{}));
    api.reply('/content/works/7/blueprint', _session(confirmed: true, workId: 7));
    api.reply('/content/works/7/ledger', Envelope.ok({
      'storySummary': '凌晨三点，城市电台只剩主播沈默一个人。',
      'characters': '沈默（34/男）：主播',
      'relations': '沈默 ↔ 林知夏：旧同事',
      'props': '开盘母带｜1｜沈默｜被带走｜十年前的节目母带。',
      'items': '开盘母带：被带走',
      'outline': '故事主线：追查留言来源',
      'stateBoard': '计划集数=12 集；单集时长=2 分钟。',
    }));
    api.handle('/content/works/7/ledger',
        (options) => options.method == 'PUT' ? Envelope.ok(null) : Envelope.ok({
              'storySummary': '凌晨三点，城市电台只剩主播沈默一个人。',
            }));
    await _pump(tester, api, const BlueprintPage(workId: 7), height: 2200);
    await tester.pumpAndSettle();

    // 故事核心卡右上角「编辑」。
    await tester.tap(find.text('编辑').first);
    await tester.pumpAndSettle();
    expect(find.text('编辑故事核心'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '作者改过的故事简介。');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final put = api.requests.singleWhere(
        (r) => r.method == 'PUT' && r.path.contains('/ledger'));
    expect((put.data as Map)['storySummary'], '作者改过的故事简介。');
    // 其它台账字段整份写回，避免把未改动的段落清空。
    expect((put.data as Map)['characters'], contains('沈默'));
    expect((put.data as Map)['props'], contains('开盘母带'));
  });

  testWidgets('确认资料：创建作品并进入作品工作台', (tester) async {
    final api = ScriptedApi();
    api.reply('/content/ai/blueprint/88', _session());
    api.reply('/content/ai/blueprint/88/confirm', Envelope.ok({'workId': 21}));
    final router = GoRouter(
      initialLocation: '/bp',
      routes: [
        GoRoute(
          path: '/bp',
          builder: (_, __) => const BlueprintPage(sessionId: 88, isConfirmation: true),
        ),
        GoRoute(
          path: RoutePath.workWorkspace,
          builder: (_, state) => Scaffold(
            body: Text('工作台 ${state.uri.queryParameters['id']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [api.override],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    await tester.tap(find.text('确认，开始创作'));
    await tester.pumpAndSettle();

    final post = api.requests
        .singleWhere((r) => r.path.contains('/blueprint/88/confirm'));
    expect(post.method, 'POST');
    expect(find.text('工作台 21'), findsOneWidget);
  });
}

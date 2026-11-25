import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/router/route_paths.dart';
import 'package:script_app/features/bookstore/widgets/bookstore_widgets.dart';
import 'package:script_app/features/sourcing_agent/sourcing_agent_page.dart';
import 'package:script_app/features/sourcing_agent/sourcing_agent_repository.dart';

const _work = {
  'workId': 18,
  'title': '雾港回声',
  'cover': '',
  'authorName': '测试作者',
  'episodeCount': 60,
  'wordCount': 62000,
  'rating': 9.2,
  'price': 32000,
  'budgetMatch': true,
  'canInquire': true,
  'copyrightRegistrationStatus': 'registered',
  'exclusiveStatus': '待核实',
  'tags': ['悬疑', '反转'],
  'summary': '高能悬疑反转短剧，节奏紧凑。',
};
const _brief = {
  'title': '古装权谋定制短剧',
  'taskType': 'script_storyboard',
  'genreTags': ['古装', '权谋'],
  'totalEpisodes': 60,
  'budgetYuan': 50000,
  'durationDays': 30,
  'commercialGoal': '竖屏投流',
  'requirement': '每集都有反转',
  'deliveryChecklist': ['人物小传', '分镜目录'],
};
const _sessions = '/trade/agent/sessions';

void main() {
  test('Agent endpoint is protected and forwards typed SSE events', () async {
    expect(ProtectedRoutes.isProtected(RoutePath.sourcingAgent), isTrue);
    final adapter = _AgentAdapter(fragmented: true);
    final repository = SourcingAgentRepository(_api(adapter));
    final events = <String>[];
    await repository.chat(501, '找悬疑短剧', cancelToken: CancelToken(),
        onEvent: (event) {
      events.add(event.event);
      if (event.event == 'delta') expect(event.text('text'), contains('候选'));
    });
    expect(events, [
      'step',
      'tool_call',
      'tool_result',
      'card',
      'card',
      'card',
      'card',
      'delta',
      'done'
    ]);
    expect(adapter.agentSends, ['找悬疑短剧']);
  });

  test('SSE rate-limit and uncompleted responses are surfaced as errors',
      () async {
    final adapter = _AgentAdapter();
    final repository = SourcingAgentRepository(_api(adapter));
    await expectLater(
      repository.chat(501, '超限', cancelToken: CancelToken(), onEvent: (_) {}),
      throwsA(isA<ApiException>().having((error) => error.code, 'code', 429)),
    );
    await expectLater(
      repository.chat(501, '中断', cancelToken: CancelToken(), onEvent: (_) {}),
      throwsA(isA<ApiException>()
          .having((error) => error.message, 'message', contains('中断'))),
    );
  });

  testWidgets('进入展示默认欢迎语，过滤乱码且不展示思考链，推荐书籍单行横滑且点击直达详情', (tester) async {
    final adapter = _AgentAdapter();
    await _mount(tester, adapter);
    expect(find.text('这次想找什么样的剧本？'), findsOneWidget);
    expect(find.textContaining('你好呀，我是 AI 选本顾问'), findsOneWidget);
    await tester.tap(find.textContaining('预算 5 万以内'));
    await tester.pumpAndSettle();
    // 不展示思考链/查询过程，也不显示 DSML 乱码或空的“未找到”卡片
    expect(find.text('查询过程'), findsNothing);
    expect(find.textContaining('DSML'), findsNothing);
    expect(find.textContaining('get_work_detail'), findsNothing);
    expect(find.textContaining('未找到符合条件'), findsNothing);
    expect(find.text('作品对比'), findsOneWidget);
    expect(find.text('作品推荐'), findsOneWidget);
    // 多张 work_list 卡片已按 workId 去重合并为共 2 部，单行横向 ListView 展示
    expect(find.text('共 2 部'), findsOneWidget);
    expect(find.text('左右滑动'), findsOneWidget);
    final horizontalLists = tester
        .widgetList<ListView>(find.byType(ListView))
        .where((view) => view.scrollDirection == Axis.horizontal);
    expect(horizontalLists, isNotEmpty);
    expect(find.byType(WorkCover), findsWidgets);
    expect(find.text('查看书籍详情'), findsWidgets);

    // 点击带封面的推荐书籍卡片直接跳转书籍详情页
    final bookCard = find.text('查看书籍详情').first;
    await tester.ensureVisible(bookCard);
    await tester.tap(bookCard);
    await tester.pumpAndSettle();
    expect(find.text('作品试读 18'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    final inquiry = find.widgetWithText(OutlinedButton, '发起询盘').first;
    await tester.ensureVisible(inquiry);
    await tester.tap(inquiry);
    await tester.pumpAndSettle();
    expect(find.text('询盘确认 18'), findsOneWidget);
    expect(adapter.inquiryWrites, 0);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新建对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('历史会话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('悬疑选本'));
    await tester.pumpAndSettle();
    expect(find.text('历史选本答复', findRichText: true), findsOneWidget);
    expect(find.text('作品推荐'), findsOneWidget);
    expect(find.byType(WorkCover), findsWidgets);
    await tester.tap(find.byTooltip('历史会话'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除会话'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(adapter.deletedSession, 501);
    expect(find.text('这次想找什么样的剧本？'), findsOneWidget);
    expect(find.textContaining('你好呀，我是 AI 选本顾问'), findsOneWidget);
  });

  testWidgets('需求草案由按钮确认后发送给平台客服', (tester) async {
    final adapter = _AgentAdapter();
    await _mount(tester, adapter);
    await tester.tap(find.textContaining('帮我起草'));
    await tester.pumpAndSettle();
    expect(find.text('古装权谋定制短剧'), findsOneWidget);
    expect(adapter.platformMessages, isEmpty);
    final button = find.widgetWithText(FilledButton, '发给平台运营立项');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('平台客服 903'), findsOneWidget);
    expect(adapter.platformMessages.single, contains('# 采购需求草案｜古装权谋定制短剧'));
    expect(adapter.platformMessages.single, contains('剧本 + 分镜'));
    expect(adapter.platformMessages.single, contains('- 分镜目录'));
  });

  testWidgets('加载中仅转圈提示，停止生成后可再次发送，429 只提示并提供客服入口', (tester) async {
    final adapter = _AgentAdapter();
    await _mount(tester, adapter);
    await tester.enterText(find.byType(TextField), '等待');
    await tester.pump();
    await tester.tap(find.text('发送'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('查询过程'), findsNothing);
    expect(find.text('停止生成'), findsOneWidget);
    await tester.tap(find.text('停止生成'));
    await tester.pumpAndSettle();
    expect(find.text('已停止生成'), findsOneWidget);
    expect(adapter.cancelled, isTrue);

    await tester.enterText(find.byType(TextField), '超限');
    await tester.pump();
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    // Dio releases the stream after the error event before returning it.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(sourcingLimitMessage), findsOneWidget);
    expect(find.text('联系平台客服'), findsOneWidget);
    expect(find.textContaining('剩余'), findsNothing);
  });

  testWidgets('未找到作品时屏蔽检索路径表与技术术语，以温和语气提示', (tester) async {
    final adapter = _AgentAdapter();
    await _mount(tester, adapter);
    await tester.tap(find.textContaining('甜宠爽剧'));
    await tester.pumpAndSettle();
    expect(find.textContaining('scanLimited'), findsNothing);
    expect(find.textContaining('检索方式'), findsNothing);
    expect(find.textContaining('标签 181'), findsNothing);
    expect(find.textContaining('抱歉，目前书城里暂时还没有找到', findRichText: true),
        findsOneWidget);
  });
}

Future<void> _mount(WidgetTester tester, _AgentAdapter adapter) async {
  tester.view.physicalSize = const Size(430, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: RoutePath.sourcingAgent,
    routes: [
      GoRoute(
          path: RoutePath.sourcingAgent,
          builder: (_, __) => const SourcingAgentPage()),
      GoRoute(
        path: RoutePath.workDetail,
        builder: (_, state) => Scaffold(
            appBar:
                AppBar(title: Text('作品试读 ${state.uri.queryParameters['id']}'))),
      ),
      GoRoute(
        path: RoutePath.inquiryCreate,
        builder: (_, state) => Scaffold(
            appBar: AppBar(
                title: Text('询盘确认 ${state.uri.queryParameters['workId']}'))),
      ),
      GoRoute(
        path: '${RoutePath.chatSessionList}/:sessionId',
        builder: (_, state) => Scaffold(
            appBar: AppBar(
                title: Text('平台客服 ${state.pathParameters['sessionId']}'))),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(_api(adapter))],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

ApiClient _api(_AgentAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://fixture.invalid/api/v1'));
  dio.httpClientAdapter = adapter;
  return ApiClient(dio);
}

class _AgentAdapter implements HttpClientAdapter {
  _AgentAdapter({this.fragmented = false});

  final bool fragmented;
  final agentSends = <String>[];
  final platformMessages = <String>[];
  int inquiryWrites = 0;
  int? deletedSession;
  bool cancelled = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final path = options.path;
    if (path == _sessions && options.method == 'GET') return _json([]);
    if (path == _sessions && options.method == 'POST') {
      return _json({'sessionId': 501, 'title': '新选本对话'});
    }
    if (path == '$_sessions/501' && options.method == 'DELETE') {
      deletedSession = 501;
      return _json(null);
    }
    if (path == '$_sessions/501/messages') {
      return _json([
        {
          'role': 'assistant',
          'content': '历史选本答复',
          'cards': [
            _card('work_list', {
              'works': [_work]
            })
          ]
        },
      ]);
    }
    if (path.endsWith('/chat/stream')) {
      final message = (options.data as Map)['message'] as String;
      agentSends.add(message);
      if (message == '超限') {
        return _sse([
          _event('error', {'code': 429, 'message': sourcingLimitMessage})
        ]);
      }
      if (message == '中断') {
        return _sse([
          _event('delta', {'text': '未完成'})
        ]);
      }
      if (message == '等待') {
        final stream = StreamController<Uint8List>();
        stream.add(Uint8List.fromList(
            utf8.encode(_event('step', {'message': '正在查询'}))));
        unawaited(cancelFuture?.then((_) {
          cancelled = true;
          unawaited(stream.close());
        }));
        return ResponseBody(stream.stream, 200, headers: _sseHeaders);
      }
      if (message.contains('甜宠')) {
        return _sse([
          _event('step', {'message': '正在检索'}),
          _event('card', _card('work_list', {'works': []})),
          _event('delta', {
            'text':
                '检索结论：当前无可推荐作品\n我按以下路径检索，结果全部为空：\n| 检索方式 | 参数 | 结果 |\n| --- | --- | --- |\n| 标签 181 甜宠 | 按销量排序 | 0 部 |\n所有标签检索均返回 0 且 `scanLimited` 均为 false。'
          }),
          _event('done', {'messageId': 21, 'sessionTitle': '甜宠选本', 'tokens': 300}),
        ]);
      }
      final drafting = message.contains('起草');
      return _sse([
        _event('step', {'message': '正在分析采购诉求'}),
        _event('tool_call', {'callId': 'call_1', 'label': '正在检索作品市场'}),
        _event('tool_result', {'callId': 'call_1', 'summary': '找到作品'}),
        if (drafting)
          _event('card', _card('demand_brief', _brief))
        else ...[
          _event('card', _card('work_list', {'works': []})),
          _event(
              'card',
              _card('work_list', {
                'works': [_work]
              })),
          _event(
              'card',
              _card('work_list', {
                'works': [
                  _work,
                  {
                    ..._work,
                    'workId': 19,
                    'title': '云端来信',
                  },
                ]
              })),
          _event(
              'card',
              _card('work_comparison', {
                'works': [_work]
              })),
        ],
        _event('delta', {
          'text':
              '## 候选\n- **雾港回声**\n<｜DSML｜function_calls>\n<｜DSML｜invoke name="get_work_detail">\n<｜DSML｜parameter name="workId" string="false">129</｜DSML｜parameter>\n</｜DSML｜invoke>\n</｜DSML｜function_calls>'
        }),
        _event(
            'done', {'messageId': 20, 'sessionTitle': '悬疑选本', 'tokens': 1230}),
      ], fragmented: fragmented);
    }
    if (path == '/users/me/chat/sessions' && options.method == 'POST') {
      expect((options.data as Map)['businessType'], 'GENERAL');
      return _json({'sessionId': 903, 'sessionType': 'ADMIN'});
    }
    if (path == '/users/me/chat/sessions/903/messages' &&
        options.method == 'POST') {
      final text = (options.data as Map)['content'] as String;
      platformMessages.add(text);
      return _json({
        'messageId': 904,
        'sessionId': 903,
        'senderId': 101,
        'content': text
      });
    }
    if (path == '/trade/inquiry' && options.method == 'POST') inquiryWrites++;
    throw StateError('Unexpected fixture route: ${options.method} $path');
  }

  @override
  void close({bool force = false}) {}
}

const _sseHeaders = {
  Headers.contentTypeHeader: ['text/event-stream;charset=UTF-8']
};

ResponseBody _sse(List<String> frames, {bool fragmented = false}) {
  final bytes = utf8.encode(frames.join());
  return ResponseBody(
      fragmented
          ? Stream.fromIterable(bytes.map((byte) => Uint8List.fromList([byte])))
          : Stream.value(Uint8List.fromList(bytes)),
      200,
      headers: _sseHeaders);
}

ResponseBody _json(dynamic data) =>
    ResponseBody.fromString(jsonEncode({'code': 200, 'data': data}), 200,
        headers: const {
          Headers.contentTypeHeader: ['application/json']
        });

String _event(String event, Map<String, dynamic> payload) =>
    'event: $event\r\ndata: ${jsonEncode(payload)}\r\n\r\n';

Map<String, dynamic> _card(String type, Map<String, dynamic> payload) =>
    {'type': type, 'payload': payload};

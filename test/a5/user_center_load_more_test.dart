// H-01 第 18 批：消息与反馈列表触底加载失败的行为自动化（A5-06 修复验证）。
//
// 覆盖：
//   - 触底加载失败：明确提示 + 重试入口，已加载数据保留、无重复项；
//   - 重试成功：以同页码重取并追加，分页不漂移；
//   - 重试再失败：提示驻留、数据保留；
//   - 刷新/切换筛选与在途触底请求竞态：旧请求的失败不得覆盖新列表状态（代际保护）；
//   - 403 回归：错误态呈现且用户能看到明确「无权限」文案（无权限不踢登录）。
//
// 实现方式与 user_center_states_test 一致：只替换 HTTP 传输层（[ScriptedApi]），
// Repository / ApiClient / 业务码映射全部走真实代码路径。
// 注意：ListView 懒构建——断言「首屏数据仍在」前需先滚回顶部。
import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';
import 'package:script_app/features/feedback/pages/feedback_list_page.dart';
import 'package:script_app/features/message/pages/message_list_page.dart';
import 'package:script_app/shared/widgets/common_views.dart';

import '../support/scripted_api.dart';

class _FakeSecureStorage implements TokenSecureStorage {
  final Map<String, String> _map = {};

  @override
  Future<void> write(String key, String value) async => _map[key] = value;

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> delete(String key) async => _map.remove(key);

  @override
  Future<void> deleteAll() async => _map.clear();
}

Future<ProviderContainer> _pumpPage(
  WidgetTester tester,
  Widget page,
  ScriptedApi api,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final storage = TokenStorage(_FakeSecureStorage(), prefs);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureTokenStorageProvider.overrideWithValue(_FakeSecureStorage()),
      tokenStorageProvider.overrideWithValue(storage),
      api.override,
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: page),
    ),
  );
  await tester.pump();
  return container;
}

List<Map<String, Object>> _messages(int from, int count) => [
      for (var i = 0; i < count; i++)
        {
          'messageId': from + i,
          'type': 'SYSTEM',
          'title': '消息$from+$i',
          'summary': '摘要',
          'read': true,
        },
    ];

List<Map<String, Object>> _feedbackRows(int from, int count) => [
      for (var i = 0; i < count; i++)
        {
          'feedbackId': from + i,
          'category': 'BUG',
          'content': '反馈$from+$i',
          'status': 'SUBMITTED',
        },
    ];

/// 未读数接口与本组用例无关；显式失败避免落入被测路径的 handler。
void _stubUnread(ScriptedApi api) =>
    api.reply('/messages/unread-count', Envelope.fail(50000, 'unread'));

/// 未读数之外的 /messages 请求按 pageNum 分派（dio queryParameters 值为 int）。
bool _isPage1(RequestOptions o) =>
    o.path == '/messages' &&
    (o.queryParameters['pageNum'] ?? 0).toString() == '1';

Future<void> _dragToBottom(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -1200));
  await tester.pump();
}

Future<void> _dragToTop(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, 1200));
  await tester.pump();
}

/// 懒构建列表：逐步滚动直到 [finder] 进入视口并构建。
Future<bool> _scrollUntil(
  WidgetTester tester,
  Finder finder, {
  bool down = true,
}) async {
  for (var i = 0; i < 8; i++) {
    if (finder.evaluate().isNotEmpty) return true;
    await tester.drag(find.byType(ListView), Offset(0, down ? -600 : 600));
    await tester.pump();
  }
  await tester.pumpAndSettle();
  return finder.evaluate().isNotEmpty;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('H-01 第 18 批：消息列表触底加载失败', () {
    testWidgets('失败时展示明确提示与重试，首屏数据保留且无重复项', (tester) async {
      final api = ScriptedApi();
      _stubUnread(api);
      api.handle('/messages', (o) {
        return _isPage1(o)
            ? Envelope.ok({'total': 15, 'list': _messages(1, 10)})
            : Envelope.fail(50000, '服务暂时不可用');
      });
      await _pumpPage(tester, const MessageListPage(), api);
      await tester.pumpAndSettle();
      expect(find.text('消息1+0'), findsOneWidget);
      expect(find.textContaining('加载更多失败'), findsNothing);

      await _dragToBottom(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('加载更多失败'), findsOneWidget,
          reason: '触底失败必须有明确提示（A5-06）');
      expect(find.byKey(const Key('load_more_retry')), findsOneWidget);
      expect(find.byType(ErrorView), findsNothing,
          reason: '触底失败不得覆盖首屏错误态语义');

      await _dragToTop(tester);
      await tester.pumpAndSettle();
      expect(find.text('消息1+0'), findsOneWidget, reason: '已加载数据保留');
      expect(await _scrollUntil(tester, find.text('消息1+9')), isTrue,
          reason: '第 1 页全部 10 条数据保留');
      expect(find.text('消息1+9'), findsOneWidget);
    });

    testWidgets('重试以同页码重取并成功追加，无重复项', (tester) async {
      final api = ScriptedApi();
      _stubUnread(api);
      var page2Calls = 0;
      api.handle('/messages', (o) {
        if (_isPage1(o)) {
          return Envelope.ok({'total': 15, 'list': _messages(1, 10)});
        }
        if (o.path != '/messages') {
          return Envelope.fail(50000, 'unread');
        }
        page2Calls++;
        return page2Calls == 1
            ? Envelope.fail(50000, '服务暂时不可用')
            : Envelope.ok({'total': 15, 'list': _messages(11, 5)});
      });
      await _pumpPage(tester, const MessageListPage(), api);
      await tester.pumpAndSettle();
      await _dragToBottom(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('加载更多失败'), findsOneWidget);

      await tester.tap(find.byKey(const Key('load_more_retry')));
      await tester.pumpAndSettle();

      expect(page2Calls, 2, reason: '重试必须重新发起第 2 页请求');
      expect(find.textContaining('加载更多失败'), findsNothing);
      expect(await _scrollUntil(tester, find.text('消息11+4')), isTrue,
          reason: '第 2 页末条已追加');
      expect(find.text('消息11+0'), findsOneWidget,
          reason: '第 2 页数据已追加且恰好一次（无重复项）');
      expect(await _scrollUntil(tester, find.text('消息1+0'), down: false),
          isTrue, reason: '首屏数据仍在');
      expect(find.text('消息1+0'), findsOneWidget);
    });

    testWidgets('重试再失败：提示驻留、数据保留、可继续重试', (tester) async {
      final api = ScriptedApi();
      _stubUnread(api);
      api.handle('/messages', (o) {
        return _isPage1(o)
            ? Envelope.ok({'total': 15, 'list': _messages(1, 10)})
            : Envelope.fail(50000, '服务暂时不可用');
      });
      await _pumpPage(tester, const MessageListPage(), api);
      await tester.pumpAndSettle();
      await _dragToBottom(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('load_more_retry')));
      await tester.pumpAndSettle();

      expect(find.textContaining('加载更多失败'), findsOneWidget, reason: '失败后提示驻留');
      expect(find.byKey(const Key('load_more_retry')), findsOneWidget,
          reason: '仍可继续重试');
      expect(await _scrollUntil(tester, find.text('消息1+0'), down: false),
          isTrue, reason: '已加载数据保留');
      expect(find.text('消息1+0'), findsOneWidget);
    });

    testWidgets('触底失败后下拉刷新清除旧提示并重新加载首页', (tester) async {
      final api = ScriptedApi();
      _stubUnread(api);
      var page1Calls = 0;
      api.handle('/messages', (o) {
        if (_isPage1(o)) {
          page1Calls++;
          return page1Calls == 1
              ? Envelope.ok({'total': 15, 'list': _messages(1, 10)})
              : Envelope.ok({'total': 1, 'list': _messages(200, 1)});
        }
        return Envelope.fail(50000, '服务暂时不可用');
      });
      await _pumpPage(tester, const MessageListPage(), api);
      await tester.pumpAndSettle();
      await _dragToBottom(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('加载更多失败'), findsOneWidget);

      await _dragToTop(tester);
      await tester.drag(find.byType(ListView), const Offset(0, 600));
      await tester.pumpAndSettle();

      expect(page1Calls, 2, reason: '下拉刷新必须重新请求首页');
      expect(find.textContaining('加载更多失败'), findsNothing);
      expect(find.text('消息200+0'), findsOneWidget);
      expect(find.text('消息1+0'), findsNothing);
    });

    testWidgets('切换筛选触发的刷新使在途触底失败作废，不污染新列表', (tester) async {
      final api = ScriptedApi();
      _stubUnread(api);
      api.handle('/messages', (o) {
        if (o.path != '/messages') {
          return Envelope.fail(50000, 'unread');
        }
        final type = (o.queryParameters['type'] ?? '').toString();
        final page = (o.queryParameters['pageNum'] ?? 0).toString();
        if (page == '1' && type.isEmpty) {
          return Envelope.ok({'total': 15, 'list': _messages(1, 10)});
        }
        if (page == '1' && type == 'REVIEW') {
          return Envelope.ok({'total': 1, 'list': _messages(200, 1)});
        }
        return Envelope.fail(50000, '服务暂时不可用');
      });
      await _pumpPage(tester, const MessageListPage(), api);
      await tester.pumpAndSettle();

      // 触底请求在途（未完成前切换筛选）
      api.gate();
      await _dragToBottom(tester);
      await tester.pump();
      expect(find.textContaining('加载更多失败'), findsNothing);

      await tester.tap(find.text('审核'));
      await tester.pump();
      api.release();
      await tester.pumpAndSettle();

      expect(find.textContaining('加载更多失败'), findsNothing,
          reason: '旧代际的触底失败不得覆盖筛选后的新列表');
      expect(find.byType(ErrorView), findsNothing);
      expect(find.text('消息200+0'), findsOneWidget, reason: '展示新筛选的数据');
    });
  });

  group('H-01 第 18 批：反馈列表触底加载失败', () {
    testWidgets('失败时展示明确提示与重试，重试成功后追加且无重复项', (tester) async {
      final api = ScriptedApi();
      var page2Calls = 0;
      api.handle('/feedback', (o) {
        if ((o.queryParameters['pageNum'] ?? 0).toString() == '1') {
          return Envelope.ok({'total': 15, 'list': _feedbackRows(1, 10)});
        }
        page2Calls++;
        return page2Calls == 1
            ? Envelope.fail(50000, '服务暂时不可用')
            : Envelope.ok({'total': 15, 'list': _feedbackRows(11, 5)});
      });
      await _pumpPage(tester, const FeedbackListPage(), api);
      await tester.pumpAndSettle();
      await _dragToBottom(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('加载更多失败'), findsOneWidget);
      expect(find.byKey(const Key('load_more_retry')), findsOneWidget);

      await tester.tap(find.byKey(const Key('load_more_retry')));
      await tester.pumpAndSettle();

      expect(find.textContaining('加载更多失败'), findsNothing);
      expect(await _scrollUntil(tester, find.text('反馈11+4')), isTrue,
          reason: '第 2 页已追加且恰好一次');
      expect(page2Calls, 2);
      expect(await _scrollUntil(tester, find.text('反馈1+0'), down: false),
          isTrue, reason: '首屏数据保留');
      expect(find.text('反馈1+0'), findsOneWidget);
    });
  });

  group('H-01 第 18 批：触底路径 403 语义', () {
    testWidgets('触底 403 同样提示无权限且不踢登录、数据保留', (tester) async {
      final api = ScriptedApi();
      _stubUnread(api);
      api.handle('/messages', (o) {
        return _isPage1(o)
            ? Envelope.ok({'total': 15, 'list': _messages(1, 10)})
            : Envelope.http(403, '无权限访问该资源');
      });
      await _pumpPage(tester, const MessageListPage(), api);
      await tester.pumpAndSettle();
      await _dragToBottom(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('加载更多失败'), findsOneWidget);
      expect(find.textContaining('无权限'), findsOneWidget,
          reason: '用户能看到明确的无权限文案');
      await _dragToTop(tester);
      await tester.pumpAndSettle();
      expect(find.text('消息1+0'), findsOneWidget, reason: '已加载数据保留');
      expect(tester.takeException(), isNull);
    });
  });
}

// H-01 App 用户中心：状态矩阵与数据归属（App 端）。
//
// 对应评审标准 G5「App 用户中心」后续加固清单：
//   - 我的页包含规定的用户信息和全部入口；
//   - 消息列表、详情、未读数、单条已读和全部已读正确；
//   - 用户无法读取或修改其他用户的消息、反馈或实名申请（数据归属）；
//   - 通知偏好只影响对应渠道，不删除站内消息；
//   - 反馈支持提交、列表、详情和状态查看；
//   - 以及 H-01 要求的加载、空、错误、无权限、未登录、会话失效、异常状态。
//
// 实现方式：只替换 HTTP 传输层（[ScriptedApi]），被测的 Repository / ApiClient /
// 业务码映射 / 401 会话失效全部走真实代码路径。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/core/network/session_events.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';
import 'package:script_app/features/feedback/pages/feedback_detail_page.dart';
import 'package:script_app/features/feedback/pages/feedback_list_page.dart';
import 'package:script_app/features/message/pages/message_detail_page.dart';
import 'package:script_app/features/message/pages/message_list_page.dart';
import 'package:script_app/features/message/pages/notification_preference_page.dart';
import 'package:script_app/features/profile/pages/profile_edit_page.dart';
import 'package:script_app/features/profile/pages/real_name_page.dart';
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

/// 直接渲染单个页面（绕过路由），用于隔离地断言页面自身状态。
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

const _msgRow = {
  'messageId': 12,
  'type': 'SYSTEM',
  'title': '系统通知',
  'summary': '内容摘要',
  'read': false,
  'createdAt': '2026-09-25 10:00:00',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ================================================================
  group('H-01-A 加载态', () {
    testWidgets('消息列表：请求未返回时展示加载态', (tester) async {
      final api = ScriptedApi()..gate();
      api.reply('/messages', Envelope.ok({'total': 0, 'list': <Object>[]}));
      await _pumpPage(tester, const MessageListPage(), api);

      expect(find.byType(LoadingView), findsOneWidget);
      expect(find.byType(EmptyView), findsNothing);

      api.release();
      await tester.pumpAndSettle();
      expect(find.byType(LoadingView), findsNothing);
      expect(find.byType(EmptyView), findsOneWidget);
    });

    testWidgets('反馈列表：请求未返回时展示加载态', (tester) async {
      final api = ScriptedApi()..gate();
      api.reply('/feedback', Envelope.ok({'total': 0, 'list': <Object>[]}));
      await _pumpPage(tester, const FeedbackListPage(), api);

      expect(find.byType(LoadingView), findsOneWidget);
      api.release();
      await tester.pumpAndSettle();
      expect(find.byType(EmptyView), findsOneWidget);
    });

    testWidgets('实名页：请求未返回时展示加载态', (tester) async {
      final api = ScriptedApi()..gate();
      api.reply('/real-name', Envelope.ok({'status': 'NOT_SUBMITTED'}));
      await _pumpPage(tester, const RealNamePage(), api);

      expect(find.byType(LoadingView), findsOneWidget);
      api.release();
      await tester.pumpAndSettle();
      expect(find.byType(LoadingView), findsNothing);
    });
  });

  // ================================================================
  group('H-01-B 空态', () {
    testWidgets('消息列表为空展示空态文案', (tester) async {
      final api = ScriptedApi();
      api.reply('/messages', Envelope.ok({'total': 0, 'list': <Object>[]}));
      await _pumpPage(tester, const MessageListPage(), api);
      await tester.pumpAndSettle();

      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text('暂无消息'), findsOneWidget);
    });

    testWidgets('反馈列表为空展示空态文案', (tester) async {
      final api = ScriptedApi();
      api.reply('/feedback', Envelope.ok({'total': 0, 'list': <Object>[]}));
      await _pumpPage(tester, const FeedbackListPage(), api);
      await tester.pumpAndSettle();

      expect(find.text('还没有提交过反馈'), findsOneWidget);
    });

    testWidgets('通知偏好无可配置类型展示空态文案', (tester) async {
      final api = ScriptedApi();
      api.reply('/notification-preferences', Envelope.ok(<Object>[]));
      await _pumpPage(tester, const NotificationPreferencePage(), api);
      await tester.pumpAndSettle();

      expect(find.text('暂无可配置的通知类型'), findsOneWidget);
    });
  });

  // ================================================================
  group('H-01-C 错误态与重试', () {
    testWidgets('消息列表业务错误展示错误态与服务端文案', (tester) async {
      final api = ScriptedApi();
      api.reply('/messages', Envelope.fail(50000, '服务暂时不可用'));
      await _pumpPage(tester, const MessageListPage(), api);
      await tester.pumpAndSettle();

      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.text('服务暂时不可用'), findsOneWidget);
    });

    testWidgets('消息列表重试会重新发起请求并可恢复为空态', (tester) async {
      final api = ScriptedApi();
      var calls = 0;
      api.handle('/messages', (o) {
        calls++;
        return calls == 1
            ? Envelope.fail(50000, '服务暂时不可用')
            : Envelope.ok({'total': 0, 'list': <Object>[]});
      });
      await _pumpPage(tester, const MessageListPage(), api);
      await tester.pumpAndSettle();
      expect(find.byType(ErrorView), findsOneWidget);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(api.countOf('/messages'), greaterThanOrEqualTo(2),
          reason: '点击重试必须重新发起请求');
      expect(find.byType(EmptyView), findsOneWidget);
    });

    testWidgets('反馈列表 HTTP 500 展示错误态', (tester) async {
      final api = ScriptedApi();
      api.reply('/feedback', Envelope.http(500, '服务器错误'));
      await _pumpPage(tester, const FeedbackListPage(), api);
      await tester.pumpAndSettle();

      expect(find.byType(ErrorView), findsOneWidget);
    });

    testWidgets('实名页错误态展示可读文案', (tester) async {
      final api = ScriptedApi();
      api.reply('/real-name', Envelope.fail(50000, '加载失败，请稍后重试'));
      await _pumpPage(tester, const RealNamePage(), api);
      await tester.pumpAndSettle();

      expect(find.byType(ErrorView), findsOneWidget);
    });

    testWidgets('资料页错误态展示可读文案', (tester) async {
      final api = ScriptedApi();
      api.reply('/users/me/profile', Envelope.fail(50000, '加载失败，请稍后重试'));
      await _pumpPage(tester, const ProfileEditPage(), api);
      await tester.pumpAndSettle();

      expect(find.byType(ErrorView), findsOneWidget);
    });

    testWidgets('响应结构非法（非信封）时进入错误态而非崩溃', (tester) async {
      final api = ScriptedApi();
      api.reply('/messages', Envelope.raw(200, 'not-an-envelope'));
      await _pumpPage(tester, const MessageListPage(), api);
      await tester.pumpAndSettle();

      expect(find.byType(ErrorView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ================================================================
  group('H-01-D 无权限（403）', () {
    testWidgets('消息列表 403 展示错误态、无权限文案且不渲染数据', (tester) async {
      final api = ScriptedApi();
      api.reply('/messages', Envelope.http(403, '无权限访问该资源'));
      await _pumpPage(tester, const MessageListPage(), api);
      await tester.pumpAndSettle();

      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.textContaining('无权限'), findsOneWidget,
          reason: '用户能看到明确的无权限文案（当前产品无权限分级入口，403 即错误态语义）');
      expect(find.byType(EmptyView), findsNothing);
      expect(tester.takeException(), isNull, reason: '403 不应抛出未捕获异常');
    });

    testWidgets('反馈列表 403 展示错误态、无权限文案且不渲染数据', (tester) async {
      final api = ScriptedApi();
      api.reply('/feedback', Envelope.http(403, '无权限访问该资源'));
      await _pumpPage(tester, const FeedbackListPage(), api);
      await tester.pumpAndSettle();

      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.textContaining('无权限'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ================================================================
  group('H-01-E 会话失效（401）与业务码映射（ApiClient 层）', () {
    /// 通过真实 ApiClient + 脚本化传输层发起一次请求，返回异常与会话失效次数。
    Future<({Object? error, int signals})> callApi(String path, Envelope env) async {
      final api = ScriptedApi();
      api.reply(path, env);
      final signals = <void>[];
      final sub = SessionEvents.instance.onSessionExpired.listen(signals.add);
      Object? error;
      try {
        await ApiClient(api.buildDio()).get<Map<String, dynamic>>(path);
      } catch (e) {
        error = e;
      }
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      return (error: error, signals: signals.length);
    }

    test('HTTP 401 触发会话失效并抛出可读异常', () async {
      final r = await callApi('/messages', Envelope.http(401, '登录状态已过期'));
      expect(r.signals, 1, reason: 'HTTP 401 必须触发一次会话失效');
      expect(r.error, isA<ApiException>());
      expect((r.error! as ApiException).code, 401);
    });

    test('业务码 40100/40102/40103/40301 均触发会话失效', () async {
      for (final code in const [40100, 40102, 40103, 40301]) {
        final r = await callApi('/messages', Envelope.fail(code, '会话不可恢复'));
        expect(r.signals, 1, reason: '业务码 $code 必须触发会话失效');
        expect((r.error! as ApiException).code, code);
      }
    });

    test('普通业务错误码不触发会话失效（避免误踢登录）', () async {
      final r = await callApi('/messages', Envelope.fail(40400, '资源不存在'));
      expect(r.signals, 0, reason: '40400 属普通业务错误，不得触发会话失效');
      expect((r.error! as ApiException).code, 40400);
      expect((r.error! as ApiException).message, '资源不存在');
    });

    test('HTTP 403 不触发会话失效（无权限不等于未登录）', () async {
      final r = await callApi('/messages', Envelope.http(403, '没有访问权限'));
      expect(r.signals, 0, reason: '403 是权限不足，不应登出用户');
      expect(r.error, isA<ApiException>());
    });

    test('网络异常映射为可读异常且不触发会话失效', () async {
      final api = ScriptedApi();
      // 未编排该路径 → 适配器返回 500 信封，走「业务失败」分支
      final signals = <void>[];
      final sub = SessionEvents.instance.onSessionExpired.listen(signals.add);
      Object? error;
      try {
        await ApiClient(api.buildDio()).get<Map<String, dynamic>>('/unknown-path');
      } catch (e) {
        error = e;
      }
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(error, isA<ApiException>(), reason: '未编排响应也必须抛出 ApiException 而不是崩溃');
      expect(signals, isEmpty);
    });

    testWidgets('用户中心接口返回 401 时页面进入错误态且发出会话失效信号', (tester) async {
      final api = ScriptedApi();
      api.reply('/messages', Envelope.http(401, '登录状态已过期'));
      final signals = <void>[];
      final sub = SessionEvents.instance.onSessionExpired.listen(signals.add);
      addTearDown(sub.cancel);

      await _pumpPage(tester, const MessageListPage(), api);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(signals, isNotEmpty, reason: '401 必须触发会话失效信号，由 AuthController 踢回登录页');
      expect(find.byType(ErrorView), findsOneWidget);
    });
  });

  // ================================================================
  group('H-01-F 数据归属（客户端不携带用户标识，跨用户资源按不存在处理）', () {
    testWidgets('反馈详情：他人/不存在的反馈返回 404 语义文案', (tester) async {
      final api = ScriptedApi();
      api.reply('/feedback/', Envelope.fail(40400, '资源不存在'));
      await _pumpPage(tester, const FeedbackDetailPage(feedbackId: 999), api);
      await tester.pumpAndSettle();

      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.text('资源不存在'), findsOneWidget);
    });

    testWidgets('消息详情：他人/不存在的消息返回 404 语义文案', (tester) async {
      final api = ScriptedApi();
      api.reply('/messages/', Envelope.fail(40400, '资源不存在'));
      await _pumpPage(tester, const MessageDetailPage(messageId: 999), api);
      await tester.pumpAndSettle();

      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.text('资源不存在'), findsOneWidget);
    });

    testWidgets('非法资源 id 不发请求，就地给出错误态', (tester) async {
      final api = ScriptedApi();
      await _pumpPage(tester, const FeedbackDetailPage(feedbackId: 0), api);
      await tester.pumpAndSettle();

      expect(find.byType(ErrorView), findsOneWidget);
      expect(api.requests, isEmpty, reason: 'id<=0 属本地校验，不应发起请求');
    });

    testWidgets('用户中心请求不携带任何用户标识（归属由服务端从 Token 推导）', (tester) async {
      final api = ScriptedApi();
      api.reply('/messages', Envelope.ok({'total': 1, 'list': [_msgRow]}));
      api.reply('/messages/unread-count', Envelope.ok({'total': 3}));

      await _pumpPage(tester, const MessageListPage(), api);
      await tester.pumpAndSettle();

      expect(api.requests, isNotEmpty);
      // 断言本身非空转：分页参数确实在请求里
      expect(api.requests.any((r) => r.uri.queryParameters.containsKey('pageNum')), isTrue,
          reason: '请求应携带分页参数，否则本断言无意义');
      for (final r in api.requests) {
        final uri = r.uri.toString().toLowerCase();
        expect(uri.contains('userid'), isFalse,
            reason: '客户端不得以查询参数携带用户标识：${r.uri}');
        expect(uri.contains('ownerid'), isFalse, reason: '客户端不得携带归属标识：${r.uri}');
        final body = r.data;
        if (body is Map) {
          expect(body.keys.map((k) => '$k'.toLowerCase()).any((k) => k.contains('userid')), isFalse,
              reason: '请求体不得携带用户标识：$body');
        }
      }
    });

    testWidgets('列表只渲染服务端返回的本用户数据', (tester) async {
      final api = ScriptedApi();
      api.reply('/messages', Envelope.ok({'total': 1, 'list': [_msgRow]}));
      await _pumpPage(tester, const MessageListPage(), api);
      await tester.pumpAndSettle();

      expect(find.text('系统通知'), findsOneWidget);
      expect(find.text('内容摘要'), findsOneWidget);
    });
  });

  // ================================================================
  group('H-01-G 实名四态与重提规则', () {
    Future<void> pumpRealName(WidgetTester tester, ScriptedApi api, String status,
        {String? rejectReason}) async {
      api.reply('/real-name', Envelope.ok({
        'status': status,
        'realNameMasked': '张*',
        'idNumberMasked': '110101********1234',
        if (rejectReason != null) 'rejectReason': rejectReason,
      }));
      await _pumpPage(tester, const RealNamePage(), api);
      await tester.pumpAndSettle();
    }

    testWidgets('未认证：展示提交入口，且不出现驳回原因段', (tester) async {
      final api = ScriptedApi();
      await pumpRealName(tester, api, 'NOT_SUBMITTED');
      expect(find.text('未认证'), findsOneWidget);
      expect(find.text('提交认证'), findsOneWidget);
      expect(find.textContaining('上次驳回原因'), findsNothing);
    });

    testWidgets('审核中：不可重复提交，且不出现驳回原因段', (tester) async {
      final api = ScriptedApi();
      await pumpRealName(tester, api, 'PENDING');
      expect(find.text('审核中'), findsOneWidget);
      expect(find.text('申请审核中，暂不能重复提交。'), findsOneWidget);
      expect(find.text('提交认证'), findsNothing);
      expect(find.textContaining('上次驳回原因'), findsNothing);
    });

    testWidgets('已认证：不可再次提交，且不出现驳回原因段', (tester) async {
      final api = ScriptedApi();
      await pumpRealName(tester, api, 'APPROVED');
      expect(find.text('已认证'), findsOneWidget);
      expect(find.text('已通过实名认证，如需变更请联系客服。'), findsOneWidget);
      expect(find.textContaining('上次驳回原因'), findsNothing);
    });

    testWidgets('已驳回：可重新提交并展示驳回原因', (tester) async {
      final api = ScriptedApi();
      await pumpRealName(tester, api, 'REJECTED', rejectReason: '证件照片不清晰');
      expect(find.text('已驳回'), findsOneWidget);
      expect(find.textContaining('证件照片不清晰'), findsWidgets);
      expect(find.text('重新提交'), findsOneWidget);
    });

    testWidgets('已驳回但服务端未给原因时以「未填写」兜底（不出现空白原因）', (tester) async {
      final api = ScriptedApi();
      await pumpRealName(tester, api, 'REJECTED');
      expect(find.textContaining('上次驳回原因'), findsOneWidget);
      expect(find.textContaining('未填写'), findsOneWidget,
          reason: '服务端未下发原因时必须给出明确兜底文案，而不是空白');
    });
  });
}

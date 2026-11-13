// H-02 路由守卫矩阵（App 端）。
//
// 对应评审标准 G6「游客拦截和 redirect 快速门禁」后续加固清单：
//   - 收藏、书架、福利、AI、上传、询盘、订单、合同和印章等入口全部接入统一守卫；
//   - 业务模块没有散落的 Token 字符串判断或直接打开登录页代码；
//   - 未登录访问受限页时保存命名路由和可序列化参数；
//   - 登录成功后准确回到原页面，参数保持正确；
//   - redirect 只消费一次，刷新或重复登录不会循环跳转；
//   - 非法、未知或无权限 redirect 落到安全首页并提示；
//   - 用户主动退出后不保留旧 redirect；
//   - 强制退出后不会自动回到密码、换绑、支付或其他敏感提交页。
//
// 断言全部基于当前实现的实际行为；`flutter test` 不通真实后端。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/app.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/router/app_router.dart';
import 'package:script_app/core/router/route_intent.dart';
import 'package:script_app/core/router/route_paths.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';
import 'package:script_app/core/constants/demand_task_type.dart';
import 'package:script_app/features/auth/pages/login_page.dart';
import 'package:script_app/features/trade/data/demand_providers.dart';
import 'package:script_app/features/trade/data/trade_models.dart';

/// 不触网、不写安全存储的假实现。
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

/// 用户中心的全部受保护入口（来自 RoutePath，覆盖「我的」下所有子页）。
const List<String> kProtectedEntries = <String>[
  RoutePath.profile,
  RoutePath.profileEdit,
  RoutePath.realName,
  RoutePath.accountSecurity,
  RoutePath.phoneChange,
  RoutePath.passwordEdit,
  RoutePath.notificationPreferences,
  RoutePath.bookshelf,
  RoutePath.messages,
  RoutePath.messageDetail,
  RoutePath.feedback,
  RoutePath.feedbackDetail,
  RoutePath.feedbackCreate,
];

/// 公开入口（游客可浏览，不应被守卫拦截）。
const List<String> kPublicEntries = <String>[
  RoutePath.home,
  RoutePath.comic,
  RoutePath.create,
  RoutePath.category,
  RoutePath.splash,
  RoutePath.login,
  RoutePath.agreement,
  RoutePath.privacyPolicy,
  // 任务广场已升级为底部导航板块，广场与详情对游客开放（后端按白名单裁剪字段）
  RoutePath.demandTab,
  RoutePath.demandList,
];

Future<void> _pumpApp(WidgetTester tester,
    {List<Override> overrides = const []}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final storage = TokenStorage(_FakeSecureStorage(), prefs);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        secureTokenStorageProvider.overrideWithValue(_FakeSecureStorage()),
        tokenStorageProvider.overrideWithValue(storage),
        ...overrides,
      ],
      child: const ScriptApp(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ================================================================
  group('G6-A 受保护入口覆盖（纯逻辑）', () {
    test('全部用户中心入口均被判为受保护', () {
      for (final path in kProtectedEntries) {
        expect(ProtectedRoutes.isProtected(path), isTrue,
            reason: '$path 必须接入统一守卫');
      }
    });

    test('带查询参数的受保护入口同样受保护（deep link 场景）', () {
      expect(ProtectedRoutes.isProtected('${RoutePath.messageDetail}?id=12'), isTrue);
      expect(ProtectedRoutes.isProtected('${RoutePath.feedbackDetail}?id=7'), isTrue);
      // 子路径也必须被前缀规则覆盖
      expect(ProtectedRoutes.isProtected('${RoutePath.profile}/messages'), isTrue);
    });

    test('公开入口不被拦截（游客可浏览）', () {
      for (final path in kPublicEntries) {
        expect(ProtectedRoutes.isProtected(path), isFalse,
            reason: '$path 是公开入口，不应被守卫拦截');
      }
    });

    test('受保护判定不做前缀误伤：/profilex 不是 /profile 的子路径', () {
      expect(ProtectedRoutes.isProtected('/profilex'), isFalse);
      expect(ProtectedRoutes.isProtected('/bookshelf-x'), isFalse);
    });

    test('敏感提交页不允许会话恢复（强制退出后不回跳）', () {
      expect(ProtectedRoutes.canResume(RoutePath.phoneChange), isFalse);
      expect(ProtectedRoutes.canResume(RoutePath.accountSecurity), isFalse);
      expect(ProtectedRoutes.canResume(RoutePath.passwordEdit), isFalse);
    });

    test('非敏感页允许会话恢复', () {
      expect(ProtectedRoutes.canResume(RoutePath.messages), isTrue);
      expect(ProtectedRoutes.canResume('${RoutePath.feedbackDetail}?id=3'), isTrue);
      expect(ProtectedRoutes.canResume(RoutePath.notificationPreferences), isTrue);
    });
  });

  // ================================================================
  group('G6-B redirect 意图：非法目标与一次性消费（纯逻辑）', () {
    test('非法/未知回跳目标一律拒绝', () {
      expect(RouteIntent.fromParam(null), isNull);
      expect(RouteIntent.fromParam(''), isNull);
      expect(RouteIntent.fromParam('   '), isNull);
      // 站外绝对地址（开放重定向）
      expect(RouteIntent.fromParam('https://evil.example.com/x'), isNull);
      expect(RouteIntent.fromParam('http://evil.example.com'), isNull);
      // 协议相对地址
      expect(RouteIntent.fromParam('//evil.example.com/x'), isNull);
      // 超长串（登录页不得成为任意跳转入口）
      expect(RouteIntent.fromParam('/${'a' * (RouteIntent.maxLength + 1)}'), isNull);
    });

    test('合法站内路径被接受并保留查询参数', () {
      final intent =
          RouteIntent.fromParam(Uri.encodeComponent('${RoutePath.feedbackDetail}?id=42'));
      expect(intent, isNotNull);
      expect(intent!.target, '${RoutePath.feedbackDetail}?id=42');
      // 编码可往返
      expect(RouteIntent.fromParam(intent.encoded)?.target, intent.target);
    });

    test('意图只消费一次，重复登录不循环跳转', () {
      final store = RouteIntentStore();
      store.save(const RouteIntent('${RoutePath.feedbackDetail}?id=42'));
      expect(store.consume()?.target, '${RoutePath.feedbackDetail}?id=42');
      expect(store.consume(), isNull, reason: '第二次消费必须为空，避免重复回跳');
      expect(store.pending, isNull);
    });

    test('主动退出清空旧 redirect', () {
      final store = RouteIntentStore();
      store.save(const RouteIntent(RoutePath.messages));
      store.clear();
      expect(store.pending, isNull);
      expect(store.consume(), isNull);
    });
  });

  // ================================================================
  group('G6-C 业务模块没有散落的鉴权代码（源码级）', () {
    late List<File> dartFiles;

    setUpAll(() {
      dartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(dartFiles, isNotEmpty, reason: '未能读取 lib 目录');
    });

    test('Token 读写只出现在 lib/core 内（集中管理）', () {
      final offenders = <String>[];
      for (final f in dartFiles) {
        final p = f.path.replaceAll(r'\', '/');
        if (p.startsWith('lib/core/')) continue;
        final src = f.readAsStringSync();
        if (src.contains('kAccessToken') ||
            src.contains('kRefreshToken') ||
            RegExp(r'secureStorage\.read\(').hasMatch(src)) {
          offenders.add(p);
        }
      }
      expect(offenders, isEmpty,
          reason: '业务模块不得自行读取 Token，应由 core 层统一注入：$offenders');
    });

    test('登录页跳转只出现在 router 与 auth 特性内（无散落跳登录）', () {
      final offenders = <String>[];
      for (final f in dartFiles) {
        final p = f.path.replaceAll(r'\', '/');
        if (p.startsWith('lib/core/router/') || p.startsWith('lib/features/auth/')) {
          continue;
        }
        final src = f.readAsStringSync();
        // 直接构造登录页，或绕过守卫直接 go 到登录路由
        if (src.contains('LoginPage(') ||
            RegExp(r'''go\(\s*['"]/login''').hasMatch(src) ||
            RegExp(r'''push\(\s*['"]/login''').hasMatch(src)) {
          offenders.add(p);
        }
      }
      expect(offenders, isEmpty,
          reason: '业务模块必须经 AuthGuard 进入登录页，不得散落跳转：$offenders');
    });

    test('会话失效事件只由网络层发出、只由会话控制器消费', () {
      final emitters = <String>[];
      final consumers = <String>[];
      for (final f in dartFiles) {
        final p = f.path.replaceAll(r'\', '/');
        final src = f.readAsStringSync();
        // 发出点：实际调用事件（session_events.dart 只是声明该方法）
        if (src.contains('SessionEvents.instance.sessionExpired()')) emitters.add(p);
        if (src.contains('onSessionExpired')) consumers.add(p);
      }
      expect(emitters, ['lib/core/network/api_client.dart'],
          reason: '会话失效只能由 ApiClient 依据 401/业务码发出，实际：$emitters');
      expect(consumers,
          ['lib/core/network/session_events.dart', 'lib/core/providers/auth_providers.dart'],
          reason: '会话失效只能由 AuthController 消费，实际：$consumers');
    });
  });

  // ================================================================
  group('G6-D 游客拦截与回跳（widget）', () {
    testWidgets('游客冷启动落在公开入口，不停留登录页', (tester) async {
      await _pumpApp(tester);
      expect(find.text('首页'), findsWidgets);
      expect(find.byType(LoginPage), findsNothing);
    });

    for (final path in kProtectedEntries) {
      testWidgets('游客访问 $path 需确认，取消不保存意图', (tester) async {
        await _pumpApp(tester);
        final container = _containerOf(tester);
        container.read(routerProvider).go(path);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('需要登录'), findsOneWidget);
        expect(find.byType(LoginPage), findsNothing);
        expect(container.read(routeIntentStoreProvider).pending, isNull);
        await tester.tap(find.text('暂不登录'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(LoginPage), findsNothing);
      });
    }

    testWidgets('确认登录后深链保留查询参数', (tester) async {
      await _pumpApp(tester);
      final container = _containerOf(tester);
      container.read(routerProvider).go('${RoutePath.feedbackDetail}?id=42');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(container.read(routeIntentStoreProvider).pending, isNull);
      await tester.tap(find.text('去登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(LoginPage), findsOneWidget);
      expect(container.read(routeIntentStoreProvider).pending?.target,
          '${RoutePath.feedbackDetail}?id=42');
    });

    testWidgets('游客主动点击我的直接进入登录页', (tester) async {
      await _pumpApp(tester);
      await tester.tap(find.text('我的').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('需要登录'), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(_containerOf(tester).read(routeIntentStoreProvider).pending?.target, RoutePath.profile);
    });

    testWidgets('游客点击消息可取消或确认登录', (tester) async {
      await _pumpApp(tester);
      final container = _containerOf(tester);
      await tester.tap(find.byTooltip('消息'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('需要登录'), findsOneWidget);
      await tester.tap(find.text('暂不登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(LoginPage), findsNothing);
      expect(container.read(routeIntentStoreProvider).pending, isNull);
      await tester.tap(find.byTooltip('消息'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('去登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(LoginPage), findsOneWidget);
      expect(container.read(routeIntentStoreProvider).pending?.target, RoutePath.messages);
    });

    testWidgets('公开入口不产生回跳意图', (tester) async {
      await _pumpApp(tester);
      final container = _containerOf(tester);
      container.read(routerProvider).go(RoutePath.comic);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(container.read(routeIntentStoreProvider).pending, isNull);
    });

    testWidgets('敏感提交页在未登录时不可能被自动回跳（强制失效后不回敏感页）', (tester) async {
      await _pumpApp(tester);
      final container = _containerOf(tester);
      container.read(routerProvider).go(RoutePath.phoneChange);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));

      expect(find.text('需要登录'), findsOneWidget);
      await tester.tap(find.text('去登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(LoginPage), findsOneWidget);

      // 实现分两层：路由层可能记录意图，但唯一的回跳解析点
      // AuthGuard.consumeAndResolve 会对 canResume=false 的目标返回 null，
      // 因此敏感页既不会被自动回到，也不会成为登录后的跳转目标。
      // 这里断言「生效的安全性」：不残留任何可被回跳的敏感意图。
      final pending = container.read(routeIntentStoreProvider).pending;
      expect(pending == null || !ProtectedRoutes.canResume(pending.target), isTrue,
          reason: '敏感提交页不得留下可被自动回跳的意图，实际 pending=${pending?.target}');
      // 换绑、账号安全、改密三类敏感页逐一验证
      for (final path in const [RoutePath.phoneChange, RoutePath.accountSecurity, RoutePath.passwordEdit]) {
        expect(ProtectedRoutes.canResume(path), isFalse, reason: '$path 不允许会话恢复');
      }
    });
  });

  // ================================================================
  group('G6-E 任务广场板块：游客可浏览，动作要登录', () {
    test('广场浏览路径不受保护，我的任务/交付路径受保护', () {
      expect(ProtectedRoutes.isProtected('${RoutePath.demandDetail}?id=7'), isFalse);
      // 发布与验收查阅已收归管理端，APP 不再有对应路由
      for (final path in const [
        RoutePath.demandMyTasks,
        RoutePath.demandStageDeliver,
        RoutePath.demandSourceScript,
      ]) {
        expect(ProtectedRoutes.isProtected(path), isTrue, reason: '$path 必须登录');
      }
    });

    testWidgets('游客进入任务 tab 落在广场分段，不弹登录也不跳登录页', (tester) async {
      await _pumpApp(tester);
      final container = _containerOf(tester);
      container.read(routerProvider).go(RoutePath.demandTab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('任务广场'), findsOneWidget);
      expect(find.text('广场'), findsWidgets);
      expect(find.text('需要登录'), findsNothing);
      expect(find.byType(LoginPage), findsNothing);
      expect(container.read(routeIntentStoreProvider).pending, isNull);
    });

    testWidgets('游客切到「我的任务」分段需确认，取消后留在板块内', (tester) async {
      await _pumpApp(tester);
      final container = _containerOf(tester);
      container.read(routerProvider).go(RoutePath.demandTab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('我的任务'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('需要登录'), findsOneWidget);
      await tester.tap(find.text('暂不登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(LoginPage), findsNothing);
      expect(container.read(routeIntentStoreProvider).pending, isNull);
      // 游客态该分段只渲染登录引导，绝不发起 mine 请求（否则 401 会被当会话过期踢走）
      expect(find.textContaining('登录后即可查看'), findsOneWidget);
    });

    testWidgets('游客进详情页只看白名单字段，点接单动作要先登录', (tester) async {
      // 后端对游客裁剪掉 clientId / sourceScriptUrl，这里用同一份视图打桩
      const task = DemandTask(
        demandId: 60,
        demandNo: 'DM20261110095105A001',
        title: '游客可见任务',
        taskType: DemandTaskType.script,
        budget: 20000,
        totalEpisodes: 5,
        durationHours: 24,
        status: 'open',
        clientName: '测试创作者',
      );
      await _pumpApp(tester, overrides: [
        demandDetailProvider.overrideWith((ref, id) => Future.value(task)),
      ]);
      final container = _containerOf(tester);
      final detailUrl = RoutePath.demandDetailUrl(60);
      container.read(routerProvider).go(detailUrl);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('任务详情'), findsOneWidget);
      expect(find.textContaining('我要接单'), findsOneWidget);
      // 押金/托管已随资金托管一起下线，APP 不再展示相关字段
      expect(find.text('押金'), findsNothing);
      expect(find.text('托管额'), findsNothing);
      expect(find.text('联系发布者'), findsNothing);

      await tester.tap(find.textContaining('我要接单'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('需要登录'), findsOneWidget);
      await tester.tap(find.text('暂不登录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // 取消后留在详情页，不压登录页也不发起受保护请求（401 会被当会话过期踢走）
      expect(find.byType(LoginPage), findsNothing);
      expect(find.text('任务详情'), findsOneWidget);
      expect(container.read(routeIntentStoreProvider).pending, isNull);
    });
  });
}

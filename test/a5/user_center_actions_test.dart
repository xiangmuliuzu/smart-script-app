// H-05 用户中心动作（App 端）：消息、反馈、换绑、资料更新。
//
// 对应评审标准 §7 要求：
//   - 消息未读数、单条已读、全部已读和跨用户拒绝；
//   - 反馈提交、列表、详情和错误状态；
//   - 换绑旧号验证、新号验证、手机号占用和成功后退出；
//   - 个人资料更新与全局状态同步。
//
// 走真实 ApiClient / Repository 代码路径，只替换 HTTP 传输层。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/core/constants/app_constants.dart';
import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';
import 'package:script_app/features/auth/data/auth_repository.dart';
import 'package:script_app/features/feedback/pages/feedback_create_page.dart';
import 'package:script_app/features/profile/pages/profile_edit_page.dart';
import 'package:script_app/features/user_center/data/message_repository.dart';
import 'package:script_app/features/user_center/data/user_center_models.dart';
import 'package:script_app/features/user_center/data/user_center_repository.dart';
import 'package:script_app/models/user.dart';

import '../support/scripted_api.dart';

MessageRepository _msgRepo(ScriptedApi api) => MessageRepository(ApiClient(api.buildDio()));
FeedbackRepository _fbRepo(ScriptedApi api) => FeedbackRepository(ApiClient(api.buildDio()));
UserCenterRepository _ucRepo(ScriptedApi api) => UserCenterRepository(ApiClient(api.buildDio()));

Future<void> _pumpCreateFeedback(WidgetTester tester, ScriptedApi api) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        secureTokenStorageProvider.overrideWithValue(InMemoryTokenSecureStorage()),
        api.override,
      ],
      child: const MaterialApp(home: FeedbackCreatePage()),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ================================================================
  group('H-05-A 消息：未读数 / 单条已读 / 全部已读 / 跨用户拒绝', () {
    test('未读数解析 total 与 byType', () async {
      final api = ScriptedApi();
      api.reply('/messages/unread-count', Envelope.ok({'total': 5, 'byType': {'SYSTEM': 3, 'ORDER': 2}}));
      final count = await _msgRepo(api).unreadCount();
      expect(count.total, 5);
      expect(count.byType['SYSTEM'], 3);
      expect(count.byType['ORDER'], 2);
    });

    test('单条已读使用 PUT 且重复调用幂等（不抛出）', () async {
      final api = ScriptedApi();
      api.reply('/messages/12/read', Envelope.ok(null));
      final repo = _msgRepo(api);
      await repo.markRead(12);
      await repo.markRead(12);
      expect(api.countOf('/messages/12/read'), 2);
      expect(api.requests.every((r) => r.method == 'PUT'), isTrue, reason: '已读必须是 PUT');
    });

    test('全部已读使用 PUT', () async {
      final api = ScriptedApi();
      api.reply('/messages/read-all', Envelope.ok(null));
      await _msgRepo(api).markAllRead();
      expect(api.countOf('/messages/read-all'), 1);
      expect(api.requests.first.method, 'PUT');
    });

    test('跨用户/不存在的消息详情返回 404 语义并抛出可读异常', () async {
      final api = ScriptedApi();
      api.reply('/messages/999', Envelope.fail(40400, '资源不存在'));
      await expectLater(
        _msgRepo(api).detail(999),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 40400)),
      );
    });

    test('跨用户标记已读被拒且不静默吞错', () async {
      final api = ScriptedApi();
      api.reply('/messages/999/read', Envelope.fail(40400, '资源不存在'));
      await expectLater(_msgRepo(api).markRead(999), throwsA(isA<ApiException>()));
    });

    test('消息列表分页参数传递给服务端', () async {
      final api = ScriptedApi();
      api.reply('/messages', Envelope.ok({'total': 0, 'list': <Object>[]}));
      await _msgRepo(api).list(pageNum: 2, pageSize: 20, type: 'SYSTEM');
      final q = api.requests.first.uri.queryParameters;
      expect(q['pageNum'], '2');
      expect(q['pageSize'], '20');
      expect(q['type'], 'SYSTEM');
    });
  });

  // ================================================================
  group('H-05-B 反馈：提交 / 列表 / 详情 / 错误', () {
    test('提交成功返回 feedbackId', () async {
      final api = ScriptedApi();
      api.reply('/feedback', Envelope.ok({'feedbackId': 33, 'status': 'SUBMITTED'}));
      final id = await _fbRepo(api).create(category: 'BUG', content: '这是一个可复现的问题描述');
      expect(id, 33);
      expect(api.requests.first.method, 'POST');
    });

    test('服务端未返回 feedbackId 时抛出可读异常', () async {
      final api = ScriptedApi();
      api.reply('/feedback', Envelope.ok({'status': 'SUBMITTED'}));
      await expectLater(
        _fbRepo(api).create(category: 'BUG', content: '这是一个可复现的问题描述'),
        throwsA(isA<ApiException>()),
      );
    });

    test('提交失败（业务错误）抛出服务端文案', () async {
      final api = ScriptedApi();
      api.reply('/feedback', Envelope.fail(40000, '内容不能超过 2000 个字'));
      await expectLater(
        _fbRepo(api).create(category: 'BUG', content: 'x' * 10),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', '内容不能超过 2000 个字')),
      );
    });

    test('列表为空时 isEmpty 为真', () async {
      final api = ScriptedApi();
      api.reply('/feedback', Envelope.ok({'total': 0, 'list': <Object>[]}));
      final page = await _fbRepo(api).list();
      expect(page.total, 0);
      expect(page.isEmpty, isTrue);
    });

    test('详情 404 抛出可读异常（跨用户与不存在同语义）', () async {
      final api = ScriptedApi();
      api.reply('/feedback/999', Envelope.fail(40400, '资源不存在'));
      await expectLater(
        _fbRepo(api).detail(999),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 40400)),
      );
    });
  });

  // ================================================================
  group('H-05-C 换绑手机号：旧号验证 / 新号发码 / 占用 / 确认', () {
    test('旧号验证成功返回 stepUpToken', () async {
      final api = ScriptedApi();
      api.reply('/users/me/phone/change/old/verify', Envelope.ok({'stepUpToken': 'st-1', 'expiresIn': 600}));
      final step = await _ucRepo(api).verifyOldPhone('123456');
      expect(step.stepUpToken, 'st-1');
      expect(step.expiresIn, 600);
    });

    test('旧号验证未返回凭证时抛出可读异常（不静默放行）', () async {
      final api = ScriptedApi();
      api.reply('/users/me/phone/change/old/verify', Envelope.ok({'expiresIn': 600}));
      await expectLater(_ucRepo(api).verifyOldPhone('123456'), throwsA(isA<ApiException>()));
    });

    test('新号被占用（服务端 409）抛出可读异常，客户端不自行判定占用', () async {
      final api = ScriptedApi();
      api.reply('/users/me/phone/change/new/send', Envelope.fail(40900, '该手机号已被注册'));
      await expectLater(
        _ucRepo(api).sendNewPhoneCode('13900000000'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', '该手机号已被注册')),
      );
      // 占用判定只在服务端：客户端仅提交新号
      final body = api.requests.first.data as Map;
      expect(body.containsKey('newPhone'), isTrue);
      expect(body.containsKey('taken'), isFalse);
    });

    test('确认换绑成功后返回掩码手机号（会话吊销由服务端负责）', () async {
      final api = ScriptedApi();
      api.reply('/users/me/phone/change/confirm', Envelope.ok({'phoneMasked': '139****0000'}));
      final masked = await _ucRepo(api).confirmPhoneChange(
        newPhone: '13900000000',
        code: '123456',
        stepUpToken: 'st-1',
      );
      expect(masked, '139****0000');
      final body = api.requests.first.data as Map;
      expect(body['stepUpToken'], 'st-1', reason: '确认必须携带旧号验证凭证');
    });

    test('确认失败（凭证过期/验证码错误）抛出可读异常', () async {
      final api = ScriptedApi();
      api.reply('/users/me/phone/change/confirm', Envelope.fail(40901, '验证码已失效'));
      await expectLater(
        _ucRepo(api).confirmPhoneChange(newPhone: '13900000000', code: '000000', stepUpToken: 'st-1'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  // ================================================================
  group('H-05-D 资料更新与全局同步', () {
    test('无变更时不发请求，直接提示无需保存', () async {
      final api = ScriptedApi();
      await expectLater(
        _ucRepo(api).updateProfile(),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', '没有需要保存的修改')),
      );
      expect(api.requests, isEmpty, reason: '无字段变更不应发起请求');
    });

    test('只提交发生变更的字段', () async {
      final api = ScriptedApi();
      api.reply('/users/me/profile', Envelope.ok({
        'userId': 601,
        'userType': '01',
        'nickname': '新昵称',
        'phoneMasked': '138****8000',
        'realNameStatus': 'NOT_SUBMITTED',
      }));
      final updated = await _ucRepo(api).updateProfile(nickname: '新昵称');
      expect(updated.nickname, '新昵称');
      final body = api.requests.first.data as Map;
      expect(body.keys, contains('nickname'));
      expect(body.containsKey('avatar'), isFalse, reason: '未变更字段不应提交');
    });
  });

  // ================================================================
  group('H-05-E 反馈提交页本地校验（widget）', () {
    testWidgets('内容不足 5 字时本地拦截且不发请求', (tester) async {
      final api = ScriptedApi();
      await _pumpCreateFeedback(tester, api);

      await tester.enterText(find.byType(TextField).first, '太短');
      await tester.tap(find.text('提交'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('请至少输入 5 个字'), findsOneWidget);
      expect(api.requests, isEmpty, reason: '本地校验失败不得发起请求');
    });

    testWidgets('超长内容在输入处即被截断为 2000 字（无法提交超限内容）', (tester) async {
      final api = ScriptedApi();
      await _pumpCreateFeedback(tester, api);

      await tester.enterText(find.byType(TextField).first, 'x' * 2001);
      await tester.pump();

      // 输入框 maxLength=2000：超限内容在进入控制器前已被截断，
      // 因此不存在「超长内容被提交」的路径（服务端另有长度校验作为兜底）。
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.maxLength, 2000);
      expect(field.controller!.text.length, 2000, reason: '超长输入必须被截断为上限长度');
      expect(api.requests, isEmpty, reason: '仅输入不应发起请求');
    });

    testWidgets('合法内容提交成功并提示', (tester) async {
      final api = ScriptedApi();
      api.reply('/feedback', Envelope.ok({'feedbackId': 77, 'status': 'SUBMITTED'}));
      await _pumpCreateFeedback(tester, api);

      await tester.enterText(find.byType(TextField).first, '这是一个足够长的反馈内容描述');
      await tester.tap(find.text('提交'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.countOf('/feedback'), 1);
      expect(find.textContaining('提交成功'), findsOneWidget);
    });
  });

  // ================================================================
  group('H-05-H 资料保存后的全局同步（widget）', () {
    testWidgets('保存成功：提交变更字段、刷新全局 currentUser 并重新拉取资料', (tester) async {
      final api = ScriptedApi();
      api.handle('/users/me/profile', (req) {
        final nickname = req.method == 'PUT' ? '新昵称' : '旧昵称';
        return Envelope.ok({
          'userId': 601,
          'userType': '01',
          'nickname': nickname,
          'phoneMasked': '138****8000',
          'realNameStatus': 'NOT_SUBMITTED',
        });
      });
      final repo = await _pumpProfileEdit(tester, api);

      expect(find.byType(ProfileEditPage), findsOneWidget);
      expect(find.text('旧昵称'), findsOneWidget, reason: '进入页面应展示服务端返回的当前资料');
      final getsBefore = api.countOf('/users/me/profile');
      expect(getsBefore, 1, reason: '进入页面拉取一次资料');

      await tester.enterText(find.byType(TextField).first, '新昵称');
      repo.meCalls = 0; // 只统计「保存之后」的全局刷新

      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final puts = api.requests.where((req) => req.method == 'PUT').toList();
      expect(puts, hasLength(1), reason: '保存应提交一次 PUT');
      expect((puts.single.data as Map)['nickname'], '新昵称');

      expect(repo.meCalls, 1,
          reason: '保存成功后必须 refreshMe() 刷新全局 currentUser（规格 §8.3）');
      expect(api.countOf('/users/me/profile'), greaterThan(getsBefore),
          reason: '保存后应重新拉取资料，页面展示服务端最新值');

      // 保存成功会返回上一页
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('无变更时不发请求，也不触发全局刷新', (tester) async {
      final api = ScriptedApi();
      api.reply(
        '/users/me/profile',
        Envelope.ok({
          'userId': 601,
          'userType': '01',
          'nickname': '旧昵称',
          'phoneMasked': '138****8000',
          'realNameStatus': 'NOT_SUBMITTED',
        }),
      );
      final repo = await _pumpProfileEdit(tester, api);
      repo.meCalls = 0;

      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.requests.where((r) => r.method == 'PUT'), isEmpty,
          reason: '无字段变更不得发起保存请求');
      expect(repo.meCalls, 0, reason: '未保存成功不得刷新全局 currentUser');
      // 保活的 Scaffold 可能各渲染一份 toast，故不断言唯一
      expect(find.text('没有需要保存的修改'), findsWidgets);
    });
  });

  // ================================================================
  group('A-bio 个人简介（2026-09-28 契约修订）', () {
    UserProfile bioProfile(Map<String, dynamic> extra) => UserProfile.fromJson(Map.from({
          'userId': 601,
          'userType': '01',
          'nickname': '剧本小王',
          'phoneMasked': '138****8000',
          'realNameStatus': 'NOT_SUBMITTED',
        }..addAll(extra)));

    test('模型：bio 缺省/null 解析为 null，有值时透传', () {
      expect(bioProfile({}).bio, isNull);
      expect(bioProfile({'bio': null}).bio, isNull);
      expect(bioProfile({'bio': '热爱剧本创作'}).bio, '热爱剧本创作');
    });

    test('新增简介：只提交 bio，未变更字段不上送', () async {
      final api = ScriptedApi();
      api.reply('/users/me/profile', Envelope.ok({
        'userId': 601, 'userType': '01', 'nickname': '剧本小王',
        'bio': '热爱剧本创作', 'phoneMasked': '138****8000',
      }));
      final updated = await _ucRepo(api).updateProfile(bio: '热爱剧本创作');
      expect(updated.bio, '热爱剧本创作');
      final body = api.requests.first.data as Map;
      expect(body['bio'], '热爱剧本创作');
      expect(body.containsKey('nickname'), isFalse, reason: '未变更的昵称不应提交');
      expect(body.containsKey('avatar'), isFalse, reason: '未变更的头像不应提交');
    });

    test('清空简介：提交空串 bio（契约允许清空）', () async {
      final api = ScriptedApi();
      api.reply('/users/me/profile', Envelope.ok({
        'userId': 601, 'userType': '01', 'nickname': '剧本小王',
        'phoneMasked': '138****8000',
      }));
      final updated = await _ucRepo(api).updateProfile(bio: '');
      expect(updated.bio, isNull, reason: '服务端空简介返回 null（未填写）');
      final body = api.requests.first.data as Map;
      expect(body['bio'], '', reason: '清空必须显式提交空串，而非省略字段');
    });

    test('简介与昵称同时修改：两个字段都上送', () async {
      final api = ScriptedApi();
      api.reply('/users/me/profile', Envelope.ok({
        'userId': 601, 'userType': '01', 'nickname': '新昵称', 'bio': '新简介',
        'phoneMasked': '138****8000',
      }));
      await _ucRepo(api).updateProfile(nickname: '新昵称', bio: '新简介');
      final body = api.requests.first.data as Map;
      expect(body['nickname'], '新昵称');
      expect(body['bio'], '新简介');
    });

    test('简介超长在本地即被拒绝，不发请求', () async {
      final api = ScriptedApi();
      await expectLater(
        _ucRepo(api).updateProfile(bio: 'x' * 201),
        throwsA(isA<ApiException>()),
      );
      expect(api.requests, isEmpty, reason: '超长简介不得发起请求');
    });

    testWidgets('编辑页：加载简介、保存提交 bio 并刷新全局资料', (tester) async {
      final api = ScriptedApi();
      api.handle('/users/me/profile', (req) {
        if (req.method == 'PUT') {
          return Envelope.ok({
            'userId': 601, 'userType': '01', 'nickname': '剧本小王',
            'bio': '热爱剧本创作', 'phoneMasked': '138****8000',
          });
        }
        return Envelope.ok({
          'userId': 601, 'userType': '01', 'nickname': '剧本小王',
          'phoneMasked': '138****8000',
        });
      });
      final repo = await _pumpProfileEdit(tester, api);

      // 简介输入框是第二个 TextField（昵称、简介）
      final bioField = find.byType(TextField).at(1);
      expect(tester.widget<TextField>(bioField).maxLength, 200,
          reason: '简介输入框上限必须与服务端一致（200）');

      repo.meCalls = 0;
      await tester.enterText(bioField, '热爱剧本创作');
      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final puts = api.requests.where((req) => req.method == 'PUT').toList();
      expect(puts, hasLength(1));
      expect((puts.single.data as Map)['bio'], '热爱剧本创作');
      expect((puts.single.data as Map).containsKey('nickname'), isFalse);
      expect(repo.meCalls, 1, reason: '保存成功后必须刷新全局 currentUser');

      // 与既有成功用例一致：冲刷退出动画与网络定时器
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('清空简介后保存：PUT 提交空串 bio', (tester) async {
      final api = ScriptedApi();
      api.handle('/users/me/profile', (req) {
        if (req.method == 'PUT') {
          return Envelope.ok({
            'userId': 601, 'userType': '01', 'nickname': '剧本小王',
            'phoneMasked': '138****8000',
          });
        }
        return Envelope.ok({
          'userId': 601, 'userType': '01', 'nickname': '剧本小王',
          'bio': '旧简介', 'phoneMasked': '138****8000',
        });
      });
      final repo = await _pumpProfileEdit(tester, api);

      final bioField = find.byType(TextField).at(1);
      expect(find.text('旧简介'), findsOneWidget, reason: '进入页面应展示当前简介');

      repo.meCalls = 0;
      await tester.enterText(bioField, '');
      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final puts = api.requests.where((req) => req.method == 'PUT').toList();
      expect(puts, hasLength(1), reason: '清空也是一次真实变更');
      expect((puts.single.data as Map)['bio'], '');
      expect(repo.meCalls, 1);

      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('保存失败（超长被服务端拒绝）：提示错误、不刷新、不退出', (tester) async {
      final api = ScriptedApi();
      api.handle('/users/me/profile', (req) {
        if (req.method == 'PUT') {
          return Envelope.fail(40000, 'bio too long');
        }
        return Envelope.ok({
          'userId': 601, 'userType': '01', 'nickname': '剧本小王',
          'bio': '旧简介', 'phoneMasked': '138****8000',
        });
      });
      final repo = await _pumpProfileEdit(tester, api);

      repo.meCalls = 0;
      await tester.enterText(find.byType(TextField).at(1), '新简介');
      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('bio too long'), findsWidgets,
          reason: '应展示服务端错误信息');
      expect(repo.meCalls, 0, reason: '保存失败不得刷新全局资料');
      expect(find.byType(ProfileEditPage), findsOneWidget, reason: '失败不应退出编辑页');
    });
  });
}

/// 只统计 me() 调用的假认证仓库：用于断言保存后刷新了全局 currentUser。
class _CountingMeRepo implements AuthRepository {
  int meCalls = 0;

  @override
  Future<User> me() async {
    meCalls++;
    return const User(userId: 601, userType: UserType.user, nickname: '新昵称');
  }

  @override
  Future<void> logout() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_CountingMeRepo> _pumpProfileEdit(WidgetTester tester, ScriptedApi api) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final secure = InMemoryTokenSecureStorage();
  // 有凭据，_restore 才会走到 me()（全局身份摘要）
  await secure.write(AppConstants.kAccessToken, 'at');
  await secure.write(AppConstants.kRefreshToken, 'rt');
  final repo = _CountingMeRepo();

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('home'))),
      GoRoute(path: '/profile/edit', builder: (_, __) => const ProfileEditPage()),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        secureTokenStorageProvider.overrideWithValue(secure),
        tokenStorageProvider.overrideWithValue(TokenStorage(secure, prefs)),
        // 资料读写走真实 Repository/ApiClient，只替换 HTTP 传输层
        apiClientProvider.overrideWithValue(ApiClient(api.buildDio())),
        authRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  router.push('/profile/edit');
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return repo;
}

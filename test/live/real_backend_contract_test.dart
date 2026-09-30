// 真实后端联调（App 端）：身份五路径 + 用户中心契约 + 跨用户拒绝 + Token 域隔离。
//
// 评审标准 §7 明确要求：「真实联调测试不能因后端未启动而在发布验收中静默跳过。
// CI 或验收脚本必须先启动完整依赖，再运行 Flutter 联调用例。」
//
// 因此本文件**不做 skip**：
//   - 后端不可达时立即失败，并打印可执行的启动步骤；
//   - 凭据只从环境变量读取，缺失即失败（不内置可用凭据）。
//
// 运行（单元/widget 阶段不包含本目录）：
//   flutter test test/live
//
// 环境变量：
//   LIVE_BASE_URL       默认 http://127.0.0.1:8080/api/v1
//   LIVE_SMS_CODE       测试环境 Mock 短信验证码（与后端 APP_SMS_MOCK_CODE 一致）
//   LIVE_ADMIN_USER     管理端账号（已实名 / 有角色路径需要）
//   LIVE_ADMIN_PASSWORD 管理端口令
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';
import 'package:script_app/features/auth/data/auth_repository.dart';
import 'package:script_app/features/bookstore/data/content_repository.dart';
import 'package:script_app/features/user_center/data/message_repository.dart';
import 'package:script_app/features/user_center/data/user_center_repository.dart';

final String kBase =
    Platform.environment['LIVE_BASE_URL'] ?? 'http://127.0.0.1:8080/api/v1';
final String kSmsCode = Platform.environment['LIVE_SMS_CODE'] ?? '';
final String kAdminUser = Platform.environment['LIVE_ADMIN_USER'] ?? '';
final String kAdminPassword = Platform.environment['LIVE_ADMIN_PASSWORD'] ?? '';

/// 后端根地址（去掉 /api/v1 前缀），用于健康检查与 PC 管理端登录。
String get kHostRoot => kBase.replaceAll(RegExp(r'/api/v1/?$'), '');

/// 接入真实后端的 App 端网络栈（真实拦截器 + 真实 TokenStorage）。
class LiveStack {
  LiveStack(this.secure, this.storage, this.apiClient, this.repository);

  final TokenSecureStorage secure;
  final TokenStorage storage;
  final ApiClient apiClient;
  final AuthRepository repository;
}

Future<LiveStack> _stack() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final secure = InMemoryTokenSecureStorage();
  final storage = TokenStorage(secure, prefs);
  final graph = AuthNetworkGraph.create(storage);
  // AuthNetworkGraph 使用编译期 BASE_URL；此处指向运行时真实后端地址
  graph.apiClient.dioForTest.options.baseUrl = kBase;
  return LiveStack(secure, storage, graph.apiClient, graph.repository);
}

class LiveAccount {
  LiveAccount(this.userId, this.phone, this.token);

  final int userId;
  final String phone;
  final String token;
}

String _randPhone() {
  final n = DateTime.now().microsecondsSinceEpoch % 100000000;
  return '139${n.toString().padLeft(8, '0')}';
}

/// 通过真实注册接口建立账号，并把会话写入本地存储（供拦截器注入 Bearer）。
Future<LiveAccount> _registerAccount(LiveStack stack) async {
  final phone = _randPhone();
  await stack.repository.sendSms(phone: phone, scene: 'REGISTER');
  final session = await stack.repository.register(
    phone: phone,
    code: kSmsCode,
    password: 'LiveCheck!2026',
    deviceId: 'live-integration',
  );
  await stack.storage.saveSession(
    accessToken: session.accessToken,
    refreshToken: session.refreshToken,
    user: session.user.toJson(),
  );
  return LiveAccount(session.user.userId, phone, session.accessToken);
}

Future<LiveAccount> _loginAccount(LiveStack stack, String phone) async {
  // 验证码登录需先按 LOGIN 场景发码（与注册场景独立，不受注册冷却影响）
  await stack.repository.sendSms(phone: phone, scene: 'LOGIN');
  final session = await stack.repository.smsLogin(
    phone: phone,
    code: kSmsCode,
    deviceId: 'live-integration',
  );
  await stack.storage.saveSession(
    accessToken: session.accessToken,
    refreshToken: session.refreshToken,
    user: session.user.toJson(),
  );
  return LiveAccount(session.user.userId, phone, session.accessToken);
}

Future<Dio> _adminDio() async {
  final loginDio = Dio(BaseOptions(baseUrl: kHostRoot, contentType: Headers.jsonContentType));
  final resp = await loginDio.post('/login', data: {
    'username': kAdminUser,
    'password': kAdminPassword,
  });
  final token = (resp.data as Map)['token'] as String?;
  if (token == null || token.isEmpty) {
    throw StateError('管理端登录未返回 token，请检查 LIVE_ADMIN_USER / LIVE_ADMIN_PASSWORD');
  }
  return Dio(BaseOptions(
    baseUrl: kHostRoot,
    contentType: Headers.jsonContentType,
    headers: {'Authorization': 'Bearer $token'},
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // flutter_test 的 TestWidgetsFlutterBinding 会把所有 HttpClient 替换为
    // 「一律返回 400」的 mock；真实联调必须恢复真实实现，否则无法联后端。
    // 这是本套用例必须显式处理的前置，也是「不静默跳过」的一部分。
    HttpOverrides.global = null;

    // 前置校验必须显式失败，绝不静默跳过（评审标准 §7）
    if (kSmsCode.isEmpty) {
      fail('缺少 LIVE_SMS_CODE：真实联调不接受内置凭据，也不允许跳过。'
          '示例：LIVE_SMS_CODE=<后端 APP_SMS_MOCK_CODE> flutter test test/live');
    }
    if (kAdminUser.isEmpty || kAdminPassword.isEmpty) {
      fail('缺少 LIVE_ADMIN_USER / LIVE_ADMIN_PASSWORD：已实名与有角色路径需要管理端账号。');
    }
    final probe = Dio(BaseOptions(baseUrl: kHostRoot, connectTimeout: const Duration(seconds: 5)));
    try {
      await probe.get('/captchaImage');
    } catch (e) {
      fail('后端不可达（$kHostRoot）：真实联调必须先把完整依赖启动后再运行。'
          '启动方式见《A5-A7-加固-第3批执行记录.md》复现一节。底层错误：$e');
    }
  });

  test('游客路径：公开列表可读、私有接口被拒', () async {
    final stack = await _stack();
    final content = ContentRepository(stack.apiClient);

    // 书城作品列表是公开接口，游客可读；载荷为 {total, list}，不下发身份摘要。
    final works = await content.pageWorks(pageNum: 1, pageSize: 5);
    expect(works.total, greaterThanOrEqualTo(0));
    expect(works.list.length, lessThanOrEqualTo(5));

    await expectLater(content.shelf(), throwsA(isA<ApiException>()),
        reason: '游客访问需登录的书架接口必须被拒绝');
  });

  test('注册登录：真实下发 App 会话，且与 /auth/me 一致', () async {
    final stack = await _stack();
    final account = await _registerAccount(stack);
    expect(account.token, isNotEmpty);
    expect(account.userId, greaterThan(0));

    final me = await stack.repository.me();
    expect(me.userId, account.userId, reason: '/auth/me 必须返回同一用户');
  });

  test('未实名路径：实名未提交、无角色、书架不具备下载准入', () async {
    final stack = await _stack();
    final account = await _registerAccount(stack);

    final me = await stack.repository.me();
    expect(me.realNameStatus, 'NOT_SUBMITTED');
    expect(me.roles, isEmpty, reason: '新注册账号无角色');
    expect(me.isRealNameApproved, isFalse);

    final shelf = await ContentRepository(stack.apiClient).shelf();
    expect(shelf.downloadable, isFalse, reason: '未实名不得放行下载');
    expect(shelf.realNameRequired, isTrue);
    expect(shelf.identity.userId, account.userId, reason: '归属必须来自服务端下发的身份');
    expect(shelf.works, isNotEmpty, reason: '书架应返回作品列表');
  });

  test('无角色路径：角色判定与实名判定取不同字段，互不推导', () async {
    final stack = await _stack();
    await _registerAccount(stack);

    final me = await stack.repository.me();
    expect(me.roles, isEmpty);
    expect(me.hasRole('common'), isFalse);
    expect(me.isRealNameApproved, isFalse, reason: '无角色不等于已实名');
  });

  test('反馈闭环：提交 → 列表 → 详情（真实后端）', () async {
    final stack = await _stack();
    await _registerAccount(stack);

    final feedback = FeedbackRepository(stack.apiClient);
    final content = '真实联调反馈：${DateTime.now().millisecondsSinceEpoch}';
    final id = await feedback.create(category: 'BUG', content: content);
    expect(id, greaterThan(0));

    final page = await feedback.list();
    expect(page.list.any((f) => f.feedbackId == id), isTrue, reason: '列表必须包含刚提交的反馈');

    final detail = await feedback.detail(id);
    expect(detail.content, content, reason: '详情内容必须与提交一致');
  });

  test('消息未读数：真实后端返回可解析的计数', () async {
    final stack = await _stack();
    await _registerAccount(stack);

    final count = await MessageRepository(stack.apiClient).unreadCount();
    expect(count.total, greaterThanOrEqualTo(0));
  });

  test('跨用户拒绝：A 不得读取 B 的反馈（真实后端按不存在处理）', () async {
    final stackA = await _stack();
    final accountA = await _registerAccount(stackA);

    final stackB = await _stack();
    await _registerAccount(stackB);
    final bId = await FeedbackRepository(stackB.apiClient)
        .create(category: 'BUG', content: 'B 的反馈，仅用于跨用户拒绝验证。');

    // 切回 A 的 Token 访问 B 的资源
    stackA.storage.saveSession(accessToken: accountA.token, refreshToken: 'x');
    await expectLater(
      FeedbackRepository(stackA.apiClient).detail(bId),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 40400)),
      reason: '跨用户读取必须按资源不存在处理',
    );
  });

  test('Token 域隔离：App Token 访问 PC 管理端被拒（真实后端）', () async {
    final stack = await _stack();
    final account = await _registerAccount(stack);

    final dio = Dio(BaseOptions(baseUrl: kHostRoot, contentType: Headers.jsonContentType));
    final resp = await dio.get(
      '/api/v1/admin/app-users',
      queryParameters: {'pageNum': 1, 'pageSize': 5},
      options: Options(
        headers: {'Authorization': 'Bearer ${account.token}'},
        validateStatus: (_) => true,
      ),
    );
    final body = resp.data;
    final code = (body is Map) ? body['code'] : null;
    expect(resp.statusCode == 401 || resp.statusCode == 403 || code == 401 || code == 403, isTrue,
        reason: 'App Token 不得访问管理端，实际 HTTP=${resp.statusCode} code=$code');
  });

  test('已实名路径：管理端审核通过后准入放行（真实后端全链路）', () async {
    final stack = await _stack();
    final account = await _registerAccount(stack);

    await UserCenterRepository(stack.apiClient).submitRealName(
      realName: '联调用户',
      idNumber: '110101199001011234',
      materialRefs: const ['/profile/upload/live-integration.png'],
      resubmit: false,
    );

    final admin = await _adminDio();
    // status=PENDING + applicationId 降序：h2_test 已积累数千条历史申请且服务端
    // pageSize 上限 100，无过滤/无排序的首页不保证包含本条新申请（第 21 批实测
    // total=5573、PENDING 196 条 > 上限 100）。过滤与排序不改变用例意图：
    // 断言的仍是「刚提交的申请可被管理端查到并决定」。
    final listResp = await admin.get('/api/v1/admin/real-name-applications', queryParameters: {
      'pageNum': 1,
      'pageSize': 100,
      'status': 'PENDING',
      'orderByColumn': 'applicationId',
      'isAsc': 'desc',
    });
    final rows = ((listResp.data as Map)['rows'] as List).cast<Map>();
    final mine = rows.where((r) => r['userId'] == account.userId).toList();
    expect(mine, isNotEmpty, reason: '管理端应能查到刚提交的实名申请');
    final appId = mine.first['applicationId'];

    await admin.put('/api/v1/admin/real-name-applications/$appId/decision',
        data: {'decision': 'APPROVE', 'expectedStatus': 'PENDING'});

    final me = await stack.repository.me();
    expect(me.realNameStatus, 'APPROVED', reason: '审核通过后身份摘要必须为已实名');
    expect(me.isRealNameApproved, isTrue);

    final shelf = await ContentRepository(stack.apiClient).shelf();
    expect(shelf.downloadable, isTrue, reason: '已实名后准入放行');
    expect(shelf.realNameRequired, isFalse);
  });

  test('有角色路径：管理端授权后角色生效（真实后端）', () async {
    final stack = await _stack();
    final account = await _registerAccount(stack);

    final admin = await _adminDio();
    // A4 契约：App 用户只能授予 app_grantable=1 的角色（role_id=2 默认为 0，不可授）
    await admin.put('/api/v1/admin/app-users/${account.userId}/roles',
        data: {'roleIds': [100], 'reason': 'A 模块实时联调'});

    // 重新登录后角色必须生效
    final relogin = await _loginAccount(stack, account.phone);
    expect(relogin.userId, account.userId, reason: '同一账号重新登录');
    final me = await stack.repository.me();
    expect(me.roles, contains('app_creator'), reason: '重新登录后角色必须生效');
    expect(me.hasRole('app_creator'), isTrue);
    expect(me.permissions, isNotEmpty, reason: '有角色应带权限集');
    expect(me.isRealNameApproved, isFalse, reason: '有角色不等于已实名（互不推导）');
  });
}

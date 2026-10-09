// B 模块 AI 辅助创作真实联调（接口 2.9.10 写作 / 2.9.11 润色 / 2.9.12 记录 / 2.9.13 大纲）。
//
// 四个接口均为私有（需 App Token）：路径落在 /content/ai/**，未登记 App 凭证域白名单，走 authenticated。
//
// 本批为「仅后端」：App 端无对应页面与数据层规格（接口文档 2.9.10~2.9.13 的「对应页面」章节为空），
// 故本测试直接用 Dio 打后端接口，不经过业务 Repository。
//
// 依赖外部 AI 服务（后端转发到 AI_SERVICE_URL，默认 http://127.0.0.1:3000）：
//   - 正常运行：本机起 stub AI 服务，覆盖 401 / 写作 / 润色 / 记录 / 大纲；
//   - 不可用验证：停掉 stub 且设 LIVE_AI_DOWN=true，仅跑 503 分支。
//
// 前置：后端已启动（java -jar ruoyi-admin.jar）。
//
// 运行：
//   LIVE_SMS_CODE=<mock码> flutter test test/live/ai_contract_test.dart
//   LIVE_AI_DOWN=true LIVE_SMS_CODE=<mock码> flutter test test/live/ai_contract_test.dart
//
// 环境变量：
//   LIVE_BASE_URL   默认 http://127.0.0.1:8080/api/v1
//   LIVE_SMS_CODE   测试环境 Mock 短信验证码（与后端 APP_SMS_MOCK_CODE 一致）
//   LIVE_AI_DOWN    'true' 时只验证 AI 服务不可用按 503 拒绝
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';

final String kBase =
    Platform.environment['LIVE_BASE_URL'] ?? 'http://127.0.0.1:8080/api/v1';
final String kSmsCode = Platform.environment['LIVE_SMS_CODE'] ?? '';
final bool kAiDown = Platform.environment['LIVE_AI_DOWN'] == 'true';

/// 构造裸 Dio（与 ApiClient.buildDio 相同的状态码口径），可选注入 Bearer。
Dio _rawDio({String? token}) => Dio(BaseOptions(
      baseUrl: kBase,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 60),
      contentType: Headers.jsonContentType,
      validateStatus: (status) => status != null && status < 500 && status != 401,
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
    ));

String _randPhone() {
  final n = DateTime.now().microsecondsSinceEpoch % 100000000;
  return '136${n.toString().padLeft(8, '0')}';
}

/// 注册随机账号并返回 App Access Token。
Future<String> _loginToken() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final storage = TokenStorage(InMemoryTokenSecureStorage(), prefs);
  final graph = AuthNetworkGraph.create(storage);
  graph.apiClient.dioForTest.options.baseUrl = kBase;

  final phone = _randPhone();
  await graph.repository.sendSms(phone: phone, scene: 'REGISTER');
  final session = await graph.repository.register(
    phone: phone,
    code: kSmsCode,
    password: 'LiveCheck!2026',
    deviceId: 'live-ai',
  );
  return session.accessToken;
}

/// 整个测试文件只注册一次并复用 Token：
/// 注册会发短信，后端对同 IP 有「每小时短信上限」（默认 30），逐用例注册会触发 42902。
String? _cachedToken;

Future<String> _token() async => _cachedToken ??= await _loginToken();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // flutter_test 会把 HttpClient 替换为「一律 400」的 mock，真实联调必须还原。
    HttpOverrides.global = null;
    if (kSmsCode.isEmpty) {
      fail('缺少 LIVE_SMS_CODE：真实联调不接受内置凭据，也不允许跳过。'
          '示例：LIVE_SMS_CODE=123456 flutter test test/live/ai_contract_test.dart');
    }
    final probe = Dio(BaseOptions(baseUrl: kBase, connectTimeout: const Duration(seconds: 5)));
    try {
      await probe.get('/content/ai/write-records');
    } on DioException {
      // 接口存在（未登录会 401）；连不通才视为后端未启动
    } catch (e) {
      fail('后端不可达（$kBase）：请先启动后端。底层错误：$e');
    }
  });

  // ===== 仅验证 AI 服务不可用：停掉 stub 后以 LIVE_AI_DOWN=true 运行 =====
  if (kAiDown) {
    test('AI 服务不可用：写作/润色/大纲均按 503 拒绝，不返回编造内容', () async {
      final token = await _token();
      final client = ApiClient(_rawDio(token: token));

      Future<void> expect503(Future<void> Function() call) async {
        await expectLater(
          call(),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 503)),
        );
      }

      await expect503(() => client.post('/content/ai/write', data: {'prompt': '写一段开场'}));
      await expect503(() => client.post('/content/ai/polish', data: {'content': '待润色的句子'}));
      await expect503(() => client.post('/content/ai/outline', data: {'inspiration': '雨夜'}));
    });
    return;
  }

  // ===== 正常链路（stub AI 服务在线）=====
  group('鉴权', () {
    test('未登录访问四个 AI 接口一律 401', () async {
      final guest = ApiClient(_rawDio());

      Future<void> expect401(Future<void> Function() call) async {
        await expectLater(
          call(),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 401)),
        );
      }

      await expect401(() => guest.post('/content/ai/write', data: {'prompt': 'x'}));
      await expect401(() => guest.post('/content/ai/polish', data: {'content': 'x'}));
      await expect401(() => guest.get('/content/ai/write-records'));
      await expect401(() => guest.post('/content/ai/outline', data: {'inspiration': 'x'}));
    });
  });

  group('2.9.10 AI 写作', () {
    test('生成内容并落库，返回 content 与 recordId', () async {
      final token = await _token();
      final client = ApiClient(_rawDio(token: token));
      final data = await client.post<Map<String, dynamic>>(
        '/content/ai/write',
        data: {'prompt': '一个雨夜，主角回到旧宅', 'type': 'scene'},
        parser: (raw) => Map<String, dynamic>.from(raw as Map),
      );
      expect(data, isNotNull);
      expect((data!['content'] as String).isNotEmpty, isTrue, reason: '应返回生成内容');
      expect(data['recordId'] as int, greaterThan(0), reason: '应返回落库记录ID');
    });

    test('prompt 为空按 400 拒绝', () async {
      final token = await _token();
      final client = ApiClient(_rawDio(token: token));
      await expectLater(
        client.post('/content/ai/write', data: {'prompt': '   '}),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 400)),
      );
    });
  });

  group('2.9.11 AI 润色', () {
    test('润色内容并落库，返回 content 与 recordId', () async {
      final token = await _token();
      final client = ApiClient(_rawDio(token: token));
      final data = await client.post<Map<String, dynamic>>(
        '/content/ai/polish',
        data: {'content': '他把门推开，里面一片漆黑。', 'style': '文学'},
        parser: (raw) => Map<String, dynamic>.from(raw as Map),
      );
      expect(data, isNotNull);
      expect((data!['content'] as String).isNotEmpty, isTrue, reason: '应返回润色后内容');
      expect(data['recordId'] as int, greaterThan(0));
    });

    test('content 为空按 400 拒绝', () async {
      final token = await _token();
      final client = ApiClient(_rawDio(token: token));
      await expectLater(
        client.post('/content/ai/polish', data: {'content': ''}),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 400)),
      );
    });
  });

  group('2.9.12 AI 写作记录', () {
    test('分页返回当前用户记录，且能查到刚落库的记录', () async {
      final token = await _token();
      final client = ApiClient(_rawDio(token: token));

      final written = await client.post<Map<String, dynamic>>(
        '/content/ai/write',
        data: {'prompt': '记录用例：主角登场'},
        parser: (raw) => Map<String, dynamic>.from(raw as Map),
      );
      final recordId = written!['recordId'] as int;

      final page = await client.get<Map<String, dynamic>>(
        '/content/ai/write-records',
        query: {'page': 1, 'pageSize': 20},
        parser: (raw) => Map<String, dynamic>.from(raw as Map),
      );
      expect(page, isNotNull);
      expect(page!['total'] as int, greaterThanOrEqualTo(1), reason: '应至少有刚落库的记录');
      final list = (page['list'] as List).cast<Map<String, dynamic>>();
      expect(list, isNotEmpty);
      expect(
        list.any((e) => e['recordId'] == recordId),
        isTrue,
        reason: '分页结果应包含刚落库的 recordId=$recordId',
      );
      final first = list.first;
      expect(first['writeType'], isNotNull);
      expect(first['createdAt'], isNotNull);
    });
  });

  group('2.9.13 AI 大纲生成', () {
    test('生成大纲并落 sys_ai_request，返回 outline/requestNo/quotaUsed=1', () async {
      final token = await _token();
      final client = ApiClient(_rawDio(token: token));
      final data = await client.post<Map<String, dynamic>>(
        '/content/ai/outline',
        data: {'inspiration': '一场跨越十年的复仇', 'genre': '悬疑', 'style': '冷峻'},
        parser: (raw) => Map<String, dynamic>.from(raw as Map),
      );
      expect(data, isNotNull);
      expect(data!['outline'], isNotNull, reason: '应返回生成的大纲对象');
      expect((data['requestNo'] as String).isNotEmpty, isTrue, reason: '应返回请求编号');
      expect(data['quotaUsed'], 1, reason: '本批 quotaUsed 固定记 1');
    });
  });
}
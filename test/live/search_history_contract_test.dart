// B 模块搜索历史真实联调（App 端）：2.7.4 列表 / 2.7.5 删单条 / 2.7.6 清空，
// 以及契约未定义、按 sys_search_history 表补齐的写入接口（POST 记录）。
//
// 这组接口是 App 私有（需 App Access Token），因此单独成文件，不复用纯游客的
// content_preview / content_contact：那两个文件的用例不需要任何凭据。
// 本文件用随机手机号真实注册建号（历史天然为空），断言只覆盖契约行为。
//
// 不做 skip：后端不可达或缺失 LIVE_SMS_CODE 时立即失败（评审标准 §7）。
//
// 运行：LIVE_SMS_CODE=123456 flutter test test/live/search_history_contract_test.dart
//
// 环境变量：
//   LIVE_BASE_URL  默认 http://127.0.0.1:8080/api/v1
//   LIVE_SMS_CODE  测试环境 Mock 短信验证码（与后端 APP_SMS_MOCK_CODE 一致）
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';
import 'package:script_app/features/bookstore/data/content_repository.dart';

final String kBase =
    Platform.environment['LIVE_BASE_URL'] ?? 'http://127.0.0.1:8080/api/v1';
final String kSmsCode = Platform.environment['LIVE_SMS_CODE'] ?? '';

/// 无 Token 的裸 Dio 仓库：用于验证未登录被拒（401）。
ContentRepository _guestRepo() {
  final dio = Dio(BaseOptions(
    baseUrl: kBase,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 10),
  ));
  return ContentRepository(ApiClient(dio));
}

String _randPhone() {
  final n = DateTime.now().microsecondsSinceEpoch % 100000000;
  return '138${n.toString().padLeft(8, '0')}';
}

/// 注册随机账号并返回已注入 Bearer 的仓库（会话已写入本地存储供拦截器使用）。
Future<ContentRepository> _loggedInRepo() async {
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
    deviceId: 'live-search-history',
  );
  await storage.saveSession(
    accessToken: session.accessToken,
    refreshToken: session.refreshToken,
    user: session.user.toJson(),
  );
  return ContentRepository(graph.apiClient);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // flutter_test 会把 HttpClient 替换为「一律 400」的 mock，真实联调必须还原。
    HttpOverrides.global = null;
    if (kSmsCode.isEmpty) {
      fail('缺少 LIVE_SMS_CODE：真实联调不接受内置凭据，也不允许跳过。'
          '示例：LIVE_SMS_CODE=123456 flutter test test/live');
    }
    final probe = Dio(BaseOptions(baseUrl: kBase, connectTimeout: const Duration(seconds: 5)));
    try {
      await probe.get('/content/works');
    } catch (e) {
      fail('后端不可达（$kBase）：请先启动后端。底层错误：$e');
    }
  });

  test('搜索历史：写入→合并计数→列表倒序→删单条→清空', () async {
    final repo = await _loggedInRepo();

    // 新账号历史为空。
    expect(await repo.listSearchHistory(), isEmpty, reason: '新注册账号不应有搜索历史');

    // 写入一条：中文关键词需无损（JSON body UTF-8）。
    await repo.recordSearchHistory('科幻科幻');
    final afterFirst = await repo.listSearchHistory();
    expect(afterFirst.length, 1);
    expect(afterFirst.first.keyword, '科幻科幻');
    expect(afterFirst.first.searchCount, 1);

    // 同关键词再查：合并计数而非新增。
    await repo.recordSearchHistory('科幻科幻');
    final afterMerge = await repo.listSearchHistory();
    expect(afterMerge.length, 1, reason: '重复关键词应合并为一条');
    expect(afterMerge.first.searchCount, 2);

    // 再写另一个关键词：按最近搜索时间倒序，新关键词在前。
    await repo.recordSearchHistory('悬疑');
    final afterSecond = await repo.listSearchHistory();
    expect(afterSecond.length, 2);
    expect(afterSecond.first.keyword, '悬疑');

    // 删除单条：目标消失，其余保留。
    final sciFi = afterSecond.firstWhere((e) => e.keyword == '科幻科幻');
    await repo.removeSearchHistory(sciFi.id);
    final afterRemove = await repo.listSearchHistory();
    expect(afterRemove.map((e) => e.keyword), isNot(contains('科幻科幻')));

    // 删除不存在/非本人记录：按 404 拒绝（归属由服务端身份决定）。
    await expectLater(
      repo.removeSearchHistory(999999999),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 404)),
    );

    // 清空：幂等，重复调用仍成功。
    await repo.clearSearchHistory();
    expect(await repo.listSearchHistory(), isEmpty);
    await repo.clearSearchHistory();
  });

  test('搜索历史：空关键词与超长关键词按 400 拒绝', () async {
    final repo = await _loggedInRepo();

    await expectLater(
      repo.recordSearchHistory('   '),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 400)),
    );
    await expectLater(
      repo.recordSearchHistory('x' * 101),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 400)),
    );
  });

  test('搜索历史：未登录（无 Token）被拒', () async {
    final guest = _guestRepo();
    await expectLater(
      guest.listSearchHistory(),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 401)),
    );
    await expectLater(
      guest.recordSearchHistory('游客'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 401)),
    );
  });
}
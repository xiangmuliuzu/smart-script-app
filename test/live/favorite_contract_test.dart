// B 模块收藏真实联调（App 端）：2.7.10 收藏/取消（含幂等与 404）、2.7.11 收藏列表，
// 以及契约未定义、按约定补充的收藏态查询（GET /content/favorites/{workId}）。
//
// 这组接口是 App 私有（需 App Access Token），因此单独成文件，不复用纯游客的
// content_preview / content_contact。用随机手机号真实注册建号（收藏天然为空），
// 断言只覆盖契约行为，并在结束时取消收藏，避免污染真实库。
//
// 不做 skip：后端不可达或缺失 LIVE_SMS_CODE 时立即失败（评审标准 §7）。
//
// 运行：LIVE_SMS_CODE=123456 flutter test test/live/favorite_contract_test.dart
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
    deviceId: 'live-favorite',
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

  test('收藏：列表为空→收藏→收藏态→幂等→列表可见→取消→幂等→列表为空', () async {
    final repo = await _loggedInRepo();

    // 取一部真实上架作品作为收藏目标；书城无数据时无法联调，直接失败。
    final works = await repo.pageWorks(pageNum: 1, pageSize: 1);
    expect(works.list, isNotEmpty, reason: '书城无上架作品，无法进行收藏联调');
    final workId = works.list.first.workId;

    // 新账号收藏为空。
    expect((await repo.pageFavorites(pageNum: 1, pageSize: 10)).list, isEmpty,
        reason: '新注册账号不应有收藏');
    expect((await repo.favoriteStatus(workId)).favorited, isFalse);

    // 收藏：成功后可查到收藏态，列表含目标作品。
    await repo.addFavorite(workId);
    expect((await repo.favoriteStatus(workId)).favorited, isTrue);
    final afterAdd = await repo.pageFavorites(pageNum: 1, pageSize: 10);
    expect(afterAdd.list.map((e) => e.workId), contains(workId));

    // 重复收藏：幂等成功，不产生重复项。
    await repo.addFavorite(workId);
    final afterDup = await repo.pageFavorites(pageNum: 1, pageSize: 10);
    expect(afterDup.list.where((e) => e.workId == workId).length, 1,
        reason: '重复收藏应幂等，不产生重复记录');

    // 取消收藏：收藏态翻转，列表不再包含。
    await repo.removeFavorite(workId);
    expect((await repo.favoriteStatus(workId)).favorited, isFalse);
    expect((await repo.pageFavorites(pageNum: 1, pageSize: 10)).list, isEmpty);

    // 重复取消：幂等成功（不返回 404）。
    await repo.removeFavorite(workId);
  });

  test('收藏：收藏不可见作品按 404 拒绝', () async {
    final repo = await _loggedInRepo();
    await expectLater(
      repo.addFavorite(999999999),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 404)),
    );
  });

  test('收藏：未登录（无 Token）被拒', () async {
    final guest = _guestRepo();
    await expectLater(
      guest.addFavorite(1),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 401)),
    );
    await expectLater(
      guest.pageFavorites(pageNum: 1, pageSize: 10),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 401)),
    );
    await expectLater(
      guest.favoriteStatus(1),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 401)),
    );
  });
}
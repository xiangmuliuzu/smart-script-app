// B 模块书架真实联调（App 端）：2.7.12 书架管理（列表 / 加入书架 / 移出书架），
// 以及契约未单列、按约定补充的书架态查询（GET /content/shelf/{workId}）。
//
// 这与收藏联调同属 App 私有接口（需 App Access Token），故同样用随机手机号真实注册建号
// （书架天然为空），断言只覆盖契约行为，并在结束时移出书架，避免污染真实库。
//
// 不做 skip：后端不可达或缺失 LIVE_SMS_CODE 时立即失败（评审标准 §7）。
//
// 运行：LIVE_SMS_CODE=123456 flutter test test/live/shelf_contract_test.dart
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
    deviceId: 'live-shelf',
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

  test('书架：列表为空→加入→书架态→幂等→列表可见→移出→幂等→列表为空', () async {
    final repo = await _loggedInRepo();

    // 取一部真实上架作品作为书架目标；书城无数据时无法联调，直接失败。
    final works = await repo.pageWorks(pageNum: 1, pageSize: 1);
    expect(works.list, isNotEmpty, reason: '书城无上架作品，无法进行书架联调');
    final workId = works.list.first.workId;

    // 新账号书架为空。
    final initial = await repo.shelf(pageNum: 1, pageSize: 10);
    expect(initial.total, 0, reason: '新注册账号书架不应有作品');
    expect(initial.list, isEmpty);
    expect((await repo.shelfStatus(workId)).onShelf, isFalse);

    // 身份摘要块随列表接口一并下发（A6 身份联通，契约 §2.3）。
    expect(initial.identity.authenticated, isTrue, reason: '书架接口需下发身份摘要块');
    expect(initial.identity.guest, isFalse);

    // 加入书架：书架态翻转，列表含目标作品。
    await repo.addShelf(workId);
    expect((await repo.shelfStatus(workId)).onShelf, isTrue);
    final afterAdd = await repo.shelf(pageNum: 1, pageSize: 10);
    expect(afterAdd.total, 1);
    expect(afterAdd.list.map((e) => e.workId), contains(workId));

    // 重复加入：幂等成功，不产生重复项（表上有 uk_user_work 唯一键）。
    await repo.addShelf(workId);
    final afterDup = await repo.shelf(pageNum: 1, pageSize: 10);
    expect(afterDup.total, 1, reason: '重复加入应幂等，不产生重复记录');
    expect(afterDup.list.where((e) => e.workId == workId).length, 1);

    // 移出书架：书架态翻转，列表不再包含。
    await repo.removeShelf(workId);
    expect((await repo.shelfStatus(workId)).onShelf, isFalse);
    expect((await repo.shelf(pageNum: 1, pageSize: 10)).list, isEmpty);

    // 重复移出：幂等成功（不返回 404）。
    await repo.removeShelf(workId);
  });

  test('书架：加入不可见作品按 404 拒绝', () async {
    final repo = await _loggedInRepo();
    await expectLater(
      repo.addShelf(999999999),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 404)),
    );
  });

  test('书架：未登录（无 Token）被拒', () async {
    final guest = _guestRepo();
    await expectLater(
      guest.addShelf(1),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 401)),
    );
    await expectLater(
      guest.shelf(pageNum: 1, pageSize: 10),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 401)),
    );
    await expectLater(
      guest.shelfStatus(1),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 401)),
    );
  });
}
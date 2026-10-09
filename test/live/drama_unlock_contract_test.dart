// B 模块剧集解锁真实联调（App 端，接口 2.8.7 解锁状态 / 2.8.8 付费解锁 / 2.8.9 广告解锁）。
//
// 三个接口均为私有（需 App Token）：均为两段路径 /content/episodes/{id}/xxx，
// 不命中 /content/episodes/* 单段白名单，走 App 凭证域 authenticated。
//
// 私有链路用随机手机号真实注册建号（解锁记录天然为空），断言只覆盖契约行为。
// 不做 skip：后端不可达或缺失 LIVE_SMS_CODE 时立即失败（评审标准 §7）。
//
// 前置：后端已启动 + 已执行 sql/app_2_8_drama_seed.sql
//      （种子含 work 3、免费集 900001/900002、付费集 900003 is_free=0 unlock_type=coin）。
//
// 运行：LIVE_SMS_CODE=<mock码> flutter test test/live/drama_unlock_contract_test.dart
//
// 环境变量：
//   LIVE_BASE_URL             默认 http://127.0.0.1:8080/api/v1
//   LIVE_SMS_CODE             测试环境 Mock 短信验证码（与后端 APP_SMS_MOCK_CODE 一致）
//   LIVE_WORK_ID              种子作品 ID，默认 3
//   LIVE_EPISODE_ID           免费种子剧集 ID，默认 900001
//   LIVE_PAID_EPISODE_ID      付费种子剧集 ID，默认 900003
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';
import 'package:script_app/features/comic/data/drama_repository.dart';

final String kBase =
    Platform.environment['LIVE_BASE_URL'] ?? 'http://127.0.0.1:8080/api/v1';
final String kSmsCode = Platform.environment['LIVE_SMS_CODE'] ?? '';
final int kWorkId = int.parse(Platform.environment['LIVE_WORK_ID'] ?? '3');
final int kFreeEpisodeId = int.parse(Platform.environment['LIVE_EPISODE_ID'] ?? '900001');
final int kPaidEpisodeId = int.parse(Platform.environment['LIVE_PAID_EPISODE_ID'] ?? '900003');

/// 无 Token 的裸 Dio 仓库：用于验证未登录被拒（401）。
DramaRepository _guestRepo() {
  final dio = Dio(BaseOptions(
    baseUrl: kBase,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 10),
  ));
  return DramaRepository(ApiClient(dio));
}

String _randPhone() {
  final n = DateTime.now().microsecondsSinceEpoch % 100000000;
  return '137${n.toString().padLeft(8, '0')}';
}

/// 注册随机账号并返回已注入 Bearer 的仓库（会话写入本地存储供拦截器使用）。
Future<DramaRepository> _loggedInRepo() async {
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
    deviceId: 'live-unlock',
  );
  await storage.saveSession(
    accessToken: session.accessToken,
    refreshToken: session.refreshToken,
    user: session.user.toJson(),
  );
  return DramaRepository(graph.apiClient);
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
      await probe.get('/content/episodes/$kFreeEpisodeId');
    } catch (e) {
      fail('后端不可达或剧集接口未放行（$kBase）：请先启动后端。底层错误：$e');
    }
  });

  group('2.8.7 剧集解锁状态', () {
    test('免费集：直接下发已解锁', () async {
      final status = await (await _loggedInRepo()).unlockStatus(kFreeEpisodeId);
      expect(status.isUnlocked, isTrue, reason: '免费集无需解锁');
    });

    test('付费集：新账号未解锁，且回带剧集配置的解锁方式', () async {
      final status = await (await _loggedInRepo()).unlockStatus(kPaidEpisodeId);
      expect(status.isUnlocked, isFalse, reason: '新账号在付费集上不应有解锁记录');
      expect(status.unlockType, isNotEmpty, reason: '应回带剧集配置的 unlock_type');
    });

    test('剧集不存在按 404 拒绝', () async {
      await expectLater(
        (await _loggedInRepo()).unlockStatus(999999999),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 404)),
      );
    });
  });

  group('2.8.8 付费解锁', () {
    test('解锁成功→状态转为已解锁→重复解锁幂等（同一 unlockId）', () async {
      final repo = await _loggedInRepo();

      final first = await repo.unlockEpisode(kPaidEpisodeId);
      expect(first.unlockId, greaterThan(0), reason: '应回带新增的解锁记录ID');
      expect(first.message, isNotEmpty);

      final after = await repo.unlockStatus(kPaidEpisodeId);
      expect(after.isUnlocked, isTrue, reason: '解锁后状态应转为已解锁');

      final again = await repo.unlockEpisode(kPaidEpisodeId);
      expect(again.unlockId, first.unlockId, reason: '重复解锁应幂等，返回既有记录');
    });

    test('免费集按 400 拒绝', () async {
      final repo = await _loggedInRepo();
      await expectLater(
        repo.unlockEpisode(kFreeEpisodeId),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 400)),
      );
    });

    test('剧集不存在按 404 拒绝', () async {
      final repo = await _loggedInRepo();
      await expectLater(
        repo.unlockEpisode(999999999),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 404)),
      );
    });
  });

  group('2.8.9 广告解锁', () {
    test('解锁成功→状态转为已解锁→重复解锁幂等（同一 unlockId）', () async {
      final repo = await _loggedInRepo();

      final first = await repo.adUnlockEpisode(kPaidEpisodeId, adId: 1);
      expect(first.unlockId, greaterThan(0));

      final after = await repo.unlockStatus(kPaidEpisodeId);
      expect(after.isUnlocked, isTrue);

      final again = await repo.adUnlockEpisode(kPaidEpisodeId);
      expect(again.unlockId, first.unlockId, reason: '重复解锁应幂等，返回既有记录');
    });

    test('免费集按 400 拒绝', () async {
      final repo = await _loggedInRepo();
      await expectLater(
        repo.adUnlockEpisode(kFreeEpisodeId),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 400)),
      );
    });
  });

  test('锁定链路未登录（无 Token）一律 401', () async {
    final guest = _guestRepo();
    Future<void> expect401(Future<void> Function() call) async {
      await expectLater(
        call(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 401)),
      );
    }

    await expect401(() => guest.unlockStatus(kPaidEpisodeId));
    await expect401(() => guest.unlockEpisode(kPaidEpisodeId));
    await expect401(() => guest.adUnlockEpisode(kPaidEpisodeId));
  });
}
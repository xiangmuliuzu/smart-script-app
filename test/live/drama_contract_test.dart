// B 模块外部视频/漫剧真实联调（App 端，接口 2.8.1 ~ 2.8.17）。
//
// 覆盖两条链路：
//   公开（游客可读）：2.8.1 信息流 / 2.8.2 剧集列表 / 2.8.3 剧集详情 /
//                     2.8.15 外部视频详情 / 2.8.16 找同款剧本；
//   私有（需 App Token）：2.8.4 保存进度 / 2.8.5 获取进度 / 2.8.6 播放历史 /
//                     2.8.13 追更 / 2.8.14 追更列表 / 2.8.17 举报。
//
// 私有链路用随机手机号真实注册建号（进度/历史/追更天然为空），断言只覆盖契约行为。
// 不做 skip：后端不可达或缺失 LIVE_SMS_CODE 时立即失败（评审标准 §7）。
//
// 前置：后端已启动 + 已执行 sql/app_2_8_drama_seed.sql（种子含 drama 900001/900002、
//       episode 900001~900003、channel 90001、关联 work_id=3）。
//
// 运行：LIVE_SMS_CODE=<mock码> flutter test test/live/drama_contract_test.dart
//
// 环境变量：
//   LIVE_BASE_URL            默认 http://127.0.0.1:8080/api/v1
//   LIVE_SMS_CODE            测试环境 Mock 短信验证码（与后端 APP_SMS_MOCK_CODE 一致）
//   LIVE_WORK_ID             种子关联作品 ID，默认 3
//   LIVE_DRAMA_ID            有原著的种子视频 ID，默认 900001
//   LIVE_DRAMA_NO_WORK_ID    无原著的种子视频 ID，默认 900002
//   LIVE_EPISODE_ID          免费种子剧集 ID，默认 900001
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';
import 'package:script_app/features/comic/data/drama_models.dart';
import 'package:script_app/features/comic/data/drama_repository.dart';

final String kBase =
    Platform.environment['LIVE_BASE_URL'] ?? 'http://127.0.0.1:8080/api/v1';
final String kSmsCode = Platform.environment['LIVE_SMS_CODE'] ?? '';
final int kWorkId = int.parse(Platform.environment['LIVE_WORK_ID'] ?? '3');
final int kDramaId = int.parse(Platform.environment['LIVE_DRAMA_ID'] ?? '900001');
final int kDramaNoWorkId = int.parse(Platform.environment['LIVE_DRAMA_NO_WORK_ID'] ?? '900002');
final int kEpisodeId = int.parse(Platform.environment['LIVE_EPISODE_ID'] ?? '900001');

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
    deviceId: 'live-drama',
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
      await probe.get('/content/drama-feed', queryParameters: {'page': 1, 'pageSize': 1});
    } catch (e) {
      fail('后端不可达或漫剧信息流接口未放行（$kBase）：请先启动后端。底层错误：$e');
    }
  });

  group('2.8 公开链路（游客可读）', () {
    test('2.8.1 信息流：分页结构 {total,list}，元素为契约字段', () async {
      final repo = _guestRepo();
      final page = await repo.pageFeed(pageNum: 1, pageSize: 5);
      expect(page.total, greaterThanOrEqualTo(1), reason: '种子数据未生效或信息流为空');
      expect(page.list, isNotEmpty);
      for (final item in page.list) {
        expect(item.dramaId, greaterThan(0));
        expect(item.title, isA<String>());
        expect(item.hasRelatedWork, isA<bool>());
      }
    });

    test('2.8.15 外部视频详情：回带 dramaId / 渠道 / 关联原著口径', () async {
      final detail = await _guestRepo().dramaDetail(kDramaId);
      expect(detail.dramaId, kDramaId);
      expect(detail.title, isNotEmpty);
      expect(detail.hasRelatedWork, isTrue, reason: '种子 drama $kDramaId 应绑定原著');
      expect(detail.channelName, isNotEmpty, reason: '详情应 JOIN 出渠道名称');
      expect(detail.status, isA<String>());
    });

    test('2.8.15 外部视频详情：不存在按 404 拒绝', () async {
      await expectLater(
        _guestRepo().dramaDetail(999999999),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 404)),
      );
    });

    test('2.8.2 剧集列表：data={list}，含免费与付费集且按集号升序', () async {
      final list = await _guestRepo().listEpisodes(kWorkId);
      expect(list, isNotEmpty, reason: '种子作品 $kWorkId 应有剧集');
      for (final e in list) {
        expect(e.workId, kWorkId);
        expect(e.episodeId, greaterThan(0));
      }
      // 集号升序
      final nos = list.map((e) => e.episodeNo).toList();
      final sorted = [...nos]..sort();
      expect(nos, sorted, reason: '剧集应按集号升序下发');
      // 种子里第 3 集为付费集（unlock_type=coin）
      expect(list.any((e) => e.isFree), isTrue, reason: '应存在免费集');
      expect(list.any((e) => !e.isFree), isTrue, reason: '应存在付费集');
    });

    test('2.8.3 剧集详情：回带播放地址与解锁信息', () async {
      final detail = await _guestRepo().episodeDetail(kEpisodeId);
      expect(detail.episodeId, kEpisodeId);
      expect(detail.workId, kWorkId);
      expect(detail.videoUrl, isA<String>());
      expect(detail.isFree, isTrue, reason: '种子剧集 $kEpisodeId 为免费集');
    });

    test('2.8.3 剧集详情：不存在按 404 拒绝', () async {
      await expectLater(
        _guestRepo().episodeDetail(999999999),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 404)),
      );
    });

    test('2.8.16 找同款剧本：绑定原著时 work 与作品详情同结构', () async {
      final payload = await _guestRepo().relatedWork(kDramaId);
      expect(payload.dramaId, kDramaId);
      expect(payload.hasRelatedWork, isTrue);
      expect(payload.work, isNotNull, reason: '原著作品可见时应下发 work');
      expect(payload.work!.workId, greaterThan(0));
      expect(payload.work!.title, isNotEmpty);
    });

    test('2.8.16 找同款剧本：未绑定原著时 hasRelatedWork=false 且 work 为空', () async {
      final payload = await _guestRepo().relatedWork(kDramaNoWorkId);
      expect(payload.dramaId, kDramaNoWorkId);
      expect(payload.hasRelatedWork, isFalse);
      expect(payload.work, isNull);
    });

    test('2.8.16 找同款剧本：不存在按 404 拒绝', () async {
      await expectLater(
        _guestRepo().relatedWork(999999999),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 404)),
      );
    });
  });

  group('2.8 私有链路（需 App Token）', () {
    test('2.8.4/2.8.5 播放进度：新账号无记录→写入→读回一致', () async {
      final repo = await _loggedInRepo();

      final initial = await repo.getProgress(kEpisodeId);
      expect(initial.progress, 0, reason: '新账号无进度记录时应为 0');
      expect(initial.duration, isNull, reason: '无记录时不臆造总时长');

      await repo.saveProgress(kEpisodeId, progress: 12, duration: 120);
      final after = await repo.getProgress(kEpisodeId);
      expect(after.progress, 12);
      expect(after.duration, 120);

      // 进度为负按 400 拒绝（入参校验）
      await expectLater(
        repo.saveProgress(kEpisodeId, progress: -1),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 400)),
      );
      // 剧集不存在按 404 拒绝
      await expectLater(
        repo.saveProgress(999999999, progress: 1),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 404)),
      );
    });

    test('2.8.6 播放历史：保存进度后该集出现在历史中', () async {
      final repo = await _loggedInRepo();
      await repo.saveProgress(kEpisodeId, progress: 30, duration: 120);

      final page = await repo.pagePlayHistory(pageNum: 1, pageSize: 10);
      expect(page.total, greaterThanOrEqualTo(1));
      final ids = page.list.map((e) => e.episodeId);
      expect(ids, contains(kEpisodeId), reason: '保存进度应同时刷新播放历史');
      final row = page.list.firstWhere((e) => e.episodeId == kEpisodeId);
      expect(row.workId, kWorkId);
      expect(row.workTitle, isNotEmpty, reason: '历史应 JOIN 出作品标题');
      expect(row.progressSeconds, 30, reason: '历史应带出续播位置');
    });

    test('2.8.13/2.8.14 追更：订阅→列表可见→取消→幂等取消', () async {
      final repo = await _loggedInRepo();

      expect((await repo.pageSubscriptions(pageNum: 1, pageSize: 20)).list, isEmpty,
          reason: '新账号追更列表应为空');

      await repo.subscribe(kWorkId);
      final after = await repo.pageSubscriptions(pageNum: 1, pageSize: 20);
      expect(after.total, greaterThanOrEqualTo(1));
      final mine = after.list.where((e) => e.workId == kWorkId).toList();
      expect(mine, hasLength(1), reason: '重复订阅应幂等，不产生重复记录');
      expect(mine.first.title, isNotEmpty);

      // 重复订阅仍幂等
      await repo.subscribe(kWorkId);
      expect(
        (await repo.pageSubscriptions(pageNum: 1, pageSize: 20)).list.where((e) => e.workId == kWorkId),
        hasLength(1),
      );

      await repo.unsubscribe(kWorkId);
      expect(
        (await repo.pageSubscriptions(pageNum: 1, pageSize: 20)).list.where((e) => e.workId == kWorkId),
        isEmpty,
      );
      // 未订阅时取消：幂等成功
      await repo.unsubscribe(kWorkId);
    });

    test('2.8.13 追更：不可见作品按 404 拒绝', () async {
      final repo = await _loggedInRepo();
      await expectLater(
        repo.subscribe(999999999),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 404)),
      );
    });

    test('2.8.17 举报：提交成功回带 reportId 与初始状态', () async {
      final repo = await _loggedInRepo();
      final result = await repo.report(
        targetType: ReportTargetType.externalDrama,
        targetId: kDramaId,
        reason: ReportReason.all.first.label,
        description: '联调测试举报，可删除',
      );
      expect(result.reportId, greaterThan(0));
      expect(result.status, isNotEmpty);
    });

    test('2.8.17 举报：入参非法按 400 拒绝', () async {
      final repo = await _loggedInRepo();
      await expectLater(
        repo.report(targetType: ReportTargetType.externalDrama, targetId: 0, reason: '色情低俗'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 400)),
      );
      await expectLater(
        repo.report(targetType: ReportTargetType.externalDrama, targetId: kDramaId, reason: ''),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 400)),
      );
    });

    test('私有接口未登录（无 Token）一律 401', () async {
      final guest = _guestRepo();
      Future<void> expect401(Future<void> Function() call) async {
        await expectLater(
          call(),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 401)),
        );
      }

      await expect401(() => guest.getProgress(kEpisodeId));
      await expect401(() => guest.saveProgress(kEpisodeId, progress: 1));
      await expect401(() async {
        await guest.pagePlayHistory(pageNum: 1, pageSize: 10);
      });
      await expect401(() => guest.subscribe(kWorkId));
      await expect401(() => guest.unsubscribe(kWorkId));
      await expect401(() async {
        await guest.pageSubscriptions(pageNum: 1, pageSize: 10);
      });
      await expect401(() => guest.report(
            targetType: ReportTargetType.externalDrama,
            targetId: kDramaId,
            reason: '色情低俗',
          ));
    });
  });
}
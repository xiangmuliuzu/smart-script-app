// B 模块剧集评论与点赞真实联调（App 端，接口 2.8.10 评论列表 / 2.8.11 发表评论 / 2.8.12 点赞）。
//
// 三个接口均为私有（需 App Token）：路径都是 /content/episodes/{id}/xxx 两段，
// 不命中 /content/episodes/* 的单段公开白名单，落到 /content/** 的 authenticated 规则。
//
// 私有链路用随机手机号真实注册建号，断言只覆盖契约行为。
// 不做 skip：后端不可达或缺失 LIVE_SMS_CODE 时立即失败（评审标准 §7）。
//
// 前置：后端已启动 + 已执行 sql/app_2_8_drama_seed.sql
//      （种子含免费集 900001，评论/点赞挂在剧集上，剧集本身无写接口，只能复用种子）。
//
// 运行：LIVE_SMS_CODE=<mock码> flutter test test/live/comment_contract_test.dart
//
// 环境变量：
//   LIVE_BASE_URL     默认 http://127.0.0.1:8080/api/v1
//   LIVE_SMS_CODE     测试环境 Mock 短信验证码（与后端 APP_SMS_MOCK_CODE 一致）
//   LIVE_EPISODE_ID   种子剧集 ID，默认 900001
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
final int kEpisodeId = int.parse(Platform.environment['LIVE_EPISODE_ID'] ?? '900001');

/// 联调评论前缀（便于结束后按前缀清理，评论无删除接口）。
const String kMark = '联调评论';

/// 断言 App 信封的失败码（B 模块 App 契约：HTTP 恒 200，成败看 code）。
Matcher _code(int code) => isA<ApiException>().having((e) => e.code, 'code', code);

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
  return '136${n.toString().padLeft(8, '0')}';
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
    deviceId: 'live-comment',
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
      await probe.get('/content/episodes/$kEpisodeId');
    } catch (e) {
      fail('后端不可达或剧集不存在（$kBase，剧集 $kEpisodeId）：请先启动后端并执行 2.8 种子。底层错误：$e');
    }
  });

  group('2.8.10 评论列表', () {
    test('未登录（无 Token）按 401 拒绝', () async {
      await expectLater(
        _guestRepo().pageComments(kEpisodeId, pageNum: 1, pageSize: 20),
        throwsA(_code(401)),
      );
    });

    test('剧集不存在按 404 拒绝', () async {
      await expectLater(
        (await _loggedInRepo()).pageComments(999999999, pageNum: 1, pageSize: 20),
        throwsA(_code(404)),
      );
    });

    test('发表后可见于列表，字段与提交一致', () async {
      final repo = await _loggedInRepo();
      final content = '$kMark-${DateTime.now().millisecondsSinceEpoch}';
      final commentId = await repo.createComment(kEpisodeId, content: content);
      expect(commentId, greaterThan(0));

      final page = await repo.pageComments(kEpisodeId, pageNum: 1, pageSize: 50);
      expect(page.total, greaterThan(0));
      final item = page.list.firstWhere((e) => e.commentId == commentId);
      expect(item.content, content);
      expect(item.parentId, 0, reason: '一级评论 parentId 应为 0');
      expect(item.episodeId, kEpisodeId);
      expect(item.likeCount, 0);
      expect(item.replyCount, 0);
      expect(item.nickName, isNotEmpty, reason: '应关联出用户昵称');
      expect(item.createdAt, isNotNull, reason: '应下发发表时间');
    });
  });

  group('2.8.11 发表评论 / 回复', () {
    test('一级评论 + 回复组成两级结构，父评论回复数递增', () async {
      final repo = await _loggedInRepo();
      final parentId = await repo.createComment(
        kEpisodeId,
        content: '$kMark-父-${DateTime.now().millisecondsSinceEpoch}',
      );
      final replyContent = '$kMark-子-${DateTime.now().millisecondsSinceEpoch}';
      final replyId = await repo.createComment(
        kEpisodeId,
        content: replyContent,
        parentId: parentId,
      );
      expect(replyId, greaterThan(0));

      final page = await repo.pageComments(kEpisodeId, pageNum: 1, pageSize: 50);
      final parent = page.list.firstWhere((e) => e.commentId == parentId);
      final reply = page.list.firstWhere((e) => e.commentId == replyId);
      expect(parent.replyCount, greaterThanOrEqualTo(1), reason: '回复应累加父评论 reply_count');
      expect(reply.parentId, parentId, reason: '回复应带回 parentId');
      expect(reply.isTopLevel, isFalse);
    });

    test('内容为空 / 超长按 400 拒绝', () async {
      final repo = await _loggedInRepo();
      await expectLater(repo.createComment(kEpisodeId, content: ''), throwsA(_code(400)));
      await expectLater(repo.createComment(kEpisodeId, content: '  '), throwsA(_code(400)));
      await expectLater(
        repo.createComment(kEpisodeId, content: 'x' * 501),
        throwsA(_code(400)),
      );
    });

    test('回复不存在或跨剧集的评论按 400 拒绝', () async {
      final repo = await _loggedInRepo();
      await expectLater(
        repo.createComment(kEpisodeId, content: '$kMark-越界回复', parentId: 999999999),
        throwsA(_code(400)),
      );
    });

    test('剧集不存在按 404 拒绝', () async {
      final repo = await _loggedInRepo();
      await expectLater(
        repo.createComment(999999999, content: '$kMark-幽灵剧集'),
        throwsA(_code(404)),
      );
    });
  });

  group('2.8.12 剧集点赞', () {
    test('点赞 → 取消：态与计数随之变化，重复点赞幂等', () async {
      final repo = await _loggedInRepo();

      final first = await repo.likeEpisode(kEpisodeId);
      expect(first.liked, isTrue);
      expect(first.likeCount, greaterThanOrEqualTo(1));

      final again = await repo.likeEpisode(kEpisodeId);
      expect(again.liked, isTrue);
      expect(again.likeCount, first.likeCount, reason: '重复点赞应幂等，计数不变');

      final off = await repo.unlikeEpisode(kEpisodeId);
      expect(off.liked, isFalse);
      expect(off.likeCount, first.likeCount - 1, reason: '取消点赞应减一');

      final offAgain = await repo.unlikeEpisode(kEpisodeId);
      expect(offAgain.liked, isFalse);
      expect(offAgain.likeCount, off.likeCount, reason: '重复取消应幂等，计数不变');
    });

    test('未登录按 401、剧集不存在按 404 拒绝', () async {
      final guest = _guestRepo();
      await expectLater(guest.likeEpisode(kEpisodeId), throwsA(_code(401)));
      await expectLater(guest.unlikeEpisode(kEpisodeId), throwsA(_code(401)));

      final repo = await _loggedInRepo();
      await expectLater(repo.likeEpisode(999999999), throwsA(_code(404)));
      await expectLater(repo.unlikeEpisode(999999999), throwsA(_code(404)));
    });
  });
}
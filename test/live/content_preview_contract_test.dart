// B 模块试读链路真实联调（App 端）：章节目录 / 章节正文 / 试读包。
//
// 这三个接口都是游客可读的公开接口，**不需要任何账号凭据**，因此单独成文件：
// real_backend_contract_test.dart 的 setUpAll 强制要求 LIVE_SMS_CODE 与
// LIVE_ADMIN_*，会把一条纯游客链路卡在没有管理端账号的环境里跑不起来。
//
// 与那份用例一致，本文件同样不做 skip：后端不可达即失败。
//
// 前置：后端已启动，且已执行 scripts/db/seed-steps.txt 中的 B 模块测试数据
//      （seed-content-chapter-testdata 会为某个已上架作品开启试读并写入 5 章）。
//
// 运行：
//   flutter test test/live/content_preview_contract_test.dart
//
// 环境变量：
//   LIVE_BASE_URL  默认 http://127.0.0.1:8080/api/v1
//   LIVE_WORK_ID   已开启试读的作品 ID，默认 3
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/features/bookstore/data/content_repository.dart';

final String kBase =
    Platform.environment['LIVE_BASE_URL'] ?? 'http://127.0.0.1:8080/api/v1';
final int kWorkId = int.parse(Platform.environment['LIVE_WORK_ID'] ?? '3');

ContentRepository _repo() {
  final dio = Dio(BaseOptions(
    baseUrl: kBase,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 10),
  ));
  return ContentRepository(ApiClient(dio));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // 与 real_backend_contract_test.dart 同理：flutter_test 会把 HttpClient
    // 换成「一律 400」的 mock，真实联调必须恢复真实实现。
    HttpOverrides.global = null;

    final probe = Dio(BaseOptions(
      baseUrl: kBase,
      connectTimeout: const Duration(seconds: 5),
    ));
    try {
      // 用章节目录做可达性探测：它同时验证了公开白名单真的放行了该路径。
      await probe.get('/content/works/$kWorkId/chapters');
    } catch (e) {
      fail('后端不可达或章节目录接口未放行（$kBase）：请先启动后端并执行 B 模块 seed。'
          '底层错误：$e');
    }
  });

  test('章节目录：载荷含试读配置，可读性完全由服务端判定', () async {
    final payload = await _repo().listChapters(kWorkId);

    expect(payload.workId, kWorkId, reason: '载荷必须回带作品 ID');
    expect(payload.previewEnabled, isTrue, reason: 'seed 已为该作品开启试读');
    expect(payload.previewEpisodes, greaterThan(0));
    expect(payload.chapters, isNotEmpty, reason: '目录不得为空');
    expect(payload.total, payload.chapters.length,
        reason: '本接口不分页，total 应等于目录条数');

    // 试读边界：前 previewEpisodes 章可读，之后一律不可读。
    for (final chapter in payload.chapters) {
      final shouldRead = chapter.chapterNo <= payload.previewEpisodes;
      expect(chapter.readable, shouldRead,
          reason: '第 ${chapter.chapterNo} 章的 readable 与试读集数不一致');
      expect(chapter.chapterTitle, isNotEmpty, reason: '目录应下发章节标题');
      expect(chapter.wordCount, greaterThan(0), reason: '目录应下发字数');
    }
  });

  test('章节正文：试读范围内下发正文，且归属正确', () async {
    final repo = _repo();
    final payload = await repo.listChapters(kWorkId);
    final free = payload.chapters.firstWhere((c) => c.readable);

    final detail = await repo.chapterDetail(free.chapterId);

    expect(detail.readable, isTrue);
    expect(detail.workId, kWorkId, reason: '正文必须归属同一作品');
    expect(detail.chapterNo, free.chapterNo);
    expect(detail.content, isNotNull, reason: '可读章节必须下发正文');
    expect(detail.content!.trim(), isNotEmpty);
    expect(detail.wordCount, greaterThan(0));
  });

  test('章节正文：超出试读范围按 403 拒绝，且不下发正文', () async {
    final repo = _repo();
    final payload = await repo.listChapters(kWorkId);
    final locked = payload.chapters.where((c) => !c.readable).toList();

    expect(locked, isNotEmpty,
        reason: 'seed 数据应包含超出试读范围的章节（chapter_no 3..5）');

    try {
      await repo.chapterDetail(locked.first.chapterId);
      fail('超出试读范围的章节必须被拒绝，实际却成功返回');
    } on ApiException catch (e) {
      expect(e.code, 403, reason: '试读边界是业务拒绝，应使用 403');
      expect(e.message, isNotEmpty);
      final data = e.data;
      if (data is Map) {
        expect(data['content'], isNull, reason: '403 分支不得夹带正文');
      }
    }
  });

  test('章节正文：不存在的章节按 404 拒绝', () async {
    await expectLater(
      _repo().chapterDetail(999999),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 404)),
    );
  });

  test('试读包：可读章节与目录口径一致，且带试读文件', () async {
    final repo = _repo();
    final payload = await repo.listChapters(kWorkId);
    final preview = await repo.workPreview(kWorkId);

    expect(preview.workId, kWorkId);
    expect(preview.previewEnabled, isTrue);
    expect(preview.previewEpisodes, payload.previewEpisodes,
        reason: '试读包与目录必须来自同一份试读配置');
    expect(preview.previewChapters.length, payload.previewEpisodes,
        reason: '试读包只含可读章节');
    for (final chapter in preview.previewChapters) {
      expect(chapter.readable, isTrue);
    }
    expect(preview.previewFiles, isNotEmpty, reason: 'seed 写入了 1 个试读文件');
    for (final file in preview.previewFiles) {
      expect(file.fileName, isNotEmpty);
      expect(file.fileUrl, isNotEmpty, reason: '试读文件必须给出可访问地址');
    }
  });
}
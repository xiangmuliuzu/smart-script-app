// B 模块版权合作联系方式真实联调（App 端，接口 2.7.9）。
//
// 该接口为游客可读的公开接口，不需要任何账号凭据，因此单独成文件
// （与 content_preview_contract_test.dart 同理：real_backend_contract_test.dart
// 的 setUpAll 强制要求管理端账号，会把纯游客链路卡住）。
//
// 断言只覆盖「契约结构」与「可见性边界」，不耦合开发库是否已登记联系方式：
//   - 结构：回带 workId、hasContact 为 bool、displayScope 可空字符串/字符串；
//   - 404：作品不存在/未上架时按 404 拒绝，与作品详情口径一致。
//
// 前置：后端已启动。
// 运行：flutter test test/live/content_contact_contract_test.dart
//
// 环境变量：
//   LIVE_BASE_URL  默认 http://127.0.0.1:8080/api/v1
//   LIVE_WORK_ID   已上架作品 ID，默认 3
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
    HttpOverrides.global = null;

    final probe = Dio(BaseOptions(
      baseUrl: kBase,
      connectTimeout: const Duration(seconds: 5),
    ));
    try {
      // 用作品详情做可达性探测：联系方式接口同属 /content/works/** 公开白名单。
      await probe.get('/content/works/$kWorkId');
    } catch (e) {
      fail('后端不可达或作品详情接口未放行（$kBase）：请先启动后端。底层错误：$e');
    }
  });

  test('版权合作联系方式：回带 workId，范围与是否登记为契约字段', () async {
    final contact = await _repo().workContact(kWorkId);

    expect(contact.workId, kWorkId, reason: '响应必须回带请求的作品 ID');
    // hasContact 已由模型收敛为 bool；此处只需确保能正常解析（不抛错）。
    expect(contact.hasContact, isA<bool>());
    // 未登记时 displayScope 为空串，登记时为后端原样下发的范围值。
    expect(contact.displayScope, isA<String>());
  });

  test('版权合作联系方式：作品不存在按 404 拒绝', () async {
    await expectLater(
      _repo().workContact(999999),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 404)),
    );
  });
}
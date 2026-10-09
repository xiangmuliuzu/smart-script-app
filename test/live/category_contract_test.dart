// B 模块分类模块真实联调（App 端，接口 2.10.1 分类列表 / 2.10.3 标签列表）。
//
// 两个接口均为游客可读的公开接口，不需要账号凭据，因此单独成文件
// （与 content_contact_contract_test.dart 同理：real_backend_contract_test.dart
// 的 setUpAll 强制要求管理端账号，会把纯游客链路卡住）。
//
// 断言只覆盖「契约结构」与「游客可见性」，不耦合开发库是否已登记分类/标签数据：
//   - 结构：统一信封 data.list 为数组，元素可解析出 categoryId/categoryName、tagId/tagName；
//   - 顶级语义：parentId=0 的请求必须只返回 parent_id=0 的顶级分类；
//   - 可见性：不带任何 Token 即可读取（不返回 401）。
// 列表允许为空（开发库可能尚未登记数据）。
//
// 前置：后端已启动。
// 运行：flutter test test/live/category_contract_test.dart
//
// 环境变量：
//   LIVE_BASE_URL  默认 http://127.0.0.1:8080/api/v1
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/features/bookstore/data/content_repository.dart';

final String kBase =
    Platform.environment['LIVE_BASE_URL'] ?? 'http://127.0.0.1:8080/api/v1';

/// 无 Token 的裸 Dio 仓库：分类/标签是公开接口，必须允许游客读取。
ContentRepository _guestRepo() {
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
    // flutter_test 会把 HttpClient 替换为「一律 400」的 mock，真实联调必须还原。
    HttpOverrides.global = null;

    final probe =
        Dio(BaseOptions(baseUrl: kBase, connectTimeout: const Duration(seconds: 5)));
    try {
      await probe.get('/content/categories');
    } catch (e) {
      fail('后端不可达（$kBase）：请先启动后端。底层错误：$e');
    }
  });

  test('分类列表：游客可读，下发 list，元素含 categoryId/categoryName', () async {
    final categories = await _guestRepo().listCategories(parentId: 0);

    for (final item in categories) {
      expect(item.categoryId, greaterThan(0), reason: '分类 ID 必须为正整数');
      expect(item.categoryName, isNotEmpty, reason: '分类名称不应为空');
      // parentId=0 是「取顶级」过滤（SQL 为 AND parent_id = 0），故顶级分类的 parentId 必为 0。
      expect(item.parentId, 0, reason: '顶级分类的 parentId 应为 0');
    }
  });

  test('标签列表：游客可读，元素含 tagId/tagName', () async {
    final tags = await _guestRepo().listTags();

    for (final item in tags) {
      expect(item.tagId, greaterThan(0), reason: '标签 ID 必须为正整数');
      expect(item.tagName, isNotEmpty, reason: '标签名称不应为空');
    }
  });
}
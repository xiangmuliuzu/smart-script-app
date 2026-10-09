// B 模块「上传与创作」真实联调（App 端）：2.9.2~2.9.9
// （创建 / 更新 / 删除 / 草稿箱 / 审核状态 / 版本列表 / 新建版本 / 版本详情），
// 以及 2.9.1 文件上传的类型白名单拒绝路径。
//
// 这些全是 App 私有接口（需 App Access Token），故与书架/收藏联调一致：
// 用随机手机号真实注册建号（草稿天然为空），断言只覆盖契约行为，
// 结束时删除本次创建的作品，避免污染真实库。
//
// 上传只在「被拒绝」路径上断言（封面传非图片按 400），因为成功上传会在
// 服务端 uploadPath 留下文件且契约没有删除接口；成功上传与超大文件 413
// 已单独人工验证（返回 {fileId:null,url,fileName} / HTTP 413 + code 41300）。
//
// 不做 skip：后端不可达或缺失 LIVE_SMS_CODE 时立即失败（评审标准 §7）。
//
// 运行：LIVE_SMS_CODE=123456 flutter test test/live/work_manage_contract_test.dart
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
import 'package:script_app/features/create/data/create_repository.dart';

final String kBase =
    Platform.environment['LIVE_BASE_URL'] ?? 'http://127.0.0.1:8080/api/v1';
final String kSmsCode = Platform.environment['LIVE_SMS_CODE'] ?? '';

/// 断言 App 信封的失败码（B 模块 App 契约：HTTP 恒 200，成败看 code）。
Matcher _code(int code) =>
    isA<ApiException>().having((e) => e.code, 'code', code);

/// 无 Token 的裸 Dio 仓库：用于验证未登录被拒（401）。
CreateRepository _guestRepo() {
  final dio = Dio(BaseOptions(
    baseUrl: kBase,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 10),
  ));
  return CreateRepository(ApiClient(dio));
}

String _randPhone() {
  final n = DateTime.now().microsecondsSinceEpoch % 100000000;
  return '138${n.toString().padLeft(8, '0')}';
}

/// 一次联调会话：创作仓库（本次新增）与书城仓库（取真实分类）。
class _Session {
  _Session(this.create, this.content);

  final CreateRepository create;
  final ContentRepository content;
}

/// 注册随机账号并返回已注入 Bearer 的仓库（会话已写入本地存储供拦截器使用）。
Future<_Session> _loggedIn() async {
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
    deviceId: 'live-work-manage',
  );
  await storage.saveSession(
    accessToken: session.accessToken,
    refreshToken: session.refreshToken,
    user: session.user.toJson(),
  );
  return _Session(CreateRepository(graph.apiClient), ContentRepository(graph.apiClient));
}

/// 取一个真实存在的顶级分类 ID（category_id 落库为 NOT NULL，必须真实有效）。
Future<int> _firstCategoryId(ContentRepository content) async {
  final categories = await content.listCategories(parentId: 0);
  expect(categories, isNotEmpty, reason: '库中无顶级分类，无法创建作品');
  return categories.first.categoryId;
}

/// 创建一个联调作品，并登记结束时删除（已删除时忽略 404）。
Future<int> _createDisposableWork(_Session s, {String prefix = '联调'}) async {
  final workId = await s.create.createWork(
    title: '$prefix${DateTime.now().millisecondsSinceEpoch}',
    categoryId: await _firstCategoryId(s.content),
  );
  addTearDown(() async {
    try {
      await s.create.deleteWork(workId);
    } on ApiException {
      // 用例已自行删除：忽略重复删除的 404
    }
  });
  return workId;
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

  test('创作：未登录（无 Token）全部创作接口被拒', () async {
    final guest = _guestRepo();
    // MultipartFile.fromFile 会先读文件长度，故上传断言必须指向真实存在的文件。
    final dir = Directory.systemTemp.createTempSync('live_guest_check');
    addTearDown(() => dir.deleteSync(recursive: true));
    final guestFile = File('${dir.path}${Platform.pathSeparator}live_guest.txt')
      ..writeAsStringSync('guest');
    await expectLater(guest.pageDrafts(pageNum: 1, pageSize: 10), throwsA(_code(401)));
    await expectLater(
        guest.createWork(title: '联调未登录', categoryId: 1), throwsA(_code(401)));
    await expectLater(guest.updateWork(1, title: '联调未登录'), throwsA(_code(401)));
    await expectLater(guest.deleteWork(1), throwsA(_code(401)));
    await expectLater(guest.reviewStatus(1), throwsA(_code(401)));
    await expectLater(guest.listVersions(1), throwsA(_code(401)));
    await expectLater(guest.createVersion(1, content: '联调未登录'), throwsA(_code(401)));
    await expectLater(guest.versionDetail(1), throwsA(_code(401)));
    await expectLater(
      guest.uploadFile(
        filePath: guestFile.path,
        fileName: 'live_guest.txt',
        type: 'cover',
      ),
      throwsA(_code(401)),
    );
  });

  test('创作：必填校验 → 草稿箱可见 → 审核状态 → 更新 → 删除', () async {
    final s = await _loggedIn();
    final categoryId = await _firstCategoryId(s.content);

    // title 缺失 / 空串按 400 拒绝。
    await expectLater(s.create.createWork(title: '', categoryId: categoryId), throwsA(_code(400)));
    // category_id 非正整数按 400 拒绝（该列 NOT NULL，不编造默认分类）。
    await expectLater(s.create.createWork(title: '联调缺分类', categoryId: 0), throwsA(_code(400)));

    final title = '联调草稿${DateTime.now().millisecondsSinceEpoch}';
    final workId = await s.create.createWork(
      title: title,
      categoryId: categoryId,
      description: '联调简介',
      price: 1.5,
    );
    expect(workId, greaterThan(0));
    addTearDown(() async {
      try {
        await s.create.deleteWork(workId);
      } on ApiException {
        // 用例末尾已删除
      }
    });

    // 草稿箱：新账号仅此一条，字段与提交一致（camelCase 出参）。
    final drafts = await s.create.pageDrafts(pageNum: 1, pageSize: 10);
    expect(drafts.list.map((e) => e.workId), contains(workId));
    final item = drafts.list.firstWhere((e) => e.workId == workId);
    expect(item.status, 'draft');
    expect(item.title, title);
    expect(item.summary, '联调简介');
    expect(item.price, 1.5);
    expect(item.genreId, categoryId);

    // 审核状态：草稿状态派生为「待审核」，无驳回意见。
    final status = await s.create.reviewStatus(workId);
    expect(status.status, 'draft');
    expect(status.reviewResult, 'pending');
    expect(status.reviewComment, isNull);

    // 更新：标题与价格可改，回读一致。
    final newTitle = '$title改';
    await s.create.updateWork(workId, title: newTitle, price: 2.5);
    final afterUpdate = await s.create.pageDrafts(pageNum: 1, pageSize: 10);
    final updated = afterUpdate.list.firstWhere((e) => e.workId == workId);
    expect(updated.title, newTitle);
    expect(updated.price, 2.5);

    // 负价格按 400 拒绝。
    await expectLater(s.create.updateWork(workId, price: -1), throwsA(_code(400)));

    // 删除（逻辑删除）：草稿箱不再可见；再查/再删均按 404。
    await s.create.deleteWork(workId);
    final afterDelete = await s.create.pageDrafts(pageNum: 1, pageSize: 10);
    expect(afterDelete.list.map((e) => e.workId), isNot(contains(workId)));
    await expectLater(s.create.reviewStatus(workId), throwsA(_code(404)));
    await expectLater(s.create.deleteWork(workId), throwsA(_code(404)));
  });

  test('创作：版本新建 → 列表当前版本标记 → 详情正文往返', () async {
    final s = await _loggedIn();
    final workId = await _createDisposableWork(s, prefix: '联调版本');

    expect(await s.create.listVersions(workId), isEmpty, reason: '新建作品不应有版本');

    final v1 = await s.create.createVersion(
      workId,
      versionDesc: '首版',
      content: '正文A\n第二行',
    );
    expect(v1, greaterThan(0));
    var versions = await s.create.listVersions(workId);
    expect(versions.length, 1);
    expect(versions.first.versionNo, '1');
    expect(versions.first.changeLog, '首版');
    expect(versions.first.isCurrentVersion, isTrue, reason: '新版本应置为当前版本');

    // 再建一版：version_no 作品内自增，当前版本唯一且指向最新。
    final v2 = await s.create.createVersion(workId, versionDesc: '修订', content: '正文B');
    versions = await s.create.listVersions(workId);
    expect(versions.length, 2);
    final currents = versions.where((e) => e.isCurrentVersion).toList();
    expect(currents.length, 1, reason: '当前版本必须唯一');
    expect(currents.first.versionId, v2);
    expect(versions.firstWhere((e) => e.versionId == v1).isCurrent, '0');

    // 详情：正文全文往返（列表下发的正文为空，只有详情带 content）。
    final detail = await s.create.versionDetail(v1);
    expect(detail.versionId, v1);
    expect(detail.versionNo, '1');
    expect(detail.content, '正文A\n第二行');
    expect(detail.changeLog, '首版');
  });

  test('创作：非本人作品与不存在作品一律按 404 处理', () async {
    final s = await _loggedIn();

    // 他人作品（work_id=1 为既有数据，必不属于刚注册的账号）：不区分「不存在」与「无权」。
    await expectLater(s.create.reviewStatus(1), throwsA(_code(404)));
    await expectLater(s.create.listVersions(1), throwsA(_code(404)));
    await expectLater(s.create.updateWork(1, title: '越权修改'), throwsA(_code(404)));
    await expectLater(s.create.deleteWork(1), throwsA(_code(404)));

    // 不存在的主键：同样 404。
    const ghost = 999999999;
    await expectLater(s.create.reviewStatus(ghost), throwsA(_code(404)));
    await expectLater(s.create.listVersions(ghost), throwsA(_code(404)));
    await expectLater(s.create.createVersion(ghost, content: '越权建版本'), throwsA(_code(404)));
    await expectLater(s.create.versionDetail(ghost), throwsA(_code(404)));
  });

  test('创作：文件上传按用途做类型白名单（封面传非图片按 400）', () async {
    final s = await _loggedIn();
    final dir = Directory.systemTemp.createTempSync('live_upload_check');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}live_cover_check.txt')
      ..writeAsStringSync('not an image');

    // type=cover 只接受图片扩展名：否则在落盘前就被拒，不留残留文件。
    await expectLater(
      s.create.uploadFile(
        filePath: file.path,
        fileName: 'live_cover_check.txt',
        type: 'cover',
      ),
      throwsA(_code(400)),
    );
  });
}
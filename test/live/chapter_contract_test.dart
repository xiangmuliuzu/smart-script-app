// B 模块 App 章节编辑真实联调（接口文档未定义章节 CRUD 规格，按模块约定补齐）：
//   GET    /content/works/{workId}/chapters/manage  作者视角章节列表（不过滤 status）
//   POST   /content/works/{workId}/chapters         新增章节
//   PUT    /content/chapters/{chapterId}            更新章节
//   DELETE /content/chapters/{chapterId}            删除章节（物理删除）
//
// 鉴权口径（与 AppAuthSecurityConfig 一致）：
//   - manage 是 GET 且落在 /content/works/** 的「GET-only 游客白名单」内，
//     但业务层强制校验作者归属，故无身份游客拿到的是 404（而非 401），他人作品是 403；
//   - create/update/delete 非 GET，落 /content/** 的 authenticated 规则，无 Token 一律 401。
//
// 私有链路用随机手机号真实注册建号，作品用 2.9.2 真实创建，结束时删除，避免污染真实库。
// 不做 skip：后端不可达或缺失 LIVE_SMS_CODE 时立即失败（评审标准 §7）。
//
// 运行：LIVE_SMS_CODE=<mock码> flutter test test/live/chapter_contract_test.dart
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
Matcher _code(int code) => isA<ApiException>().having((e) => e.code, 'code', code);

/// 无 Token 的裸 Dio 仓库：用于验证未登录被拒。
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
  return '137${n.toString().padLeft(8, '0')}';
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
    deviceId: 'live-chapter',
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
Future<int> _createDisposableWork(_Session s, {String prefix = '联调章节'}) async {
  final workId = await s.create.createWork(
    title: '$prefix${DateTime.now().millisecondsSinceEpoch}',
    categoryId: await _firstCategoryId(s.content),
  );
  addTearDown(() async {
    try {
      await s.create.deleteWork(workId);
    } on ApiException {
      // 用例未删除或已删除：忽略 404
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

  group('章节管理：作者视角列表', () {
    test('未登录按 404（GET 白名单内但业务层拒绝无身份）', () async {
      await expectLater(_guestRepo().listWorkChapters(1), throwsA(_code(404)));
    });

    test('作品不存在按 404', () async {
      final s = await _loggedIn();
      await expectLater(s.create.listWorkChapters(999999999), throwsA(_code(404)));
    });

    test('新建作品初始无章节；新增后可见且字段一致', () async {
      final s = await _loggedIn();
      final workId = await _createDisposableWork(s);
      expect(await s.create.listWorkChapters(workId), isEmpty, reason: '新建作品不应有章节');

      const content = '正文A\n第二行';
      final chapterId = await s.create.createChapter(
        workId,
        chapterNo: 1,
        chapterTitle: '第 1 章',
        content: content,
      );
      expect(chapterId, greaterThan(0));

      final list = await s.create.listWorkChapters(workId);
      expect(list.length, 1);
      final item = list.first;
      expect(item.chapterId, chapterId);
      expect(item.chapterNo, 1);
      expect(item.chapterTitle, '第 1 章');
      expect(item.wordCount, content.length, reason: '字数应由后端按正文长度计算');
      expect(item.isFree, isFalse, reason: '未传 isFree 时默认付费（"0"）');
      expect(item.status, '0', reason: '新增章节默认正常（目录可见）');
      expect(item.isHidden, isFalse);
    });
  });

  group('章节管理：新增校验', () {
    test('序号重复按 400；序号非法/标题空或超长/isFree 非法按 400', () async {
      final s = await _loggedIn();
      final workId = await _createDisposableWork(s);
      await s.create.createChapter(workId, chapterNo: 1, chapterTitle: '第一章', content: 'x');

      await expectLater(
        s.create.createChapter(workId, chapterNo: 1, chapterTitle: '重复序号', content: 'x'),
        throwsA(_code(400)),
      );
      await expectLater(
        s.create.createChapter(workId, chapterNo: 0, chapterTitle: '非法序号', content: 'x'),
        throwsA(_code(400)),
      );
      await expectLater(
        s.create.createChapter(workId, chapterNo: 2, chapterTitle: '  ', content: 'x'),
        throwsA(_code(400)),
      );
      await expectLater(
        s.create.createChapter(workId, chapterNo: 3, chapterTitle: 'x' * 101, content: 'x'),
        throwsA(_code(400)),
      );
      await expectLater(
        s.create.createChapter(
          workId,
          chapterNo: 4,
          chapterTitle: '非法标记',
          content: 'x',
          isFree: '2',
        ),
        throwsA(_code(400)),
      );
    });

    test('作品不存在按 404', () async {
      final s = await _loggedIn();
      await expectLater(
        s.create.createChapter(999999999, chapterNo: 1, chapterTitle: '幽灵', content: 'x'),
        throwsA(_code(404)),
      );
    });
  });

  group('章节管理：更新', () {
    test('改标题/正文/isFree 回读一致，字数随正文重算', () async {
      final s = await _loggedIn();
      final workId = await _createDisposableWork(s);
      final chapterId =
          await s.create.createChapter(workId, chapterNo: 1, chapterTitle: '旧标题', content: '旧');

      await s.create.updateChapter(
        chapterId,
        chapterTitle: '新标题',
        content: '新的正文内容',
        isFree: '1',
      );
      final item =
          (await s.create.listWorkChapters(workId)).firstWhere((e) => e.chapterId == chapterId);
      expect(item.chapterTitle, '新标题');
      expect(item.wordCount, '新的正文内容'.length, reason: '正文变更应重算字数');
      expect(item.isFree, isTrue);
    });

    test('仅改状态：置隐藏后列表仍在且 status="1"，可再置回正常', () async {
      final s = await _loggedIn();
      final workId = await _createDisposableWork(s);
      final chapterId =
          await s.create.createChapter(workId, chapterNo: 1, chapterTitle: '状态切换', content: 'x');

      await s.create.updateChapter(chapterId, status: '1');
      var item =
          (await s.create.listWorkChapters(workId)).firstWhere((e) => e.chapterId == chapterId);
      expect(item.status, '1');
      expect(item.isHidden, isTrue, reason: '作者视角须能看到隐藏章节以便恢复');

      await s.create.updateChapter(chapterId, status: '0');
      item = (await s.create.listWorkChapters(workId)).firstWhere((e) => e.chapterId == chapterId);
      expect(item.status, '0');
    });

    test('无可更新字段按 400；章节不存在按 404', () async {
      final s = await _loggedIn();
      final workId = await _createDisposableWork(s);
      final chapterId =
          await s.create.createChapter(workId, chapterNo: 1, chapterTitle: '空更新', content: 'x');

      await expectLater(s.create.updateChapter(chapterId), throwsA(_code(400)));
      await expectLater(
        s.create.updateChapter(999999999, chapterTitle: '幽灵'),
        throwsA(_code(404)),
      );
    });
  });

  group('章节管理：删除', () {
    test('删除后列表不再可见；重复删除按 404', () async {
      final s = await _loggedIn();
      final workId = await _createDisposableWork(s);
      final chapterId =
          await s.create.createChapter(workId, chapterNo: 1, chapterTitle: '待删除', content: 'x');

      await s.create.deleteChapter(chapterId);
      final list = await s.create.listWorkChapters(workId);
      expect(list.map((e) => e.chapterId), isNot(contains(chapterId)));
      await expectLater(s.create.deleteChapter(chapterId), throwsA(_code(404)));
    });
  });

  group('章节管理：权限', () {
    test('未登录：manage 按 404，写接口按 401', () async {
      final guest = _guestRepo();
      await expectLater(guest.listWorkChapters(1), throwsA(_code(404)));
      await expectLater(
        guest.createChapter(1, chapterNo: 1, chapterTitle: '未登录', content: 'x'),
        throwsA(_code(401)),
      );
      await expectLater(guest.updateChapter(1, chapterTitle: '未登录'), throwsA(_code(401)));
      await expectLater(guest.deleteChapter(1), throwsA(_code(401)));
    });

    test('他人作品：manage/新增按 403，更新/删除他人章节按 403', () async {
      final owner = await _loggedIn();
      final other = await _loggedIn();
      final workId = await _createDisposableWork(owner);
      final chapterId =
          await owner.create.createChapter(workId, chapterNo: 1, chapterTitle: '私有章节', content: 'x');

      await expectLater(other.create.listWorkChapters(workId), throwsA(_code(403)));
      await expectLater(
        other.create.createChapter(workId, chapterNo: 2, chapterTitle: '越权新增', content: 'x'),
        throwsA(_code(403)),
      );
      await expectLater(
        other.create.updateChapter(chapterId, chapterTitle: '越权修改'),
        throwsA(_code(403)),
      );
      await expectLater(other.create.deleteChapter(chapterId), throwsA(_code(403)));

      // 越权失败不应影响原作者数据。
      final list = await owner.create.listWorkChapters(workId);
      expect(list.map((e) => e.chapterId), contains(chapterId));
    });
  });
}
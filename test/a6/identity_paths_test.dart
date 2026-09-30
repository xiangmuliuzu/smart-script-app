// H-03 App 端身份表现：游客 / 未实名 / 已实名 / 无角色 / 有角色。
//
// 对应评审标准 G7「统一身份能力」后续加固清单：
//   - B、C、D、E 可以通过公共接口取得用户 ID、登录态、游客状态、角色、权限和实名状态；
//   - 当前用户 ID 只能来自服务端安全上下文；
//   - 游客没有伪造用户 ID；
//   - 角色判断和实名判断互相独立；
//   - 未登录、已登录未实名、已实名、无角色和有角色五种路径有自动化测试；
//   - 公共契约包含字段含义、空值、错误语义和兼容策略。
//
// 身份一律来自服务端载荷（IdentitySummary / User），客户端不参与推导。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/core/constants/app_constants.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/providers/auth_providers.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';
import 'package:script_app/features/auth/data/auth_repository.dart';
import 'package:script_app/features/bookstore/data/content_repository.dart';
import 'package:script_app/features/bookstore/pages/bookshelf_page.dart';
import 'package:script_app/models/user.dart';

import '../support/scripted_api.dart';

class _FakeSecureStorage implements TokenSecureStorage {
  final Map<String, String> _map = {};

  @override
  Future<void> write(String key, String value) async => _map[key] = value;

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> delete(String key) async => _map.remove(key);

  @override
  Future<void> deleteAll() async => _map.clear();
}

/// 只实现 me()：用于让 AuthController 的启动恢复直接得到指定身份。
class _MeRepo implements AuthRepository {
  _MeRepo(this.user);

  final User user;

  @override
  Future<User> me() async => user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _guestIdentity = {
  'authenticated': false,
  'guest': true,
  'userId': null,
  'accountType': null,
  'realNameStatus': 'NOT_SUBMITTED',
  'authorCapability': false,
  'roleCodes': <String>[],
  'permissionCodes': <String>[],
};

const _work = {'workId': 1, 'title': '示例剧本·长夜', 'authorName': '甲', 'category': '都市', 'wordCount': 100};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ================================================================
  group('H-03-A 公共身份契约：五路径与空值/兼容', () {
    test('游客：authenticated=false、guest=true、userId 为空', () {
      final id = IdentitySummary.fromJson(Map<String, dynamic>.from(_guestIdentity));
      expect(id.authenticated, isFalse);
      expect(id.guest, isTrue);
      expect(id.userId, isNull, reason: '游客不得携带用户 ID');
      expect(id.roleCodes, isEmpty);
      expect(id.realNameStatus, 'NOT_SUBMITTED');
    });

    test('已登录未实名：有 userId、实名未提交、无角色', () {
      final id = IdentitySummary.fromJson({
        ..._guestIdentity,
        'authenticated': true,
        'guest': false,
        'userId': 101,
        'accountType': '01',
      });
      expect(id.authenticated, isTrue);
      expect(id.guest, isFalse);
      expect(id.userId, 101);
      expect(id.realNameStatus, 'NOT_SUBMITTED');
      expect(id.roleCodes, isEmpty);
    });

    test('已实名：realNameStatus=APPROVED', () {
      final id = IdentitySummary.fromJson({
        ..._guestIdentity,
        'authenticated': true,
        'guest': false,
        'userId': 102,
        'realNameStatus': 'APPROVED',
      });
      expect(id.realNameStatus, 'APPROVED');
    });

    test('无角色：roleCodes/permissionCodes 均为空', () {
      final id = IdentitySummary.fromJson({
        ..._guestIdentity,
        'authenticated': true,
        'guest': false,
        'userId': 103,
      });
      expect(id.roleCodes, isEmpty);
      expect(id.permissionCodes, isEmpty);
    });

    test('有角色：roleCodes/permissionCodes 由服务端下发', () {
      final id = IdentitySummary.fromJson({
        ..._guestIdentity,
        'authenticated': true,
        'guest': false,
        'userId': 104,
        'roleCodes': ['common'],
        'permissionCodes': ['content:work:query'],
      });
      expect(id.roleCodes, contains('common'));
      expect(id.permissionCodes, contains('content:work:query'));
    });

    test('缺字段时采取「保守默认」：视为游客且未实名，不猜测身份', () {
      final id = IdentitySummary.fromJson(const {});
      expect(id.authenticated, isFalse, reason: '缺字段不得默认为已登录');
      expect(id.guest, isTrue);
      expect(id.userId, isNull);
      expect(id.realNameStatus, 'NOT_SUBMITTED', reason: '缺字段不得默认为已实名');
      expect(id.authorCapability, isFalse);
      expect(id.roleCodes, isEmpty);
    });

    test('类型异常容错：非字符串角色被过滤，数值 userId 被接受', () {
      final id = IdentitySummary.fromJson({
        'authenticated': true,
        'guest': false,
        'userId': 105,
        'roleCodes': ['common', 7, null, 'creator'],
      });
      expect(id.roleCodes, ['common', 'creator']);
    });

    test('前向兼容：未知 accountType 原样保留，不抛异常', () {
      final id = IdentitySummary.fromJson({
        ..._guestIdentity,
        'authenticated': true,
        'guest': false,
        'userId': 106,
        'accountType': '99',
        'futureField': {'x': 1},
      });
      expect(id.accountType, '99');
    });

    test('载荷缺 identity 时按游客处理（不崩溃）', () {
      final payload = ShelfPayload.fromJson({
        'works': [_work],
        'downloadable': false,
        'realNameRequired': true,
      });
      expect(payload.identity.guest, isTrue);
      expect(payload.identity.authenticated, isFalse);
      expect(payload.works, hasLength(1));
    });
  });

  // ================================================================
  group('H-03-B 业务准入与角色判定的独立性', () {
    ShelfPayload shelf(String status, {bool? downloadable, bool? realNameRequired}) =>
        ShelfPayload.fromJson({
          'identity': {
            ..._guestIdentity,
            'authenticated': true,
            'guest': false,
            'userId': 200,
            'realNameStatus': status,
            'roleCodes': const <String>[],
          },
          'works': [_work],
          'downloadable': downloadable ?? (status == 'APPROVED'),
          'realNameRequired': realNameRequired ?? (status != 'APPROVED'),
        });

    test('游客：不可下载且需要实名', () {
      final p = ShelfPayload.fromJson({
        'identity': _guestIdentity,
        'works': [_work],
        'downloadable': false,
        'realNameRequired': true,
      });
      expect(p.downloadable, isFalse);
      expect(p.realNameRequired, isTrue);
    });

    test('已登录未实名：不可下载且需要实名', () {
      final p = shelf('NOT_SUBMITTED');
      expect(p.downloadable, isFalse);
      expect(p.realNameRequired, isTrue);
    });

    test('已实名：可下载且不再要求实名', () {
      final p = shelf('APPROVED');
      expect(p.downloadable, isTrue);
      expect(p.realNameRequired, isFalse);
    });

    test('角色与实名互不推导：有角色但未实名 → 准入仍不放行', () {
      const user = User(
        userId: 301,
        userType: UserType.user,
        roles: ['common'],
        permissions: ['content:work:query'],
        realNameStatus: 'NOT_SUBMITTED',
      );
      expect(user.hasRole('common'), isTrue, reason: '有角色');
      expect(user.hasRole('creator'), isFalse);
      expect(user.isRealNameApproved, isFalse, reason: '有角色不等于已实名');
    });

    test('角色与实名互不推导：已实名但无角色 → 准入放行且无角色', () {
      const user = User(
        userId: 302,
        userType: UserType.user,
        roles: [],
        realNameStatus: 'APPROVED',
      );
      expect(user.hasRole('common'), isFalse, reason: '无角色');
      expect(user.isRealNameApproved, isTrue, reason: '已实名不等于有角色');
    });

    test('权限判定支持通配与空值', () {
      const wildcard = User(userId: 1, userType: UserType.user, permissions: ['*:*:*']);
      const empty = User(userId: 2, userType: UserType.user);
      expect(wildcard.hasPermission('anything:at:all'), isTrue);
      expect(empty.hasPermission('content:work:query'), isFalse);
    });

    test('游客态下的用户名册为空且未实名（不继承任何身份）', () {
      const user = User(userId: 0, userType: UserType.user);
      expect(user.roles, isEmpty);
      expect(user.isRealNameApproved, isFalse);
      expect(user.authorCapability, isFalse);
    });
  });

  // ================================================================
  group('H-03-C 游客不能伪造用户 ID（客户端无本地推导）', () {
    test('源码级：IdentitySummary 只经解析构造，客户端不得硬编码身份', () {
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      final offenders = <String>[];
      for (final f in files) {
        final p = f.path.replaceAll(r'\', '/');
        final src = f.readAsStringSync();
        // 只允许在契约定义体内构造 IdentitySummary（含 factory 与 const 构造声明）
        final constructions = RegExp(r'IdentitySummary\(').allMatches(src).length;
        if (constructions == 0) continue;
        final isDefinition = p.endsWith('content_repository.dart');
        if (!isDefinition) offenders.add('$p ($constructions 处)');
      }
      expect(offenders, isEmpty,
          reason: '身份只能来自服务端载荷解析，业务代码不得自行构造：$offenders');
    });

    test('响应中的 userId 原样呈现，客户端不做兜底填充', () {
      final id = IdentitySummary.fromJson(Map<String, dynamic>.from(_guestIdentity));
      expect(id.userId, isNull, reason: '服务端未给 userId 时客户端不得填充默认值');
    });
  });

  // ================================================================
  group('H-03-D App 表现：未实名与已实名的准入差异（widget）', () {
    Future<ProviderContainer> pumpShelf(
      WidgetTester tester,
      ScriptedApi api, {
      required User user,
      required Map<String, Object?> shelfPayload,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secure = _FakeSecureStorage();
      await secure.write(AppConstants.kAccessToken, 'token-for-test');
      await secure.write(AppConstants.kRefreshToken, 'refresh-for-test');
      final storage = TokenStorage(secure, prefs);

      api.reply('/content/shelf', Envelope.ok(shelfPayload));

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          secureTokenStorageProvider.overrideWithValue(secure),
          tokenStorageProvider.overrideWithValue(storage),
          authRepositoryProvider.overrideWithValue(_MeRepo(user)),
          api.override,
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: BookshelfPage()),
        ),
      );
      await tester.pump();
      // 确定性等待启动会话恢复完成：断言/点击前必须已处于 authenticated，
      // 否则 RealNameGuard 会因 user == null 走登录守卫（本页未挂 GoRouter）。
      await container.read(authControllerProvider.notifier).refreshMe();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(container.read(authControllerProvider).user, isNotNull,
          reason: '测试前置：会话恢复必须得到已登录身份');
      return container;
    }

    const verifiedUser = User(
      userId: 401,
      userType: UserType.user,
      realNameStatus: 'APPROVED',
      nickname: '已实名用户',
    );
    const notVerifiedUser = User(
      userId: 402,
      userType: UserType.user,
      realNameStatus: 'NOT_SUBMITTED',
      nickname: '未实名用户',
    );

    Map<String, Object?> shelfOf(User u) => {
          'identity': {
            'authenticated': true,
            'guest': false,
            'userId': u.userId,
            'realNameStatus': u.realNameStatus,
            'roleCodes': u.roles,
          },
          'works': [_work],
          'downloadable': u.isRealNameApproved,
          'realNameRequired': !u.isRealNameApproved,
        };

    testWidgets('已登录未实名：书架展示「需实名认证」并展示身份摘要', (tester) async {
      final api = ScriptedApi();
      await pumpShelf(tester, api, user: notVerifiedUser, shelfPayload: shelfOf(notVerifiedUser));

      expect(find.text('我的书架'), findsOneWidget);
      expect(find.byTooltip('需实名认证'), findsOneWidget);
      expect(find.byTooltip('下载素材'), findsNothing);
      // 身份摘要由服务端下发
      expect(find.text('身份摘要（由服务端下发）'), findsOneWidget);
      expect(find.text('示例剧本·长夜'), findsOneWidget);
    });

    testWidgets('已实名：书架展示「下载素材」入口', (tester) async {
      final api = ScriptedApi();
      await pumpShelf(tester, api, user: verifiedUser, shelfPayload: shelfOf(verifiedUser));

      expect(find.byTooltip('下载素材'), findsOneWidget);
      expect(find.byTooltip('需实名认证'), findsNothing);
    });

    testWidgets('未实名点击下载：被实名准入拦截并弹出引导（不放行下载）', (tester) async {
      final api = ScriptedApi();
      await pumpShelf(tester, api, user: notVerifiedUser, shelfPayload: shelfOf(notVerifiedUser));

      await tester.tap(find.byTooltip('需实名认证'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('需要实名认证'), findsOneWidget, reason: '未实名必须被准入守卫拦截');
      expect(find.textContaining('下载《示例剧本·长夜》素材需要先完成实名认证。'), findsOneWidget);
      expect(find.textContaining('已开始下载'), findsNothing, reason: '未实名不得执行下载');
    });

    testWidgets('已实名点击下载：直接放行（不出现实名引导）', (tester) async {
      final api = ScriptedApi();
      await pumpShelf(tester, api, user: verifiedUser, shelfPayload: shelfOf(verifiedUser));

      await tester.tap(find.byTooltip('下载素材'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('需要实名认证'), findsNothing, reason: '已实名不应再被实名准入拦截');
      expect(find.textContaining('已开始下载'), findsOneWidget);
    });

    testWidgets('书架数据归属取自服务端身份（请求不携带 userId）', (tester) async {
      final api = ScriptedApi();
      await pumpShelf(tester, api, user: verifiedUser, shelfPayload: shelfOf(verifiedUser));

      expect(api.countOf('/content/shelf'), 1);
      for (final r in api.requests) {
        expect(r.uri.toString().toLowerCase().contains('userid'), isFalse,
            reason: '书架请求不得携带用户标识：${r.uri}');
      }
    });
  });
}

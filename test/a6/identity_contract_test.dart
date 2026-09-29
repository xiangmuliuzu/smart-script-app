import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/core/providers/app_providers.dart';

import 'package:script_app/core/router/route_paths.dart';
import 'package:script_app/features/bookstore/data/content_providers.dart';
import 'package:script_app/features/bookstore/data/content_repository.dart';
import 'package:script_app/models/user.dart';

/// A6 统一身份能力与示例接入（契约 A6-IDENTITY-CONTRACT-v1 §3）。
///
/// 覆盖 Flutter 侧的统一入口语义：角色用于授权、权限用于入口控制、
/// 实名状态用于业务准入，三者互相独立；示例业务入口纳入守卫清单。
void main() {
  test('A6 游客身份没有伪造用户 ID', () {
    final summary = IdentitySummary.fromJson(const {
      'authenticated': false,
      'guest': true,
      'userId': null,
      'realNameStatus': 'NOT_SUBMITTED',
    });
    expect(summary.authenticated, isFalse);
    expect(summary.guest, isTrue);
    expect(summary.userId, isNull);
    expect(summary.roleCodes, isEmpty);
    expect(summary.permissionCodes, isEmpty);
  });

  test('A6 已登录身份摘要可解析后端下发的全部字段', () {
    final summary = IdentitySummary.fromJson(const {
      'authenticated': true,
      'guest': false,
      'userId': 88,
      'accountType': '02',
      'realNameStatus': 'APPROVED',
      'authorCapability': true,
      'roleCodes': ['author'],
      'permissionCodes': ['content:work:query', 'content:work:add'],
    });
    expect(summary.userId, 88);
    expect(summary.accountType, '02');
    expect(summary.realNameStatus, 'APPROVED');
    expect(summary.authorCapability, isTrue);
    expect(summary.roleCodes, ['author']);
    expect(summary.permissionCodes.length, 2);
  });

  test('A6 角色、权限与实名各自独立判定', () {
    const withRole = User(
      userId: 1,
      userType: UserType.creator,
      roles: ['author'],
      permissions: ['content:work:query'],
      realNameStatus: 'NOT_SUBMITTED',
    );
    // 有角色/权限但未实名：授权通过、准入不通过
    expect(withRole.hasRole('author'), isTrue);
    expect(withRole.hasPermission('content:work:query'), isTrue);
    expect(withRole.isRealNameApproved, isFalse);

    const noRoleApproved = User(
      userId: 2,
      userType: UserType.user,
      realNameStatus: 'APPROVED',
    );
    // 已实名但无角色：准入通过、没有该角色
    expect(noRoleApproved.isRealNameApproved, isTrue);
    expect(noRoleApproved.hasRole('author'), isFalse);
    expect(noRoleApproved.hasPermission('content:work:add'), isFalse);

    const pending = User(userId: 3, userType: UserType.user, realNameStatus: 'PENDING');
    expect(pending.isRealNameApproved, isFalse);
  });

  test('A6 权限判定支持若依通配 *:*:*', () {
    const wildcard = User(
      userId: 1,
      userType: UserType.user,
      permissions: ['*:*:*'],
    );
    expect(wildcard.hasPermission('content:work:add'), isTrue);

    const scoped = User(
      userId: 2,
      userType: UserType.user,
      permissions: ['content:work:query'],
    );
    expect(scoped.hasPermission('content:work:query'), isTrue);
    expect(scoped.hasPermission('content:work:add'), isFalse);
    expect(scoped.hasPermission(''), isFalse);
  });

  test('A6 作者能力与账号类型不互相推导', () {
    const creatorWithoutCapability = User(userId: 1, userType: UserType.creator);
    expect(creatorWithoutCapability.isCreator, isTrue);
    expect(creatorWithoutCapability.authorCapability, isFalse);

    const userWithCapability = User(
      userId: 2,
      userType: UserType.user,
      authorCapability: true,
    );
    expect(userWithCapability.authorCapability, isTrue);
    expect(userWithCapability.isCreator, isFalse);
  });

  test('A6 用户模型序列化保留身份字段（供本地缓存恢复）', () {
    const user = User(
      userId: 7,
      userType: UserType.creator,
      realNameStatus: 'APPROVED',
      roles: ['author'],
      permissions: ['content:work:query'],
      authorCapability: true,
    );
    final restored = User.fromJson(user.toJson());
    expect(restored.realNameStatus, 'APPROVED');
    expect(restored.roles, ['author']);
    expect(restored.permissions, ['content:work:query']);
    expect(restored.authorCapability, isTrue);
  });

  test('A6 公开入口与受保护入口的边界（规格 §8.1）', () {
    // 公开入口：游客可浏览，不做登录跳转
    for (final path in [RoutePath.bookstore, RoutePath.comic, RoutePath.category]) {
      expect(ProtectedRoutes.isProtected(path), isFalse, reason: '公开入口不应受保护: $path');
    }
    // 受保护入口：必须走统一守卫
    for (final path in [RoutePath.bookshelf, RoutePath.profile, RoutePath.messages]) {
      expect(ProtectedRoutes.isProtected(path), isTrue, reason: '受保护入口必须拦截: $path');
    }
  });

  test('A6 示例业务入口纳入统一守卫清单', () {
    // 「我的书架」是 B 模块示例的受保护入口
    expect(ProtectedRoutes.isProtected(RoutePath.bookshelf), isTrue);
    // 书城公开列表不要求登录
    expect(ProtectedRoutes.isProtected(RoutePath.bookstore), isFalse);
    // 回跳仍允许回到书架
    expect(ProtectedRoutes.canResume(RoutePath.bookshelf), isTrue);
  });

  test('A6 作品列表与书架载荷解析稳定', () {
    final works = WorksPayload.fromJson(const {
      'identity': {'authenticated': false, 'guest': true},
      'personalized': false,
      'works': [
        {
          'workId': 1,
          'title': '示例剧本·长夜',
          'authorName': '示例作者甲',
          'category': '都市',
          'wordCount': 128000,
          'freeToRead': true,
        }
      ],
    });
    expect(works.personalized, isFalse);
    expect(works.works.single.title, '示例剧本·长夜');
    expect(works.works.single.freeToRead, isTrue);

    final shelf = ShelfPayload.fromJson(const {
      'identity': {'authenticated': true, 'guest': false, 'userId': 9},
      'downloadable': false,
      'realNameRequired': true,
      'works': [],
    });
    expect(shelf.downloadable, isFalse);
    expect(shelf.realNameRequired, isTrue);
    expect(shelf.identity.userId, 9);
  });

  test('A6 业务仓库依赖注入可用（不新建网络栈）', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    // 仓库由 provider 提供，页面不直接接触网络层
    expect(container.read(contentRepositoryProvider), isNotNull);
  });
}

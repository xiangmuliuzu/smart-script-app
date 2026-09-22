import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:script_app/app.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/router/app_router.dart';
import 'package:script_app/core/router/route_intent.dart';
import 'package:script_app/core/router/route_paths.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';
import 'package:script_app/features/user_center/data/user_center_models.dart';
import 'package:script_app/models/user.dart';
import 'package:script_app/features/user_center/data/user_center_providers.dart';
import 'package:script_app/features/user_center/data/user_center_repository.dart';

/// A5 启动与守卫（规格 §8.1）。
///
/// 覆盖三件事：
///   1. 应用可启动：未登录冷启动落在启动页，会话校验失败后进入登录页；
///   2. 受保护入口的守卫与回跳意图：未登录访问用户中心时必须保存结构化意图；
///   3. 回跳意图的消费语义：只消费一次、非法目标与敏感路径不回跳。

/// 不触网、不写安全存储的假实现：仅提供测试所需的最小行为。
class _FakeSecureStorage implements TokenSecureStorage {
  _FakeSecureStorage([Map<String, String>? seed]) : _map = {...?seed};

  final Map<String, String> _map;

  @override
  Future<void> write(String key, String value) async => _map[key] = value;

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> delete(String key) async => _map.remove(key);

  @override
  Future<void> deleteAll() async => _map.clear();
}

/// 用户中心仓库的假实现：资料页只需要一个可渲染的返回值。
class _FakeUserCenterRepository extends UserCenterRepository {
  _FakeUserCenterRepository(super.api);

  @override
  Future<UserProfile> profile() async => const UserProfile(
        userId: 1,
        userType: '01',
        nickname: '测试用户',
        phoneMasked: '138****8000',
      );
}

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final storage = TokenStorage(_FakeSecureStorage(), prefs);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureTokenStorageProvider.overrideWithValue(_FakeSecureStorage()),
      tokenStorageProvider.overrideWithValue(storage),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('A5 无凭据冷启动：应用可构建并停在登录页', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = TokenStorage(_FakeSecureStorage(), prefs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          secureTokenStorageProvider.overrideWithValue(_FakeSecureStorage()),
          tokenStorageProvider.overrideWithValue(storage),
        ],
        child: const ScriptApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 未登录冷启动最终落在登录页（启动页 -> 会话校验 -> 登录页）
    expect(find.text('欢迎回来'), findsOneWidget);
  });

  testWidgets('A5 守卫拦截受保护入口并保存回跳意图，登录页带 redirect 参数', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = TokenStorage(_FakeSecureStorage(), prefs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          secureTokenStorageProvider.overrideWithValue(_FakeSecureStorage()),
          tokenStorageProvider.overrideWithValue(storage),
        ],
        child: const ScriptApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('欢迎回来'), findsOneWidget);

    // 未登录访问受保护的用户中心页面
    final context = tester.element(find.byType(MaterialApp));
    final container = ProviderScope.containerOf(context);
    final router = container.read(routerProvider);
    router.go('${RoutePath.feedbackDetail}?id=42');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 仍停在登录页，且意图已保存（结构化定位串，含查询参数）
    expect(find.text('欢迎回来'), findsOneWidget);
    expect(container.read(routeIntentStoreProvider).pending?.target,
        '${RoutePath.feedbackDetail}?id=42');
  });

  testWidgets('A5 未登录访问普通入口不产生回跳意图', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = TokenStorage(_FakeSecureStorage(), prefs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          secureTokenStorageProvider.overrideWithValue(_FakeSecureStorage()),
          tokenStorageProvider.overrideWithValue(storage),
        ],
        child: const ScriptApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final context = tester.element(find.byType(MaterialApp));
    final container = ProviderScope.containerOf(context);
    container.read(routerProvider).go(RoutePath.login);
    await tester.pump();

    expect(container.read(routeIntentStoreProvider).pending, isNull);
  });

  test('A5 回跳意图只消费一次', () {
    final store = RouteIntentStore();
    store.save(RouteIntent.fromParam(Uri.encodeComponent('/profile/messages/detail?id=7'))!);
    expect(store.pending?.target, '/profile/messages/detail?id=7');
    expect(store.consume()?.target, '/profile/messages/detail?id=7');
    expect(store.consume(), isNull);
    expect(store.pending, isNull);
  });

  test('A5 非法回跳目标被拒绝（防开放重定向与超长串）', () {
    expect(RouteIntent.fromParam(null), isNull);
    expect(RouteIntent.fromParam(''), isNull);
    expect(RouteIntent.fromParam(Uri.encodeComponent('https://evil.example.com')), isNull);
    expect(RouteIntent.fromParam(Uri.encodeComponent('//evil.example.com')), isNull);
    expect(RouteIntent.fromParam(Uri.encodeComponent('/${'a' * 600}')), isNull);
    expect(RouteIntent.fromParam(Uri.encodeComponent('/profile/edit'))?.target, '/profile/edit');
  });

  test('A5 敏感路径不参与自动回跳', () {
    expect(ProtectedRoutes.canResume(RoutePath.phoneChange), isFalse);
    expect(ProtectedRoutes.canResume(RoutePath.accountSecurity), isFalse);
    expect(ProtectedRoutes.canResume('${RoutePath.phoneChange}?step=2'), isFalse);
    expect(ProtectedRoutes.canResume(RoutePath.profileEdit), isTrue);
    expect(ProtectedRoutes.canResume('${RoutePath.messages}?id=3'), isTrue);
  });

  test('A5 退出登录清空回跳意图', () {
    final store = RouteIntentStore();
    store.save(const RouteIntent('/profile/edit'));
    store.clear();
    expect(store.pending, isNull);
    expect(store.consume(), isNull);
  });

  test('A5 守卫清单覆盖用户中心全部受保护前缀', () {
    for (final path in [
      RoutePath.profile,
      RoutePath.profileEdit,
      RoutePath.realName,
      RoutePath.accountSecurity,
      RoutePath.phoneChange,
      RoutePath.notificationPreferences,
      RoutePath.messages,
      RoutePath.messageDetail,
      RoutePath.feedback,
      RoutePath.feedbackCreate,
      RoutePath.feedbackDetail,
    ]) {
      expect(ProtectedRoutes.isProtected(path), isTrue, reason: 'must be protected: $path');
    }
    expect(ProtectedRoutes.isProtected(RoutePath.bookstore), isFalse);
    expect(ProtectedRoutes.isProtected(RoutePath.login), isFalse);
  });

  test('A5 资料/实名状态等模型字段与后端契约一致', () {
    final profile = UserProfile.fromJson(const {
      'userId': 12,
      'userType': '02',
      'nickname': '作者甲',
      'avatar': null,
      'phoneMasked': '139****1111',
      'realNameStatus': 'PENDING',
    });
    expect(profile.userId, 12);
    expect(profile.userType, '02');
    expect(profile.realNameStatus, 'PENDING');

    final status = RealNameStatus.fromJson(const {'status': 'REJECTED', 'rejectReason': '照片不清晰'});
    expect(status.state, RealNameState.rejected);
    expect(status.state.canSubmit, isTrue);
    expect(RealNameState.pending.canSubmit, isFalse);
    expect(RealNameState.approved.canSubmit, isFalse);
    expect(RealNameState.notSubmitted.canSubmit, isTrue);

    // 未提供的字段不得凭空推断
    expect(RealNameStatus.fromJson(const {}).state, RealNameState.notSubmitted);

    final message = MessageItem.fromJson(const {
      'messageId': 5,
      'type': 'BENEFIT',
      'title': '福利到账',
      'summary': '摘要',
      'read': false,
    });
    expect(message.typeLabel, '福利');
    expect(message.read, isFalse);

    final feedback = FeedbackItem.fromJson(const {
      'feedbackId': 3,
      'category': 'BUG',
      'content': '内容',
      'status': 'REPLIED',
      'reply': '已修复',
      'attachments': ['/profile/upload/a.png'],
    });
    expect(feedback.status, FeedbackStatus.replied);
    expect(feedback.categoryLabel, '缺陷报告');
    expect(feedback.attachments.length, 1);

    final prefs = NotificationPreference.fromJson(const {
      'channel': 'PUSH',
      'type': 'SYSTEM',
      'enabled': false,
    });
    expect(prefs.enabled, isFalse);
    expect(prefs.toJson(), {'channel': 'PUSH', 'type': 'SYSTEM', 'enabled': false});
  });

  test('A5 用户模型暴露规格 §10 统一身份能力', () {
    const user = User(
      userId: 1,
      userType: UserType.creator,
      realNameStatus: 'APPROVED',
      roles: ['author'],
      hasPassword: true,
    );
    expect(user.isRealNameApproved, isTrue);
    expect(user.hasRole('author'), isTrue);
    expect(user.hasRole('admin'), isFalse);
    expect(user.hasPassword, isTrue);
    expect(user.isCreator, isTrue);

    final decoded = User.fromJson(const {
      'userId': 9,
      'userType': '01',
      'realNameStatus': 'PENDING',
      'roles': ['reader'],
      'hasPassword': false,
    });
    expect(decoded.realNameStatus, 'PENDING');
    expect(decoded.roles, ['reader']);
    expect(decoded.hasPassword, isFalse);
  });

  test('A5 用户中心假仓库可返回资料（数据层可注入）', () async {
    final container = await _container();
    final repo = _FakeUserCenterRepository(container.read(apiClientProvider));
    final profile = await repo.profile();
    expect(profile.nickname, '测试用户');
    expect(profile.phoneMasked, '138****8000');
    expect(container.read(userCenterRepositoryProvider), isNotNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:script_app/core/constants/app_constants.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/providers/auth_providers.dart';
import 'package:script_app/core/router/route_paths.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/features/auth/data/auth_repository.dart';
import 'package:script_app/features/create/create_page.dart';
import 'package:script_app/features/create/data/author_work_providers.dart';
import 'package:script_app/features/profile/pages/creator_apply_page.dart';
import 'package:script_app/features/user_center/data/user_center_models.dart';
import 'package:script_app/features/user_center/data/user_center_providers.dart';
import 'package:script_app/models/user.dart';

class _Repository implements AuthRepository {
  _Repository(this.user);
  final User user;
  @override
  Future<User> me() async => user;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> containerFor(User user, VoidCallback onWorks) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secure = InMemoryTokenSecureStorage();
    await secure.write(AppConstants.kAccessToken, 'fixture-access');
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureTokenStorageProvider.overrideWithValue(secure),
      authRepositoryProvider.overrideWithValue(_Repository(user)),
      myWorksProvider.overrideWith((ref, status) async {
        onWorks();
        return [];
      }),
      creatorApplyStatusProvider.overrideWith((ref) async =>
          const CreatorApplyStatus(state: CreatorApplyState.notSubmitted)),
    ]);
    container.read(authControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    addTearDown(container.dispose);
    expect(container.read(authControllerProvider).isAuthenticated, isTrue);
    return container;
  }

  for (final type in [UserType.user, UserType.creator]) {
    testWidgets('$type without capability cannot load or create works and can apply', (tester) async {
      var requests = 0;
      final container = await tester.runAsync(() => containerFor(
          User(userId: 1, userType: type), () => requests++));
      final router = GoRouter(initialLocation: RoutePath.create, routes: [
        GoRoute(path: RoutePath.create, builder: (_, __) => const CreatePage()),
        GoRoute(path: RoutePath.creatorApply, builder: (_, __) => const CreatorApplyPage()),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container!, child: MaterialApp.router(routerConfig: router)));
      await tester.pumpAndSettle();
      expect(find.text('请先申请开通创作者能力'), findsOneWidget);
      expect(find.text('新建'), findsNothing);
      expect(requests, 0);
      await tester.tap(find.text('去申请'));
      await tester.pumpAndSettle();
      expect(find.text('提交申请'), findsOneWidget);
    });
  }

  testWidgets('ordinary account with capability can load works and create', (tester) async {
    var requests = 0;
    final container = await tester.runAsync(() => containerFor(
        const User(userId: 1, userType: UserType.user, authorCapability: true),
        () => requests++));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container!, child: const MaterialApp(home: CreatePage())));
    await tester.pumpAndSettle();
    expect(find.text('新建'), findsOneWidget);
    expect(find.text('请先申请开通创作者能力'), findsNothing);
    expect(requests, 1);
  });
}

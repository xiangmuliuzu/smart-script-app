import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:script_app/core/constants/app_constants.dart';
import 'package:script_app/core/network/session_events.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/providers/auth_providers.dart';
import 'package:script_app/core/router/app_router.dart';
import 'package:script_app/core/router/route_paths.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/features/auth/data/auth_repository.dart';
import 'package:script_app/features/user_center/data/user_center_models.dart';
import 'package:script_app/features/user_center/data/user_center_providers.dart';
import 'package:script_app/models/user.dart';

const _user = User(userId: 12, userType: UserType.user, realNameStatus: 'PENDING');

class _RefreshRepository implements AuthRepository {
  Completer<User>? refreshGate;
  @override
  Future<User> me() => refreshGate?.future ?? Future.value(_user);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({ProviderContainer container, _RefreshRepository repository})> setup() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secure = InMemoryTokenSecureStorage();
    await secure.write(AppConstants.kAccessToken, 'fixture-access');
    await secure.write(AppConstants.kRefreshToken, 'fixture-refresh');
    final repository = _RefreshRepository();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureTokenStorageProvider.overrideWithValue(secure),
      authRepositoryProvider.overrideWithValue(repository),
      realNameStatusProvider.overrideWith((ref) async => const RealNameStatus(state: RealNameState.pending)),
    ]);
    container.read(authControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    addTearDown(container.dispose);
    expect(container.read(authControllerProvider).isAuthenticated, isTrue);
    return (container: container, repository: repository);
  }

  testWidgets('verified identity refresh keeps the real-name router location', (tester) async {
    final harness = await tester.runAsync(setup);
    final container = harness!.container;
    final router = container.read(routerProvider);
    addTearDown(router.dispose);
    router.go(RoutePath.realName);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    harness.repository.refreshGate = Completer<User>();
    final refreshing = container.read(authControllerProvider.notifier).refreshMe();
    await tester.pump(const Duration(milliseconds: 20));
    expect(container.read(authControllerProvider).isAuthenticated, isTrue);
    expect(router.routeInformationProvider.value.uri.path, RoutePath.realName);
    harness.repository.refreshGate!.complete(const User(userId: 12, userType: UserType.user, nickname: 'refreshed', realNameStatus: 'PENDING'));
    await refreshing;
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, RoutePath.realName);
    expect(container.read(authControllerProvider).user?.nickname, 'refreshed');
  });

  test('transient refresh failure preserves an already verified session', () async {
    final harness = await setup();
    harness.repository.refreshGate = Completer<User>();
    final refreshing = harness.container.read(authControllerProvider.notifier).refreshMe();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    harness.repository.refreshGate!.completeError(Exception('temporary network failure'));
    await refreshing;
    expect(harness.container.read(authControllerProvider).isAuthenticated, isTrue);
  });

  test('expiry during identity refresh cannot revive the old session', () async {
    final harness = await setup();
    harness.repository.refreshGate = Completer<User>();
    final refreshing = harness.container.read(authControllerProvider.notifier).refreshMe();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    SessionEvents.instance.sessionExpired();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    harness.repository.refreshGate!.complete(_user);
    await refreshing;
    expect(harness.container.read(authControllerProvider).status, AuthStatus.unauthenticated);
    expect(harness.container.read(authControllerProvider).user, isNull);
  });
}

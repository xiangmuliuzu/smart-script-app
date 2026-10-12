import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/providers/auth_providers.dart';
import 'package:script_app/core/router/route_paths.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/core/storage/token_storage.dart';
import 'package:script_app/features/auth/data/auth_repository.dart';
import 'package:script_app/features/auth/pages/password_login_page.dart';
import 'package:script_app/features/auth/widgets/auth_buttons.dart';
import 'package:dio/dio.dart';

class _RecordingController extends AuthController {
  _RecordingController(super.storage, super.repository);
  int calls = 0;
  String? captchaCode, captchaUuid;
  @override
  Future<void> loginWithPassword(String phone, String password,
      {String? deviceId, String? code, String? uuid}) async {
    calls++;
    captchaCode = code;
    captchaUuid = uuid;
    state = const AuthState(AuthStatus.authenticated);
  }
}

void main() {
  testWidgets('enabled RuoYi captcha is required and submitted with its uuid',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = TokenStorage(
        InMemoryTokenSecureStorage(), await SharedPreferences.getInstance());
    final controller =
        _RecordingController(storage, AuthRepository(ApiClient(Dio())));
    final router = GoRouter(initialLocation: RoutePath.passwordLogin, routes: [
      GoRoute(
          path: RoutePath.passwordLogin,
          builder: (_, __) => const PasswordLoginPage()),
      GoRoute(
          path: RoutePath.home,
          builder: (_, __) => const Scaffold(body: Text('已登录'))),
    ]);
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith((_) => controller),
      loginCaptchaProvider.overrideWith((_) async => {
            'captchaEnabled': true,
            'uuid': 'captcha-id',
            'img':
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          }),
    ]);
    addTearDown(container.dispose);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), '13900000007');
    await tester.enterText(fields.at(1), 'Passw0rdX');
    final button = find.widgetWithText(PrimaryButton, '登录');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(controller.calls, 0);
    expect(find.text('请输入图形验证码'), findsWidgets);
    await tester.enterText(fields.at(2), '1234');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(controller.calls, 1);
    expect(controller.captchaCode, '1234');
    expect(controller.captchaUuid, 'captcha-id');
    expect(find.text('已登录'), findsOneWidget);
  });
}

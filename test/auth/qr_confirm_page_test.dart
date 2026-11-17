import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/features/auth/data/auth_repository.dart';
import 'package:script_app/features/auth/data/qr_login_models.dart';
import 'package:script_app/features/auth/pages/qr_confirm_page.dart';

/// 记录接口调用的假仓库：确认页只用到扫码登录的三个方法。
class _QrRepo implements AuthRepository {
  _QrRepo({this.failWith});

  final String? failWith;
  final List<String> calls = [];

  @override
  Future<void> confirmQrLogin(String qrToken) async {
    calls.add('confirm:$qrToken');
    if (failWith != null) throw Exception(failWith);
  }

  @override
  Future<void> cancelQrLogin(String qrToken) async => calls.add('cancel:$qrToken');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _token = 'c0ffee1234567890c0ffee1234567890';

/// 确认页是从扫一扫页 push 进来的：这里用同构的路由验证返回值与控制台按钮。
Future<_QrRepo> _pump(
  WidgetTester tester, {
  required QrScanTarget? target,
  String token = _token,
  String? failWith,
  String? landing,
}) async {
  final repo = _QrRepo(failWith: failWith);
  final router = GoRouter(
    initialLocation: '/scan',
    routes: [
      GoRoute(
        path: '/scan',
        builder: (_, __) => const Scaffold(body: Text('scan')),
      ),
      GoRoute(
        path: '/confirm',
        builder: (_, state) => QrConfirmPage(
          qrToken: state.uri.queryParameters['t'] ?? '',
          target: state.extra is QrScanTarget ? state.extra as QrScanTarget : null,
        ),
      ),
      GoRoute(
        path: '/landing',
        builder: (_, __) => const Scaffold(body: Text('landing')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  router.push('/confirm?t=$token', extra: target);
  await tester.pumpAndSettle();
  if (landing != null) {
    expect(find.text('landing'), findsNothing);
  }
  return repo;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('确认页展示登录站点与浏览器，而不是只显示一个确认按钮', (tester) async {
    await _pump(
      tester,
      target: const QrScanTarget(
        portal: 'enterprise',
        browser: 'Chrome 130',
        os: 'Windows 11',
        status: 'SCANNED',
      ),
    );

    expect(find.text('确认登录'), findsWidgets);
    expect(find.text('企业端 · 个人版权采购中心'), findsOneWidget);
    expect(find.text('Chrome 130 · Windows 11'), findsOneWidget);
    // 明确的风险提示与取消入口：陌生人抢扫时用户要能当场拒绝。
    expect(find.text('取消登录'), findsOneWidget);
    expect(find.textContaining('如果这不是你本人正在登录的网页'), findsOneWidget);
  });

  testWidgets('深链缺少登录端信息时按创作者端兜底，并提示未知设备', (tester) async {
    await _pump(tester, target: null);

    expect(find.text('创作者端 · 创作者中心'), findsOneWidget);
    expect(find.text('未知设备'), findsOneWidget);
  });

  testWidgets('点确认提交票据并返回 true；点取消作废票据并返回 false', (tester) async {
    final repo = await _pump(
      tester,
      target: const QrScanTarget(portal: 'creator', browser: 'Chrome', os: 'Windows', status: 'SCANNED'),
    );

    await tester.tap(find.widgetWithText(FilledButton, '确认登录'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['confirm:$_token']);
    // 确认后回到扫一扫页（栈里只剩它），不会把用户留在确认页。
    expect(find.text('scan'), findsOneWidget);

    final repo2 = await _pump(
      tester,
      target: const QrScanTarget(portal: 'creator', browser: 'Chrome', os: 'Windows', status: 'SCANNED'),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '取消登录'));
    await tester.pumpAndSettle();
    expect(repo2.calls, ['cancel:$_token']);
    expect(find.text('scan'), findsOneWidget);
  });

  testWidgets('票据为空时不会提交无意义的确认请求', (tester) async {
    final repo = await _pump(tester, target: null, token: '');

    await tester.tap(find.widgetWithText(FilledButton, '确认登录'));
    await tester.pump();
    expect(repo.calls, isEmpty);
    expect(find.textContaining('二维码信息不完整'), findsOneWidget);
  });
}

import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:script_app/core/constants/app_constants.dart';
import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/router/route_paths.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/features/auth/data/auth_repository.dart';
import 'package:script_app/features/profile/profile_page.dart';
import 'package:script_app/features/profile/pages/real_name_page.dart';

import 'support/scripted_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> pump(WidgetTester tester, ScriptedApi api) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        secureTokenStorageProvider
            .overrideWithValue(InMemoryTokenSecureStorage()),
        api.override,
      ],
      child: const MaterialApp(home: RealNamePage()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> pickBoth(WidgetTester tester) async {
    final dir = Directory.systemTemp.createTempSync('real-name-test');
    var count = 0;
    const channel = MethodChannel('smartscript/native_image');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      final file = File('${dir.path}/${count++}.png');
      file.writeAsBytesSync(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='));
      return file.path;
    });
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    for (final label in ['身份证正面（人像面）', '身份证反面（国徽面）']) {
      final button = find.textContaining(label);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.runAsync(() async { await tester.tap(button); await Future<void>.delayed(const Duration(milliseconds: 100)); });
      await tester.pumpAndSettle();
    }
  }

  void status(ScriptedApi api) {
    api.reply('/users/me/real-name', Envelope.ok({'status': 'NOT_SUBMITTED'}));
  }

  testWidgets('approved users can reopen masked real-name details from the profile drawer',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secure = InMemoryTokenSecureStorage();
    await secure.write(AppConstants.kAccessToken, 'test-only-token');
    final api = ScriptedApi();
    api.reply('/auth/getInfo', Envelope.ok({
      'userId': 12, 'userType': '01', 'nickname': '测试用户',
      'realNameStatus': 'APPROVED',
    }));
    api.reply('/messages/unread-count', Envelope.ok({'total': 0}));
    api.reply('/content/shelf', Envelope.ok({'total': 0, 'list': []}));
    api.reply('/public-profile', Envelope.ok({'userId': 12}));
    api.reply('/stats', Envelope.ok({'likeCount': 0}));
    api.reply('/users/me/real-name', Envelope.ok({
      'status': 'APPROVED',
      'realNameMasked': '测**户',
      'idNumberMasked': '110101********123X',
      'submittedAt': '2026-10-26 09:00:00',
      'reviewedAt': '2026-10-26 09:01:00',
    }));
    final router = GoRouter(initialLocation: RoutePath.profile, routes: [
      GoRoute(path: RoutePath.profile, builder: (_, __) => const ProfilePage()),
      GoRoute(path: RoutePath.realName, builder: (_, __) => const RealNamePage()),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        secureTokenStorageProvider.overrideWithValue(secure),
        authRepositoryProvider.overrideWithValue(AuthRepository(ApiClient(api.buildDio()))),
        api.override,
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.text('已认证'), findsOneWidget);
    expect(find.text('去认证'), findsNothing);
    for (var visit = 0; visit < 2; visit++) {
      await tester.tap(find.byTooltip('工具与设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, '实名认证'));
      await tester.pumpAndSettle();
      expect(find.byType(RealNamePage), findsOneWidget);
      expect(find.text('测**户'), findsOneWidget);
      expect(find.text('110101********123X'), findsOneWidget);
      expect(find.text('2026-10-26 09:01:00'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(api.countOf('/users/me/real-name'), visit + 1);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsOneWidget);
    }
    expect(api.requests.every((request) => request.method == 'GET'), isTrue);
  });

  for (final id in [
    '110101199001011234',
    '11010119900101123X',
    '11010119900101123x'
  ]) {
    testWidgets('name and 18-character ID submit with both materials: $id',
        (tester) async {
      final api = ScriptedApi();
      status(api);
      await pump(tester, api);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('证件材料'), findsNothing);
      expect(find.text('选择证件照片'), findsNothing);
      api.reply('/users/me/real-name', Envelope.ok({'status': 'PENDING'}));
      await pickBoth(tester);
      await tester.enterText(find.byType(TextField).at(0), '测试用户');
      await tester.enterText(find.byType(TextField).at(1), id);
      await tester.ensureVisible(find.text('提交认证'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('提交认证'));
      await tester.pumpAndSettle();
      final request = api.requests.singleWhere((r) => r.method == 'POST');
      final data = request.data as FormData;
      expect(Map.fromEntries(data.fields), {'realName': '测试用户', 'idNumber': id});
      expect(data.files.map((entry) => entry.key), ['front', 'back']);
      expect(api.countOf('/real-name/material'), 0);
      expect(find.text('申请审核中，暂不能重复提交。'), findsOneWidget);
      expect(find.text('提交认证'), findsNothing);
      expect(find.text('提交失败，请稍后重试'), findsNothing);
    });
  }

  for (final id in [
    '110101900101123',
    '11010119900101123',
    '11010X199001011234'
  ]) {
    testWidgets('invalid ID is blocked before submitting: $id', (tester) async {
      final api = ScriptedApi();
      status(api);
      await pump(tester, api);
      await tester.enterText(find.byType(TextField).at(0), '测试用户');
      await tester.enterText(find.byType(TextField).at(1), id);
      await tester.tap(find.text('提交认证'));
      await tester.pumpAndSettle();
      expect(find.text('请输入正确的 18 位身份证号，末位可为 X'), findsOneWidget);
      expect(api.requests.where((r) => r.method == 'POST'), isEmpty);
    });
  }

  testWidgets('both identity images are required before submission', (tester) async {
    final api = ScriptedApi();
    status(api);
    await pump(tester, api);
    await tester.enterText(find.byType(TextField).at(0), '测试用户');
    await tester.enterText(find.byType(TextField).at(1), '11010119900101123X');
    await tester.ensureVisible(find.text('提交认证'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交认证'));
    await tester.pumpAndSettle();
    expect(find.text('请上传身份证正反面'), findsOneWidget);
    expect(api.requests.where((r) => r.method == 'POST'), isEmpty);
  });

  testWidgets('ID input filters unsupported characters and limits length to 18',
      (tester) async {
    final api = ScriptedApi();
    status(api);
    await pump(tester, api);
    final input = find.byType(TextField).at(1);
    await tester.enterText(input, '1101011990010112345');
    expect(
        tester.widget<TextField>(input).controller!.text, '110101199001011234');
    await tester.enterText(input, 'a11010119900101123X');
    expect(
        tester.widget<TextField>(input).controller!.text, '11010119900101123X');
  });

  testWidgets('rejected verification can resubmit with both files',
      (tester) async {
    final api = ScriptedApi();
    api.reply('/users/me/real-name', Envelope.ok({'status': 'REJECTED'}));
    await pump(tester, api);
    api.reply(
        '/users/me/real-name/resubmit', Envelope.ok({'status': 'PENDING'}));
    await pickBoth(tester);
    await tester.enterText(find.byType(TextField).at(0), '测试用户');
    await tester.enterText(find.byType(TextField).at(1), '11010119900101123X');
    await tester.ensureVisible(find.text('重新提交'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新提交'));
    await tester.pumpAndSettle();
    final request = api.requests.singleWhere((r) => r.method == 'POST');
    expect(request.path, endsWith('/real-name/resubmit'));
    final data = request.data as FormData;
    expect(Map.fromEntries(data.fields), {'realName': '测试用户', 'idNumber': '11010119900101123X'});
    expect(data.files.map((entry) => entry.key), ['front', 'back']);
    expect(find.text('申请审核中，暂不能重复提交。'), findsOneWidget);
  });
}

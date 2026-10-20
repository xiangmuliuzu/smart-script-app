import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';
import 'package:script_app/features/profile/pages/real_name_page.dart';
import 'package:script_app/features/user_center/data/user_center_repository.dart';

import 'support/scripted_api.dart';

const _image =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
const _reference = 'realname/12/0123456789abcdef0123456789abcdef.png';

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

  void status(ScriptedApi api) {
    api.reply('/users/me/real-name', Envelope.ok({'status': 'NOT_SUBMITTED'}));
  }

  test(
      'repository uploads multipart to private material endpoint and rejects empty results',
      () async {
    final api = ScriptedApi();
    final repository = UserCenterRepository(ApiClient(api.buildDio()));
    api.reply('/users/me/real-name/material',
        Envelope.ok({'materialRef': _reference}));
    expect(
        await repository.uploadRealNameMaterial(
            bytes: base64Decode(_image), filename: 'realname.png'),
        _reference);
    final form = api.requests.single.data as FormData;
    expect(form.files.single.key, 'file');
    expect(form.files.single.value.filename, 'realname.png');
    api.reply('/users/me/real-name/material', Envelope.ok({'materialRef': ''}));
    await expectLater(
        repository.uploadRealNameMaterial(bytes: [1], filename: 'realname.png'),
        throwsA(isA<ApiException>()));
  });

  for (final id in [
    '110101199001011234',
    '11010119900101123X',
    '11010119900101123x'
  ]) {
    testWidgets('name and 18-character ID submit without material: $id',
        (tester) async {
      final api = ScriptedApi();
      status(api);
      await pump(tester, api);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('证件材料'), findsNothing);
      expect(find.text('选择证件照片'), findsNothing);
      api.reply('/users/me/real-name', Envelope.ok({'status': 'APPROVED'}));
      await tester.enterText(find.byType(TextField).at(0), '测试用户');
      await tester.enterText(find.byType(TextField).at(1), id);
      await tester.tap(find.text('提交认证'));
      await tester.pumpAndSettle();
      final request = api.requests.singleWhere((r) => r.method == 'POST');
      expect(request.data, {'realName': '测试用户', 'idNumber': id});
      expect(api.countOf('/real-name/material'), 0);
      expect(find.text('实名认证通过'), findsOneWidget);
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

  testWidgets('rejected verification can resubmit without files',
      (tester) async {
    final api = ScriptedApi();
    api.reply('/users/me/real-name', Envelope.ok({'status': 'REJECTED'}));
    await pump(tester, api);
    api.reply(
        '/users/me/real-name/resubmit', Envelope.ok({'status': 'APPROVED'}));
    await tester.enterText(find.byType(TextField).at(0), '测试用户');
    await tester.enterText(find.byType(TextField).at(1), '11010119900101123X');
    await tester.tap(find.text('重新提交'));
    await tester.pumpAndSettle();
    final request = api.requests.singleWhere((r) => r.method == 'POST');
    expect(request.path, endsWith('/real-name/resubmit'));
    expect(
        request.data, {'realName': '测试用户', 'idNumber': '11010119900101123X'});
    expect(find.text('实名认证通过'), findsOneWidget);
  });
}

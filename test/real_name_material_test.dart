import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  const channel = MethodChannel('smartscript/native_image');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

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

  Future<void> pick(WidgetTester tester, {String button = '选择证件照片'}) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('realname-picker-');
      final file = File('${dir.path}/certificate.png');
      await file.writeAsBytes(base64Decode(_image));
      messenger.setMockMethodCallHandler(channel, (_) async => file.path);
      await tester.tap(find.text(button));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // 选择器已读完并清理临时文件。
      expect(await file.exists(), isFalse);
      await dir.delete();
    });
    await tester.pump();
  }

  Future<void> fillAndSubmit(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), '测试用户');
    await tester.enterText(find.byType(TextField).at(1), '110101199001011234');
    await tester.ensureVisible(find.text('提交认证'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交认证'));
    await tester.pumpAndSettle();
  }

  test(
      'repository uploads multipart to private material endpoint and rejects empty results',
      () async {
    final api = ScriptedApi();
    final repository = UserCenterRepository(ApiClient(api.buildDio()));
    api.reply('/users/me/real-name/material', Envelope.ok({'materialRef': _reference}));
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

  testWidgets('cancel and missing material do not upload or submit',
      (tester) async {
    final api = ScriptedApi();
    status(api);
    await pump(tester, api);
    expect(find.byType(TextField), findsNWidgets(2));
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await tester.tap(find.text('选择证件照片'));
    await tester.pumpAndSettle();
    await fillAndSubmit(tester);
    expect(find.text('请先上传证件照片'), findsOneWidget);
    expect(api.requests.where((r) => r.method == 'POST'), isEmpty);
  });

  testWidgets(
      'upload failure can retry, remove, replace and submit exact reference',
      (tester) async {
    final api = ScriptedApi();
    status(api);
    api.reply('/users/me/real-name/material', Envelope.fail(50000, '材料上传失败'));
    await pump(tester, api);
    await pick(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('材料上传失败'), findsOneWidget);
    await fillAndSubmit(tester);
    expect(
        api.requests
            .where((r) => r.method == 'POST' && r.path.endsWith('/real-name')),
        isEmpty);
    api.reply('/users/me/real-name/material', Envelope.ok({'materialRef': _reference}));
    await tester.ensureVisible(find.text('重试上传'));
    await tester.tap(find.text('重试上传'));
    await tester.pumpAndSettle();
    expect(find.text('上传成功'), findsOneWidget);
    expect(api.countOf('/real-name/material'), 2);
    // 取消更换不得清空已有上传结果。
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await tester.tap(find.text('更换照片'));
    await tester.pumpAndSettle();
    expect(find.text('上传成功'), findsOneWidget);
    final preview = tester.widget<Image>(find.byType(Image)).image;
    final previewKey = await preview.obtainKey(ImageConfiguration.empty);
    expect(PaintingBinding.instance.imageCache.containsKey(previewKey), isTrue);
    await tester.tap(find.text('移除照片'));
    await tester.pumpAndSettle();
    expect(PaintingBinding.instance.imageCache.containsKey(previewKey), isFalse,
        reason: 'Removing certificate photos must evict their shared preview cache');
    expect(find.text('上传成功'), findsNothing);
    await fillAndSubmit(tester);
    expect(find.text('请先上传证件照片'), findsOneWidget);
    await tester.ensureVisible(find.text('选择证件照片'));
    await pick(tester);
    await tester.pumpAndSettle();
    api.handle(
        '/users/me/real-name',
        (request) => request.method == 'POST'
            ? Envelope.ok({'status': 'PENDING'})
            : Envelope.fail(50000, '状态刷新失败'));
    await fillAndSubmit(tester);
    final submission = api.requests.singleWhere(
        (r) => r.method == 'POST' && r.path.endsWith('/real-name'));
    expect(submission.data['materialRefs'], [_reference]);
    expect(find.text('审核中'), findsOneWidget);
    expect(find.text('提交认证'), findsNothing);
    expect(find.text('提交失败，请稍后重试'), findsNothing);
  });

  testWidgets('in-flight upload disables submit and cannot submit twice',
      (tester) async {
    final api = ScriptedApi();
    status(api);
    api.reply('/users/me/real-name/material', Envelope.ok({'materialRef': _reference}));
    await pump(tester, api);
    api.gate();
    await pick(tester);
    final button = tester
        .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '提交认证'));
    expect(button.onPressed, isNull);
    expect(find.text('正在上传…'), findsOneWidget);
    expect(api.countOf('/real-name/material'), 1);
    await tester.runAsync(() async {
      api.release();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('上传成功'), findsOneWidget);
  });

  testWidgets('leaving the page evicts the certificate preview', (tester) async {
    final api = ScriptedApi();
    status(api);
    api.reply('/users/me/real-name/material', Envelope.ok({'materialRef': _reference}));
    await pump(tester, api);
    await pick(tester);
    await tester.pumpAndSettle();
    final provider = tester.widget<Image>(find.byType(Image)).image;
    final key = await provider.obtainKey(ImageConfiguration.empty);
    expect(PaintingBinding.instance.imageCache.containsKey(key), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(PaintingBinding.instance.imageCache.containsKey(key), isFalse);
  });
}

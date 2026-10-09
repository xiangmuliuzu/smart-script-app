import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/core/services/native_image_picker.dart';
import 'package:script_app/core/utils/avatar_url.dart';
import 'package:script_app/features/user_center/data/user_center_repository.dart';
import 'support/scripted_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('smartscript/native_image');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('platform avatars use current host and retain gateway prefix', () {
    const path = '/profile/upload/2026/10/09/avatar.png';
    for (final value in [
      path,
      'http://localhost:8080$path',
      'http://10.0.2.2:8080$path',
      'https://old.test/gateway$path'
    ]) {
      expect(avatarUrl(value, baseUrl: 'http://10.0.2.2:8080/api/v1'),
          'http://10.0.2.2:8080$path');
      expect(avatarUrl(value, baseUrl: 'https://api.test/gateway/api/v1/'),
          'https://api.test/gateway$path');
    }
    expect(
        avatarUrl('/profile/avatar/a.jpg', baseUrl: 'https://api.test/api/v1'),
        'https://api.test/profile/avatar/a.jpg');
    expect(
        avatarUrl('http://old.test/profile/upload/a%20b.png',
            baseUrl: 'https://api.test/api/v1'),
        'https://api.test/profile/upload/a%20b.png');
  });

  test('external avatars stay unchanged and unsafe protocols are rejected', () {
    expect(avatarUrl('https://cdn.test/images/a.png'),
        'https://cdn.test/images/a.png');
    for (final value in [
      null,
      '',
      'data:image/png;base64,abc',
      'javascript:alert(1)',
      '//other.test/a.png'
    ]) {
      expect(avatarUrl(value), '');
    }
  });

  test('picker cancellation does not produce an image', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await NativeImagePicker.pickImage(), isNull);
  });

  test('picker preserves format and always cleans temporary image', () async {
    final dir = await Directory.systemTemp.createTemp('avatar-picker-');
    try {
      for (final ext in ['png', 'jpg', 'gif', 'bmp']) {
        final file = File('${dir.path}/selected.$ext');
        await file.writeAsBytes([1, 2, 3]);
        messenger.setMockMethodCallHandler(channel, (_) async => file.path);
        final image = await NativeImagePicker.pickImage();
        expect(image?.filename, 'avatar.$ext');
        expect(image?.bytes, [1, 2, 3]);
        expect(await file.exists(), isFalse);
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('oversized or empty cache is rejected and deleted before upload',
      () async {
    final dir = await Directory.systemTemp.createTemp('avatar-picker-limit-');
    try {
      for (final size in [0, NativeImagePicker.maxImageBytes + 1]) {
        final file = File('${dir.path}/selected.png');
        await file.writeAsBytes(List<int>.filled(size, 0));
        messenger.setMockMethodCallHandler(channel, (_) async => file.path);
        await expectLater(NativeImagePicker.pickImage(),
            throwsA(isA<NativeImageException>()));
        expect(await file.exists(), isFalse);
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('native size rejection retains the user-facing message', () async {
    messenger.setMockMethodCallHandler(
        channel,
        (_) async =>
            throw PlatformException(code: 'too_large', message: '图片不能超过 5 MB'));
    await expectLater(
        NativeImagePicker.pickImage(),
        throwsA(isA<NativeImageException>()
            .having((e) => e.message, 'message', '图片不能超过 5 MB')));
  });

  test('upload saves the resource path and supports an older URL-only backend',
      () async {
    final api = ScriptedApi();
    final repository = UserCenterRepository(ApiClient(api.buildDio()));
    api.reply(
        '/users/me/avatar',
        Envelope.ok({
          'path': '/profile/upload/a.png',
          'url': 'http://localhost:8080/profile/upload/a.png'
        }));
    expect(
        await repository.uploadAvatar(bytes: [1, 2, 3], filename: 'avatar.png'),
        '/profile/upload/a.png');
    api.reply('/users/me/avatar',
        Envelope.ok({'url': 'https://api.test/profile/upload/a.png'}));
    expect(
        await repository.uploadAvatar(bytes: [1, 2, 3], filename: 'avatar.png'),
        'https://api.test/profile/upload/a.png');
  });
}

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/features/update/data/apk_installer.dart';
import 'package:script_app/features/update/data/app_update_repository.dart';
import 'package:script_app/features/update/data/app_version_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppVersionInfo', () {
    test('按 versionCode 判断新旧，versionName 仅展示', () {
      const info = AppVersionInfo(
        versionCode: 3,
        versionName: '1.0.2',
        minVersionCode: 2,
        url: 'https://example.com/app.apk',
        notes: '修复问题',
      );
      expect(info.isNewerThan(2), isTrue);
      expect(info.isNewerThan(3), isFalse);
      expect(info.hasDownloadUrl, isTrue);
      expect(info.isForcedFor(1), isTrue);
      expect(info.isForcedFor(2), isFalse);
    });

    test('相对路径与绝对地址都算可下载，空地址视为无更新', () {
    const relative = AppVersionInfo(
      versionCode: 2,
      versionName: '1.0.1',
      minVersionCode: 0,
      url: '/profile/app/script-app-1.0.1-2.apk',
      notes: '',
    );
    expect(relative.hasDownloadUrl, isTrue);
    expect(relative.isNewerThan(1), isTrue);

    const empty = AppVersionInfo(
      versionCode: 2,
      versionName: '1.0.1',
      minVersionCode: 0,
      url: '',
      notes: '',
    );
    expect(empty.hasDownloadUrl, isFalse);
    expect(empty.isNewerThan(1), isFalse);
  });

  test('未配置下载地址视为无更新，覆盖未知版本号', () {
      const info = AppVersionInfo(
        versionCode: 9,
        versionName: '9.0.0',
        minVersionCode: 0,
        url: '',
        notes: '',
      );
      expect(info.isNewerThan(1), isFalse);
    });

    test('解析后端 JSON（size 可缺省）', () {
      final info = AppVersionInfo.fromJson({
        'versionCode': 5,
        'versionName': '1.0.4',
        'minVersionCode': 3,
        'url': '/profile/apk/app.apk',
        'notes': '说明',
        'size': null,
      });
      expect(info.versionCode, 5);
      expect(info.minVersionCode, 3);
      expect(info.size, isNull);
      // 后台可以填 /profile/app/x.apk 相对路径，由客户端补全为服务器地址
      expect(info.isNewerThan(1), isTrue);
    });
  });

  test('下载地址支持相对路径补全为服务器地址', () {
    final repo = AppUpdateRepository(ApiClient(Dio()));
    expect(
      repo.resolveDownloadUrl('/profile/apk/app.apk'),
      endsWith('/profile/apk/app.apk'),
    );
    expect(
      repo.resolveDownloadUrl('https://cdn.example.com/app.apk'),
      'https://cdn.example.com/app.apk',
    );
  });

  test('download 走真实 HTTP，可拿到进度并落盘', () async {
    // flutter_test 默认拦截 HttpClient（一律 400），这里临时换回真实实现。
    HttpOverrides.global = null;
    final dir = Directory.systemTemp.createTempSync('apk_update_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType('application', 'vnd.android.package-archive')
        ..headers.contentLength = 1024;
      request.response.add(List<int>.filled(1024, 7));
      request.response.close();
    });

    final progress = <double>[];
    final repo = AppUpdateRepository(ApiClient(Dio()));
    final target = File('${dir.path}/app.apk');
    await repo.download(
      url: 'http://${server.address.address}:${server.port}/app.apk',
      savePath: target.path,
      onProgress: progress.add,
    );

    expect(await target.length(), 1024);
    expect(progress, isNotEmpty);
    expect(progress.last, 1.0);
  });

  test('清理历史安装包只保留最新两个', () async {
    final dir = Directory.systemTemp.createTempSync('apk_cleanup_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (var i = 1; i <= 4; i++) {
      final file = File('${dir.path}/script-app-1.0.$i-$i.apk');
      file.writeAsBytesSync([i]);
      file.setLastModifiedSync(DateTime(2026, 11, i));
    }
    File('${dir.path}/notes.txt').writeAsStringSync('keep me');

    await ApkInstaller.cleanupOldApks(dir);

    final left = dir
        .listSync()
        .whereType<File>()
        .map((f) => f.path.split(Platform.pathSeparator).last)
        .toList()
      ..sort();
    expect(left, ['notes.txt', 'script-app-1.0.3-3.apk', 'script-app-1.0.4-4.apk']);
  });

  test('安装包文件头校验：APK 通过，伪装成 APK 的网页被拒', () async {
    final dir = Directory.systemTemp.createTempSync('apk_header_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    final real = File('${dir.path}/real.apk')
      ..writeAsBytesSync([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00]);
    expect(await ApkInstaller.looksLikeApk(real), isTrue);

    final html = File('${dir.path}/fake.apk')
      ..writeAsStringSync('<html>404 Not Found</html>');
    expect(await ApkInstaller.looksLikeApk(html), isFalse);

    expect(await ApkInstaller.looksLikeApk(File('${dir.path}/missing.apk')), isFalse);
  });

  group('ApkInstaller 原生通道', () {
    tearDown(() {
      ApkInstaller.channel = const MethodChannel('smartscript/native_update');
      ApkInstaller.debugLocalBuildNumber = null;
      ApkInstaller.debugDownloadDirectory = null;
    });

    test('返回 false 表示已跳转「安装未知应用」授权页', () async {
      ApkInstaller.channel = const MethodChannel('smartscript/native_update.test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        ApkInstaller.channel,
        (call) async => call.method == 'installApk' ? false : null,
      );
      expect(await ApkInstaller.install('/tmp/app.apk'), isFalse);
    });

    test('平台错误转成可展示的中文文案', () async {
      ApkInstaller.channel = const MethodChannel('smartscript/native_update.test2');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        ApkInstaller.channel,
        (call) async => throw PlatformException(code: 'missing_file'),
      );
      await expectLater(
        ApkInstaller.install('/tmp/app.apk'),
        throwsA(isA<ApkInstallException>()
            .having((e) => e.message, 'message', '安装包不存在，请重新下载')),
      );
    });
  });
}

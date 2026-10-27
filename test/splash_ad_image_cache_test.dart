import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:script_app/features/splash/splash_ad_image_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late List<int> png;
  const firstUrl = 'https://example.com/ad-v1.png';
  const secondUrl = 'https://example.com/ad-v2.png';

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('splash-ad-cache-test-');
    png = await File('assets/images/logo_script.png').readAsBytes();
  });
  tearDown(() async => temp.delete(recursive: true));

  test('完整图片落盘后，新缓存实例直接读取文件而不再次下载', () async {
    var requests = 0;
    SplashAdImageCache cache() => SplashAdImageCache(
          directory: () async => temp,
          client: () => MockClient((request) async {
            requests++;
            return http.Response.bytes(png, 200);
          }),
        );
    final downloaded = await cache().load(firstUrl);
    expect(downloaded, isNotNull);
    expect(await downloaded!.readAsBytes(), png);
    final cached = await cache().load(firstUrl);
    expect(cached!.path, downloaded.path);
    expect(requests, 1);
  });

  test('更换 URL 不误用旧图，失败下载不破坏旧缓存，成功后只保留新图', () async {
    var valid = true;
    final cache = SplashAdImageCache(
      directory: () async => temp,
      client: () => MockClient((request) async => valid
          ? http.Response.bytes(png, 200)
          : http.Response('<html>not an image</html>', 200)),
    );
    final first = await cache.load(firstUrl);
    expect(await cache.read(secondUrl), isNull);
    valid = false;
    expect(await cache.load(secondUrl), isNull);
    expect((await cache.read(firstUrl))!.path, first!.path);
    valid = true;
    expect(await cache.load(secondUrl), isNotNull);
    expect(await cache.read(firstUrl), isNull);
    expect(await first.exists(), isFalse);
    expect(await cache.read(secondUrl), isNotNull);
  });

  test('HTTP 失败和超过五 MB 的素材不写入缓存', () async {
    final failed = SplashAdImageCache(
      directory: () async => temp,
      client: () =>
          MockClient((request) async => http.Response('missing', 404)),
    );
    expect(await failed.load(firstUrl), isNull);
    final oversized = SplashAdImageCache(
      directory: () async => temp,
      client: () => MockClient.streaming((request, body) async =>
          http.StreamedResponse(const Stream.empty(), 200,
              contentLength: 5 * 1024 * 1024 + 1)),
    );
    expect(await oversized.load(firstUrl), isNull);
    expect(await failed.read(firstUrl), isNull);
  });

  test('缓存文件被系统回收后可以重新下载', () async {
    var requests = 0;
    final cache = SplashAdImageCache(
      directory: () async => temp,
      client: () => MockClient((request) async {
        requests++;
        return http.Response.bytes(png, 200);
      }),
    );
    final file = await cache.load(firstUrl);
    await file!.delete();
    expect(await cache.read(firstUrl), isNull);
    expect(await cache.load(firstUrl), isNotNull);
    expect(requests, 2);
  });
}

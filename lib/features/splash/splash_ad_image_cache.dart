import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/config/app_config.dart';

/// 只缓存当前一张开屏素材。URL 变化时重新下载，完整校验后才替换旧缓存。
class SplashAdImageCache {
  SplashAdImageCache({
    Future<Directory> Function()? directory,
    http.Client Function()? client,
  })  : _directory = directory ?? getTemporaryDirectory,
        _client = client ?? (() => http.Client());

  final Future<Directory> Function() _directory;
  final http.Client Function() _client;
  static const _maxBytes = 5 * 1024 * 1024;

  Future<Directory> _root() async =>
      Directory('${(await _directory()).path}/splash-ad');

  Future<File?> read(String url) async {
    try {
      final root = await _root();
      final data =
          jsonDecode(await File('${root.path}/index.json').readAsString());
      final name = data['file'];
      if (data['url'] != url ||
          name is! String ||
          !RegExp(r'^ad-\d+\.img$').hasMatch(name)) return null;
      final file = File('${root.path}/$name');
      final size = await file.length();
      return size > 0 && size <= _maxBytes ? file : null;
    } catch (_) {
      return null;
    }
  }

  Future<File?> load(String url) async {
    final cached = await read(url);
    if (cached != null) {
      if (AppConfig.enableNetworkLog) {
        debugPrint('Splash image: disk cache hit');
      }
      return cached;
    }
    final client = _client();
    try {
      final bytes =
          await _download(client, url).timeout(const Duration(seconds: 20));
      if (bytes == null) return null;
      // 静态资源错误有时也返回 HTTP 200；只缓存真正能解码的图片。
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      final root = await (await _root()).create(recursive: true);
      final name = 'ad-${DateTime.now().microsecondsSinceEpoch}.img';
      final file =
          await File('${root.path}/$name').writeAsBytes(bytes, flush: true);
      final index = File('${root.path}/index.tmp');
      await index.writeAsString(jsonEncode({'url': url, 'file': name}),
          flush: true);
      await index.rename('${root.path}/index.json');
      // 新文件与索引已就绪后再清理，不让下载失败破坏仍有效的旧缓存。
      await for (final entry in root.list()) {
        final entryName = entry.uri.pathSegments.last;
        if (entry is File &&
            entryName != name &&
            RegExp(r'^ad-\d+\.img$').hasMatch(entryName)) {
          try {
            await entry.delete();
          } catch (_) {/* 系统稍后可回收缓存文件。 */}
        }
      }
      if (AppConfig.enableNetworkLog) {
        debugPrint('Splash image: cached download');
      }
      return file;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  Future<Uint8List?> _download(http.Client client, String url) async {
    final response = await client.send(http.Request('GET', Uri.parse(url)));
    if (response.statusCode != 200 || (response.contentLength ?? 0) > _maxBytes) {
      return null;
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > _maxBytes) return null;
      bytes.add(chunk);
    }
    return bytes.isEmpty ? null : bytes.takeBytes();
  }
}

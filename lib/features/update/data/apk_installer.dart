import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// 应用内更新：下载 APK 并交给系统安装器（不跳转浏览器）。
///
/// 普通应用无法静默安装，因此拆成三步：下载到应用目录 → 拉起系统安装确认 →
/// 用户在系统弹窗确认。首次安装前系统会要求允许「安装未知应用」，
/// [ApkInstaller.install] 返回 false 时表示已把用户引导到该设置页。
class ApkInstaller {
  ApkInstaller._();

  /// 单测可替换为桩通道。
  @visibleForTesting
  static MethodChannel channel =
      const MethodChannel('smartscript/native_update');

  /// 单测注入：绕过原生通道读取 build 号 / 下载目录。
  @visibleForTesting
  static int? debugLocalBuildNumber;

  @visibleForTesting
  static Future<Directory> Function()? debugDownloadDirectory;

  /// 本机 build 号（Android 为 versionCode）。
  ///
  /// 优先读原生 `BuildConfig.VERSION_CODE`，它与 `flutter build --build-number=N`
  /// 写入的版本号完全一致；非 Android 平台或通道缺失时回退到 package_info_plus。
  static Future<int> localBuildNumber() async {
    if (debugLocalBuildNumber != null) return debugLocalBuildNumber!;
    if (!Platform.isAndroid) return _packageBuildNumber();
    try {
      final code = await channel.invokeMethod<int>('buildNumber');
      if (code != null) return code;
    } on MissingPluginException {
      // 单测/桌面调试没有原生通道
    } on PlatformException {
      // 读取失败不阻塞更新检查
    }
    return _packageBuildNumber();
  }

  static Future<int> _packageBuildNumber() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 下载目录：应用专属外部目录（卸载即清理，无需存储权限，FileProvider 可共享）。
  static Future<Directory> downloadDirectory() async {
    if (debugDownloadDirectory != null) return debugDownloadDirectory!();
    if (Platform.isAndroid) {
      final dir = await getExternalStorageDirectory();
      if (dir != null) {
        final target = Directory('${dir.path}/updates');
        await target.create(recursive: true);
        return target;
      }
    }
    return getTemporaryDirectory();
  }

  /// 校验下载到的文件确实是 APK（ZIP 头 `PK\x03\x04`）。
  ///
  /// 服务器返回错误页（网关 200 + HTML）、或下载被中间代理改写时，
  /// 文件大小可能对得上但内容是网页；这里拦下来，避免把坏包交给安装器。
  static Future<bool> looksLikeApk(File file) async {
    try {
      final raf = await file.open();
      try {
        final header = await raf.read(4);
        return header.length == 4 &&
            header[0] == 0x50 &&
            header[1] == 0x4B &&
            header[2] == 0x03 &&
            header[3] == 0x04;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// 清理历史安装包，只保留最新的 [keep] 个。
  ///
  /// 每个 APK 二三十 MB，版本攒多了会白占用户几十到上百 MB 的应用目录。
  static Future<void> cleanupOldApks(Directory dir, {int keep = 2}) async {
    try {
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.apk')) {
          files.add(entity);
        }
      }
      if (files.length <= keep) return;
      final withTime = <(File, DateTime)>[];
      for (final file in files) {
        withTime.add((file, (await file.stat()).modified));
      }
      withTime.sort((a, b) => b.$2.compareTo(a.$2));
      for (final entry in withTime.skip(keep)) {
        await entry.$1.delete();
      }
    } catch (_) {
      // 清理失败不影响本次下载与安装
    }
  }

  /// 安装已下载的 APK。
  ///
  /// 返回 true 表示已拉起系统安装器；false 表示用户尚未授权安装未知应用，
  /// 已跳到系统设置页（用户授权并返回后重新调用即可）。
  static Future<bool> install(String path) async {
    // 不按平台提前拒绝：非 Android 端没有该原生通道，会走下面的 MissingPluginException 分支。
    try {
      final started = await channel.invokeMethod<bool>('installApk', {'path': path});
      return started ?? false;
    } on MissingPluginException {
      throw const ApkInstallException('当前版本不支持应用内安装');
    } on PlatformException catch (e) {
      throw ApkInstallException(_friendly(e));
    }
  }

  static String _friendly(PlatformException e) {
    switch (e.code) {
      case 'missing_file':
        return '安装包不存在，请重新下载';
      case 'no_settings':
        return '请先在系统设置中允许本应用安装未知应用';
      case 'install_failed':
        return '无法启动安装，请稍后重试';
      default:
        return '安装失败，请稍后重试';
    }
  }
}

/// 安装失败的可展示错误。
class ApkInstallException implements Exception {
  const ApkInstallException(this.message);

  final String message;

  @override
  String toString() => message;
}

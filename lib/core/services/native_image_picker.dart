import 'dart:io';

import 'package:flutter/services.dart';

/// 平台原生图片选择（A5 头像上传用）。
///
/// 不引入第三方 picker 插件：Android 侧 [MainActivity] 用系统选择器取图，
/// 复制到应用缓存后把路径回传 Dart；本类只负责读字节与清理临时文件。
class NativeImagePicker {
  NativeImagePicker._();

  static const MethodChannel _channel = MethodChannel('smartscript/native_image');

  /// 调起系统选择器。
  ///
  /// 返回所选图片的字节与文件名；用户取消返回 null。
  static Future<PickedImage?> pickImage() async {
    final String? path;
    try {
      path = await _channel.invokeMethod<String>('pickImage');
    } on PlatformException catch (e) {
      throw NativeImageException(e.message ?? '无法打开图片选择器');
    } on MissingPluginException {
      // 非 Android 平台（如桌面调试）未注册该通道
      throw NativeImageException('当前平台不支持图片选择');
    }
    if (path == null || path.isEmpty) {
      return null;
    }
    final file = File(path);
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return PickedImage(bytes: bytes, filename: _fileName(file.path));
    } finally {
      // 临时文件用完即删，不把用户选择的原图留在应用缓存里
      try {
        await file.delete();
      } catch (_) {
        // 清理失败不影响上传流程
      }
    }
  }

  /// 从缓存路径还原一个对用户可读的文件名（扩展名影响上传的 MIME 判断）。
  static String _fileName(String path) {
    final base = path.split(Platform.pathSeparator).last;
    final dot = base.lastIndexOf('.');
    final ext = dot >= 0 ? base.substring(dot) : '.jpg';
    return 'avatar${ext == '.img' ? '.jpg' : ext}';
  }
}

class PickedImage {
  const PickedImage({required this.bytes, required this.filename});

  final List<int> bytes;
  final String filename;

  int get sizeInBytes => bytes.length;
}

class NativeImageException implements Exception {
  NativeImageException(this.message);

  final String message;

  @override
  String toString() => message;
}

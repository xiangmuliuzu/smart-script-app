import 'dart:io';

import 'package:flutter/services.dart';

/// 本地系统通知（Android 顶部横幅）。
///
/// 走平台原生 MethodChannel，不引入第三方通知/推送插件。
///
/// 边界：这是 **App 运行时的本地通知**——只有 App 进程存活（前台，或刚退到后台且未被系统回收）
/// 时，Dart 侧轮询到新消息才会弹窗；App 被系统彻底杀掉后收不到（那需要真正的离线推送）。
/// 非 Android 平台（如桌面调试）本类为安全空操作。
class LocalNotifier {
  LocalNotifier._();

  static const MethodChannel _channel =
      MethodChannel('smartscript/native_notify');

  /// 申请通知权限（Android 13+ POST_NOTIFICATIONS）；返回是否已授予。
  /// 低版本 Android 与其它平台直接视为已授予/不可用。
  static Future<bool> ensurePermission() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('ensureNotificationPermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 弹出系统通知；[id] 相同会覆盖同一条。返回是否成功弹出。
  static Future<bool> show({
    required int id,
    required String title,
    String body = '',
  }) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('showNotification', {
            'id': id,
            'title': title,
            'body': body,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// APP-14 / APP-15：源码级门禁。
void main() {
  final libRoot = Directory('lib');

  test('APP-14 production 无 enterTestSession / DEMO_SESSION / 测试进入', () {
    final offenders = <String>[];
    for (final f in libRoot.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      if (src.contains('enterTestSession') ||
          src.contains('DEMO_SESSION') ||
          src.contains('测试进入（免登录')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty, reason: 'production 不得保留免登录路径: $offenders');
  });

  test('APP-13 源码不得把 Token 写入 SharedPreferences', () {
    final offenders = <String>[];
    for (final f in libRoot.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll('\\', '/');
      if (path.contains('secure_token_storage')) continue;
      final src = f.readAsStringSync();
      if (src.contains("prefs.setString(AppConstants.spToken") ||
          src.contains("prefs.setString('auth_token'") ||
          src.contains("_prefs.setString(AppConstants.kAccessToken") ||
          src.contains("_prefs.setString(AppConstants.kRefreshToken")) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty, reason: 'SharedPreferences 不得保存 Token: $offenders');
  });

  test('APP-15 认证代码不得打印 Token/密码/验证码明文', () {
    final patterns = [
      RegExp(r"print\(.*(token|password|code|refreshToken)"),
      RegExp(r"debugPrint\(.*(token|password|code|refreshToken)"),
      RegExp(r"developer\.log\(.*(accessToken|refreshToken|password)"),
    ];
    final offenders = <String>[];
    for (final f in libRoot
        .listSync(recursive: true)
        .whereType<File>()
        .where((e) => e.path.replaceAll('\\', '/').contains('auth'))) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final p in patterns) {
        if (p.hasMatch(src)) {
          offenders.add(f.path);
          break;
        }
      }
    }
    expect(offenders, isEmpty, reason: '日志不得含敏感信息: $offenders');
  });

  test('认证接口路径符合 A3 契约', () {
    final endpoints = File('lib/core/constants/api_endpoints.dart').readAsStringSync();
    for (final path in [
      '/auth/sms/send',
      '/auth/sms/login',
      '/auth/password/login',
      '/auth/register',
      '/auth/token/refresh',
      '/auth/logout',
      '/auth/me',
      '/auth/password/set',
      '/auth/password/change',
      '/auth/password/reset',
      '/auth/agreements',
    ]) {
      expect(endpoints.contains(path), isTrue, reason: '缺少契约路径 $path');
    }
    expect(endpoints.contains("'/auth/login'"), isFalse);
    expect(endpoints.contains("'/auth/login-sms'"), isFalse);
    expect(endpoints.contains("'/auth/refresh'"), isFalse);
    expect(endpoints.contains("'/auth/sms-code'"), isFalse);
  });
}

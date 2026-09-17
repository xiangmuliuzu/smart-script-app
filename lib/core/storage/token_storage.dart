import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';

/// 登录态本地存储（token / refreshToken / 当前角色 / 用户缓存）。
///
/// 由框架层统一持有，供网络拦截器与 auth 状态共用，页面不要各自存 token。
class TokenStorage {
  TokenStorage(this._prefs);

  final SharedPreferences _prefs;

  String? get token => _prefs.getString(AppConstants.spToken);

  String? get refreshToken => _prefs.getString(AppConstants.spRefreshToken);

  /// 当前登录账号类型：creator / client（接口文档 2.1.3 userType）。
  String? get userType => _prefs.getString(AppConstants.spUserType);

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  /// 读取缓存的用户信息（用于重启后恢复会话），无缓存时返回 null。
  Map<String, dynamic>? get cachedUser {
    final raw = _prefs.getString(AppConstants.spUserCache);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheUser(Map<String, dynamic> userJson) =>
      _prefs.setString(AppConstants.spUserCache, jsonEncode(userJson));

  Future<void> saveSession({
    required String token,
    String? refreshToken,
    String? userType,
    Map<String, dynamic>? user,
  }) async {
    await _prefs.setString(AppConstants.spToken, token);
    if (refreshToken != null) {
      await _prefs.setString(AppConstants.spRefreshToken, refreshToken);
    }
    if (userType != null) {
      await _prefs.setString(AppConstants.spUserType, userType);
    }
    if (user != null) {
      await cacheUser(user);
    }
  }

  Future<void> clear() async {
    await _prefs.remove(AppConstants.spToken);
    await _prefs.remove(AppConstants.spRefreshToken);
    await _prefs.remove(AppConstants.spUserType);
    await _prefs.remove(AppConstants.spUserCache);
  }
}

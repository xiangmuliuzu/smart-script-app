import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import 'secure_token_storage.dart';

/// A3 session storage:
/// - Access/Refresh Token live in [TokenSecureStorage] only.
/// - SharedPreferences stores non-sensitive display cache only.
class TokenStorage {
  TokenStorage(this._secure, this._prefs);

  final TokenSecureStorage _secure;
  final SharedPreferences _prefs;

  String? _token;
  String? _refreshToken;

  String? get token => _token;

  String? get refreshToken => _refreshToken;

  bool get isLoggedIn => _token != null && _token!.isNotEmpty;

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

  Future<void> loadFromSecure() async {
    _token = await _secure.read(AppConstants.kAccessToken);
    _refreshToken = await _secure.read(AppConstants.kRefreshToken);
  }

  Future<void> cacheUser(Map<String, dynamic> userJson) =>
      _prefs.setString(AppConstants.spUserCache, jsonEncode(userJson));

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    Map<String, dynamic>? user,
  }) async {
    await _secure.write(AppConstants.kAccessToken, accessToken);
    await _secure.write(AppConstants.kRefreshToken, refreshToken);
    _token = accessToken;
    _refreshToken = refreshToken;
    if (user != null) {
      await cacheUser(user);
    }
  }

  Future<void> updateTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _secure.write(AppConstants.kAccessToken, accessToken);
    await _secure.write(AppConstants.kRefreshToken, refreshToken);
    _token = accessToken;
    _refreshToken = refreshToken;
  }

  /// Atomic credential wipe (refresh failure / replay / account disabled).
  Future<void> clear() async {
    await _secure.delete(AppConstants.kAccessToken);
    await _secure.delete(AppConstants.kRefreshToken);
    _token = null;
    _refreshToken = null;
    await _prefs.remove(AppConstants.spUserCache);
  }

  /// Used by APP-13: assert SharedPreferences never holds tokens.
  Future<bool> prefsContainCredentials() async {
    for (final key in [
      AppConstants.kAccessToken,
      AppConstants.kRefreshToken,
      'auth_token',
      'auth_refresh_token',
      'a3_access_token',
      'a3_refresh_token',
    ]) {
      final v = _prefs.getString(key);
      if (v != null && v.isNotEmpty) return true;
    }
    return false;
  }
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import 'secure_token_storage.dart';

/// A3 session storage:
/// - The RuoYi token lives in [TokenSecureStorage] only.
/// - SharedPreferences stores non-sensitive display cache only.
class TokenStorage {
  TokenStorage(this._secure, this._prefs);

  final TokenSecureStorage _secure;
  final SharedPreferences _prefs;

  String? _token;
  int _generation = 0;
  int _tokenGeneration = 0;
  Future<void>? _writes;

  int get generation => _generation;
  int get tokenGeneration => _tokenGeneration;

  Future<void> _serialize(Future<void> Function() action) {
    final operation =
        _writes == null ? action() : _writes!.then((_) => action());
    final queued = operation.catchError((Object _) {});
    _writes = queued;
    queued.then((_) {
      if (identical(_writes, queued)) _writes = null;
    });
    return operation;
  }

  String? get token => _token;

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
    final generation = _generation;
    if (_writes != null) await _writes;
    final token = await _secure.read(AppConstants.kAccessToken);
    // Remove the retired refresh token when upgrading an existing installation.
    await _secure.delete(AppConstants.kRefreshToken);
    if (generation == _generation) {
      _token = token;
      _tokenGeneration = generation;
    }
  }

  Future<void> cacheUser(Map<String, dynamic> userJson) =>
      _prefs.setString(AppConstants.spUserCache, jsonEncode(userJson));

  Future<void> saveSession(
      {required String token, Map<String, dynamic>? user}) {
    final generation = ++_generation;
    return _serialize(() async {
      await _secure.write(AppConstants.kAccessToken, token);
      await _secure.delete(AppConstants.kRefreshToken);
      if (generation == _generation) {
        _token = token;
        _tokenGeneration = generation;
        if (user != null) await cacheUser(user);
      }
    });
  }

  /// Clear credentials when signing out or the RuoYi session expires.
  Future<void> clear() {
    _tokenGeneration = ++_generation;
    _token = null;
    return _serialize(() async {
      await _secure.delete(AppConstants.kAccessToken);
      await _secure.delete(AppConstants.kRefreshToken);
      await _prefs.remove(AppConstants.spUserCache);
    });
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

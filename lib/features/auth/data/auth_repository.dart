import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../models/user.dart';

/// A3 AuthRepository — pages never call Dio/Token/Storage directly.
class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  /// Cached current agreement versions from GET /auth/agreements.
  List<Map<String, String>>? _agreementAcceptances;

  Future<void> sendSms({
    required String phone,
    required String scene,
    String? deviceId,
  }) async {
    await _api.post(
      ApiEndpoints.smsSend,
      data: {
        'phone': phone,
        'scene': scene,
        if (deviceId != null) 'deviceId': deviceId,
      },
    );
  }

  /// Loads current agreement type/version pairs from the server (not hardcoded).
  Future<List<Map<String, String>>> currentAgreementAcceptances({bool forceReload = false}) async {
    if (!forceReload && _agreementAcceptances != null) {
      return _agreementAcceptances!;
    }
    final list = await agreements();
    final acceptances = <Map<String, String>>[];
    for (final item in list) {
      final type = item['type'] as String?;
      final version = item['version'] as String?;
      if (type != null && version != null && version.isNotEmpty) {
        acceptances.add({'type': type, 'version': version});
      }
    }
    if (acceptances.length < 2) {
      throw ApiException('协议版本获取失败，请稍后重试');
    }
    _agreementAcceptances = acceptances;
    return acceptances;
  }

  Future<AuthSession> smsLogin({
    required String phone,
    required String code,
    required String deviceId,
    String? deviceName,
    bool acceptAgreements = true,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.smsLogin,
      data: {
        'phone': phone,
        'code': code,
        'deviceId': deviceId,
        if (deviceName != null) 'deviceName': deviceName,
        if (acceptAgreements)
          'agreementAcceptances': await currentAgreementAcceptances(),
      },
      parser: _mapParser,
    );
    return _requireSession(data);
  }

  Future<AuthSession> passwordLogin({
    required String phone,
    required String password,
    required String deviceId,
    String? deviceName,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.passwordLogin,
      data: {
        'phone': phone,
        'password': password,
        'deviceId': deviceId,
        if (deviceName != null) 'deviceName': deviceName,
      },
      parser: _mapParser,
    );
    return _requireSession(data);
  }

  Future<AuthSession> register({
    required String phone,
    required String code,
    required String password,
    required String deviceId,
    String? deviceName,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.register,
      data: {
        'phone': phone,
        'code': code,
        'password': password,
        'deviceId': deviceId,
        if (deviceName != null) 'deviceName': deviceName,
        'agreementAcceptances': await currentAgreementAcceptances(forceReload: true),
      },
      parser: _mapParser,
    );
    return _requireSession(data);
  }

  Future<AuthSession> refresh({
    required String refreshToken,
    required String deviceId,
    String? deviceName,
  }) async {
    final data = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.tokenRefresh,
      data: {
        'refreshToken': refreshToken,
        'deviceId': deviceId,
        if (deviceName != null) 'deviceName': deviceName,
      },
      parser: _mapParser,
    );
    return _requireSession(data);
  }

  Future<void> logout() async {
    await _api.post(ApiEndpoints.logout);
  }

  Future<User> me() async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.me,
      parser: _mapParser,
    ) ??
        const <String, dynamic>{};
    if (data.isEmpty) throw ApiException('获取用户信息失败');
    return User.fromJson(data);
  }

  Future<void> passwordSet(String password) async {
    await _api.post(ApiEndpoints.passwordSet, data: {'password': password});
  }

  Future<void> passwordChange({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _api.post(
      ApiEndpoints.passwordChange,
      data: {'oldPassword': oldPassword, 'newPassword': newPassword},
    );
  }

  Future<void> passwordReset({
    required String phone,
    required String code,
    required String newPassword,
  }) async {
    await _api.post(
      ApiEndpoints.passwordReset,
      data: {'phone': phone, 'code': code, 'newPassword': newPassword},
    );
  }

  Future<List<Map<String, dynamic>>> agreements() async {
    final data = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.agreements,
      parser: _mapParser,
    ) ??
        const <String, dynamic>{};
    final list = data['agreements'];
    if (list is List) {
      return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }

  static Map<String, dynamic> _mapParser(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  static AuthSession _requireSession(Map<String, dynamic>? data) {
    final session = data;
    final access = session == null ? null : session['accessToken'] as String?;
    if (access == null || access.isEmpty || session == null) {
      throw ApiException('登录失败：响应缺少会话');
    }
    return AuthSession.fromJson(session);
  }
}

import 'package:dio/dio.dart';

import '../../storage/token_storage.dart';

/// RuoYi renews the Redis session on authenticated requests. No refresh token.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._storage);

  final TokenStorage _storage;

  bool isPublic(String path) {
    final p = Uri.tryParse(path)?.path ?? path;
    final normalized = p.startsWith('/api/v1') ? p.substring(7) : p;
    return const [
          '/auth/login',
          '/auth/captchaImage',
          '/auth/password/login',
          '/auth/sms/send',
          '/auth/sms/login',
          '/auth/register',
          '/auth/password/reset',
          '/auth/agreements',
          '/captchaImage',
        ].contains(normalized) ||
        normalized.startsWith('/auth/oauth/');
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['tokenGeneration'] = _storage.tokenGeneration;
    if (isPublic(options.path)) options.extra['skipSessionExpiry'] = true;
    final token = _storage.token;
    if (token != null && token.isNotEmpty && !isPublic(options.path)) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401 && !isPublic(err.requestOptions.path)) {
      final sent = err.requestOptions.headers['Authorization'];
      if (sent == 'Bearer ${_storage.token}' &&
          err.requestOptions.extra['tokenGeneration'] == _storage.generation) {
        final clearedGeneration = _storage.generation + 1;
        await _storage.clear();
        if (_storage.generation != clearedGeneration) {
          err.requestOptions.extra['skipSessionExpiry'] = true;
        }
      } else {
        err.requestOptions.extra['skipSessionExpiry'] = true;
      }
    }
    handler.next(err);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final sent = response.requestOptions.headers['Authorization'];
    if (sent != null &&
        (sent != 'Bearer ${_storage.token}' ||
            response.requestOptions.extra['tokenGeneration'] !=
                _storage.generation)) {
      response.requestOptions.extra['skipSessionExpiry'] = true;
    }
    handler.next(response);
  }
}

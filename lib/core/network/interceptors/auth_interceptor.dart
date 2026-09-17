import 'dart:developer' as developer;

import 'package:dio/dio.dart';

import '../../storage/token_storage.dart';

/// 认证拦截器：自动为业务请求注入 `Authorization: Bearer {token}`。
///
/// 登录/注册等无需鉴权的接口通过 [_publicPaths] 跳过。
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._storage);

  final TokenStorage _storage;

  /// 无需携带 token 的公开接口。
  static const List<String> _publicPaths = [
    '/auth/sms-code',
    '/auth/register',
    '/auth/login',
    '/auth/login-sms',
    '/auth/password/reset',
    '/auth/refresh',
  ];

  bool _isPublic(String path) =>
      _publicPaths.any((p) => path.startsWith(p));

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _storage.token;
    if (token != null && token.isNotEmpty && !_isPublic(options.path)) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // 401：登录态失效，交由上层 auth 状态处理（清 token + 跳登录）。
    if (err.response?.statusCode == 401) {
      developer.log('收到 401，登录态可能已失效', name: 'AuthInterceptor');
    }
    handler.next(err);
  }
}

/// 日志拦截器（仅 debug 使用）。
class AppLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    developer.log('--> ${options.method} ${options.uri}', name: 'HTTP');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    developer.log(
      '<-- ${response.statusCode} ${response.requestOptions.uri}\n${response.data}',
      name: 'HTTP',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    developer.log(
      '<-- ERROR ${err.type} ${err.requestOptions.uri}\n${err.message}',
      name: 'HTTP',
    );
    handler.next(err);
  }
}

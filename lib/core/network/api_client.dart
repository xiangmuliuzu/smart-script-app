import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'api_exception.dart';
import 'api_response.dart';
import 'interceptors/auth_interceptor.dart';
import 'session_events.dart';

/// 网络客户端封装（框架层唯一出口）。
///
/// 页面开发者通过 [ApiClient] 的 get/post/put/delete/upload 发起请求，
/// 拿到的是已解包的 `data`；业务失败（code != 200）与网络异常统一抛 [ApiException]。
/// 登录态失效（401）由框架自动发信号并踢回登录页，页面无需处理。
class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  /// 构造一个绑定了拦截器的 Dio（供 provider 调用）。
  static Dio buildDio(AuthInterceptor authInterceptor) {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        contentType: Headers.jsonContentType,
        // 让所有状态码都进入统一处理，不自动抛异常
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    dio.interceptors.add(authInterceptor);
    if (AppConfig.enableNetworkLog) {
      dio.interceptors.add(AppLogInterceptor());
    }
    return dio;
  }

  /// GET 请求。
  Future<T?> get<T>(
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    T Function(dynamic raw)? parser,
  }) =>
      _send<T>(_dio.get<dynamic>(path,
          queryParameters: query, options: Options(headers: headers)),
          parser);

  /// POST 请求（JSON）。
  ///
  /// 需要幂等的接口（如发票 2.3.16）请在 [headers] 传 `{'Idempotency-Key': '...'}`。
  Future<T?> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    T Function(dynamic raw)? parser,
  }) =>
      _send<T>(
          _dio.post<dynamic>(path,
              data: data,
              queryParameters: query,
              options: Options(headers: headers)),
          parser);

  /// PUT 请求（JSON）。
  Future<T?> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? headers,
    T Function(dynamic raw)? parser,
  }) =>
      _send<T>(
          _dio.put<dynamic>(path, data: data, options: Options(headers: headers)),
          parser);

  /// DELETE 请求。
  Future<T?> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? headers,
    T Function(dynamic raw)? parser,
  }) =>
      _send<T>(
          _dio.delete<dynamic>(path,
              data: data, options: Options(headers: headers)),
          parser);

  /// 文件上传（multipart/form-data，接口 2.9.1）。
  ///
  /// [formData] 由页面用 `FormData.fromMap({... 'file': MultipartFile...})` 构造。
  /// 头像 / 实名材料 / 印章 / 作品文件等上传统一走这里。
  Future<T?> upload<T>(
    String path, {
    required FormData formData,
    Map<String, dynamic>? headers,
    T Function(dynamic raw)? parser,
  }) =>
      _send<T>(
          _dio.post<dynamic>(path,
              data: formData,
              options: Options(
                headers: headers,
                contentType: Headers.multipartFormDataContentType,
              )),
          parser);

  /// 统一的响应解析与错误处理。
  Future<T?> _send<T>(
    Future<Response<dynamic>> future,
    T Function(dynamic raw)? parser,
  ) async {
    try {
      final resp = await future;

      // HTTP 层 401：登录态失效
      if (resp.statusCode == 401) {
        SessionEvents.instance.sessionExpired();
        throw ApiException('登录状态已过期，请重新登录', code: 401);
      }

      final body = resp.data;
      if (body is! Map) {
        throw ApiException('响应格式错误', code: resp.statusCode);
      }

      final apiResp = ApiResponse<T>.fromJson(
        Map<String, dynamic>.from(body),
        parser: parser,
      );

      if (!apiResp.isSuccess) {
        // 业务层 401：同样视为登录态失效
        if (apiResp.code == 401) SessionEvents.instance.sessionExpired();
        throw ApiException(
          apiResp.message.isEmpty ? '请求失败' : apiResp.message,
          code: apiResp.code,
          data: apiResp.data,
        );
      }
      return apiResp.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) SessionEvents.instance.sessionExpired();
      throw ApiException(_mapDioError(e), code: e.response?.statusCode);
    }
  }

  String _mapDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '网络超时，请稍后重试';
      case DioExceptionType.connectionError:
        return '网络连接失败，请检查网络或后端地址';
      case DioExceptionType.badCertificate:
        return '安全证书校验失败';
      case DioExceptionType.cancel:
        return '请求已取消';
      default:
        return '网络异常，请稍后重试';
    }
  }
}

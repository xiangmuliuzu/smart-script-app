import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/friendly_error.dart';
import 'app_version_models.dart';

/// App 更新所需的网络与文件下载（版本接口 + APK 下载）。
///
/// 版本接口在后端是匿名可达的，但已登录用户仍应带上 Token 以获得统一身份；
/// 复用全局 [ApiClient] 即可（AuthInterceptor 的公开白名单里已登记 `/app/version`，
/// 401 时不会误触发「登录已过期」）。
class AppUpdateRepository {
  AppUpdateRepository(this._client);

  final ApiClient _client;

  /// APK 下载单独建一个 Dio：下载用不到业务拦截器，且需要关闭超时、允许大文件。
  static final Dio _downloadDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(minutes: 10),
    sendTimeout: const Duration(minutes: 10),
  ));

  /// 拉取最新版本信息。
  Future<AppVersionInfo> fetchLatest() async {
    final data = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.appVersion,
      parser: (raw) => Map<String, dynamic>.from(raw as Map),
    );
    return AppVersionInfo.fromJson(data ?? const <String, dynamic>{});
  }

  /// 解析下载地址：服务器下发的 `/profile/app/xxx.apk` 是相对路径，补成 baseUrl 的 origin。
  ///
  /// 与后端公开静态资源（`/profile/**`）同源；但也兼容后台直接填 CDN 绝对地址。
  String resolveDownloadUrl(String raw) {
    final value = raw.trim();
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) return value;
    return '${Uri.parse(AppConfig.baseUrl).origin}'
        '${value.startsWith('/') ? value : '/$value'}';
  }

  /// 下载 APK 到本地文件，回调返回 0~1 的进度。
  Future<void> download({
    required String url,
    required String savePath,
    CancelToken? cancelToken,
    void Function(double progress)? onProgress,
  }) async {
    try {
      await _downloadDio.download(
        resolveDownloadUrl(url),
        savePath,
        cancelToken: cancelToken,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          if (total <= 0 || onProgress == null) return;
          onProgress((received / total).clamp(0.0, 1.0));
        },
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw ApkDownloadException(_describeDownloadError(e));
    }
  }

  static String _describeDownloadError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return FriendlyError.timeout;
      case DioExceptionType.connectionError:
        return FriendlyError.network;
      case DioExceptionType.badResponse:
        return FriendlyError.messageForStatus(e.response?.statusCode) ??
            '下载失败，请稍后重试';
      default:
        return '下载失败，请检查网络后重试';
    }
  }
}

/// 下载失败（文案已是对用户友好的中文，可直接展示）。
class ApkDownloadException implements Exception {
  const ApkDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

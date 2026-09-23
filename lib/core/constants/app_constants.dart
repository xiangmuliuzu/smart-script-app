/// 通用常量。
class AppConstants {
  AppConstants._();

  /// 应用名。
  static const String appName = '智能剧本创作平台';

  /// 统一响应成功码（接口文档 1.2：`{ "code": 200, ... }`）。
  static const int codeSuccess = 200;

  /// 分页默认参数。
  static const int defaultPageNo = 1;
  static const int defaultPageSize = 10;

  /// 本地存储 key（集中管理，避免散落）。
  /// SharedPreferences 仅允许非敏感缓存，禁止存放 Token。
  static const String spUserCache = 'auth_user_cache';

  /// Secure storage keys (A3 credentials).
  static const String kAccessToken = 'a3_access_token';
  static const String kRefreshToken = 'a3_refresh_token';
}

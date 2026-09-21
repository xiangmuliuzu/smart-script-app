/// 全局应用配置。
///
/// 说明：App 端**不直接连数据库**（数据库接入信息是后端 Spring Boot 用的）。
/// App 只通过接口文档约定的 RESTful API 通信，网关前缀为 `/api/v1`。
class AppConfig {
  AppConfig._();

  /// 环境标识（debug / staging / prod）。
  static const String env = 'debug';

  /// 接口基础地址。
  ///
  /// A3 后端为 RuoYi Spring Boot，默认端口 8080，契约前缀 `/api/v1`。
  /// Android 模拟器访问宿主机使用 `10.0.2.2`。
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://10.0.2.2:8080/api/v1',
  );

  /// 连接超时。
  static const Duration connectTimeout = Duration(seconds: 10);

  /// 接收超时。
  static const Duration receiveTimeout = Duration(seconds: 30);

  /// 是否输出网络日志（禁止打印 Token/密码/验证码）。
  static const bool enableNetworkLog = bool.fromEnvironment(
    'ENABLE_NETWORK_LOG',
    defaultValue: false,
  );

  /// 是否 production 构建（禁止演示会话）。
  static const bool isProduction = bool.fromEnvironment('dart.vm.product');
}

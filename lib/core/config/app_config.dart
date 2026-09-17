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
  /// 【重要】当前项目在 Android 模拟器（x86_64）上运行，模拟器访问宿主机的
  /// localhost 必须使用 `10.0.2.2`，而不是 `127.0.0.1`。
  /// - Android 模拟器：http://10.0.2.2:3000/api/v1
  /// - iOS 模拟器 / PC 直连：http://127.0.0.1:3000/api/v1
  /// - 真机调试：改成后端所在机队的局域网 IP，例如 http://192.168.x.x:3000/api/v1
  ///
  /// 后端地址变动时，只改这一处即可（这也是接口文档 1.2 与团队约定）。
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/api/v1',
  );

  /// 连接超时。
  static const Duration connectTimeout = Duration(seconds: 10);

  /// 接收超时。
  static const Duration receiveTimeout = Duration(seconds: 30);

  /// 是否输出网络日志（仅 debug）。
  static const bool enableNetworkLog = true;
}

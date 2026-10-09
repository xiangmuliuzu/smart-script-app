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

  // ===== 后端静态资源地址 =====

  /// 视为「本机后端」的资源主机名。
  static const Set<String> _localAssetHosts = {'localhost', '127.0.0.1', '0.0.0.0'};

  /// 把指向本机后端的资源地址归一为 [baseUrl] 的 origin，其余地址原样返回。
  ///
  /// 后端下发的封面/Banner 地址是开发机地址（`http://localhost:8080/...`）：
  /// PC 浏览器可直连，但在真机/模拟器上 `localhost` 指向设备自身而取不到图。
  /// 归一后「后端地址怎么配，图片就怎么取」，PC/App 共用同一份数据、互不影响。
  static String resolveAssetUrl(String raw) {
    if (raw.isEmpty) return raw;
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || !_localAssetHosts.contains(uri.host)) {
      return raw;
    }
    return Uri.parse(baseUrl)
        .replace(path: uri.path, query: uri.hasQuery ? uri.query : null)
        .toString();
  }

  // ===== 认证表单参数（与 A3 后端校验规则一致，仅用于即时反馈） =====

  /// 手机号位数（中国大陆，后端规则 `^1\d{10}$`）。
  static const int phoneLength = 11;

  /// 验证码位数下限（后端 `@Size(min = 4, max = 8)`）。
  static const int smsCodeMinLength = 4;

  /// 验证码位数上限（后端短信模板当前下发 6 位，此处按契约上限放开输入）。
  static const int smsCodeMaxLength = 8;

  /// 登录密码长度范围（后端 `password length must be 8-64`）。
  static const int passwordMinLength = 8;
  static const int passwordMaxLength = 64;

  /// 验证码倒计时秒数（发送成功后开始；发送失败不倒计时）。
  static const int smsCooldownSeconds = 60;

  /// 默认国家区号（第一期仅支持中国大陆，结构上预留切换能力）。
  static const String defaultCountryCode = '+86';

  /// 协议版本兜底值：服务端 `/auth/agreements` 未返回时展示，不作为提交依据。
  static const String agreementVersion = '1.0';
}

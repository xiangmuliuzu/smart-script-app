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
  /// 默认连接服务器统一 HTTPS 入口，契约前缀为 `/api/v1`。
  /// 本地联调可通过 `--dart-define=BASE_URL=...` 覆盖。
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://www.eyhereal.site/api/v1',
  );

  /// 连接超时。
  static const Duration connectTimeout = Duration(seconds: 10);

  /// 接收超时。
  static const Duration receiveTimeout = Duration(seconds: 30);

  /// 是否输出网络日志（禁止打印 Token/密码/验证码）。
  static const bool enableNetworkLog = bool.fromEnvironment(
    'ENABLE_NETWORK_LOG',
    defaultValue: true,
  );

  /// 是否 production 构建（禁止演示会话）。
  static const bool isProduction = bool.fromEnvironment('dart.vm.product');

  // ===== 后端静态资源地址 =====

  /// 视为「本机后端」的资源主机名。
  static const Set<String> _localAssetHosts = {
    'localhost',
    '127.0.0.1',
    '0.0.0.0',
    // Android 模拟器访问宿主机的别名：不同开发环境（模拟器/真机）会存下不同 host，
    // 归一后才能共用同一份后端数据。
    '10.0.2.2',
  };

  /// 后端公开静态资源前缀（与后端 ResourcesConfig 的 `/profile/**` 映射一致）。
  static const String _mediaPathPrefix = '/profile/';

  /// 把后端下发的资源地址解析为当前设备可访问的地址。
  ///
  /// 覆盖三种形态：
  ///   - 相对路径（`/profile/upload/...`）：补上 [baseUrl] 的 origin；
  ///   - 内嵌 `/profile/` 的绝对地址（本机 `http://localhost:8080/profile/...`、
  ///     服务器 `http://<IP 或域名>/profile/...`）：截取 `/profile/` 之后的部分再拼 origin；
  ///   - 其余（CDN / 公网 https）原样返回。
  ///
  /// 为什么不能只按 host 白名单判断：在服务器上上传的图片会把服务器地址存进共享库，
  /// 该 host 不在本机白名单内，原样请求会打到前端站点、拿回 index.html 导致破图。
  /// 按 `/profile/` 锚点归一后，「后端地址怎么配，图片就怎么取」，各端共用同一份数据。
  static String resolveAssetUrl(String raw) {
    if (raw.isEmpty) return raw;
    final origin = Uri.parse(baseUrl).origin;
    final mediaIndex = raw.indexOf(_mediaPathPrefix);
    if (mediaIndex >= 0) return '$origin${raw.substring(mediaIndex)}';
    if (raw.startsWith('/')) return '$origin$raw';
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
  static const String agreementVersion = '1.0.0';
}

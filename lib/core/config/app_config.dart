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

  /// 远端存储基址：公开媒体（头像、作品图、印章图）一律从这里取。
  ///
  /// 每台开发机各存一份磁盘必然互看不见，故图片不访问本机 `uploadPath`；
  /// 口径与 PC 端 vite dev 的 `VITE_REMOTE_MEDIA_BASE` 一致。
  /// 留空则退回接口所在 origin（单机部署时的旧行为）。
  static const String mediaBaseUrl = String.fromEnvironment(
    'MEDIA_BASE_URL',
    defaultValue: 'https://www.eyhereal.site',
  );

  /// 带签名参数、必须由签发方后端提供的媒体路径
  /// （后端 `ProfileAccessSigner.GUARDED_PREFIXES` 的两种历史形态）。
  /// 签名密钥按机器不同，这类地址改投远端只会把 403 变成破图。
  static const List<String> signedMediaPrefixes = [
    '/profile/contract/',
    '/profile/upload/contract/',
  ];

  /// 公开媒体的挂载根：配了 [mediaBaseUrl] 用它，否则用 [apiRoot]。
  static String mediaRoot(String apiRoot) => mediaRootWith(mediaBaseUrl, apiRoot);

  /// [mediaRoot] 的可注入版本，供测试固定存储基址。
  static String mediaRootWith(String mediaBase, String apiRoot) {
    final configured = mediaBase.replaceFirst(RegExp(r'/+$'), '');
    return configured.isEmpty
        ? apiRoot.replaceFirst(RegExp(r'/+$'), '')
        : configured;
  }

  /// 是否为受签名保护的材料路径。
  static bool isSignedMedia(String resource) =>
      signedMediaPrefixes.any(resource.startsWith);

  /// 把后端下发的资源地址解析为当前设备可访问的地址。
  ///
  /// 覆盖三种形态：
  ///   - 内嵌 `/profile/` 的地址（相对路径、本机 `http://localhost:8080/profile/...`、
  ///     服务器绝对地址）：截出 `/profile/` 之后的部分重新挂载——公开媒体挂
  ///     [mediaBaseUrl]（远端存储），受签名保护的材料挂签发它的后端；
  ///   - 其余以 `/` 开头的站内路径：补 [baseUrl] 的 origin；
  ///   - CDN / 公网 https：原样返回。
  ///
  /// 为什么不能只按 host 白名单判断：在服务器上上传的图片会把服务器地址存进共享库，
  /// 该 host 不在本机白名单内，原样请求会打到前端站点、拿回 index.html 导致破图。
  /// 按 `/profile/` 锚点归一后，图片来源只取决于存储配置，各端共用同一份数据。
  static String resolveAssetUrl(String raw,
      {String? apiBaseUrl, String? mediaBaseUrl}) {
    if (raw.isEmpty) return raw;
    final api = apiBaseUrl ?? baseUrl;
    final origin = Uri.parse(api).origin;
    final mediaIndex = raw.indexOf(_mediaPathPrefix);
    if (mediaIndex >= 0) {
      final resource = raw.substring(mediaIndex);
      final root = isSignedMedia(resource)
          ? origin
          : mediaRootWith(mediaBaseUrl ?? AppConfig.mediaBaseUrl, origin);
      return '$root$resource';
    }
    if (raw.startsWith('/')) return '$origin$raw';
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || !_localAssetHosts.contains(uri.host)) {
      return raw;
    }
    return Uri.parse(api)
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

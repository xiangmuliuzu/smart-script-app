/// 扫码登录（App 扫码 → 网页登录）的数据层。
///
/// 服务端按「票据」推进状态：WAITING → SCANNED → CONFIRMED。
/// App 只负责把扫到的票据标记为自己扫的，并在用户点确认时提交；
/// 网页令牌由服务端签发到发起出码的那个浏览器，App 全程不接触对方令牌。
class QrLoginModels {
  QrLoginModels._();
}

/// `POST /auth/qr/scan` 的返回：告诉 App 这张码来自哪个站点的哪个浏览器。
class QrScanTarget {
  const QrScanTarget({
    required this.portal,
    required this.browser,
    required this.os,
    required this.status,
  });

  /// creator / enterprise。
  final String portal;
  final String? browser;
  final String? os;
  final String status;

  /// 给用户看的站点名：确认页必须让用户认出「这是不是我自己打开的那个窗口」。
  String get portalLabel => switch (portal) {
        'enterprise' => '企业端 · 个人版权采购中心',
        _ => '创作者端 · 创作者中心',
      };

  /// 浏览器 + 系统，缺失时回退为「未知设备」。
  String get deviceLabel {
    final parts = [browser, os].whereType<String>().where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? '未知设备' : parts.join(' · ');
  }

  static QrScanTarget fromJson(Map<String, dynamic> json) => QrScanTarget(
        portal: (json['portal'] as String?) ?? 'creator',
        browser: json['browser'] as String?,
        os: json['os'] as String?,
        status: (json['status'] as String?) ?? 'SCANNED',
      );
}

/// 二维码内容：`juyunce://qr-login?t=<token>`。
///
/// 用 App 专用 scheme 而不是网页地址：通用扫码器只会显示一串文本，
/// 不会把用户带去任何网页，也就没有仿冒站点可乘之机。同时兼容网页地址形态
/// （`https://<host>/qr-login?t=`），便于以后换成通用链接而不必升级 App。
const String qrLoginScheme = 'juyunce';
const String qrLoginHost = 'qr-login';
const String qrLoginPath = '/qr-login';

/// 从扫到的原始字符串里取出票据；不是扫码登录链接时返回 null。
String? parseQrLoginToken(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return null;

  final matched = uri.scheme == qrLoginScheme
      // 自定义 scheme：Uri 会把 qr-login 解析成 host。
      ? uri.host == qrLoginHost
      // 网页形态：只看 path，不信任具体域名（站点可能换域名，票据本身才是凭据）。
      : (uri.scheme == 'http' || uri.scheme == 'https') && uri.path == qrLoginPath;
  if (!matched) return null;

  final token = uri.queryParameters['t'];
  if (token == null || token.length < 16 || token.length > 128) return null;
  return token;
}

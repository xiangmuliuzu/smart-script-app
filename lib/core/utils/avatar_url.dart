import '../config/app_config.dart';

/// 平台图片按「存储统一在远端」解析：公开媒体挂 [AppConfig.mediaBaseUrl]，
/// 带签名的合同材料仍挂签发它的后端（密钥按机器不同，投远端只会 403）。
/// 兼容历史开发机/模拟器存下的绝对地址：一律按 `/profile/` 锚点重挂。
String avatarUrl(
  String? raw, {
  String baseUrl = AppConfig.baseUrl,
  String mediaBaseUrl = AppConfig.mediaBaseUrl,
}) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return '';
  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.hasScheme && uri.scheme != 'http' && uri.scheme != 'https') ||
      (!uri.hasScheme && (!value.startsWith('/') || value.startsWith('//')))) {
    return '';
  }
  final match = RegExp(r'/profile/').firstMatch(uri.path);
  if (match == null) return value;
  final resource = uri.path.substring(match.start);
  if (resource.contains('\\') ||
      resource.split('/').any((part) => part == '.' || part == '..')) {
    return '';
  }
  final apiRoot = Uri.parse(baseUrl
      .replaceFirst(RegExp(r'/+$'), '')
      .replaceFirst(RegExp(r'/api/v1$'), ''));
  if (AppConfig.isSignedMedia(resource)) {
    // 签名参数就是这类地址的可读性本身，丢掉等于把材料变成 403
    final query = uri.hasQuery ? '?${uri.query}' : '';
    return '${apiRoot.replace(path: '${apiRoot.path}$resource')}$query';
  }
  final media = Uri.parse(AppConfig.mediaRootWith(mediaBaseUrl, apiRoot.toString()));
  return media.replace(path: '${media.path}$resource').toString();
}

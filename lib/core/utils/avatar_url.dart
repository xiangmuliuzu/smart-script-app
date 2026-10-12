import '../config/app_config.dart';

/// 平台头像按当前后端展示，兼容历史开发机/模拟器的绝对地址。
String avatarUrl(String? raw, {String baseUrl = AppConfig.baseUrl}) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return '';
  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.hasScheme && uri.scheme != 'http' && uri.scheme != 'https') ||
      (!uri.hasScheme && (!value.startsWith('/') || value.startsWith('//')))) {
    return '';
  }
  final match = RegExp(r'/profile/(?:upload|avatar)/').firstMatch(uri.path);
  if (match == null) return value;
  final resource = uri.path.substring(match.start);
  if (resource.contains('\\') ||
      resource.split('/').any((part) => part == '.' || part == '..')) {
    return '';
  }
  final root = Uri.parse(baseUrl
      .replaceFirst(RegExp(r'/+$'), '')
      .replaceFirst(RegExp(r'/api/v1$'), ''));
  return root.replace(path: '${root.path}$resource').toString();
}

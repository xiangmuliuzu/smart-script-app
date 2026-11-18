/// App 版本检查的响应模型（对应后端 `GET /api/v1/app/version`）。
///
/// 后端只按 [versionCode] 判断新旧；[versionName] 仅用于展示。
class AppVersionInfo {
  const AppVersionInfo({
    required this.versionCode,
    required this.versionName,
    required this.minVersionCode,
    required this.url,
    required this.notes,
    this.size,
  });

  /// 最新安装包的 versionCode（与 Android build-number 一致）。
  final int versionCode;

  /// 最新版本名，如 `1.0.1`。
  final String versionName;

  /// 强制更新的最低 versionCode：本机低于它时弹窗不可跳过。
  final int minVersionCode;

  /// APK 下载地址；为空表示后台尚未配置，按「无更新」处理。
  final String url;

  /// 更新说明（纯文本，可含换行）。
  final String notes;

  /// APK 字节数（后台可选配置）；为空时不做大小校验。
  final int? size;

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    final rawCode = json['versionCode'];
    return AppVersionInfo(
      versionCode: rawCode is num ? rawCode.toInt() : int.tryParse('$rawCode') ?? 0,
      versionName: (json['versionName'] ?? '').toString(),
      minVersionCode: _asInt(json['minVersionCode']) ?? 0,
      url: (json['url'] ?? '').toString().trim(),
      notes: (json['notes'] ?? '').toString(),
      size: _asInt(json['size']),
    );
  }

  static int? _asInt(Object? raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString());
  }

  /// 是否可下载：支持 https 绝对地址，也支持后台填写 `/profile/app/x.apk`
  /// 这类相对路径（与 App 接口同源，由客户端补全）。
  /// 为空或无法识别时视为无更新，避免弹出下载必然失败的弹窗。
  bool get hasDownloadUrl {
    final value = url.trim();
    if (value.isEmpty) return false;
    return value.startsWith('http://') ||
        value.startsWith('https://') ||
        value.startsWith('/');
  }

  /// 相对本机 buildNumber 是否有更新。
  bool isNewerThan(int localBuild) => hasDownloadUrl && versionCode > localBuild;

  /// 相对本机 buildNumber 是否必须更新（低于后台设置的下限）。
  bool isForcedFor(int localBuild) =>
      minVersionCode > 0 && localBuild < minVersionCode;
}

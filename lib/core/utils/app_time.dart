/// 全 App 统一时间口径。
///
/// 后端下发的时间一律是北京时间（多为无时区后缀的 ISO 或 `yyyy-MM-dd HH:mm:ss`）。
/// 设备本地时区不可信（模拟器冷启会掉回 GMT，用户也可改系统时区），
/// 因此解析必须钉到 +08:00，展示与自然日比较必须走北京墙钟。
class AppTime {
  AppTime._();

  static const Duration beijingOffset = Duration(hours: 8);

  /// 解析服务端时间为绝对时刻；无时区后缀的字符串按北京时间对待。
  static DateTime? parse(dynamic value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is DateTime) return value.toUtc();
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    var iso = text.replaceFirst(' ', 'T');
    final hasZone =
        iso.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(iso);
    if (!hasZone) {
      final hasTime = RegExp(r'\d{2}:\d{2}').hasMatch(iso);
      iso = '$iso${hasTime ? '' : 'T00:00:00'}+08:00';
    }
    return DateTime.tryParse(iso);
  }

  /// 北京墙钟视图：year/month/day/hour/minute 字段即展示值。
  /// 带 isUtc 标记，防止再被 toLocal() 二次平移。
  static DateTime beijing(DateTime instant) => instant.toUtc().add(beijingOffset);

  /// 当前时刻的北京墙钟视图。
  static DateTime nowBeijing() => beijing(DateTime.now());

  static String two(int v) => v.toString().padLeft(2, '0');

  /// `HH:mm`
  static String formatHourMinute(DateTime instant) {
    final b = beijing(instant);
    return '${two(b.hour)}:${two(b.minute)}';
  }

  /// `yyyy-MM-dd`
  static String formatDate(DateTime? instant) {
    if (instant == null) return '-';
    final b = beijing(instant);
    return '${b.year}-${two(b.month)}-${two(b.day)}';
  }

  /// `yyyy-MM-dd HH:mm`
  static String formatDateTime(DateTime? instant) {
    if (instant == null) return '-';
    final b = beijing(instant);
    return '${b.year}-${two(b.month)}-${two(b.day)} ${two(b.hour)}:${two(b.minute)}';
  }

  /// 北京自然日差：target 距 now 几天（0=今天，1=昨天，负数=明天之后）。
  static int dayDiffBeijing(DateTime target, {DateTime? now}) {
    final n = now != null ? beijing(now) : nowBeijing();
    final t = beijing(target);
    return DateTime(n.year, n.month, n.day)
        .difference(DateTime(t.year, t.month, t.day))
        .inDays;
  }
}

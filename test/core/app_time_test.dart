import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/core/utils/app_time.dart';

void main() {
  // 2026-11-23 09:00 北京 = 01:00 UTC
  final beijingMorning = DateTime.utc(2026, 11, 23, 1);

  group('AppTime.parse', () {
    test('naive ISO 按北京时间对待，与设备时区无关', () {
      final parsed = AppTime.parse('2026-11-23T09:00:00')!;
      expect(parsed.toUtc().millisecondsSinceEpoch,
          beijingMorning.millisecondsSinceEpoch);
    });

    test('空格分隔的 yyyy-MM-dd HH:mm:ss 同样解析正确', () {
      final parsed = AppTime.parse('2026-11-23 09:00:00')!;
      expect(parsed.toUtc().millisecondsSinceEpoch,
          beijingMorning.millisecondsSinceEpoch);
    });

    test('带 Z 或偏移后缀的字符串保留原时刻', () {
      expect(AppTime.parse('2026-11-23T01:00:00Z')!.toUtc().millisecondsSinceEpoch,
          beijingMorning.millisecondsSinceEpoch);
      expect(AppTime.parse('2026-11-23T09:00:00+08:00')!.toUtc().millisecondsSinceEpoch,
          beijingMorning.millisecondsSinceEpoch);
    });

    test('epoch 毫秒直接是绝对时刻', () {
      final parsed = AppTime.parse(beijingMorning.millisecondsSinceEpoch)!;
      expect(parsed.toUtc(), beijingMorning);
    });

    test('纯日期按北京零点，展示日期不漂移', () {
      final parsed = AppTime.parse('2026-11-23')!;
      final b = AppTime.beijing(parsed);
      expect('${b.year}-${b.month}-${b.day}', '2026-11-23');
    });

    test('空串与 null 返回 null', () {
      expect(AppTime.parse(''), isNull);
      expect(AppTime.parse(null), isNull);
    });
  });

  group('展示与日界', () {
    test('formatDateTime 输出北京墙钟', () {
      expect(AppTime.formatDateTime(beijingMorning), '2026-11-23 09:00');
      expect(AppTime.formatDate(beijingMorning), '2026-11-23');
      expect(AppTime.formatHourMinute(beijingMorning), '09:00');
    });

    test('撤回窗口：2 分钟内的旧时刻消息不因设备时区被误判', () {
      final justNow = DateTime.now().subtract(const Duration(minutes: 1));
      expect(DateTime.now().difference(justNow) <= const Duration(minutes: 2),
          isTrue);
      final tooOld = DateTime.now().subtract(const Duration(minutes: 3));
      expect(DateTime.now().difference(tooOld) <= const Duration(minutes: 2),
          isFalse);
    });

    test('dayDiffBeijing 按北京自然日：昨晚消息今早仍是昨天', () {
      // 北京 23:30 的消息，相对北京次日 00:30 差 1 个自然日
      final msg = DateTime.utc(2026, 11, 22, 15, 30); // 23:30 +08
      final now = DateTime.utc(2026, 11, 22, 16, 30); // 次日 00:30 +08
      expect(AppTime.dayDiffBeijing(msg, now: now), 1);
    });
  });
}

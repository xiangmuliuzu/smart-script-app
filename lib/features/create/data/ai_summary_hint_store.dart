import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 「AI 已按作品资料起草本章概要」提示的本地去重记录。
///
/// 该提示只在**首次**进入某章的概要页展示：编辑概要或再次进入本章不再打扰。
/// 这是纯展示偏好（属于 SharedPreferences 允许的非敏感缓存），
/// 权威数据仍是后端章节 summary / 本章资料，读不到时按「未展示过」处理。
class AiSummaryHintStore {
  AiSummaryHintStore._();

  static const String _prefix = 'ai_summary_hint_seen_';

  static String _key(int workId) => '$_prefix$workId';

  /// 是否已展示过某章的起稿概要提示。
  static Future<bool> hasSeen(int workId, int chapterNo) async {
    if (workId <= 0 || chapterNo <= 0) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(workId));
      if (raw == null || raw.isEmpty) return false;
      final decoded = jsonDecode(raw);
      return decoded is List && decoded.map((e) => '$e').contains('$chapterNo');
    } catch (_) {
      return false;
    }
  }

  /// 标记某章提示已展示（失败静默，不打断写作）。
  static Future<void> markSeen(int workId, int chapterNo) async {
    if (workId <= 0 || chapterNo <= 0) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(workId));
      final list = <String>{};
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) list.addAll(decoded.map((e) => '$e'));
      }
      list.add('$chapterNo');
      await prefs.setString(_key(workId), jsonEncode(list.toList()));
    } catch (_) {
      // 忽略：提示去重失败只会导致提示多显示一次。
    }
  }
}

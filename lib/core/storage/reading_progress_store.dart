import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 本地阅读进度：按作品ID记录「最后阅读到的章节」。
///
/// 与服务端书架进度（PUT /content/shelf/{workId}/progress）互补：
/// 服务端进度仅在作品已加入书架时对续读可用（未加书架返回 404 被静默忽略），
/// 本存储对游客与未加书架用户同样生效，确保作品详情页「试读」按钮
/// 「读过就能续上、首次进第一章」的口径在任何身份下都成立。
class ReadProgress {
  const ReadProgress({
    required this.workId,
    required this.chapterId,
    this.chapterNo = 0,
    this.chapterTitle = '',
    this.updatedAtMs = 0,
  });

  final int workId;
  final int chapterId;
  final int chapterNo;
  final String chapterTitle;

  /// 记录时刻（毫秒），仅用于未来扩展（如多端合并），当前续读不依赖它。
  final int updatedAtMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'workId': workId,
        'chapterId': chapterId,
        'chapterNo': chapterNo,
        'chapterTitle': chapterTitle,
        'updatedAtMs': updatedAtMs,
      };

  factory ReadProgress.fromJson(Map<String, dynamic> json) => ReadProgress(
        workId: (json['workId'] as num?)?.toInt() ?? 0,
        chapterId: (json['chapterId'] as num?)?.toInt() ?? 0,
        chapterNo: (json['chapterNo'] as num?)?.toInt() ?? 0,
        chapterTitle: json['chapterTitle'] as String? ?? '',
        updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
      );
}

/// 阅读进度的本地读写工具（静态方法，内部按需获取 SharedPreferences）。
class ReadingProgressStore {
  ReadingProgressStore._();

  /// 进度存储键前缀；后接作品ID，一部作品一条记录。
  static const String _prefix = 'reading_progress_';

  static String _key(int workId) => '$_prefix$workId';

  /// 记录某作品最后阅读到的章节。失败静默——进度是附加信息，不应打断阅读主链路。
  static Future<void> save({
    required int workId,
    required int chapterId,
    int chapterNo = 0,
    String chapterTitle = '',
  }) async {
    if (workId <= 0 || chapterId <= 0) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final progress = ReadProgress(
        workId: workId,
        chapterId: chapterId,
        chapterNo: chapterNo,
        chapterTitle: chapterTitle,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await prefs.setString(_key(workId), jsonEncode(progress.toJson()));
    } catch (_) {
      // 忽略：本地写入异常不影响阅读与进度上报。
    }
  }

  /// 读取某作品的最后阅读进度；无记录或解析失败返回 null。
  static Future<ReadProgress?> load(int workId) async {
    if (workId <= 0) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(workId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final progress =
          ReadProgress.fromJson(Map<String, dynamic>.from(decoded));
      return progress.chapterId > 0 ? progress : null;
    } catch (_) {
      return null;
    }
  }
}

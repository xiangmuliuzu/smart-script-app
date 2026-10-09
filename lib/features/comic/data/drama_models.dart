/// B 模块外部视频（漫剧）页面模型（接口文档 2.8）。
///
/// 字段与后端 DTO 一一对应，不自行拼装：
///   - [DramaFeedItem]      ← AppDramaFeedItem（2.8.1 信息流）
///   - [DramaDetail]        ← AppExternalDramaDetailDto（2.8.15）
///   - [EpisodeItem]        ← AppEpisodeItem（2.8.2）
///   - [EpisodeDetail]      ← AppEpisodeDetailDto（2.8.3）
///   - [PlayProgress]       ← AppPlayProgressDto（2.8.5）
///   - [PlayHistoryItem]    ← AppPlayHistoryItem（2.8.6）
///   - [SubscriptionItem]   ← AppSubscriptionItem（2.8.14）
///   - [CommentItem]        ← AppCommentItem（2.8.10）
///   - [EpisodeLikeResult]  ← AppEpisodeLikeResult（2.8.12）
///   - [RelatedWorkPayload] ← AppRelatedWorkDto（2.8.16；work 复用书城 [BookItem]）
///   - [ReportResult]       ← AppReportResultDto（2.8.17）
///
/// tinyint 列在若依风格下以字符串 "0"/"1" 下发，这里统一转成 bool；
/// 时间列由后端按 `yyyy-MM-dd HH:mm:ss` 下发，保持字符串供页面直接展示。
library;

import '../../bookstore/data/bookstore_models.dart';

bool _flag(dynamic value) => value == '1' || value == 1 || value == true;

String _text(dynamic value) => value == null ? '' : value.toString();

int _int(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _intOrNull(dynamic value) {
  if (value is num) return value.toInt();
  if (value is String && value.isNotEmpty) return int.tryParse(value);
  return null;
}

double _decimal(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

/// 短剧信息流条目（2.8.1）。
///
/// [coverFileId] 为文件ID：库端无通用文件表可反查 URL，页面按能力兜底占位。
/// [hasRelatedWork] 与 2.8.16 同一口径（related_work_id 非空）。
class DramaFeedItem {
  const DramaFeedItem({
    required this.dramaId,
    this.title = '',
    this.coverFileId,
    this.externalUrl = '',
    this.sourceType = '',
    this.channelId,
    this.channelName = '',
    this.relatedWorkId,
    this.hasRelatedWork = false,
  });

  final int dramaId;
  final String title;
  final int? coverFileId;
  final String externalUrl;
  final String sourceType;
  final int? channelId;
  final String channelName;
  final int? relatedWorkId;
  final bool hasRelatedWork;

  factory DramaFeedItem.fromJson(Map<String, dynamic> json) => DramaFeedItem(
        dramaId: _int(json['dramaId']),
        title: _text(json['title']),
        coverFileId: _intOrNull(json['coverFileId']),
        externalUrl: _text(json['externalUrl']),
        sourceType: _text(json['sourceType']),
        channelId: _intOrNull(json['channelId']),
        channelName: _text(json['channelName']),
        relatedWorkId: _intOrNull(json['relatedWorkId']),
        hasRelatedWork: _flag(json['hasRelatedWork']),
      );
}

/// 外部视频详情（2.8.15）。
class DramaDetail {
  const DramaDetail({
    required this.dramaId,
    this.title = '',
    this.coverFileId,
    this.externalUrl = '',
    this.sourceType = '',
    this.channelId,
    this.channelName = '',
    this.platform = '',
    this.relatedWorkId,
    this.hasRelatedWork = false,
    this.status = '',
  });

  final int dramaId;
  final String title;
  final int? coverFileId;
  final String externalUrl;
  final String sourceType;
  final int? channelId;
  final String channelName;
  final String platform;
  final int? relatedWorkId;
  final bool hasRelatedWork;
  final String status;

  factory DramaDetail.fromJson(Map<String, dynamic> json) => DramaDetail(
        dramaId: _int(json['dramaId']),
        title: _text(json['title']),
        coverFileId: _intOrNull(json['coverFileId']),
        externalUrl: _text(json['externalUrl']),
        sourceType: _text(json['sourceType']),
        channelId: _intOrNull(json['channelId']),
        channelName: _text(json['channelName']),
        platform: _text(json['platform']),
        relatedWorkId: _intOrNull(json['relatedWorkId']),
        hasRelatedWork: _flag(json['hasRelatedWork']),
        status: _text(json['status']),
      );
}

/// 剧集列表条目（2.8.2）。列表不下发播放地址，播放地址在详情（2.8.3）。
class EpisodeItem {
  const EpisodeItem({
    required this.episodeId,
    required this.workId,
    this.episodeNo = 0,
    this.title = '',
    this.coverUrl = '',
    this.duration = 0,
    this.isFree = false,
    this.unlockType = '',
    this.price = 0,
    this.playCount = 0,
  });

  final int episodeId;
  final int workId;
  final int episodeNo;
  final String title;
  final String coverUrl;

  /// 时长（秒）。
  final int duration;
  final bool isFree;
  final String unlockType;
  final double price;
  final int playCount;

  /// 时长文案；后端未下发时长（0）时不展示。
  String get durationLabel {
    if (duration <= 0) return '';
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// 付费标记：免费集不展示金额。
  String get payLabel => isFree ? '免费' : '¥${price.toStringAsFixed(2)}';

  factory EpisodeItem.fromJson(Map<String, dynamic> json) => EpisodeItem(
        episodeId: _int(json['episodeId']),
        workId: _int(json['workId']),
        episodeNo: _int(json['episodeNo']),
        title: _text(json['title']),
        coverUrl: _text(json['coverUrl']),
        duration: _int(json['duration']),
        isFree: _flag(json['isFree']),
        unlockType: _text(json['unlockType']),
        price: _decimal(json['price']),
        playCount: _int(json['playCount']),
      );
}

/// 剧集详情（2.8.3）。
class EpisodeDetail {
  const EpisodeDetail({
    required this.episodeId,
    required this.workId,
    this.episodeNo = 0,
    this.title = '',
    this.videoUrl = '',
    this.coverUrl = '',
    this.duration = 0,
    this.isFree = false,
    this.unlockType = '',
    this.price = 0,
  });

  final int episodeId;
  final int workId;
  final int episodeNo;
  final String title;

  /// 播放地址（外部地址，由客户端按能力打开）。
  final String videoUrl;
  final String coverUrl;
  final int duration;
  final bool isFree;
  final String unlockType;
  final double price;

  String get payLabel => isFree ? '免费' : '¥${price.toStringAsFixed(2)}';

  factory EpisodeDetail.fromJson(Map<String, dynamic> json) => EpisodeDetail(
        episodeId: _int(json['episodeId']),
        workId: _int(json['workId']),
        episodeNo: _int(json['episodeNo']),
        title: _text(json['title']),
        videoUrl: _text(json['videoUrl']),
        coverUrl: _text(json['coverUrl']),
        duration: _int(json['duration']),
        isFree: _flag(json['isFree']),
        unlockType: _text(json['unlockType']),
        price: _decimal(json['price']),
      );
}

/// 剧集解锁状态（2.8.7，需 App Token）。免费集后端直接下发已解锁。
class EpisodeUnlockStatus {
  const EpisodeUnlockStatus({this.isUnlocked = false, this.unlockType = ''});

  /// 是否已解锁。
  final bool isUnlocked;

  /// 解锁方式（后端取剧集配置，可为空）。
  final String unlockType;

  factory EpisodeUnlockStatus.fromJson(Map<String, dynamic> json) => EpisodeUnlockStatus(
        isUnlocked: _flag(json['isUnlocked']),
        unlockType: _text(json['unlockType']),
      );
}

/// 剧集解锁结果（2.8.8 付费解锁 / 2.8.9 广告解锁）。重复解锁时后端返回既有 unlockId。
class UnlockResult {
  const UnlockResult({this.unlockId = 0, this.message = ''});

  final int unlockId;
  final String message;

  factory UnlockResult.fromJson(Map<String, dynamic> json) => UnlockResult(
        unlockId: _int(json['unlockId']),
        message: _text(json['message']),
      );
}

/// 剧集评论条目（2.8.10）。parentId=0 为一级评论，非 0 为对一级评论的回复。
class CommentItem {
  const CommentItem({
    required this.commentId,
    required this.episodeId,
    required this.userId,
    this.nickName = '',
    this.avatar = '',
    this.content = '',
    this.likeCount = 0,
    this.replyCount = 0,
    this.parentId = 0,
    this.createdAt,
  });

  final int commentId;
  final int episodeId;
  final int userId;
  final String nickName;
  final String avatar;
  final String content;
  final int likeCount;
  final int replyCount;

  /// 父评论ID；0 表示一级评论。
  final int parentId;

  /// 发表时间（"yyyy-MM-dd HH:mm:ss"）。
  final String? createdAt;

  /// 是否一级评论。
  bool get isTopLevel => parentId == 0;

  factory CommentItem.fromJson(Map<String, dynamic> json) => CommentItem(
        commentId: _int(json['commentId']),
        episodeId: _int(json['episodeId']),
        userId: _int(json['userId']),
        nickName: _text(json['nickName']),
        avatar: _text(json['avatar']),
        content: _text(json['content']),
        likeCount: _int(json['likeCount']),
        replyCount: _int(json['replyCount']),
        parentId: _int(json['parentId']),
        createdAt: json['createdAt'] as String?,
      );
}

/// 剧集点赞结果（2.8.12）。幂等：重复点赞/取消返回当前态。
class EpisodeLikeResult {
  const EpisodeLikeResult({this.liked = false, this.likeCount = 0});

  final bool liked;
  final int likeCount;

  factory EpisodeLikeResult.fromJson(Map<String, dynamic> json) => EpisodeLikeResult(
        liked: _flag(json['liked']),
        likeCount: _int(json['likeCount']),
      );
}

/// 播放进度（2.8.5）。无记录时后端下发 progress=0、duration=null。
class PlayProgress {
  const PlayProgress({this.progress = 0, this.duration});

  /// 已播放秒数。
  final int progress;

  /// 总时长（秒）；无记录时为 null。
  final int? duration;

  /// 播放完成比例（0~1）；无总时长时按 0 处理。
  double get ratio {
    final total = duration ?? 0;
    if (total <= 0) return 0;
    return (progress / total).clamp(0, 1).toDouble();
  }

  factory PlayProgress.fromJson(Map<String, dynamic> json) => PlayProgress(
        progress: _int(json['progress']),
        duration: _intOrNull(json['duration']),
      );
}

/// 播放历史条目（2.8.6）。
class PlayHistoryItem {
  const PlayHistoryItem({
    required this.id,
    required this.workId,
    this.workTitle = '',
    required this.episodeId,
    this.episodeTitle = '',
    this.coverUrl = '',
    this.episodeNo = 0,
    this.playTime,
    this.progressSeconds = 0,
    this.totalDuration = 0,
  });

  final int id;
  final int workId;
  final String workTitle;
  final int episodeId;
  final String episodeTitle;
  final String coverUrl;
  final int episodeNo;

  /// 最近播放时间（"yyyy-MM-dd HH:mm:ss"）。
  final String? playTime;
  final int progressSeconds;
  final int totalDuration;

  /// 进度文案；无进度时返回当前集文案。
  String get progressLabel {
    final episode = episodeNo > 0 ? '第 $episodeNo 集' : episodeTitle;
    if (progressSeconds <= 0) return episode;
    return '$episode · 已看 $progressSeconds 秒';
  }

  factory PlayHistoryItem.fromJson(Map<String, dynamic> json) => PlayHistoryItem(
        id: _int(json['id']),
        workId: _int(json['workId']),
        workTitle: _text(json['workTitle']),
        episodeId: _int(json['episodeId']),
        episodeTitle: _text(json['episodeTitle']),
        coverUrl: _text(json['coverUrl']),
        episodeNo: _int(json['episodeNo']),
        playTime: json['playTime'] as String?,
        progressSeconds: _int(json['progressSeconds']),
        totalDuration: _int(json['totalDuration']),
      );
}

/// 追更订阅条目（2.8.14）。
class SubscriptionItem {
  const SubscriptionItem({
    required this.workId,
    this.title = '',
    this.cover = '',
    this.authorName = '',
    this.episodeCount = 0,
    this.price = 0,
    this.notifyEnabled = false,
    this.createdAt,
  });

  final int workId;
  final String title;
  final String cover;
  final String authorName;
  final int episodeCount;
  final double price;

  /// 是否开启更新提醒。
  final bool notifyEnabled;

  /// 订阅时间（"yyyy-MM-dd HH:mm:ss"）。
  final String? createdAt;

  factory SubscriptionItem.fromJson(Map<String, dynamic> json) => SubscriptionItem(
        workId: _int(json['workId']),
        title: _text(json['title']),
        cover: _text(json['cover']),
        authorName: _text(json['authorName']),
        episodeCount: _int(json['episodeCount']),
        price: _decimal(json['price']),
        notifyEnabled: _flag(json['notifyEnabled']),
        createdAt: json['createdAt'] as String?,
      );
}

/// 找同款剧本（2.8.16）：关联剧本信息与作品详情同结构，故复用 [BookItem]。
class RelatedWorkPayload {
  const RelatedWorkPayload({
    required this.dramaId,
    this.hasRelatedWork = false,
    this.work,
  });

  final int dramaId;
  final bool hasRelatedWork;

  /// 关联剧本；未绑定原著时为 null。
  final BookItem? work;

  factory RelatedWorkPayload.fromJson(Map<String, dynamic> json) {
    final raw = json['work'];
    return RelatedWorkPayload(
      dramaId: _int(json['dramaId']),
      hasRelatedWork: _flag(json['hasRelatedWork']),
      work: raw is Map ? BookItem.fromJson(Map<String, dynamic>.from(raw)) : null,
    );
  }
}

/// 举报结果（2.8.17）。
class ReportResult {
  const ReportResult({required this.reportId, this.status = ''});

  final int reportId;
  final String status;

  factory ReportResult.fromJson(Map<String, dynamic> json) => ReportResult(
        reportId: _int(json['reportId']),
        status: _text(json['status']),
      );
}

/// 举报对象类型常量（2.8.17 target_type）。
///
/// 数据库设计文档 sys_report.target_type 的「枚举值」列为空，接口文档也未约定取值，
/// 故只登记本模块确实会用到的取值：与表名 sys_external_drama 对齐，不额外发明同义枚举。
class ReportTargetType {
  ReportTargetType._();

  /// 外部视频（sys_external_drama）。
  static const String externalDrama = 'external_drama';
}

/// 举报原因（reason，varchar(50)；接口文档未约定取值，此处为界面提供的可选项）。
class ReportReason {
  const ReportReason(this.label);

  final String label;

  static const List<ReportReason> all = <ReportReason>[
    ReportReason('色情低俗'),
    ReportReason('违法违规'),
    ReportReason('侵权盗版'),
    ReportReason('虚假信息'),
    ReportReason('其他'),
  ];
}